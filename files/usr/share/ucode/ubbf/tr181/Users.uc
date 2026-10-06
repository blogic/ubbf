'use strict';

import {
	passwd_get_all, shadow_get_all, group_get_all,
	group_set as group_set_raw,
	is_static_user, is_static_group, is_role_group,
	shells_get, user_groups_find,
	password_hash, credentials_check,
	user_add, user_del, user_update_field,
	shadow_update_hash, shadow_set_locked,
	group_add, group_del, group_members_update
} from 'users';
import * as schemas from 'ubbf.schemas.Users';
import { log_err } from 'ubbf.utils.logging';
import * as ubbf from 'ubbf';

/**
 * Builds a group index map from groupname to instance number.
 *
 * @param {array} groups - Array of group objects
 * @returns {object} Map of groupname → instance number string
 */
function group_index_build(groups) {
	let idx = {};
	for (let i = 0; i < length(groups); i++)
		idx[groups[i].groupname] = sprintf('%d', i + 1);
	return idx;
}

/**
 * Builds a role index map from groupname to role instance number.
 *
 * @param {array} groups - Array of group objects
 * @returns {object} Map of groupname → role instance number string
 */
function role_index_build(groups) {
	let idx = {};
	let n = 0;
	for (let gr in groups) {
		if (!is_role_group(gr.groupname))
			continue;
		n++;
		idx[gr.groupname] = sprintf('%d', n);
	}
	return idx;
}

/**
 * Builds a shell index map from path to instance number.
 *
 * @param {array} shells - Array of shell path strings
 * @returns {object} Map of shell path → instance number string
 */
function shell_index_build(shells) {
	let idx = {};
	for (let i = 0; i < length(shells); i++)
		idx[shells[i]] = sprintf('%d', i + 1);
	return idx;
}

/**
 * Builds GroupParticipation CSV from a user's group memberships.
 *
 * @param {string} username - Username
 * @param {number} primary_gid - User's primary group ID from passwd
 * @param {array} groups - All group objects
 * @param {object} group_idx - Group index map
 * @returns {string} Comma-separated path references
 */
function group_participation_build(username, primary_gid, groups, group_idx) {
	let parts = [];
	for (let gr in groups) {
		let member = (gr.gid == primary_gid);

		if (!member && gr?.members) {
			for (let m in gr.members) {
				if (m == username) {
					member = true;
					break;
				}
			}
		}

		if (!member)
			continue;

		let idx = group_idx[gr.groupname];
		if (idx)
			push(parts, sprintf('Device.Users.Group.%s', idx));
	}
	return join(',', parts);
}

/**
 * Builds RoleParticipation CSV from a user's role memberships.
 *
 * @param {string} username - Username
 * @param {number} primary_gid - User's primary group ID from passwd
 * @param {array} groups - All group objects
 * @param {object} role_idx - Role index map
 * @returns {string} Comma-separated path references
 */
function role_participation_build(username, primary_gid, groups, role_idx) {
	let parts = [];
	for (let gr in groups) {
		if (!is_role_group(gr.groupname))
			continue;

		let member = (gr.gid == primary_gid);

		if (!member && gr?.members) {
			for (let m in gr.members) {
				if (m == username) {
					member = true;
					break;
				}
			}
		}

		if (!member)
			continue;

		let idx = role_idx[gr.groupname];
		if (idx)
			push(parts, sprintf('Device.Users.Role.%s', idx));
	}
	return join(',', parts);
}

/**
 * Converts a passwd/shadow entry to a TR-181 User object.
 *
 * @param {object} pw - Passwd entry
 * @param {object} shadow_map - Map of username → shadow entry
 * @param {array} groups - All group objects
 * @param {object} group_idx - Group index map
 * @param {object} role_idx - Role index map
 * @param {object} shell_idx - Shell index map
 * @returns {object} TR-181 User object
 */
function user_to_object(pw, shadow_map, groups, group_idx, role_idx, shell_idx) {
	let sp = shadow_map[pw.username];
	let hash = sp?.hash ?? '';
	let locked = (substr(hash, 0, 1) == '!');

	let shell_ref = '';
	if (pw.shell && shell_idx[pw.shell])
		shell_ref = sprintf('Device.Users.SupportedShell.%s', shell_idx[pw.shell]);

	return {
		Alias: sprintf('cpe-User-%s', pw.username),
		Enable: locked ? 'false' : 'true',
		UserID: sprintf('%d', pw.uid),
		Username: pw.username,
		Password: '',
		Shell: shell_ref,
		StaticUser: is_static_user(pw.username, pw.uid) ? 'true' : 'false',
		RemoteAccessCapable: 'false',
		Language: '',
		GroupParticipation: group_participation_build(pw.username, pw.gid, groups, group_idx),
		RoleParticipation: role_participation_build(pw.username, pw.gid, groups, role_idx)
	};
}

