function render_config() {
    let bulkdata = ubbf_get(config, 'Device.BulkData');
    if (!bulkdata)
        return;

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
            uci_set_boolean(output, section_path + '.http_use_date_header', ubbf_to_bool(http.UseDateHeader));
            uci_set_boolean(output, section_path + '.http_retry_enable', ubbf_to_bool(http.RetryEnable));
            uci_set_number(output, section_path + '.http_retry_min_interval', ubbf_to_int(http.RetryMinimumWaitInterval));
            uci_set_number(output, section_path + '.http_retry_multiplier', ubbf_to_int(http.RetryIntervalMultiplier));

            let uri_params = ubbf_instances(http, 'RequestURIParameter');
            for (let param in uri_params) {
                if (param.Name && param.Reference)
                    uci_list_string(output, section_path + '.http_uri_param', sprintf('%s=%s', param.Name, param.Reference));
            }
        }

        let mqtt = ubbf_get(config, profile['.path'] + '.MQTT');
        if (mqtt) {
            uci_set_string(output, section_path + '.mqtt_topic', mqtt.PublishTopic);
            uci_set_number(output, section_path + '.mqtt_qos', ubbf_to_int(mqtt.PublishQoS));
            uci_set_boolean(output, section_path + '.mqtt_retain', ubbf_to_bool(mqtt.PublishRetain));

            if (mqtt.Reference && match(mqtt.Reference, /^Device\.MQTT\.Client\.\d+$/)) {
                let client = {};
                let proc = fs.popen(sprintf('obuspa -c get %s.', mqtt.Reference), 'r');
                if (proc) {
                    for (let line = proc.read('line'); line; line = proc.read('line')) {
                        let m = match(trim(line), /^[^ ]+ => (.*)$/);
                        if (m) {
                            let key = split(line, '.')[4];
                            key = split(key, ' ')[0];
                            client[key] = trim(m[1]);
                        }
                    }
                    proc.close();
                }
                if (client.BrokerAddress) {
                    uci_set_string(output, section_path + '.mqtt_broker', client.BrokerAddress);
                    uci_set_number(output, section_path + '.mqtt_port', ubbf_to_int(client.BrokerPort));
                    uci_set_string(output, section_path + '.mqtt_username', client.Username);
                    uci_set_string(output, section_path + '.mqtt_password', client.Password);
                    uci_set_string(output, section_path + '.mqtt_client_id', client.ClientID);
                    uci_set_boolean(output, section_path + '.mqtt_tls', client.TransportProtocol != 'TCP/IP');
                }
            }
        }

        let json_enc = ubbf_get(config, profile['.path'] + '.JSONEncoding');
        if (json_enc) {
            uci_set_string(output, section_path + '.json_report_format', json_enc.ReportFormat);
            uci_set_string(output, section_path + '.json_report_timestamp', json_enc.ReportTimestamp);
        }

        let csv_enc = ubbf_get(config, profile['.path'] + '.CSVEncoding');
        if (csv_enc) {
            uci_set_string(output, section_path + '.csv_field_separator', csv_enc.FieldSeparator);
            uci_set_string(output, section_path + '.csv_row_separator', csv_enc.RowSeparator);
            uci_set_string(output, section_path + '.csv_escape_character', csv_enc.EscapeCharacter);
            uci_set_string(output, section_path + '.csv_report_format', csv_enc.ReportFormat);
            uci_set_string(output, section_path + '.csv_row_timestamp', csv_enc.RowTimestamp);
        }

        let params = ubbf_instances(config, profile['.path'] + '.Parameter');
        for (let param in params) {
            if (param.Reference && !ubbf_to_bool(param.Exclude)) {
                if (param.Name)
                    uci_list_string(output, section_path + '.parameter', sprintf('%s:%s', param.Name, param.Reference));
                else
                    uci_list_string(output, section_path + '.parameter', param.Reference);
            }
        }
    }

}
uci_comment(output, '# generated by bulkdata.uc');
render_config();
