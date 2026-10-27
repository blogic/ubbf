// Host test of the users module handler (Device.Users, User.{i}). The
// instance map numbers the system rows; the users stand-in of tests/lib
// gives the passwd, group and shadow entries, and uci comes from a mock.
'use strict';

import { describe, it, assert, mock, beforeEach } from 'utest';
import { state_clear } from 'test_env';
import * as ubbf_lib from 'ubbf';

global.USP_ERR_INVALID_VALUE = 7012;
global.USP_ERR_PARAM_READ_ONLY = 7013;
global.USP_ERR_UNIQUE_KEY_CONFLICT = 7025;
global.USP_ERR_OBJECT_NOT_DELETABLE = 7024;

const root = { Device: { Users: { User: { '1': { Username: 'alice' } } } } };

// The handler requires uci when it loads, so it loads after the mock.
// env.etc_avail_kib steers the free space on /etc, env.precommit holds the
// precommit hook of the handler.
function handler_load() {
	let env = { etc_avail_kib: 1024 };

	mock.global.patch('uci', { data: {} });
	env.api = {
		ubbf: proto({ statvfs_info: () => ({ avail_kib: env.etc_avail_kib }),
			to_bool: (v) => v === true || v == 'true' || v == '1' }, ubbf_lib),
		utils: {},
		schema: (k) => k,
		on_commit: () => null,
		on_precommit: (cb) => { env.precommit = cb; },
		on_abort: () => null,
		operations: {},
		model: {}
	};
	include('../modules/users/handler.uc', { ubbf_module: env.api });
	return env;
}

describe('users handler', () => {
	beforeEach(() => {
		state_clear();
		ubbf_lib.instance_map_own(true);
	});

	it('numbers the system rows after the configured rows', () => {
		const user = handler_load().api.model['Device.Users.User.{i}'];

		let system = user.get({ root });
		assert.match([ '2', '3' ], keys(system), 'system rows follow the configured rows, configured accounts skipped');
		assert.match('true', system['2'].Enable, 'system account enabled');
		assert.match('false', system['3'].Enable, 'system account with a * hash is disabled');
		assert.match('file:///root', system['2'].HomeDirectory, 'system HomeDirectory');
		assert.match('Device.Users.SupportedShell.1', system['2'].Shell, 'system Shell');
		assert.match('Device.Users.Group.1', system['2'].GroupParticipation, 'system GroupParticipation names the system group');
		assert.match('root', user.get({ root, instance: 2 }).Username, 'system row by instance');
		assert.match(-7024, user.del({ path: 'Device.Users.User.2', instance: 2 }), 'a system row is not deletable');
		assert.match(null, user.del({ path: 'Device.Users.User.1', instance: 1 }), 'a configured row is deletable');
	});

	it('reads the configured rows from passwd', () => {
		const model = handler_load().api.model;
		const user = model['Device.Users.User.{i}'];

		let alice = user.get({ root, config: { Username: 'alice' } });
		assert.match('file:///home/alice', alice.HomeDirectory, 'configured HomeDirectory from passwd');
		assert.match('1000', alice.UserID, 'configured UserID from passwd');

		let absent = user.get({ root, config: { Username: 'bob', HomeDirectory: 'file:///srv/bob' } });
		assert.match('file:///srv/bob', absent.HomeDirectory, 'HomeDirectory before the commit');

		assert.match('3', model['Device.Users'].get({ root }).UserNumberOfEntries, 'UserNumberOfEntries');
	});

	it('keeps RoleName and RoleID unique and static roles read-only', () => {
		const role = handler_load().api.model['Device.Users.Role.{i}'];
		const roles = { Device: { Users: { Role: {
			'1': { RoleName: 'admin', RoleID: '1', StaticRole: 'true' },
			'4': { RoleName: 'extra', RoleID: '4', StaticRole: 'false' }
		} } } };

		assert.match(-7013, role.set({ param: 'RoleName', value: 'x', instance: 1, config: roles.Device.Users.Role['1'], root: roles }),
			'RoleName of a static role is read-only');
		assert.match(-7025, role.set({ param: 'RoleName', value: 'admin', instance: 4, config: roles.Device.Users.Role['4'], root: roles }),
			'RoleName taken by another role');
		assert.match(0, role.set({ param: 'RoleName', value: 'extra', instance: 4, config: roles.Device.Users.Role['4'], root: roles }),
			'RoleName unchanged');
		assert.match(-7025, role.set({ param: 'RoleID', value: '1', instance: 4, config: roles.Device.Users.Role['4'], root: roles }),
			'RoleID taken by another role');
		assert.match(0, role.set({ param: 'RoleID', value: '5', instance: 4, root: roles }), 'RoleID free');
	});

	it('accepts only an absolute file URL as HomeDirectory', () => {
		const user = handler_load().api.model['Device.Users.User.{i}'];

		assert.match(0, user.set({ param: 'HomeDirectory', value: 'file://localhost/srv' }), 'HomeDirectory accepted');
		assert.match(0, user.set({ param: 'HomeDirectory', value: '' }), 'HomeDirectory empty');
		assert.match(-7012, user.set({ param: 'HomeDirectory', value: 'file://srv' }), 'HomeDirectory relative');
		assert.match(-7012, user.set({ param: 'HomeDirectory', value: 'file:///a\n/b' }), 'HomeDirectory newline');
	});

	// An empty Password locks the account, unless PasswordRequired is false;
	// root is locked in every case.
	it('locks the account for an empty Password', () => {
		const user = handler_load().api.model['Device.Users.User.{i}'];

		function empty_password(required, name) {
			let r = { Device: { UserInterface: { PasswordRequired: required }, Users: { User: { '1': { Username: name } } } } };
			global.hashed = [];
			let rc = user.set({ param: 'Password', value: '', instance: 1, root: r });
			return [ rc, global.hashed ];
		}

		assert.match([ 0, [] ], empty_password('true', 'alice'), 'empty password with PasswordRequired true locks');
		assert.match([ 0, [ '' ] ], empty_password('false', 'alice'), 'empty password with PasswordRequired false');
		assert.match([ 0, [] ], empty_password('false', 'root'), 'empty password for root locks');
	});

	it('checks the credentials of configured accounts only', () => {
		const check_credentials = handler_load().api.operations['Device.Users.CheckCredentialsDiagnostics()'].handler;

		assert.match('Credentials_Good', check_credentials({ Username: 'alice', Password: 'x' }, '', root).Status,
			'credentials of a configured account');
		assert.match('Credentials_Bad_Requested_Username_Not_Supported',
			check_credentials({ Username: 'root', Password: 'x' }, '', root).Status, 'credentials of root, a system account');
		assert.match('Credentials_Missing', check_credentials({ Username: 'alice', Password: '' }, '', root).Status,
			'credentials without a password');
	});

	it('refuses a commit when /etc is full', () => {
		let env = handler_load();

		assert.match(null, env.precommit(), 'precommit with room on /etc');
		env.etc_avail_kib = 4;
		assert.match('string', type(env.precommit()), 'precommit refuses a full /etc');
	});
});
