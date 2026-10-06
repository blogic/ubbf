'use strict';

export const PacketCaptureResult = {
	path: 'Device.PacketCaptureResult.{i}.',
	schema: {
		'FileLocation': dm_type.STRING,
		'StartTime': dm_type.DATETIME,
		'EndTime': dm_type.DATETIME,
		'Count': dm_type.UINT
	},
	defaults: {
		'FileLocation': '',
		'StartTime': '0001-01-01T00:00:00Z',
		'EndTime': '0001-01-01T00:00:00Z',
		'Count': '0'
	}
};
