function render_config() {
	if (!fs.stat('/usr/sbin/umap-director'))
		return;

	let network = ubbf_get(config, 'Device.WiFi.DataElements.Network');
	if (!network)
		return;

	let steering = network.X_UBBF_EasyMesh?.Steering;
	if (!steering)
		return;

	let enabled = ubbf_to_bool(steering.Enable);
	services.set_enabled('umap-director', enabled);

	if (!enabled)
		return;


	uci_named_section(output, 'umap-director.global', 'director');
	uci_set_boolean(output, 'umap-director.global.enabled', true);
	uci_set_string(output, 'umap-director.global.backend', steering.Backend);
	uci_set_number(output, 'umap-director.global.log_level', ubbf_to_int(steering.LogLevel));
	uci_set_number(output, 'umap-director.global.periodic_interval', ubbf_to_int(steering.PeriodicInterval));
	uci_set_number(output, 'umap-director.global.metric_stale_interval', ubbf_to_int(steering.MetricStaleInterval));
	uci_set_number(output, 'umap-director.global.ap_metrics_reporting_interval', ubbf_to_int(steering.APMetricsReportingInterval));

	let sq = steering.SignalQuality;
	if (sq) {
		uci_named_section(output, 'umap-director.signal_quality', 'module');
		uci_set_boolean(output, 'umap-director.signal_quality.enabled', ubbf_to_bool(sq.Enable));
		uci_set_number(output, 'umap-director.signal_quality.low_rcpi_count', ubbf_to_int(sq.LowRCPICount));
		uci_set_number(output, 'umap-director.signal_quality.high_rcpi_count', ubbf_to_int(sq.HighRCPICount));
		uci_set_number(output, 'umap-director.signal_quality.signal_threshold_2g', ubbf_to_int(sq.SignalThreshold2G));
		uci_set_number(output, 'umap-director.signal_quality.signal_threshold_5g', ubbf_to_int(sq.SignalThreshold5G));
		uci_set_number(output, 'umap-director.signal_quality.signal_threshold_6g', ubbf_to_int(sq.SignalThreshold6G));
		uci_set_number(output, 'umap-director.signal_quality.report_signal_threshold_2g', ubbf_to_int(sq.ReportSignalThreshold2G));
		uci_set_number(output, 'umap-director.signal_quality.report_signal_threshold_5g', ubbf_to_int(sq.ReportSignalThreshold5G));
		uci_set_number(output, 'umap-director.signal_quality.report_signal_threshold_6g', ubbf_to_int(sq.ReportSignalThreshold6G));
		uci_set_number(output, 'umap-director.signal_quality.hysteresis', ubbf_to_int(sq.Hysteresis));
		uci_set_number(output, 'umap-director.signal_quality.diffsnr_margin', ubbf_to_int(sq.DiffSNRMargin));
		uci_set_number(output, 'umap-director.signal_quality.unassoc_collect_time', ubbf_to_int(sq.UnassocCollectTime));
		uci_set_number(output, 'umap-director.signal_quality.beacon_collect_time', ubbf_to_int(sq.BeaconCollectTime));
		uci_set_number(output, 'umap-director.signal_quality.cooldown', ubbf_to_int(sq.Cooldown));
	}

	let al = steering.APLoad;
	if (al) {
		uci_named_section(output, 'umap-director.ap_load', 'module');
		uci_set_boolean(output, 'umap-director.ap_load.enabled', ubbf_to_bool(al.Enable));
		uci_set_number(output, 'umap-director.ap_load.overload_threshold', ubbf_to_int(al.OverloadThreshold));
		uci_set_number(output, 'umap-director.ap_load.target_threshold', ubbf_to_int(al.TargetThreshold));
		uci_set_number(output, 'umap-director.ap_load.min_steer_signal', ubbf_to_int(al.MinSteerSignal));
		uci_set_number(output, 'umap-director.ap_load.confined_duration', ubbf_to_int(al.ConfinedDuration));
		uci_set_number(output, 'umap-director.ap_load.cooldown', ubbf_to_int(al.Cooldown));
		uci_set_number(output, 'umap-director.ap_load.min_connected_time', ubbf_to_int(al.MinConnectedTime));
	}

	let bp = steering.BandPreference;
	if (bp) {
		uci_named_section(output, 'umap-director.band_preference', 'module');
		uci_set_boolean(output, 'umap-director.band_preference.enabled', ubbf_to_bool(bp.Enable));
		uci_set_number(output, 'umap-director.band_preference.rssi_cutoff', ubbf_to_int(bp.RSSICutoff));
		uci_set_number(output, 'umap-director.band_preference.pathloss_delta', ubbf_to_int(bp.PathlossDelta));
		uci_set_number(output, 'umap-director.band_preference.pathloss_delta_5_to_6', ubbf_to_int(bp.PathlossDelta5To6));
		uci_set_number(output, 'umap-director.band_preference.upgrade_margin', ubbf_to_int(bp.UpgradeMargin));
		uci_set_number(output, 'umap-director.band_preference.downgrade_count', ubbf_to_int(bp.DowngradeCount));
		uci_set_number(output, 'umap-director.band_preference.settling_delay', ubbf_to_int(bp.SettlingDelay));
		uci_set_number(output, 'umap-director.band_preference.cooldown_success', ubbf_to_int(bp.CooldownSuccess));
		uci_set_number(output, 'umap-director.band_preference.cooldown_failure', ubbf_to_int(bp.CooldownFailure));
		uci_set_number(output, 'umap-director.band_preference.max_failures_per_band', ubbf_to_int(bp.MaxFailuresPerBand));
		uci_set_number(output, 'umap-director.band_preference.failure_decay_time', ubbf_to_int(bp.FailureDecayTime));
	}

	let bl = steering.BackhaulLink;
	if (bl) {
		uci_named_section(output, 'umap-director.backhaul_link', 'module');
		uci_set_boolean(output, 'umap-director.backhaul_link.enabled', ubbf_to_bool(bl.Enable));
		uci_set_number(output, 'umap-director.backhaul_link.signal_threshold_2g', ubbf_to_int(bl.SignalThreshold2G));
		uci_set_number(output, 'umap-director.backhaul_link.signal_threshold_5g', ubbf_to_int(bl.SignalThreshold5G));
		uci_set_number(output, 'umap-director.backhaul_link.signal_threshold_6g', ubbf_to_int(bl.SignalThreshold6G));
		uci_set_number(output, 'umap-director.backhaul_link.report_signal_threshold_2g', ubbf_to_int(bl.ReportSignalThreshold2G));
		uci_set_number(output, 'umap-director.backhaul_link.report_signal_threshold_5g', ubbf_to_int(bl.ReportSignalThreshold5G));
		uci_set_number(output, 'umap-director.backhaul_link.report_signal_threshold_6g', ubbf_to_int(bl.ReportSignalThreshold6G));
		uci_set_number(output, 'umap-director.backhaul_link.signal_diff_threshold', ubbf_to_int(bl.SignalDiffThreshold));
		uci_set_number(output, 'umap-director.backhaul_link.rcpi_low_trigger', ubbf_to_int(bl.RCPILowTrigger));
		uci_set_number(output, 'umap-director.backhaul_link.rcpi_recovery_trigger', ubbf_to_int(bl.RCPIRecoveryTrigger));
		uci_set_number(output, 'umap-director.backhaul_link.throughput_drop_pct', ubbf_to_int(bl.ThroughputDropPct));
		uci_set_number(output, 'umap-director.backhaul_link.throughput_trigger', ubbf_to_int(bl.ThroughputTrigger));
		uci_set_number(output, 'umap-director.backhaul_link.topology_impact_threshold', ubbf_to_int(bl.TopologyImpactThreshold));
		uci_set_number(output, 'umap-director.backhaul_link.min_assoc_time', ubbf_to_int(bl.MinAssocTime));
		uci_set_number(output, 'umap-director.backhaul_link.unassoc_collect_time', ubbf_to_int(bl.UnassocCollectTime));
		uci_set_number(output, 'umap-director.backhaul_link.beacon_collect_time', ubbf_to_int(bl.BeaconCollectTime));
		uci_set_number(output, 'umap-director.backhaul_link.cooldown', ubbf_to_int(bl.Cooldown));
	}

	let dfs = steering.DFSEvacuation;
	if (dfs) {
		uci_named_section(output, 'umap-director.dfs_evacuation', 'module');
		uci_set_boolean(output, 'umap-director.dfs_evacuation.enabled', ubbf_to_bool(dfs.Enable));
		uci_set_number(output, 'umap-director.dfs_evacuation.disassoc_timer', ubbf_to_int(dfs.DisassocTimer));
		uci_set_number(output, 'umap-director.dfs_evacuation.evacuate_timeout', ubbf_to_int(dfs.EvacuateTimeout));
		uci_set_number(output, 'umap-director.dfs_evacuation.cac_timeout', ubbf_to_int(dfs.CACTimeout));
		uci_set_number(output, 'umap-director.dfs_evacuation.return_timeout', ubbf_to_int(dfs.ReturnTimeout));
	}

}
uci_comment(output, '# generated by umap-director.uc');
render_config();
