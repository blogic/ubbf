// UCI values cannot carry control characters (uci_value_sanitise()), and
// the CSV separators are often a tab, CR or LF: they go as \t, \r, \n.
function separator_encode(s) {
    if (s == null)
        return null;

    s = replace(s, /\\/g, '\\\\');
    s = replace(s, /\t/g, '\\t');
    s = replace(s, /\r/g, '\\r');
    return replace(s, /\n/g, '\\n');
}

function render_config() {
    let bulkdata = ubbf_get(config, 'Device.BulkData');
    if (!bulkdata) {
        services.set_enabled('ubbf-bulkdata', false);
        return;
    }

    let global_enable = ubbf_to_bool(bulkdata.Enable);
    services.set_enabled('ubbf-bulkdata', global_enable);

    if (!global_enable)
        return;

    uci_named_section(output, 'bulkdata.global', 'bulkdata');
    uci_set_boolean(output, 'bulkdata.global.enable', true);

    let profiles = ubbf_instances(config, 'Device.BulkData.Profile');

    for (let profile in profiles) {
        let section_path = 'bulkdata.@profile[-1]';

        uci_section(output, 'bulkdata profile');
        uci_set_number(output, section_path + '.instance', ubbf_to_int(profile['.instance']));
        uci_set_boolean(output, section_path + '.enable', ubbf_to_bool(profile.Enable));
        uci_set_string(output, section_path + '.alias', profile.Alias);
        uci_set_string(output, section_path + '.name', profile.Name);
        uci_set_string(output, section_path + '.protocol', profile.Protocol);
        uci_set_string(output, section_path + '.encoding_type', profile.EncodingType);
        uci_set_number(output, section_path + '.reporting_interval', ubbf_to_int(profile.ReportingInterval));
        uci_set_string(output, section_path + '.time_reference', profile.TimeReference);
        uci_set_number(output, section_path + '.number_retained_reports', ubbf_to_int(profile.NumberOfRetainedFailedReports));

        let http = ubbf_get(config, profile['.path'] + '.HTTP');
        if (http) {
            uci_set_string(output, section_path + '.http_url', http.URL);
            uci_set_string(output, section_path + '.http_username', http.Username);
            uci_set_string(output, section_path + '.http_password', http.Password);
            uci_set_string(output, section_path + '.http_method', http.Method);
            uci_set_string(output, section_path + '.http_compression', http.Compression);
            uci_set_boolean(output, section_path + '.http_use_date_header', ubbf_to_bool(http.UseDateHeader ?? 'true'));
            uci_set_boolean(output, section_path + '.http_retry_enable', ubbf_to_bool(http.RetryEnable));
            uci_set_number(output, section_path + '.http_retry_min_interval', ubbf_to_int(http.RetryMinimumWaitInterval));
            uci_set_number(output, section_path + '.http_retry_multiplier', ubbf_to_int(http.RetryIntervalMultiplier));

            // JSON per row: a Name or Reference may hold '=' or ':'.
            for (let param in ubbf_instances(http, 'RequestURIParameter'))
                if (param.Reference)
                    uci_list_string(output, section_path + '.http_uri_param',
                        sprintf('%J', { name: param.Name ?? '', reference: param.Reference }));
        }

        // The daemon resolves the reference when it publishes: the render
        // runs while the agent waits for the apply, so the agent could not
        // answer an `obuspa -c get` from here.
        let mqtt = ubbf_get(config, profile['.path'] + '.MQTT');
        if (mqtt) {
            uci_set_string(output, section_path + '.mqtt_reference', rtrim(mqtt.Reference ?? '', '.'));
            uci_set_string(output, section_path + '.mqtt_topic', mqtt.PublishTopic);
            uci_set_number(output, section_path + '.mqtt_qos', ubbf_to_int(mqtt.PublishQoS));
            uci_set_boolean(output, section_path + '.mqtt_retain', ubbf_to_bool(mqtt.PublishRetain));
        }

        let json_enc = ubbf_get(config, profile['.path'] + '.JSONEncoding');
        if (json_enc) {
            uci_set_string(output, section_path + '.json_report_format', json_enc.ReportFormat);
            uci_set_string(output, section_path + '.json_report_timestamp', json_enc.ReportTimestamp);
        }

        let csv_enc = ubbf_get(config, profile['.path'] + '.CSVEncoding');
        if (csv_enc) {
            uci_set_string(output, section_path + '.csv_field_separator', separator_encode(csv_enc.FieldSeparator));
            uci_set_string(output, section_path + '.csv_row_separator', separator_encode(csv_enc.RowSeparator));
            uci_set_string(output, section_path + '.csv_escape_character', separator_encode(csv_enc.EscapeCharacter));
            uci_set_string(output, section_path + '.csv_report_format', csv_enc.ReportFormat);
            uci_set_string(output, section_path + '.csv_row_timestamp', csv_enc.RowTimestamp);
        }

        // An excluded row removes its paths from what the other rows
        // collect (R-BULK.10a), so it goes to its own list.
        for (let param in ubbf_instances(config, profile['.path'] + '.Parameter')) {
            if (!param.Reference)
                continue;

            let list = ubbf_to_bool(param.Exclude) ? '.exclude' : '.parameter';
            uci_list_string(output, section_path + list,
                sprintf('%J', { name: param.Name ?? '', reference: param.Reference }));
        }
    }
}
uci_comment(output, '# generated by bulkdata/render.uc');
render_config();
