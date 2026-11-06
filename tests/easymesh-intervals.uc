// Host test of the metric intervals of Device.WiFi.DataElements.Network.Device
// in modules/easymesh/objectdata.uc: they read what umapd's get_agent reports,
// never the text of a Policy.Data row.
'use strict';

import { describe, it, assert } from 'utest';
import * as ubbf from 'ubbf';

const api = {
	ubbf,
	utils: {
		'wifi-dataelements': {
			ubus_topology_get: () => ({}),
			radios_bss_sort: () => [],
			client_query_get: () => null
		}
	}
};

const em = {};

include(sourcepath(0, true) + '/../modules/easymesh/objectdata.uc', { ubbf_module: api, em });

const AL = '02:00:00:00:00:a1';

function device_read(capability, config_policy) {
	const easymesh = { ConfigPolicy: { [AL]: config_policy } };
	const api_data = { capability, policy: { policy: {} } };

	return em.device_to_object({ al_address: AL }, api_data, false, easymesh, {}, {});
}

describe('Network.Device metric intervals', () => {
	it('reads the intervals of get_agent', () => {
		const dev = device_read({ metric_intervals: { collection_ms: 5000, ap_metrics_s: 15, sta_metrics_s: 15 } });

		assert.match('5000', dev.CollectionInterval);
		assert.match('15', dev.APMetricsReportingInterval);
		assert.match('15', dev.AssociatedSTAReportingInterval);
	});

	it('reads 0 for a device with no intervals', () => {
		const dev = device_read({});

		assert.match('0', dev.CollectionInterval);
		assert.match('0', dev.APMetricsReportingInterval);
		assert.match('0', dev.AssociatedSTAReportingInterval);
	});

	it('takes no value from the text of a policy row', () => {
		const dev = device_read({ metric_intervals: { collection_ms: 30000, ap_metrics_s: 30, sta_metrics_s: 0 } }, {
			metric_reporting: { collection_interval: 60, ap_metrics_interval: 15, sta_metrics_interval: 10 }
		});

		assert.match('30000', dev.CollectionInterval);
		assert.match('30', dev.APMetricsReportingInterval);
		assert.match('0', dev.AssociatedSTAReportingInterval);
	});
});
