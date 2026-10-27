// Host test of the users module handler (Device.Users, User.{i}). The
// instance map numbers the system rows and lives in /tmp/ubbf, so run it in
// a private mount namespace from the repository root, with the native
// module built for the host; tests/users/ holds a stand-in for the native
// users module, tests/hosts/ one for udebug:
//   unshare -rm sh -c 'mount -t tmpfs none /tmp/ubbf && ucode \
//     -L "$PWD/tests/users/*.uc" -L "$PWD/tests/hosts/*.uc" \
//     -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/users.uc'
'use strict';

import { instance_numbers, instance_lookup, instance_floor } from 'ubbf.utils.instance-map';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

let precommit;
let etc_avail_kib = 1024;

const api = {
	ubbf: { statvfs_info: () => ({ avail_kib: etc_avail_kib }), to_bool: (v) => v === true || v == 'true' || v == '1' },
	utils: { 'instance-map': { instance_numbers, instance_lookup, instance_floor } },
	schema: (k) => k,
	on_commit: () => null,
	on_precommit: (cb) => { precommit = cb; },
	on_abort: () => null,
	operations: {},
	model: {}
};

global.USP_ERR_INVALID_VALUE = 7012;
global.USP_ERR_PARAM_READ_ONLY = 7013;
global.USP_ERR_UNIQUE_KEY_CONFLICT = 7025;
global.USP_ERR_OBJECT_NOT_DELETABLE = 7024;

include('../modules/users/handler.uc', { ubbf_module: api });

const user = api.model['Device.Users.User.{i}'];
const root = { Device: { Users: { User: { '1': { Username: 'alice' } } } } };

let system = user.get({ root });
check('system rows follow the configured rows, configured accounts skipped', keys(system), [ '2', '3' ]);
check('system account enabled', system['2'].Enable, 'true');
check('system account with a * hash is disabled', system['3'].Enable, 'false');
check('system HomeDirectory', system['2'].HomeDirectory, 'file:///root');
check('system Shell', system['2'].Shell, 'Device.Users.SupportedShell.1');
check('system GroupParticipation names the system group', system['2'].GroupParticipation, 'Device.Users.Group.1');
check('system row by instance', user.get({ root, instance: 2 }).Username, 'root');
check('a system row is not deletable', user.del({ path: 'Device.Users.User.2', instance: 2 }), -7024);
check('a configured row is deletable', user.del({ path: 'Device.Users.User.1', instance: 1 }), null);

let alice = user.get({ root, config: { Username: 'alice' } });
check('configured HomeDirectory from passwd', alice.HomeDirectory, 'file:///home/alice');
check('configured UserID from passwd', alice.UserID, '1000');

let absent = user.get({ root, config: { Username: 'bob', HomeDirectory: 'file:///srv/bob' } });
check('HomeDirectory before the commit', absent.HomeDirectory, 'file:///srv/bob');

check('UserNumberOfEntries', api.model['Device.Users'].get({ root }).UserNumberOfEntries, '3');

const role = api.model['Device.Users.Role.{i}'];
const roles = { Device: { Users: { Role: {
	'1': { RoleName: 'admin', RoleID: '1', StaticRole: 'true' },
	'4': { RoleName: 'extra', RoleID: '4', StaticRole: 'false' }
} } } };
check('RoleName of a static role is read-only',
	role.set({ param: 'RoleName', value: 'x', instance: 1, config: roles.Device.Users.Role['1'], root: roles }), -7013);
check('RoleName taken by another role',
	role.set({ param: 'RoleName', value: 'admin', instance: 4, config: roles.Device.Users.Role['4'], root: roles }), -7025);
check('RoleName unchanged',
	role.set({ param: 'RoleName', value: 'extra', instance: 4, config: roles.Device.Users.Role['4'], root: roles }), 0);
check('RoleID taken by another role',
	role.set({ param: 'RoleID', value: '1', instance: 4, config: roles.Device.Users.Role['4'], root: roles }), -7025);
check('RoleID free', role.set({ param: 'RoleID', value: '5', instance: 4, root: roles }), 0);

check('HomeDirectory accepted', user.set({ param: 'HomeDirectory', value: 'file://localhost/srv' }), 0);
check('HomeDirectory empty', user.set({ param: 'HomeDirectory', value: '' }), 0);
check('HomeDirectory relative', user.set({ param: 'HomeDirectory', value: 'file://srv' }), -7012);
check('HomeDirectory newline', user.set({ param: 'HomeDirectory', value: 'file:///a\n/b' }), -7012);

// An empty Password locks the account, unless PasswordRequired is false;
// root is locked in every case.
function empty_password(required, name) {
	let r = { Device: { UserInterface: { PasswordRequired: required }, Users: { User: { '1': { Username: name } } } } };
	global.hashed = [];
	let rc = user.set({ param: 'Password', value: '', instance: 1, root: r });
	return [ rc, global.hashed ];
}
check('empty password with PasswordRequired true locks', empty_password('true', 'alice'), [ 0, [] ]);
check('empty password with PasswordRequired false', empty_password('false', 'alice'), [ 0, [ '' ] ]);
check('empty password for root locks', empty_password('false', 'root'), [ 0, [] ]);

const check_credentials = api.operations['Device.Users.CheckCredentialsDiagnostics()'].handler;
check('credentials of a configured account',
	check_credentials({ Username: 'alice', Password: 'x' }, '', root).Status, 'Credentials_Good');
check('credentials of root, a system account',
	check_credentials({ Username: 'root', Password: 'x' }, '', root).Status,
	'Credentials_Bad_Requested_Username_Not_Supported');
check('credentials without a password',
	check_credentials({ Username: 'alice', Password: '' }, '', root).Status, 'Credentials_Missing');

check('precommit with room on /etc', precommit(), null);
etc_avail_kib = 4;
check('precommit refuses a full /etc', type(precommit()), 'string');

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
