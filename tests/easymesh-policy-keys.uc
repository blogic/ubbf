// Host test of the policy parameters of Device.WiFi.DataElements.Network.Device
// and its Radio rows in modules/easymesh/objectdata.uc: they read the keys of
// umapd's get_policy_config (umapd-policy.md), so a value that umapd holds
// reaches the data model and a key that umapd does not hold does not.
'use strict';

import { describe, it, assert } from 'utest';
import * as ubbf from 'ubbf';

const RUID = '02:00:00:00:01:01';

const api = {
	ubbf,
	utils: {
		dhcp: { ipv6_leases_get: () => ({}) },
		'wifi-dataelements': {
			ubus_topology_get: () => ({}),
			radios_bss_sort: () => [ { radio_unique_identifier: RUID, bss: [] } ],
			client_query_get: () => null
		}
	}
};

const em = {};

include(sourcepath(0, true) + '/../modules/easymesh/objectdata.uc', { ubbf_module: api, em });

const AL = '02:00:00:00:00:a1';

function device_read(policy, config_policy) {
	const easymesh = config_policy ? { ConfigPolicy: { [AL]: config_policy } } : {};
	const api_data = { capability: {}, policy: { policy } };

	return em.device_to_object({ al_address: AL }, api_data, false, easymesh, {}, {});
}

function radio_read(policy) {
	return device_read(policy).Radio['1'];
}

describe('Network.Device policy parameters', () => {
	it('reads the disallowed station lists of umapd', () => {
		const dev = device_read({ steering: {
			local_steering_disallowed_sta: [ 'aa:bb:cc:dd:ee:ff' ],
			btm_steering_disallowed_sta: [ '11:22:33:44:55:66', '11:22:33:44:55:77' ]
		} });

		assert.match('aa:bb:cc:dd:ee:ff', dev.LocalSteeringDisallowedSTAList);
		assert.match('11:22:33:44:55:66,11:22:33:44:55:77', dev.BTMSteeringDisallowedSTAList);
	});

	it('reads no disallowed station list from keys umapd does not hold', () => {
		const dev = device_read({}, { steering: {
			local_steering_disallowed: [ 'aa:bb:cc:dd:ee:ff' ],
			btm_steering_disallowed: [ '11:22:33:44:55:66' ]
		} });

		assert.match('', dev.LocalSteeringDisallowedSTAList);
		assert.match('', dev.BTMSteeringDisallowedSTAList);
	});

	it('reads the independent scan reporting of umapd', () => {
		assert.match('true', device_read({ channel_scan_reporting: { report_independent_channel_scans: true } }).ReportIndependentScans);
		assert.match('false', device_read({ channel_scan_reporting: { report_independent_channel_scans: false } }).ReportIndependentScans);
		assert.match('false', device_read({}, { channel_scan_reporting: { report_independent_scans: true } }).ReportIndependentScans);
	});
});

describe('Network.Device.Radio policy parameters', () => {
	it('reads the steering radio entry of umapd', () => {
		const radio = radio_read({ steering: { radios: [ {
			radio_unique_identifier: RUID,
			steering_policy: 2,
			channel_utilization_threshold: 120,
			rcpi_steering_threshold: 80
		} ] } });

		assert.match('2', radio.SteeringPolicy);
		assert.match('120', radio.ChannelUtilizationThreshold);
		assert.match('80', radio.RCPISteeringThreshold);
	});

	it('reads the metric reporting radio entry of umapd', () => {
		const radio = radio_read({ metric_reporting: {
			associated_sta_traffic_stats_inclusion_policy: false,
			associated_sta_link_metrics_inclusion_policy: false,
			associated_wifi6_sta_status_inclusion_policy: false,
			radios: [ {
				radio_unique_identifier: RUID,
				sta_metrics_reporting_rcpi_threshold: 90,
				sta_metrics_reporting_rcpi_hysteresis_margin_override: 5,
				ap_metrics_channel_utilization_reporting_threshold: 50,
				associated_sta_traffic_stats_inclusion_policy: true,
				associated_sta_link_metrics_inclusion_policy: true,
				associated_wifi6_sta_status_inclusion_policy: true
			} ]
		} });

		assert.match('90', radio.STAReportingRCPIThreshold);
		assert.match('5', radio.STAReportingRCPIHysteresisMarginOverride);
		assert.match('50', radio.ChannelUtilizationReportingThreshold);
		assert.match('true', radio.AssociatedSTATrafficStatsInclusionPolicy);
		assert.match('true', radio.AssociatedSTALinkMetricsInclusionPolicy);
		assert.match('true', radio.APMetricsWiFi6);
	});

	it('takes the top-level inclusion flags of umapd for an unlisted radio', () => {
		const radio = radio_read({ metric_reporting: {
			associated_sta_traffic_stats_inclusion_policy: true,
			associated_sta_link_metrics_inclusion_policy: true,
			associated_wifi6_sta_status_inclusion_policy: true,
			radios: [ { radio_unique_identifier: '02:00:00:00:09:09', sta_metrics_reporting_rcpi_threshold: 90 } ]
		} });

		assert.match('0', radio.STAReportingRCPIThreshold);
		assert.match('true', radio.AssociatedSTATrafficStatsInclusionPolicy);
		assert.match('true', radio.AssociatedSTALinkMetricsInclusionPolicy);
		assert.match('true', radio.APMetricsWiFi6);
	});

	it('reads no radio value from top-level keys umapd does not hold', () => {
		const radio = radio_read({
			steering: { policy: 1, channel_utilization_threshold: 100, rcpi_threshold: 70 },
			metric_reporting: { rcpi_threshold: 60, rcpi_hysteresis: 4, channel_utilization_threshold: 50,
				include_traffic_stats: true, include_link_metrics: true, wifi6_metrics: true }
		});

		assert.match('0', radio.SteeringPolicy);
		assert.match('0', radio.ChannelUtilizationThreshold);
		assert.match('0', radio.RCPISteeringThreshold);
		assert.match('0', radio.STAReportingRCPIThreshold);
		assert.match('0', radio.STAReportingRCPIHysteresisMarginOverride);
		assert.match('0', radio.ChannelUtilizationReportingThreshold);
		assert.match('false', radio.AssociatedSTATrafficStatsInclusionPolicy);
		assert.match('false', radio.AssociatedSTALinkMetricsInclusionPolicy);
		assert.match('false', radio.APMetricsWiFi6);
	});
});
