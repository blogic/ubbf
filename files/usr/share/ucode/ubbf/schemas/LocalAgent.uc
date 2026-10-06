'use strict';

export const LocalAgent = {
	path: 'Device.LocalAgent.',
	schema: {
		'TransferComplete!': {
			type: 'event',
			input: [
				'Command',
				'CommandKey',
				'Requestor',
				'TransferType',
				'Affected',
				'TransferURL',
				'StartTime',
				'CompleteTime',
				'FaultCode',
				'FaultString'
			]
		},
		'X_UBBF_DiagnosticsComplete!': {
			type: 'event',
			input: [
				'Command',
				'Requestor',
				'Status',
				'FaultCode',
				'FaultString'
			]
		}
	},
	defaults: {}
};
