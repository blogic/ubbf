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
		'PacketCaptureDiagnostics()': {
			type: 'async',
			input: [
				'Interface',
				'Format',
				'Duration',
				'PacketCount',
				'ByteCount',
				'FileTarget',
				'FilterExpression',
				'Username',
				'Password'
			],
			output: [
				'Status',
				'PacketCaptureResult.{i}.FileLocation',
				'PacketCaptureResult.{i}.StartTime',
				'PacketCaptureResult.{i}.EndTime',
				'PacketCaptureResult.{i}.Count'
			]
		}
	},
	defaults: {
		'RootDataModelVersion': '2.19',
		'InterfaceStackNumberOfEntries': '0'
	}
};