/**
 * Converts a group entry to a TR-181 Group object.
 *
 * @param {object} gr - Group entry
 * @param {object} role_idx - Role index map
 * @returns {object} TR-181 Group object
 */
function group_to_object(gr, role_idx) {
	let role_parts = [];
	if (is_role_group(gr.groupname)) {
		let idx = role_idx[gr.groupname];
		if (idx)
			push(role_parts, sprintf('Device.Users.Role.%s', idx));
	}

	return {
		Alias: sprintf('cpe-Group-%s', gr.groupname),
		Enable: 'true',
		GroupID: sprintf('%d', gr.gid),
		Groupname: gr.groupname,
		StaticGroup: is_static_group(gr.groupname, gr.gid) ? 'true' : 'false',
		RoleParticipation: join(',', role_parts)
	};
}

/**
 * Converts a group entry designated as a role to a TR-181 Role object.
 *
 * @param {object} gr - Group entry acting as a role
 * @returns {object} TR-181 Role object
 */
function role_to_object(gr) {
	return {
		Alias: sprintf('cpe-Role-%s', gr.groupname),
		Enable: 'true',
		RoleID: sprintf('%d', gr.gid),
		RoleName: gr.groupname,
		StaticRole: is_static_group(gr.groupname, gr.gid) ? 'true' : 'false',
		RequiredCapabilities: ''
	};
}

/**
 * Converts a shell path to a TR-181 SupportedShell object.
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
 * Fetches all system data needed for User enumeration.
 *
 * @returns {object} Combined system data
 */
function system_data_fetch() {
	let pw_entries = passwd_get_all();
	let sp_entries = shadow_get_all();
	let gr_entries = group_get_all();
	let shells = shells_get();

	let shadow_map = {};
	for (let sp in sp_entries)
		shadow_map[sp.username] = sp;

	return {
		passwd: pw_entries,
		shadow_map,
		groups: gr_entries,
		shells,
		group_idx: group_index_build(gr_entries),
		role_idx: role_index_build(gr_entries),
		shell_idx: shell_index_build(shells)
	};
}

/**
 * Filters group entries to those designated as roles.
 *
 * @param {array} groups - All group entries
 * @returns {array} Role group entries
 */
function roles_filter(groups) {
	return filter(groups, (gr) => is_role_group(gr.groupname));
}

/**
 * Get handler for Device.Users.
 *
 * @param {object} ctx - Context object
 * @returns {object} Users container properties
 */
function users_container_get(ctx) {
	let data = system_data_fetch();
	let roles = roles_filter(data.groups);

	return {
		UserNumberOfEntries: sprintf('%d', length(data.passwd)),
		GroupNumberOfEntries: sprintf('%d', length(data.groups)),
		RoleNumberOfEntries: sprintf('%d', length(roles)),
		SupportedShellNumberOfEntries: sprintf('%d', length(data.shells)),
		SupportedCapabilities: ''
	};
}

/**
 * Get handler for Device.Users.User.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single user or enumerated users
 */
function user_get(ctx) {
	let data = system_data_fetch();

	let converter = (pw) => user_to_object(pw, data.shadow_map, data.groups,
						data.group_idx, data.role_idx, data.shell_idx);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(data.passwd, converter);

	let pw = ubbf.get_by_instance(data.passwd, ctx.instance);
	if (!pw)
		return null;

	return converter(pw);
}

/**
 * Get handler for Device.Users.Group.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single group or enumerated groups
 */
function group_get(ctx) {
	let groups = group_get_all();
	let role_idx = role_index_build(groups);

	let converter = (gr) => group_to_object(gr, role_idx);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(groups, converter);

	let gr = ubbf.get_by_instance(groups, ctx.instance);
	if (!gr)
		return null;

	return converter(gr);
}

/**
 * Get handler for Device.Users.Role.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single role or enumerated roles
 */
function role_get(ctx) {
	let groups = group_get_all();
	let roles = roles_filter(groups);

	if (ctx.instance == null)
		return ubbf.enumerate_instances(roles, role_to_object);

	let role = ubbf.get_by_instance(roles, ctx.instance);
	if (!role)
		return null;

	return role_to_object(role);
}

/**
 * Get handler for Device.Users.SupportedShell.{i}.
 *
 * @param {object} ctx - Context with optional instance number
 * @returns {object|null} Single shell or enumerated shells
 */
