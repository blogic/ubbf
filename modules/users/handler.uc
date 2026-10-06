'use strict';

// Out-of-tree module. `ubbf_module` is the scope datamodel.uc includes this
// file with, and it is visible only while the include runs, so anything the
// handlers below use later has to be bound here. See docs/ARCHITECTURE.md.

const ubbf = ubbf_module.ubbf;
const utils = ubbf_module.utils;
const model = ubbf_module.model;
const operations = ubbf_module.operations;
const on_commit = ubbf_module.on_commit;
const on_abort = ubbf_module.on_abort;
const on_precommit = ubbf_module.on_precommit;

const fs = require('fs');
const uci = require('uci');
const users = require('users');

const schema = ubbf_module.schema;

// The accounts this module manages are rows of the configuration, and the
// commit hook writes them to /etc/passwd, /etc/shadow and /etc/group. Every
// other account belongs to the system. It shows as a read-only row numbered
// from RUNTIME_BASE plus its uid (or gid), which no configured row reaches,
// so that its number does not change when another account comes or goes.
const CONFIG_PATH = '/etc/ubbf/config.json';
const RECORD_PATH = '/etc/ubbf/users-managed.json';
const RUNTIME_BASE = 10000;
const ID_MIN = 1000;
const ID_MAX = 60000;
const NAME_MAX = 32;
const PRIMARY_GROUP = 'users';
const NO_SHELL = '/bin/false';
const HOME = '/var';
const LOCKED = '!';
const LOCAL_ACCOUNT = 'admin';

const CRED_RATE_LIMIT_WINDOW = 60;
const CRED_RATE_LIMIT_MAX = 5;

let staged_passwords = {};

/**
 * Tests whether a string can be a Unix user or group name.
 *
 * @param {string} name - Candidate name
 * @returns {boolean} True for a valid name
 */
function name_valid(name) {
	return type(name) == 'string' && length(name) > 0 && length(name) <= NAME_MAX &&
		match(name, /^[a-z_][a-z0-9_-]*$/) != null;
}

/**
 * Returns a configuration table, or an empty object when it is missing.
 *
 * @param {object} table - Table object keyed by instance number
 * @returns {object} The table
 */
function rows_get(table) {
	return type(table) == 'object' ? table : {};
}

/**
 * Splits a comma-separated list of path references.
 *
 * @param {string} value - List value
 * @returns {array} Trimmed, non-empty items
 */
function refs_split(value) {
	let refs = map(split(value ?? '', ','), (s) => trim(s));
	return filter(refs, (s) => s != '');
}

/**
 * Returns the instance number of a reference to a Device.Users table row.
 *
 * @param {string} ref - Path reference, with or without trailing dot
 * @param {string} table - Table name: User, Group, Role or SupportedShell
 * @returns {number|null} Instance number, or null for another path
 */
function ref_instance(ref, table) {
	let m = match(ref ?? '', regexp(`^Device\\.Users\\.${table}\\.([0-9]+)\\.?$`));
	return m ? int(m[1]) : null;
}

/**
 * Converts a parameter value to a requested Unix id.
 *
 * @param {string} value - UserID or GroupID value
 * @returns {number|null} The id, or null when the agent chooses it
 */
function id_requested(value) {
	let id = int(value ?? '0');
	return (type(id) == 'int' && id > 0) ? id : null;
}

/**
 * Finds the lowest id at or above ID_MIN that no entry uses.
 *
 * @param {array} entries - passwd or group entries
 * @param {string} key - `uid` or `gid`
 * @returns {number} Free id
 */
function id_free(entries, key) {
	let used = {};
	for (let e in entries)
		used[e[key]] = true;

	let id = ID_MIN;
	while (used[id])
		id++;

	return id;
}

/**
 * Finds the entry whose field has a value.
 *
 * @param {array} entries - passwd, shadow or group entries
 * @param {string} key - Field name
 * @param {*} value - Value to look for
 * @returns {object|null} The entry
 */
function entry_find(entries, key, value) {
	for (let e in entries)
		if (e[key] == value)
			return e;

	return null;
}

/**
 * Lists the valid names of a configuration table.
 *
 * @param {object} rows - Table keyed by instance number
 * @param {string} key - Name parameter: Username or Groupname
 * @returns {object} Map of name to instance number string
 */
function names_index(rows, key) {
	let idx = {};
	for (let inst, row in rows)
		if (name_valid(row?.[key]))
			idx[row[key]] = inst;

	return idx;
}

