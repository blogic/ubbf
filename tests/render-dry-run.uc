// Host test of `apply --dry-run`: generate() with dry_run set writes no file
// and reloads no service, and the same config without it does write, which
// shows that the config reaches each template that writes. Run from the
// repository root with the native module built for the host:
//   tests/render/run.sh <host build> tests/render-dry-run.uc
'use strict';

import * as fs from 'fs';
import { generate } from 'ubbf.render.renderer';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

function tree(dir) {
	let out = [];
	for (let name in sort(fs.lsdir(dir) ?? [])) {
		let path = `${dir}/${name}`;
		push(out, path);
		if (fs.stat(path)?.type == 'directory')
			push(out, ...tree(path));
	}
	return out;
}

function written() {
	return [ ...tree('/etc'), ...tree('/run'), ...tree('/tmp/ubbf') ];
}

const KEY = 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHu6JdtbcJvAMYdc6iDsMaQfeaVb6LnQxTFhR8lEHcNa test';

const config = { Device: {
	DeviceInfo: { KernelFaults: { MaxKernelFaultEntries: '50' } },
	SSH: { Enable: 'true', Server: {}, AuthorizedKey: { '1': { Key: KEY }, '2': { Key: 'ssh-dss AAAAB3NzaC1kc3M=' } } },
	IP: { Interface: { '1': { Enable: 'true', Name: 'wan', Upstream: 'true', LowerLayers: 'Device.PPP.Interface.1' } } },
	PPP: { Interface: { '1': { Enable: 'true', Name: 'wan' } } },
	Firewall: { Enable: 'true', X_UBBF_DoSProtection: { IcmpRateLimit: 'true' },
		InterfaceSetting: { '1': { Enable: 'true', Interface: 'Device.IP.Interface.1' } } },
	Syslog: { Enable: 'true', Source: { '1': { Enable: 'true', KernelMessages: 'true' } },
		Action: { '1': { SourceRef: 'Device.Syslog.Source.1', LogFile: { Enable: 'true', FilePath: 'file:///var/log/test.log' } } } },
	DNS: { SD: { Enable: 'true', Advertise: { '1': { Enable: 'true', InstanceName: 'web', ServiceName: '_http._tcp', Port: '80' } } } },
	X_UBBF: { QoSify: { Enable: 'true' } }
} };

// The directories the image ships
for (let dir in [ '/etc/dropbear', '/etc/ubbf' ])
	fs.mkdir(dir, 0755);
let before = written();

let logs = [];
generate(config, logs, true);
check('a dry run writes nothing', written(), before);

generate(config, logs, false);
let files = written();
for (let path in [ '/etc/dropbear/authorized_keys', '/etc/ubbf/kernel-faults.json',
		   '/tmp/ubbf/firewall-alg.json', '/tmp/ubbf/firewall-dos.nft',
		   '/tmp/ubbf/qosify.conf', '/tmp/ubbf/umdns/web.json', '/run/ubbf-logd/config.json' ])
	check(`an apply writes ${path}`, index(files, path) >= 0, true);
check('only the accepted key is deployed', trim(fs.readfile('/etc/dropbear/authorized_keys')), KEY);

if (fail)
	printf('render logs: %J\nfiles: %J\n', logs, files);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
