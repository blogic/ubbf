'use strict';

import * as fs from 'fs';
import * as schemas from 'ubbf.schemas.DeviceInfo';
import { deviceinfo_get as deviceinfo_read } from 'ubbf.utils.deviceinfo';
import * as MemoryStatus from 'ubbf.tr181.DeviceInfo.MemoryStatus';
import * as ProcessStatus from 'ubbf.tr181.DeviceInfo.ProcessStatus';
import * as Processor from 'ubbf.tr181.DeviceInfo.Processor';
import * as VendorConfigFile from 'ubbf.tr181.DeviceInfo.VendorConfigFile';
import * as VendorLogFile from 'ubbf.tr181.DeviceInfo.VendorLogFile';
import * as FirmwareImage from 'ubbf.tr181.DeviceInfo.FirmwareImage';
import * as TemperatureStatus from 'ubbf.tr181.DeviceInfo.TemperatureStatus';
import * as ProcessFaults from 'ubbf.tr181.DeviceInfo.ProcessFaults';
import * as Reboots from 'ubbf.tr181.DeviceInfo.Reboots';
import * as KernelFaults from 'ubbf.tr181.DeviceInfo.KernelFaults';
import * as ubbf from 'ubbf';

const FIRST_USE_DATE_PATH = '/etc/ubbf/first_use_date';

/**
 * Reads the persisted first-use timestamp written by the NTP hotplug script
 * and formats it as an ISO 8601 UTC datetime. Returns null when the file is
 * missing or unparseable, so the caller falls back to the schema sentinel
 * `0001-01-01T00:00:00Z`.
 *
 * @returns {string|null} ISO 8601 datetime, or null when not yet captured
 */
function first_use_date_get() {
	let data = fs.readfile(FIRST_USE_DATE_PATH);
	if (!data)
		return null;

	let ts = int(trim(data));
	if (!ts)
		return null;

	return usp_unix_to_datetime(ts);
}

/**
 * Get handler for Device.DeviceInfo.
 *
 * @param {object} ctx - Context with config and instance info
 * @returns {object} DeviceInfo properties
 */
function deviceinfo_get(ctx) {
	let uptime = ubbf.uptime_read();
	let result = {
		...ubbf.ctx_config(ctx),
		...deviceinfo_read(),
		UpTime: sprintf('%d', uptime),
		FirmwareImageNumberOfEntries: sprintf('%d', length(FirmwareImage.banks_get())),
		ActiveFirmwareImage: FirmwareImage.active_path_get(),
		BootFirmwareImage: FirmwareImage.boot_path_get(),
		ProcessorNumberOfEntries: sprintf('%d', Processor.processor_count()),
		VendorConfigFileNumberOfEntries: sprintf('%d', length(VendorConfigFile.files_enumerate())),
		VendorLogFileNumberOfEntries: sprintf('%d', VendorLogFile.source_count())
	};

	let first_use = first_use_date_get();
	if (first_use)
		result.FirstUseDate = first_use;

	return result;
}

/**
 * Set handler for Device.DeviceInfo.
 *
 * Rejects writes to BootFirmwareImage; bank switching is only supported
 * via FirmwareImage.{i}.Activate(). Other writable parameters
 * (ProvisioningCode, HostName, FriendlyName) fall through to the
 * framework's default storage.
 *
 * @param {object} ctx - Context with param, value
 * @returns {number|null} -1 to reject, implicit return to pass through
 */
function deviceinfo_set(ctx) {
	if (ctx.param == 'BootFirmwareImage')
		return -1;
}

export const model = {
	'Device.DeviceInfo': {
		schema: schemas.DeviceInfo,
		get: deviceinfo_get,
		set: deviceinfo_set
	},

	...MemoryStatus.model,
	...ProcessStatus.model,
	...Processor.model,
	...VendorConfigFile.model,
	...VendorLogFile.model,
	...FirmwareImage.model,
	...TemperatureStatus.model,
	...ProcessFaults.model,
	...Reboots.model,
	...KernelFaults.model,

	'Device.DeviceInfo.NetworkProperties': {
		schema: schemas.NetworkProperties,
		get: () => ({
			MaxTCPWindowSize: sprintf('%d', int(ubbf.readfile_trim('/proc/sys/net/core/rmem_max', '0'))),
			TCPImplementation: ubbf.readfile_trim('/proc/sys/net/ipv4/tcp_congestion_control', '')
		})
	}
};

export const operations = {
	...VendorConfigFile.operations,
	...VendorLogFile.operations,
	...FirmwareImage.operations,
	...TemperatureStatus.operations,
	...ProcessFaults.operations,
	...Reboots.operations,
	...KernelFaults.operations
};
