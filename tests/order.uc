// Host test of order_snapshot() and orders_compute() of ubbf.so, the
// TR-181 data type Order. Run from the
// repository root with the native module built for the host:
//   ucode -L "$PWD/files/usr/share/ucode" -L "<host build>/*.so" tests/order.uc
'use strict';

import { order_snapshot, orders_compute } from 'ubbf';

let pass = 0, fail = 0;

function check(name, got, expected) {
	if (sprintf('%J', got) == sprintf('%J', expected)) { pass++; return; }
	fail++;
	printf('FAIL %s\n  expected %J\n  got      %J\n', name, expected, got);
}

function tree(orders) {
	let rows = {};
	for (let k, order in orders)
		rows[k] = { Order: order };
	return { Device: { QoS: { Classification: rows } } };
}

function orders(data) {
	let rows = data.Device.QoS.Classification;
	let out = {};
	for (let k in sort(keys(rows), (a, b) => +a - +b))
		out[k] = rows[k].Order;
	return out;
}

// Applies a change to a tree of { instance: Order } and returns the result.
function step(start, change) {
	let data = tree(start);
	let before = order_snapshot(data);
	change(data.Device.QoS.Classification);
	orders_compute(data, before);
	return orders(data);
}

check('a new row without Order goes last',
	step({ '1': '1', '2': '2' }, (r) => { r['3'] = { Order: '' }; }), { '1': '1', '2': '2', '3': '3' });
check('a new row with a taken Order moves that row and the lower ones down',
	step({ '1': '1', '2': '2' }, (r) => { r['3'] = { Order: '1' }; }), { '1': '2', '2': '3', '3': '1' });
check('a write of a taken Order moves that row and the lower ones down',
	step({ '1': '1', '2': '2', '3': '3' }, (r) => { r['3'].Order = '2'; }), { '1': '1', '2': '3', '3': '2' });
check('a write of a free Order moves nothing',
	step({ '1': '1', '2': '2' }, (r) => { r['1'].Order = '5'; }), { '1': '5', '2': '2' });
check('a deletion compacts the values',
	step({ '1': '1', '2': '2', '3': '3' }, (r) => { delete r['2']; }), { '1': '1', '3': '2' });
check('a deletion compacts after a gap',
	step({ '1': '2', '2': '7', '3': '9' }, (r) => { delete r['1']; }), { '2': '1', '3': '2' });
check('two new rows without Order go last in instance order',
	step({ '1': '1' }, (r) => { r['5'] = {}; r['4'] = {}; }), { '1': '1', '4': '2', '5': '3' });

let loaded = tree({ '1': '2', '2': '2', '3': '', '4': '1' });
orders_compute(loaded, null);
check('a loaded tree keeps its order, moves duplicates down, numbers the rest',
	orders(loaded), { '1': '2', '2': '3', '3': '4', '4': '1' });

let nested = { Device: { Firewall: { Chain: { '1': { Rule: { '1': {}, '2': { Order: '1' } } } } } } };
orders_compute(nested, null);
check('a table below a row', map(values(nested.Device.Firewall.Chain['1'].Rule), (r) => r.Order), [ '2', '1' ]);

check('nothing changes in order', orders_compute(tree({ '1': '1', '2': '2' }), null), false);

printf('passed: %d\nfailed: %d\n', pass, fail);
exit(fail ? 1 : 0);