function shell_get(ctx) {
	let shells = shells_get();

	if (ctx.instance == null)
		return ubbf.enumerate_instances(shells, shell_to_object);

	let shell = ubbf.get_by_instance(shells, ctx.instance);
	if (!shell)
		return null;

	return shell_to_object(shell);
}

/**
 * Resolves a username from a User instance number.
 *
 * @param {number} instance - 1-based instance number
 * @returns {string|null} Username or null
 */
function instance_to_username(instance) {
	let pw_entries = passwd_get_all();
	let pw = ubbf.get_by_instance(pw_entries, instance);
	return pw?.username ?? null;
}

/**
 * Set handler for Device.Users.User.{i}.
 *
 * @param {object} ctx - Context with param, value, root, instance
 * @returns {number} 0 on success, -1 on failure
 */
function user_set(ctx) {
	let username = instance_to_username(ctx.instance);
	if (!username)
		return -1;

	let pw = passwd_get_all();
	let entry = ubbf.get_by_instance(pw, ctx.instance);
	if (!entry)
		return -1;

	if (is_static_user(entry.username, entry.uid) &&
	    (ctx.param == 'Username' || ctx.param == 'UserID'))
		return -1;

	switch (ctx.param) {
	case 'Password':
		// An empty Password clears the credential (passwd -d): an empty
		// shadow hash field means "no password required". This lets the
		// data model restore the blank-password baseline, which a plain
		// no-op could not.
		if (!ctx.value || ctx.value == '') {
			if (!shadow_update_hash(username, '')) {
				log_err('user_set: failed to clear password for %s', username);
				return -1;
			}
			return 0;
		}

		let hash = password_hash(ctx.value);
		if (!hash) {
			log_err('user_set: password hashing failed for %s', username);
			return -1;
		}

		if (!shadow_update_hash(username, hash)) {
			log_err('user_set: failed to update shadow for %s', username);
			return -1;
		}

		/* Clear plaintext from config */
		let user_config = ctx.root?.Device?.Users?.User;
		if (user_config) {
			let inst_key = sprintf('%d', ctx.instance);
			if (user_config[inst_key])
				user_config[inst_key].Password = '';
		}
		return 0;

	case 'Enable':
		let locked = !ubbf.to_bool(ctx.value);
		if (!shadow_set_locked(username, locked)) {
			log_err('user_set: failed to set lock state for %s', username);
			return -1;
		}
		return 0;

	case 'Shell':
		/* Resolve shell path reference to actual path */
		let shells = shells_get();
		let shell_path = ctx.value;

		/* If value is a path reference like Device.Users.SupportedShell.1,
		 * resolve it to the actual shell path */
		let m = match(ctx.value, /Device\.Users\.SupportedShell\.(\d+)/);
		if (m) {
			let shell = ubbf.get_by_instance(shells, +m[1]);
			if (!shell)
				return -1;
			shell_path = shell;
		}

		/* Only allow shells that the system advertises in /etc/shells */
		let shell_allowed = false;
		for (let sh in shells) {
			if (sh == shell_path) {
				shell_allowed = true;
				break;
			}
		}
		if (!shell_allowed) {
			log_err('user_set: rejecting unsupported shell %s for %s', shell_path, username);
			return -1;
		}

		if (!user_update_field(username, 'shell', shell_path)) {
			log_err('user_set: failed to update shell for %s', username);
			return -1;
		}
		return 0;

	case 'GroupParticipation':
		/* Parse comma-separated path references and update group memberships */
		let groups = group_get_all();
		let group_idx = group_index_build(groups);

		/* Build reverse map: instance number → groupname */
		let idx_to_group = {};
		for (let gname in group_idx)
			idx_to_group[group_idx[gname]] = gname;

		/* Parse new participation list */
		let wanted_groups = {};
		if (ctx.value && ctx.value != '') {
			for (let ref in split(ctx.value, ',')) {
				ref = trim(ref);
				let m = match(ref, /Device\.Users\.Group\.(\d+)/);
				if (m && idx_to_group[m[1]])
					wanted_groups[idx_to_group[m[1]]] = true;
			}
		}

		/* The primary group comes from passwd, not the members list;
		 * it is always reported by the getter and cannot be granted
		 * or revoked through supplementary membership. */
		let primary_gid;
		for (let pw in passwd_get_all()) {
			if (pw.username == username) {
				primary_gid = pw.gid;
				break;
			}
		}

		/* Update each group's membership */
		let changed = false;
		for (let gr in groups) {
			if (primary_gid != null && gr.gid == primary_gid)
				continue;

			let is_member = false;
			for (let m in gr.members) {
				if (m == username) {
					is_member = true;
					break;
				}
			}

			let should_be = wanted_groups[gr.groupname] ?? false;

			if (should_be && !is_member) {
				push(gr.members, username);
				changed = true;
			} else if (!should_be && is_member) {
				gr.members = filter(gr.members, (m) => m != username);
				changed = true;
			}
		}

		if (changed && !group_set_raw(groups)) {
			log_err('user_set: failed to update group memberships for %s', username);
			return -1;
		}
		return 0;

	case 'RoleParticipation':
		/* Roles are role-flagged groups; participation is membership in
		 * those groups, keyed by the Role.{i} instance space. */
		let all_groups = group_get_all();
		let r_idx = role_index_build(all_groups);
		let r_idx_to_group = {};
		for (let gname in r_idx)
			r_idx_to_group[r_idx[gname]] = gname;

		let wanted_roles = {};
		if (ctx.value && ctx.value != '') {
			for (let ref in split(ctx.value, ',')) {
				let rm = match(trim(ref), /Device\.Users\.Role\.(\d+)/);
				if (rm && r_idx_to_group[rm[1]])
					wanted_roles[r_idx_to_group[rm[1]]] = true;
			}
		}

		let r_changed = false;
		for (let gr in all_groups) {
			if (!is_role_group(gr.groupname))
				continue;

			let is_member = index(gr.members, username) >= 0;
			let should_be = wanted_roles[gr.groupname] ?? false;

			if (should_be && !is_member) {
				push(gr.members, username);
				r_changed = true;
			} else if (!should_be && is_member) {
				gr.members = filter(gr.members, (m) => m != username);
				r_changed = true;
			}
		}

		if (r_changed && !group_set_raw(all_groups)) {
			log_err('user_set: failed to update role memberships for %s', username);
			return -1;
		}
		return 0;

	case 'Username':
	case 'UserID':
	case 'RemoteAccessCapable':
	case 'Language':
		/* No backing store: Username/UserID renaming is unsupported and
		 * RemoteAccessCapable/Language have no representation in
		 * passwd/shadow. Reject rather than silently accepting a write
		 * that the getter will never reflect. */
		log_err('user_set: %s is not writable on this device', ctx.param);
		return -USP_ERR_PARAM_READ_ONLY;
	}

	return 0;
}

