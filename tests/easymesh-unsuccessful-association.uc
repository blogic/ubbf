// Host test of ReportUnsuccessfulAssociations and MaxReportingRate of
// Device.WiFi.DataElements.Network.Device in modules/easymesh/objectdata.uc:
// they read the Unsuccessful Association Policy that umapd's
// get_policy_config holds, as MaxUnsuccessfulAssociationReportingRate does.
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

function device_read(policy, config_policy) {
	const easymesh = { ConfigPolicy: { [AL]: config_policy } };
	const api_data = { capability: {}, policy: { policy } };

	return em.device_to_object({ al_address: AL }, api_data, false, easymesh, {}, {});
}

describe('Network.Device unsuccessful association policy', () => {
	it('reads the unsuccessful_association policy of umapd', () => {
		const dev = device_read({
			unsuccessful_association: { report_unsuccessful_assocs: true, max_reporting_rate: 30 }
		});

		assert.match('true', dev.ReportUnsuccessfulAssociations);
		assert.match('30', dev.MaxReportingRate);
		assert.match('30', dev.MaxUnsuccessfulAssociationReportingRate);
	});

	it('reads false and 0 where umapd holds no such policy', () => {
		const dev = device_read({});

		assert.match('false', dev.ReportUnsuccessfulAssociations);
		assert.match('0', dev.MaxReportingRate);
	});

	it('takes no value from the metric_reporting text of a policy row', () => {
		const text = { report_unsuccessful_associations: true, max_reporting_rate: 10, ap_metrics_reporting_interval: 30 };
		const dev = device_read({
			metric_reporting: text,
			unsuccessful_association: { report_unsuccessful_assocs: false, max_reporting_rate: 20 }
		}, { metric_reporting: text });

		assert.match('false', dev.ReportUnsuccessfulAssociations);
		assert.match('20', dev.MaxReportingRate);
	});
});
