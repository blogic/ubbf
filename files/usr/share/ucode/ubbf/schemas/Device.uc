'use strict';

export const Device = {
	path: 'Device.',
	schema: {
		'RootDataModelVersion': dm_type.STRING,
		'InterfaceStackNumberOfEntries': dm_type.UINT,
		'Reboot()': {
			type: 'sync',
			input: [
				'Cause',
				'Reason'
			]
		},
		'FactoryReset()': {
			type: 'sync',
			input: []
		},
		'Shutdown()': {
			type: 'sync',
			input: [
				'Cause',
				'Reason'
			]
		}
	},
	defaults: {
		'RootDataModelVersion': '2.19',
		'InterfaceStackNumberOfEntries': '0'
	},
	since: {
		'Shutdown()': '2.21'
	}
};
