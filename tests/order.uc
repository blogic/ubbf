// Host test of order_snapshot() and orders_compute() of ubbf.so, the
// TR-181 data type Order.
'use strict';

import { describe, it, assert } from 'utest';
import { order_snapshot, orders_compute } from 'ubbf';

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

describe('Order after a change', () => {
	it('puts a new row without Order last', () => {
		assert.match({ '1': '1', '2': '2', '3': '3' },
			step({ '1': '1', '2': '2' }, (r) => { r['3'] = { Order: '' }; }));
	});

	it('moves the row with a taken Order and the lower ones down for a new row', () => {
		assert.match({ '1': '2', '2': '3', '3': '1' },
			step({ '1': '1', '2': '2' }, (r) => { r['3'] = { Order: '1' }; }));
	});

	it('moves the row with a taken Order and the lower ones down for a write', () => {
		assert.match({ '1': '1', '2': '3', '3': '2' },
			step({ '1': '1', '2': '2', '3': '3' }, (r) => { r['3'].Order = '2'; }));
	});

	it('moves nothing for a write of a free Order', () => {
		assert.match({ '1': '5', '2': '2' },
			step({ '1': '1', '2': '2' }, (r) => { r['1'].Order = '5'; }));
	});

	it('compacts the values after a deletion', () => {
		assert.match({ '1': '1', '3': '2' },
			step({ '1': '1', '2': '2', '3': '3' }, (r) => { delete r['2']; }));
		assert.match({ '2': '1', '3': '2' },
			step({ '1': '2', '2': '7', '3': '9' }, (r) => { delete r['1']; }), 'a deletion compacts after a gap');
	});

	it('puts two new rows without Order last in instance order', () => {
		assert.match({ '1': '1', '4': '2', '5': '3' },
			step({ '1': '1' }, (r) => { r['5'] = {}; r['4'] = {}; }));
	});
});

describe('Order of a loaded tree', () => {
	it('keeps its order, moves duplicates down and numbers the rest', () => {
		let loaded = tree({ '1': '2', '2': '2', '3': '', '4': '1' });
		orders_compute(loaded, null);
		assert.match({ '1': '2', '2': '3', '3': '4', '4': '1' }, orders(loaded));
	});

	it('numbers a table below a row', () => {
		let nested = { Device: { Firewall: { Chain: { '1': { Rule: { '1': {}, '2': { Order: '1' } } } } } } };
		orders_compute(nested, null);
		assert.match([ '2', '1' ], map(values(nested.Device.Firewall.Chain['1'].Rule), (r) => r.Order));
	});

	it('reports that nothing changes', () => {
		assert.match(false, orders_compute(tree({ '1': '1', '2': '2' }), null));
	});
});
