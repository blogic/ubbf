'use strict';

import * as ubus from 'ubus';
import * as schemas from 'ubbf.schemas.BulkData';
import * as ubbf from 'ubbf';

const BULKDATA_MAX_PROFILES = 5;
const BULKDATA_MIN_REPORTING_INTERVAL = 1;

/**
 * Fetches the bulk data daemon status via ubus.
 *
 * @returns {object|null} Daemon status or null if unavailable
 */
function daemon_status_get() {
    return ubus.call('ubbf-bulkdata', 'status', {}) ?? null;
}

/**
 * Gets the Device.BulkData object data with computed status.
 *
 * @param {object} ctx - Handler context with config and root
 * @returns {object} BulkData object with status and capabilities
 */
function bulkdata_get(ctx) {
    let daemon_status = daemon_status_get();

    let status = 'Disabled';
    if (ubbf.to_bool(ctx.config?.Enable)) {
        if (daemon_status?.error)
            status = 'Error';
        else
            status = 'Enabled';
    }

    return {
        ...ubbf.ctx_config(ctx),
        Status: status,
        MinReportingInterval: sprintf('%d', BULKDATA_MIN_REPORTING_INTERVAL),
        Protocols: 'HTTP,MQTT',
        EncodingTypes: 'JSON,CSV',
        ParameterWildCardSupported: 'true',
        MaxNumberOfProfiles: sprintf('%d', BULKDATA_MAX_PROFILES),
        MaxNumberOfParameterReferences: '-1'
    };
}

/**
 * Gets a BulkData profile instance.
 *
 * @param {object} ctx - Handler context with config
 * @returns {object|null} Profile data or null
 */
function profile_get(ctx) {
    if (!ctx.config)
        return null;

    return {
        ...ctx.config,
        FileTransferPassword: ''
    };
}

/**
 * Gets HTTP transport settings for a BulkData profile.
 *
 * @param {object} ctx - Handler context with config
 * @returns {object|null} HTTP config with supported methods or null
 */
function profile_http_get(ctx) {
    if (!ctx.config)
        return null;

    return {
        ...ctx.config,
        CompressionsSupported: 'GZIP',
        MethodsSupported: 'POST,PUT',
        Password: ''
    };
}

export const model = {
    'Device.BulkData': {
        schema: schemas.BulkData,
        get: bulkdata_get
    },

    'Device.BulkData.Profile': {
    },

    'Device.BulkData.Profile.{i}': {
        schema: schemas.Profile,
        get: profile_get,
        maxInstances: BULKDATA_MAX_PROFILES
    },

    'Device.BulkData.Profile.{i}.Parameter': {
    },

    'Device.BulkData.Profile.{i}.Parameter.{i}': {
        schema: schemas.Profile_Parameter
    },

    'Device.BulkData.Profile.{i}.JSONEncoding': {
        schema: schemas.Profile_JSONEncoding
    },

    'Device.BulkData.Profile.{i}.CSVEncoding': {
        schema: schemas.Profile_CSVEncoding
    },

    'Device.BulkData.Profile.{i}.HTTP': {
        schema: schemas.Profile_HTTP,
        get: profile_http_get
    },

    'Device.BulkData.Profile.{i}.HTTP.RequestURIParameter': {
    },

    'Device.BulkData.Profile.{i}.HTTP.RequestURIParameter.{i}': {
        schema: schemas.HTTP_RequestURIParameter
    },

    'Device.BulkData.Profile.{i}.MQTT': {
        schema: schemas.Profile_MQTT
    }
};

export const operations = {};
