// Host test of the URI checks in modules/syslog/shared.uc
// (LogFile.{i}.FilePath, Source.{i}.UnixDomainSocket.Path).
'use strict';

import { describe, it, assert } from 'utest';

let syslog = {};
include('../modules/syslog/shared.uc', { syslog });

describe('syslog LogFile.{i}.FilePath', () => {
	it('accepts a file URI below /var/log', () => {
		assert.match('/var/log/messages', syslog.logfile_path('file:///var/log/messages'));
		assert.match('/var/log/a/b', syslog.logfile_path('file://localhost/var/log/a/b'));
	});

	it('rejects a path outside /var/log, a directory, .. and newlines', () => {
		assert.match(null, syslog.logfile_path('file:///etc/passwd'));
		assert.match(null, syslog.logfile_path('file:///var/log/'));
		assert.match(null, syslog.logfile_path('file:///var/log/../shadow'));
		assert.match(null, syslog.logfile_path('file:///var/log/a\nb'));
		assert.match(null, syslog.logfile_path('file:///var/log/a\n'));
	});

	it('rejects a path that is not a URI', () => {
		assert.match(null, syslog.logfile_path('/var/log/messages'));
	});
});

describe('syslog Source.{i}.UnixDomainSocket.Path', () => {
	it('accepts a socket in /var/run/ubbf-syslog', () => {
		assert.match('/var/run/ubbf-syslog/app', syslog.socket_path('file:///var/run/ubbf-syslog/app'));
	});

	it('rejects a subdirectory, a newline and a path that is too long', () => {
		assert.match(null, syslog.socket_path('file:///var/run/ubbf-syslog/a/b'));
		assert.match(null, syslog.socket_path('file:///var/run/ubbf-syslog/a\nb'));
		assert.match(null, syslog.socket_path('file:///var/run/ubbf-syslog/' + sprintf('%090d', 0)));
	});
});
