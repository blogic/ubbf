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
		}
	},
	defaults: {}
};
