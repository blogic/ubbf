'use strict';

// Included with { schemas } as the scope by module_api_build() in
// datamodel.uc and by schema-gen.uc; there is nothing to export from an
// included file, so each definition is added to that object.

// Commands that join the schema of Device., which tr181/Device.uc owns.
schemas.Device_Commands = {
	schema: {
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
	}
};