/**
 * Set handler for Device.Users.Group.{i}.
 *
 * @param {object} ctx - Context with param, value, instance
 * @returns {number} 0 on success, -1 on failure
 */
function group_set_handler(ctx) {
	let groups = group_get_all();
	let gr = ubbf.get_by_instance(groups, ctx.instance);
	if (!gr)
		return -1;

	if (is_static_group(gr.groupname, gr.gid) &&
	    (ctx.param == 'Groupname' || ctx.param == 'GroupID'))
		return -1;

	switch (ctx.param) {
	case 'Groupname':
		gr.groupname = ctx.value;
		return group_set_raw(groups) ? 0 : -1;

	case 'GroupID':
		gr.gid = +ctx.value;
		return group_set_raw(groups) ? 0 : -1;
	}

	return 0;
}

const CRED_RATE_LIMIT_WINDOW = 60;
const CRED_RATE_LIMIT_MAX = 5;

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

	if (username == '')
		return { Status: 'Credentials_Bad_Requested_Username_Not_Supported' };

	if (!ubbf.rate_limit_check(`cred:${username}`, CRED_RATE_LIMIT_MAX, CRED_RATE_LIMIT_WINDOW)) {
		log_err('check_credentials: rate limited for user %s', username);
		return { Status: 'Credentials_Bad_Requested_Username_Not_Supported' };
	}

	return { Status: credentials_check(username, password) };
}

export const model = {
	'Device.Users': {
		schema: schemas.Users,
		get: users_container_get
	},

	'Device.Users.User': {
	},

	'Device.Users.User.{i}': {
		schema: schemas.User,
		get: user_get,
		set: user_set
	},

	'Device.Users.Group': {
	},

	'Device.Users.Group.{i}': {
		schema: schemas.Group,
		get: group_get,
		set: group_set_handler
	},

	'Device.Users.Role': {
	},

	'Device.Users.Role.{i}': {
		schema: schemas.Role,
		get: role_get
	},

	'Device.Users.SupportedShell': {
	},

	'Device.Users.SupportedShell.{i}': {
		schema: schemas.SupportedShell,
		get: shell_get
	}
};

export const operations = {
	'Device.Users.CheckCredentialsDiagnostics()': {
		type: 'sync',
		handler: check_credentials_handler
	}
};
