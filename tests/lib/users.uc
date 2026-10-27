const passwd = [
	{ username: 'root', uid: 0, gid: 0, gecos: 'root', home: '/root', shell: '/bin/ash' },
	{ username: 'daemon', uid: 2, gid: 2, gecos: 'daemon', home: '/var', shell: '/bin/false' },
	{ username: 'alice', uid: 1000, gid: 100, gecos: '', home: '/home/alice', shell: '/bin/false' }
];

return {
	passwd_get_all: () => passwd,
	passwd_get_by_name: (name) => filter(passwd, (pw) => pw.username == name)[0],
	group_get_all: () => [
		{ groupname: 'root', gid: 0, members: [] },
		{ groupname: 'users', gid: 100, members: [ 'alice' ] }
	],
	group_get_by_name: () => null,
	shadow_get_all: () => [ { username: 'root', hash: '$5$x' }, { username: 'daemon', hash: '*' } ],
	shells_get: () => [ '/bin/ash' ],
	credentials_check: () => 'Credentials_Good',
	password_hash: (p) => { push(global.hashed ??= [], p); return `$6$s$${p}`; }
};
