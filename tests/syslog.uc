// Host test of the URI checks in modules/syslog/shared.uc
// (LogFile.{i}.FilePath, Source.{i}.UnixDomainSocket.Path). Run from the
// repository root with the native module built for the host:
//   ucode -L "<host build>/*.so" tests/syslog.uc
'use strict';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

let syslog = {};
include('../modules/syslog/shared.uc', { syslog });

check('log file', syslog.logfile_path('file:///var/log/messages'), '/var/log/messages');
check('log file with localhost', syslog.logfile_path('file://localhost/var/log/a/b'), '/var/log/a/b');
check('log file outside /var/log', syslog.logfile_path('file:///etc/passwd'), null);
check('log directory only', syslog.logfile_path('file:///var/log/'), null);
check('log file with ..', syslog.logfile_path('file:///var/log/../shadow'), null);
check('log file with a newline', syslog.logfile_path('file:///var/log/a\nb'), null);
check('log file with a trailing newline', syslog.logfile_path('file:///var/log/a\n'), null);
check('log file not a URI', syslog.logfile_path('/var/log/messages'), null);

check('socket', syslog.socket_path('file:///var/run/ubbf-syslog/app'), '/var/run/ubbf-syslog/app');
check('socket in a subdirectory', syslog.socket_path('file:///var/run/ubbf-syslog/a/b'), null);
check('socket with a newline', syslog.socket_path('file:///var/run/ubbf-syslog/a\nb'), null);
check('socket path too long', syslog.socket_path('file:///var/run/ubbf-syslog/' + sprintf('%090d', 0)), null);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