/**
 * Reads the record of the accounts and groups this module created.
 *
 * @returns {object} `{ users, groups }`, each a map of instance to name
 */
function record_load() {
	let rec;

	try {
		rec = json(fs.readfile(RECORD_PATH) ?? '{}');
	} catch (e) {
		rec = null;
	}

	return {
		users: type(rec?.users) == 'object' ? rec.users : {},
		groups: type(rec?.groups) == 'object' ? rec.groups : {}
	};
}

/**
 * Reads the persisted configuration.
 *
 * @returns {object|null} The configuration
 */
function config_load() {
	try {
		return json(fs.readfile(CONFIG_PATH) ?? 'null');
	} catch (e) {
		return null;
	}
}

/**
 * Converts a HomeDirectory URL (RFC 8089) to a passwd home path. Only an
 * absolute path of plain characters is accepted: no percent-encoding, and
 * no `:` or newline, which would break /etc/passwd.
 *
 * @param {string} url - For example file:///home/user
 * @returns {string|null} Path, or null for an empty or invalid URL
 */
function home_path(url) {
	// ucode regexps match $ at the end of each line
	if (type(url) != 'string' || index(url, '\n') >= 0)
		return null;

	let m = match(url, /^file:\/\/(localhost)?(\/[A-Za-z0-9._~\/-]*)$/);
	return m ? m[2] : null;
}

/**
 * Converts a passwd home path to a HomeDirectory URL.
 *
 * @param {string} path - Home path from passwd
 * @returns {string} file:// URL, '' without a path
 */
function home_url(path) {
	return path ? `file://${path}` : '';
}

/**
 * Converts a shell path to a SupportedShell reference.
 *
 * @param {string} path - Login shell from passwd
 * @param {array} shells - Shells from /etc/shells
 * @returns {string} Reference, or empty for no shell access
 */
function shell_ref(path, shells) {
	let i = index(shells, path);
	return (i >= 0) ? sprintf('Device.Users.SupportedShell.%d', i + 1) : '';
}

/**
 * Converts a SupportedShell reference to a shell path.
 *
 * @param {string} ref - Reference, or empty for no shell access
 * @returns {string|null} Shell path, or null for an invalid reference
 */
function shell_path(ref) {
	if (ref == null || ref == '')
		return NO_SHELL;

	let n = ref_instance(ref, 'SupportedShell');
	if (n == null)
		return null;

	return ubbf.get_by_instance(users.shells_get(), n);
}

/**
 * Resolves a Group reference to a group name.
 *
 * @param {string} ref - Reference to a Device.Users.Group row
 * @param {object} group_rows - Configured groups
 * @param {array} gr - group entries
 * @returns {string|null} Group name
 */
function group_name_by_ref(ref, group_rows, gr) {
	let n = ref_instance(ref, 'Group');
	if (n == null)
		return null;

	if (n < RUNTIME_BASE) {
		let name = group_rows[sprintf('%d', n)]?.Groupname;
		return name_valid(name) ? name : null;
	}

	let entry = entry_find(gr, 'gid', n - RUNTIME_BASE);
	if (!entry || names_index(group_rows, 'Groupname')[entry.groupname])
		return null;

	return entry.groupname;
}

/**
 * Builds the GroupParticipation of a system account.
 *
 * @param {object} pw - passwd entry
 * @param {array} gr - group entries
 * @param {object} group_idx - Configured group name to instance
 * @returns {string} Comma-separated references
 */
function group_refs_build(pw, gr, group_idx) {
	let refs = [];

	for (let g in gr) {
		if (g.gid != pw.gid && index(g.members ?? [], pw.username) < 0)
			continue;

		let inst = group_idx[g.groupname] ?? sprintf('%d', RUNTIME_BASE + g.gid);
		push(refs, `Device.Users.Group.${inst}`);
	}

	return join(',', refs);
}

/**
 * Converts a system account to a TR-181 User object.
 *
 * @param {object} pw - passwd entry
 * @param {object} sp_map - Username to shadow entry
 * @param {array} gr - group entries
 * @param {object} group_idx - Configured group name to instance
 * @param {array} shells - Shells from /etc/shells
 * @returns {object} TR-181 User object
 */
function system_user_to_object(pw, sp_map, gr, group_idx, shells) {
	let hash = sp_map[pw.username]?.hash ?? '';

	return {
		Alias: sprintf('cpe-User-%s', pw.username),
		Enable: (substr(hash, 0, 1) == LOCKED) ? 'false' : 'true',
		UserID: sprintf('%d', pw.uid),
		Username: pw.username,
		Password: '',
		GroupParticipation: group_refs_build(pw, gr, group_idx),
		RoleParticipation: '',
		StaticUser: 'true',
		Language: '',
		Shell: shell_ref(pw.shell, shells),
		HomeDirectory: home_url(pw.home)
	};
}

/**
 * Converts a system group to a TR-181 Group object.
 *
 * @param {object} g - group entry
 * @returns {object} TR-181 Group object
 */
function system_group_to_object(g) {
	return {
		Alias: sprintf('cpe-Group-%s', g.groupname),
		Enable: 'true',
		GroupID: sprintf('%d', g.gid),
		Groupname: g.groupname,
		RoleParticipation: '',
		StaticGroup: 'true'
	};
}

/**
 * Converts a SupportedShell path to a TR-181 object.
 *
 * @param {string} shell - Shell path
 * @returns {object} TR-181 SupportedShell object
 */
function shell_to_object(shell) {
	return {
		Alias: sprintf('cpe-Shell-%s', replace(shell, /\//g, '-')),
		Enable: 'true',
		Name: shell
	};
}

/**
 * Builds the rows of the system accounts.
 *
 * @param {object} root - Configuration tree
 * @returns {object} Rows keyed by RUNTIME_BASE plus uid
 */
function system_users_get(root) {
	let user_idx = names_index(rows_get(root?.Device?.Users?.User), 'Username');
	let group_idx = names_index(rows_get(root?.Device?.Users?.Group), 'Groupname');
	let gr = users.group_get_all() ?? [];
	let shells = users.shells_get();
	let sp_map = {};
	let rows = {};

	for (let sp in users.shadow_get_all() ?? [])
		sp_map[sp.username] = sp;

	for (let pw in users.passwd_get_all() ?? []) {
		if (user_idx[pw.username])
			continue;

		rows[sprintf('%d', RUNTIME_BASE + pw.uid)] =
			system_user_to_object(pw, sp_map, gr, group_idx, shells);
	}

	return rows;
}

/**
 * Builds the rows of the system groups.
 *
 * @param {object} root - Configuration tree
 * @returns {object} Rows keyed by RUNTIME_BASE plus gid
 */
function system_groups_get(root) {
	let group_idx = names_index(rows_get(root?.Device?.Users?.Group), 'Groupname');
	let rows = {};

	for (let g in users.group_get_all() ?? []) {
		if (group_idx[g.groupname])
			continue;

		rows[sprintf('%d', RUNTIME_BASE + g.gid)] = system_group_to_object(g);
	}

	return rows;
}

/**
 * Get handler for Device.Users.
 *
 * @param {object} ctx - Context with the configuration tree
 * @returns {object} Users container properties
 */
function users_container_get(ctx) {
	let cfg = ctx.root?.Device?.Users;

	return {
		UserNumberOfEntries: sprintf('%d', length(rows_get(cfg?.User)) + length(system_users_get(ctx.root))),
		GroupNumberOfEntries: sprintf('%d', length(rows_get(cfg?.Group)) + length(system_groups_get(ctx.root))),
		RoleNumberOfEntries: sprintf('%d', length(rows_get(cfg?.Role))),
		SupportedShellNumberOfEntries: sprintf('%d', length(users.shells_get())),
		SupportedCapabilities: ''
	};
}

/**
 * Get handler for Device.Users.User.{i}: a configured account, or the
 * system accounts.
 *
 * @param {object} ctx - Context with config, instance and root
 * @returns {object|null} Single user or the system users
 */
function user_get(ctx) {
	if (ctx.config) {
		let pw = name_valid(ctx.config.Username) ? users.passwd_get_by_name(ctx.config.Username) : null;

		return {
			...ctx.config,
			UserID: pw ? sprintf('%d', pw.uid) : (ctx.config.UserID ?? '0'),
			HomeDirectory: pw ? home_url(pw.home) : (ctx.config.HomeDirectory ?? ''),
			Password: '',
			StaticUser: 'false'
		};
	}

	let rows = system_users_get(ctx.root);
	if (ctx.instance == null)
		return rows;

	return rows[sprintf('%d', ctx.instance)];
}

/**
 * Get handler for Device.Users.Group.{i}: a configured group, or the system
 * groups.
 *
 * @param {object} ctx - Context with config, instance and root
 * @returns {object|null} Single group or the system groups
 */
function group_get(ctx) {
	if (ctx.config) {
		let g = name_valid(ctx.config.Groupname) ? users.group_get_by_name(ctx.config.Groupname) : null;

		return {
			...ctx.config,
			GroupID: g ? sprintf('%d', g.gid) : (ctx.config.GroupID ?? '0'),
			StaticGroup: 'false'
		};
	}

	let rows = system_groups_get(ctx.root);
	if (ctx.instance == null)
		return rows;

	return rows[sprintf('%d', ctx.instance)];
}

/**
 * Get handler for Device.Users.Role.{i}. The roles are configuration only.
 *
 * @param {object} ctx - Context with config and instance
 * @returns {object|null} The role
 */
function role_get(ctx) {
	if (ctx.config)
		return { ...ctx.config };

	return (ctx.instance == null) ? {} : null;
}

/**
 * Get handler for Device.Users.SupportedShell.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single shell or enumerated shells
 */
function shell_get(ctx) {
	let shells = users.shells_get();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(shells, shell_to_object);

	let shell = ubbf.get_by_instance(shells, ctx.instance);
	if (!shell)
		return null;

	return shell_to_object(shell);
}

/**
 * Checks a new account or group name.
 *
 * A name that a system account or group already has is refused, because the
 * commit hook does not take over an entry it did not create.
 *
 * @param {string} value - New name
 * @param {string} inst - Instance number of the row
 * @param {object} rows - Configured rows
 * @param {string} key - Username or Groupname
 * @param {object} owned - Record of names, instance to name
 * @param {object|null} existing - The passwd or group entry with that name
 * @returns {number} 0, or a negative USP error code
 */
function name_check(value, inst, rows, key, owned, existing) {
	if (value == '')
		return 0;
	if (!name_valid(value))
		return -USP_ERR_INVALID_VALUE;

	for (let i, row in rows)
		if (i != inst && row?.[key] == value)
			return -USP_ERR_UNIQUE_KEY_CONFLICT;

	if (existing && index(values(owned), value) < 0)
		return -USP_ERR_UNIQUE_KEY_CONFLICT;

	return 0;
}

/**
 * Checks a new UserID or GroupID.
 *
 * @param {string} value - New id, "0" lets the agent choose
 * @param {string} name - Current name of the row
 * @param {array} entries - passwd or group entries
 * @param {string} id_key - `uid` or `gid`
 * @param {string} name_key - `username` or `groupname`
 * @returns {number} 0, or a negative USP error code
 */
function id_check(value, name, entries, id_key, name_key) {
	let id = id_requested(value);
	if (id == null)
		return 0;
	if (id < ID_MIN || id >= ID_MAX)
		return -USP_ERR_INVALID_VALUE;

	let entry = entry_find(entries, id_key, id);
	if (entry && entry[name_key] != name)
		return -USP_ERR_UNIQUE_KEY_CONFLICT;

	return 0;
}

/**
 * Checks that every item of a reference list names an existing row.
 *
 * @param {string} value - Comma-separated references
 * @param {string} table - Group or Role
 * @param {object} root - Configuration tree
 * @returns {number} 0, or a negative USP error code
 */
function refs_check(value, table, root) {
	let cfg = root?.Device?.Users;
	let gr = (table == 'Group') ? (users.group_get_all() ?? []) : null;

	for (let ref in refs_split(value)) {
		if (table == 'Group' && group_name_by_ref(ref, rows_get(cfg?.Group), gr) != null)
			continue;
		if (table == 'Role' && rows_get(cfg?.Role)[sprintf('%d', ref_instance(ref, 'Role') ?? 0)])
			continue;

		return -USP_ERR_INVALID_VALUE;
	}

	return 0;
}

/**
 * Tells whether an account may have an empty password: TR-181
 * UserInterface.PasswordRequired false leaves the choice to the user.
 * Root never may, because the dropbear of OpenWrt accepts a blank root
 * password (patch 600-allow-blank-root-password).
 *
 * @param {object} root - Configuration tree of the write
 * @param {string} inst - Instance number of the row
 * @returns {boolean} True when an empty password is allowed
 */
function password_optional(root, inst) {
	let required = root?.Device?.UserInterface?.PasswordRequired ?? 'true';
	let row = root?.Device?.Users?.User?.[inst];

	return !ubbf.to_bool(required) && row?.Username != null && row.Username != 'root';
}

/**
 * Hashes a new password and keeps it for the commit hook. The plain text
 * leaves the configuration at once. An empty password locks the account,
 * unless the account may have an empty one.
 *
 * @param {object} ctx - Set context
 * @param {string} inst - Instance number of the row
 * @returns {number} 0, or a negative USP error code
 */
function password_stage(ctx, inst) {
	let empty = ctx.value == null || ctx.value == '';
	let hash = (empty && !password_optional(ctx.root, inst)) ? LOCKED : users.password_hash(ctx.value ?? '');
	if (!hash) {
		utils.logging.log_err('users: password hashing failed for User.%s', inst);
		return -USP_ERR_INTERNAL_ERROR;
	}

	staged_passwords[inst] = hash;

	let row = ctx.root?.Device?.Users?.User?.[inst];
	if (row)
		row.Password = '';

	return 0;
}

/**
 * Set handler for Device.LANConfigSecurity: ConfigPassword is the password of
 * the local account admin, staged as for a Password set. TR-181 makes it the
 * password of the local user interface while UserInterface
 * .PasswordUserSelectable is absent, which it is on a CPE without LAN-side
 * auto-configuration (TR-064). The stored value is cleared at once.
 *
 * @param {object} ctx - Context with param, value and root
 * @returns {number} 0, or a negative USP error code
 */
function lanconfigsecurity_set(ctx) {
	if (ctx.param != 'ConfigPassword' || !ctx.value)
		return 0;

	for (let inst, row in rows_get(ctx.root?.Device?.Users?.User)) {
		if (row?.Username != LOCAL_ACCOUNT)
			continue;

		let rc = password_stage({ value: ctx.value, root: ctx.root }, inst);
		if (rc == 0 && ctx.root?.Device?.LANConfigSecurity)
			ctx.root.Device.LANConfigSecurity.ConfigPassword = '';

		return rc;
	}

	return -USP_ERR_INVALID_VALUE;
}

/**
 * Set handler for Device.Users.User.{i}.
 *
 * @param {object} ctx - Context with param, value, instance, config and root
 * @returns {number} 0 on success, a negative USP error code to refuse
 */
function user_set(ctx) {
	let inst = sprintf('%d', ctx.instance);
	let rows = rows_get(ctx.root?.Device?.Users?.User);

	switch (ctx.param) {
	case 'Username':
		return name_check(ctx.value, inst, rows, 'Username', record_load().users,
			users.passwd_get_by_name(ctx.value));
	case 'UserID':
		return id_check(ctx.value, ctx.config?.Username, users.passwd_get_all() ?? [],
			'uid', 'username');
	case 'Password':
		return password_stage(ctx, inst);
	case 'Shell':
		return (shell_path(ctx.value) != null) ? 0 : -USP_ERR_INVALID_VALUE;
	case 'HomeDirectory':
		return (ctx.value == '' || home_path(ctx.value) != null) ? 0 : -USP_ERR_INVALID_VALUE;
	case 'GroupParticipation':
		return refs_check(ctx.value, 'Group', ctx.root);
	case 'RoleParticipation':
		return refs_check(ctx.value, 'Role', ctx.root);
	}

	return 0;
}

/**
 * Set handler for Device.Users.Group.{i}.
 *
 * @param {object} ctx - Context with param, value, instance, config and root
 * @returns {number} 0 on success, a negative USP error code to refuse
 */
function group_set(ctx) {
	let inst = sprintf('%d', ctx.instance);
	let rows = rows_get(ctx.root?.Device?.Users?.Group);

	switch (ctx.param) {
	case 'Groupname':
		return name_check(ctx.value, inst, rows, 'Groupname', record_load().groups,
			users.group_get_by_name(ctx.value));
	case 'GroupID':
		return id_check(ctx.value, ctx.config?.Groupname, users.group_get_all() ?? [],
			'gid', 'groupname');
	case 'RoleParticipation':
		return refs_check(ctx.value, 'Role', ctx.root);
	}

	return 0;
}

/**
 * Set handler for Device.Users.Role.{i}. The name of a static role selects
 * its access rights, so it cannot change.
 *
 * @param {object} ctx - Context with param, value and config
 * @returns {number} 0 on success, a negative USP error code to refuse
 */
function role_set(ctx) {
	switch (ctx.param) {
	case 'RoleName':
		return (ctx.config?.StaticRole == 'true') ? -USP_ERR_PARAM_READ_ONLY : 0;
	case 'RequiredCapabilities':
		return (length(refs_split(ctx.value)) > 0) ? -USP_ERR_INVALID_VALUE : 0;
	}

	return 0;
}

/**
 * Delete hook for Device.Users.User.{i} and Device.Users.Group.{i}: a
 * system row is static and cannot be removed.
 *
 * @param {object} ctx - `{ path, instance }`
 * @returns {number|null} Refusal, or null to delete the configured row
 */
function system_row_del(ctx) {
	return (ctx.instance >= RUNTIME_BASE) ? -USP_ERR_OBJECT_NOT_DELETABLE : null;
}

/**
 * Delete hook for Device.Users.Role.{i}: every role is static.
 *
 * @param {object} ctx - `{ path, instance }`
 * @returns {number} Refusal
 */
function role_del(ctx) {
	return -USP_ERR_OBJECT_NOT_DELETABLE;
}

/**
 * Brings the configured groups into the group entries.
 *
 * @param {object} state - `{ pw, sp, gr }` entries, changed in place
 * @param {object} rows - Configured groups
 * @param {object} owned - Record of group names, instance to name
 * @returns {object} The new record, instance to name
 */
function groups_sync(state, rows, owned) {
	let names = {};

	for (let inst, row in rows) {
		let name = row?.Groupname;
		if (!name_valid(name))
			continue;

		let old = owned[inst];
		let entry = (old && old != name && !entry_find(state.gr, 'groupname', name))
			? entry_find(state.gr, 'groupname', old) : null;
		let renamed = !!entry;
		if (renamed)
			entry.groupname = name;
		else
			entry = entry_find(state.gr, 'groupname', name);

		if (entry && !renamed && index(values(owned), name) < 0) {
			utils.logging.log_err('users: group %s exists already, Group.%s not applied', name, inst);
			continue;
		}

		let gid = id_requested(row.GroupID);
		if (!entry) {
			entry = { groupname: name, gid: gid ?? id_free(state.gr, 'gid'), members: [] };
			push(state.gr, entry);
		} else if (gid != null) {
			entry.gid = gid;
		}

		names[inst] = name;
	}

	for (let inst, name in owned)
		if (index(values(names), name) < 0)
			state.gr = filter(state.gr, (g) => g.groupname != name);

	return names;
}

/**
 * Renames an account in the passwd, shadow and group entries.
 *
 * @param {object} state - `{ pw, sp, gr }` entries, changed in place
 * @param {string} old - Current name
 * @param {string} name - New name
 * @returns {boolean} True when the account existed
 */
function user_rename(state, old, name) {
	let pw = entry_find(state.pw, 'username', old);
	if (!pw || entry_find(state.pw, 'username', name))
		return false;

	pw.username = name;

	let sp = entry_find(state.sp, 'username', old);
	if (sp)
		sp.username = name;

	for (let g in state.gr)
		g.members = map(g.members ?? [], (m) => (m == old) ? name : m);

	return true;
}

/**
 * Creates an account with the initial password of its row, if it has one.
 *
 * @param {object} state - `{ pw, sp, gr }` entries, changed in place
 * @param {string} name - Username
 * @param {object} row - Configured row
 * @param {number} gid - Primary group id
 */
function user_create(state, name, row, gid) {
	let initial = (type(row.Password) == 'string' && row.Password != '') ? users.password_hash(row.Password) : null;

	push(state.pw, {
		username: name,
		uid: id_requested(row.UserID) ?? id_free(state.pw, 'uid'),
		gid,
		gecos: '',
		home: home_path(row.HomeDirectory) ?? HOME,
		shell: shell_path(row.Shell) ?? NO_SHELL
	});

	push(state.sp, {
		username: name,
		hash: initial ?? LOCKED,
		lastchanged: int(time() / 86400),
		min: 0,
		max: 99999,
		warn: 7,
		inactive: -1,
		expire: -1
	});
}

/**
 * Brings the configured accounts into the passwd and shadow entries.
 *
 * @param {object} state - `{ pw, sp, gr }` entries, changed in place
 * @param {object} rows - Configured users
 * @param {object} owned - Record of usernames, instance to name
 * @returns {object} The new record, instance to name
 */
function users_sync(state, rows, owned) {
	let names = {};
	let gid = entry_find(state.gr, 'groupname', PRIMARY_GROUP)?.gid ?? 100;

	for (let inst, row in rows) {
		let name = row?.Username;
		if (!name_valid(name))
			continue;

		let old = owned[inst];
		let renamed = (old && old != name) ? user_rename(state, old, name) : false;

		let pw = entry_find(state.pw, 'username', name);
		if (pw && !renamed && index(values(owned), name) < 0) {
			utils.logging.log_err('users: account %s exists already, User.%s not applied', name, inst);
			continue;
		}

		if (!pw) {
			user_create(state, name, row, gid);
		} else {
			pw.shell = shell_path(row.Shell) ?? pw.shell;
			pw.home = home_path(row.HomeDirectory) ?? pw.home;
			pw.uid = id_requested(row.UserID) ?? pw.uid;
		}

		names[inst] = name;
	}

	for (let inst, name in owned) {
		if (index(values(names), name) >= 0)
			continue;

		state.pw = filter(state.pw, (e) => e.username != name);
		state.sp = filter(state.sp, (e) => e.username != name);
		for (let g in state.gr)
			g.members = filter(g.members ?? [], (m) => m != name);
	}

	return names;
}

/**
 * Writes the staged password hashes and the Enable state into the shadow
 * entries. A locked entry keeps its hash behind the lock mark.
 *
 * @param {object} state - `{ pw, sp, gr }` entries, changed in place
 * @param {object} rows - Configured users
 * @param {object} names - Instance to username
 */
function shadow_sync(state, rows, names) {
	for (let inst, name in names) {
		let sp = entry_find(state.sp, 'username', name);
		if (!sp)
			continue;

		if (staged_passwords[inst]) {
			sp.hash = staged_passwords[inst];
			sp.lastchanged = int(time() / 86400);
		}

		let hash = sp.hash ?? '';
		let locked = substr(hash, 0, 1) == LOCKED;

		if (rows[inst]?.Enable == 'true' && locked && length(hash) > 1)
			sp.hash = substr(hash, 1);
		else if (rows[inst]?.Enable != 'true' && !locked)
			sp.hash = LOCKED + hash;
	}
}

/**
 * Sets the supplementary groups of the configured accounts from their
 * GroupParticipation. Members that this module does not manage stay.
 *
 * @param {object} state - `{ pw, sp, gr }` entries, changed in place
 * @param {object} rows - Configured users
 * @param {object} group_rows - Configured groups
 * @param {object} names - Instance to username
 */
function members_sync(state, rows, group_rows, names) {
	let wanted = {};

	for (let inst, name in names) {
		for (let ref in refs_split(rows[inst]?.GroupParticipation)) {
			let group = group_name_by_ref(ref, group_rows, state.gr);
			if (group == null)
				continue;

			wanted[group] ??= [];
			push(wanted[group], name);
		}
	}

	let managed = values(names);

	for (let g in state.gr) {
		let kept = filter(g.members ?? [], (m) => index(managed, m) < 0);
		g.members = [ ...kept, ...(wanted[g.groupname] ?? []) ];
	}
}

/**
 * Returns the password the device uses towards its ACS: the CWMP ACS
 * password (ManagementServer.Password, stored as cwmp.acs.password), else
 * the MQTT password of the USP controller connection (obuspa.acs.password).
 *
 * @returns {string|null} The password, or null when none is set
 */
function acs_password_get() {
	let cursor = uci.cursor();

	for (let source in [ [ 'cwmp', 'acs' ], [ 'obuspa', 'acs' ] ]) {
		if (!cursor.load(source[0]))
			continue;

		let password = cursor.get(source[0], source[1], 'password');
		if (type(password) == 'string' && password != '')
			return password;
	}

	return null;
}

/**
 * Gives root the ACS password (WAN SSH uses root and the ACS
 * password). Root stays a read-only system account in Device.Users; its
 * lock state does not change. Without an ACS password root keeps its own.
 *
 * @param {object} state - `{ pw, sp, gr }` entries, changed in place
 */
function root_sync(state) {
	let password = acs_password_get();
	let sp = entry_find(state.sp, 'username', 'root');
	if (!password || !sp)
		return;

	let hash = sp.hash ?? '';
	let lock = (substr(hash, 0, 1) == LOCKED) ? LOCKED : '';
	let bare = substr(hash, length(lock));

	if (bare != '' && users.crypt(password, bare) == bare)
		return;

	let fresh = users.password_hash(password);
	if (!fresh) {
		utils.logging.log_err('users: password hashing failed for root');
		return;
	}

	sp.hash = lock + fresh;
	sp.lastchanged = int(time() / 86400);
}

/**
 * Returns the entries when they differ from the state before the sync.
 *
 * @param {array} entries - New entries
 * @param {string} before - JSON of the entries before the sync
 * @returns {array|null} The entries, or null when they did not change
 */
function entries_changed(entries, before) {
	return (sprintf('%J', entries) == before) ? null : entries;
}

/**
 * Commit hook: makes the system accounts match the configured users and
 * groups. It writes only what differs, so a run with nothing to change
 * touches no file.
 */
function accounts_sync() {
	let cfg = config_load()?.Device?.Users;
	if (type(cfg) != 'object') {
		staged_passwords = {};
		return;
	}

	let state = {
		pw: users.passwd_get_all() ?? [],
		sp: users.shadow_get_all() ?? [],
		gr: users.group_get_all() ?? []
	};
	let before = {
		pw: sprintf('%J', state.pw),
		sp: sprintf('%J', state.sp),
		gr: sprintf('%J', state.gr)
	};

	let user_rows = rows_get(cfg.User);
	let group_rows = rows_get(cfg.Group);
	let owned = record_load();

	let record = {
		groups: groups_sync(state, group_rows, owned.groups),
		users: users_sync(state, user_rows, owned.users)
	};

	shadow_sync(state, user_rows, record.users);
	members_sync(state, user_rows, group_rows, record.users);
	root_sync(state);

	// The three files change together or not at all. On a failure the
	// staged passwords stay, so the next commit tries again.
	let changed = {
		group: entries_changed(state.gr, before.gr),
		passwd: entries_changed(state.pw, before.pw),
		shadow: entries_changed(state.sp, before.sp)
	};
	if ((changed.group || changed.passwd || changed.shadow) && !users.accounts_set(changed)) {
		utils.logging.log_err('users: failed to write the account files, they are unchanged');
		return;
	}

	staged_passwords = {};

	if (sprintf('%J', record) != sprintf('%J', owned))
		fs.writefile(RECORD_PATH, sprintf('%.J\n', record));
}

/**
 * Precommit hook: refuses a commit when /etc cannot hold new copies of the
 * account files, which accounts_sync() writes before it renames them; the
 * commit hook could not report that failure.
 *
 * @returns {string|null} Reason to refuse the commit, or null
 */
function accounts_space_check() {
	let need = 12;
	for (let path in [ '/etc/passwd', '/etc/shadow', '/etc/group' ])
		need += ((fs.stat(path)?.size ?? 0) + 1023) / 1024;

	let avail = ubbf.statvfs_info('/etc')?.avail_kib;
	if (avail != null && avail < need)
		return sprintf('/etc has %d KiB free, the account files need %d KiB', avail, need);

	return null;
}

/**
 * Abort hook: drops the passwords of an abandoned transaction.
 */
function staged_drop() {
	staged_passwords = {};
}

/**
 * Handler for Device.Users.CheckCredentialsDiagnostics() operation.
 *
 * @param {object} input - Operation input { Username, Password }
 * @param {string} command_key - Command tracking key
 * @param {object} root - Root config
 * @returns {object} Result with Status field
 */
function check_credentials_handler(input, command_key, root) {
	let username = input?.Username ?? '';
	let password = input?.Password ?? '';

	if (username == '' || password == '')
		return { Status: 'Credentials_Missing' };

	if (!users.rate_limit_check(`cred:${username}`, CRED_RATE_LIMIT_MAX, CRED_RATE_LIMIT_WINDOW)) {
		utils.logging.log_err('check_credentials: rate limited for user %s', username);
		return { Status: 'Credentials_Bad_Requested_Username_Not_Supported' };
	}

	return { Status: users.credentials_check(username, password) };
}

on_precommit(accounts_space_check);
on_commit(accounts_sync);
on_abort(staged_drop);

model['Device.LANConfigSecurity'] = {
	schema: schema('LANConfigSecurity'),
	set: lanconfigsecurity_set
};

model['Device.Users'] = {
	schema: schema('Users'),
	get: users_container_get
};

model['Device.Users.User'] = {};

model['Device.Users.User.{i}'] = {
	schema: schema('User'),
	get: user_get,
	set: user_set,
	del: system_row_del,
	runtime_instances: true
};

model['Device.Users.Group'] = {};

model['Device.Users.Group.{i}'] = {
	schema: schema('Group'),
	get: group_get,
	set: group_set,
	del: system_row_del,
	runtime_instances: true
};

model['Device.Users.Role'] = {};

model['Device.Users.Role.{i}'] = {
	schema: schema('Role'),
	get: role_get,
	set: role_set,
	del: role_del,
	addable: false
};

model['Device.Users.SupportedShell'] = {};

model['Device.Users.SupportedShell.{i}'] = {
	schema: schema('SupportedShell'),
	get: shell_get,
	addable: false
};

operations['Device.Users.CheckCredentialsDiagnostics()'] = {
	type: 'sync',
	handler: check_credentials_handler
};
