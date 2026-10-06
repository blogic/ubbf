function render_config() {
	const CAPABILITIES_PATH = '/tmp/ubbf/capabilities.json';

	let capabilities_raw = fs.readfile(CAPABILITIES_PATH);
	let capabilities = capabilities_raw ? json(capabilities_raw) : null;
	if (capabilities_raw && !capabilities)
		log_warn('Failed to parse %s', CAPABILITIES_PATH);
	capabilities ??= {};

	// Out-of-band 6 GHz discovery (RNR) only makes sense when there is a
	// 6 GHz BSS to advertise. Resolved once per render and consulted from
	// generate_interface / generate_mlo_interface.
	let has_6ghz_radio = capabilities.radios?.['6g'] != null;

	// One global DSCP -> 802.1D UP table per device. Computed once and
	// applied to every BSS that has WMM enabled. hostapd embeds it in the
	// 802.11u QoS Map Set IE and pushes it to the driver via
	// NL80211_CMD_SET_QOS_MAP for AP-side TX classification. Declared before
	// generate_interface / generate_mlo_interface so those closures capture it.
	let qos_map_set_csv = wifi.qos_map_set_render(
		ubbf_instances(config, 'Device.WiFi.X_UBBF_QoSMap')
	);

	/**
	 * Converts WMM access category to UCI prefix.
	 *
	 * @param {string} ac - Access category (BE/BK/VI/VO)
	 * @returns {string} UCI prefix (be/bk/vi/vo)
	 */
	function ac_to_wmm_prefix(ac) {
		let map = {
			'BE': 'be',
			'BK': 'bk',
			'VI': 'vi',
			'VO': 'vo'
		};
		return map[ac];
	}

	/**
	 * Converts TR-181 security mode to UCI encryption string.
	 *
	 * @param {string} mode - Security mode (WPA-Personal, WPA2-Personal, etc.)
	 * @returns {string} UCI encryption type
	 */
	function security_to_encryption(mode) {
		let map = {
			'WPA-Personal': 'psk',
			'WPA2-Personal': 'psk2',
			'WPA-WPA2-Personal': 'psk-mixed',
			'WPA3-Personal': 'sae',
			'WPA3-Personal-Transition': 'sae-mixed',
			'WPA-Enterprise': 'wpa',
			'WPA2-Enterprise': 'wpa2',
			'WPA-WPA2-Enterprise': 'wpa-mixed',
			'WPA3-Enterprise': 'wpa3',
		};
		return map[mode] ?? 'psk2';
	}

	/**
	 * Determines IEEE 802.11w management frame protection level.
	 *
	 * TR-181 applies MFPConfig to neither transition mode. For
	 * WPA3-Personal-Transition the level is left to wifi-scripts, which make
	 * MFP optional for the WPA2 clients and require it on a 6 GHz link.
	 *
	 * @param {string} mode - Security mode
	 * @param {string} mfp_config - MFP configuration (Required/Optional/Disabled)
	 * @returns {number|null} 0 (disabled), 1 (optional), 2 (required), or null
	 *                        to leave it to wifi-scripts
	 */
	function security_to_ieee80211w(mode, mfp_config) {
		if (mode == 'WPA3-Personal-Transition')
			return null;
		if (mfp_config == 'Required')
			return 2;
		if (mfp_config == 'Optional')
			return 1;
		if (mfp_config == 'Disabled')
			return 0;

		if (match(mode, /WPA3/))
			return 2;
		if (match(mode, /WPA2/))
			return 1;
		return 0;
	}

	/**
	 * Resolves SSID lower layer reference to radio name.
	 *
	 * @param {object} config - Configuration data
	 * @param {object} ssid_data - SSID data model object
	 * @returns {string|null} Radio name or null if not found
	 */
	function ssid_to_radio(config, ssid_data) {
		let lower = ssid_data.LowerLayers;
		if (!lower)
			return null;

		let m = match(lower, /Device\.WiFi\.Radio\.(\d+)/);
		if (!m)
			return null;

		let radio_inst = m[1];
		let radio = ubbf_get(config, `Device.WiFi.Radio.${radio_inst}`);
		return radio ? radio.Name : null;
	}

	/**
	 * Resolves SSID lower layer reference to the full radio config object.
	 *
	 * @param {object} config - Configuration data
	 * @param {object} ssid_data - SSID data model object
	 * @returns {object|null} Radio config object or null if not found
	 */
	function ssid_to_radio_data(config, ssid_data) {
		let lower = ssid_data?.LowerLayers;
		if (!lower)
			return null;

		let m = match(lower, /Device\.WiFi\.Radio\.(\d+)/);
		if (!m)
			return null;

		return ubbf_get(config, `Device.WiFi.Radio.${m[1]}`);
	}

	/**
	 * Concatenates the Payload bytes of every enabled X_UBBF_VendorIE entry
	 * on an AccessPoint into a single hex string for hostapd vendor_elements.
	 *
	 * @param {object} ap - AccessPoint config object
	 * @returns {string} Concatenated hex payload, empty string when none
	 */
	function vendor_elements_concat(ap) {
		let ies = ap?.X_UBBF_VendorIE;
		if (!ies)
			return '';

		let out = '';
		for (let inst, ie in ies) {
			if (!ie || !ubbf_to_bool(ie.Enable))
				continue;
			if (!ie.Payload)
				continue;
			out += ie.Payload;
		}
		return out;
	}

	/**
	 * Generates UCI wireless radio device section.
	 *
	 * @param {object} radio_data - Radio data model object
	 * @returns {string} UCI batch output for radio device
	 */
	function generate_radio(radio_data) {

		let radio_name = radio_data.Name;
		if (!radio_name)
			return;

		let disabled = !ubbf_to_bool(radio_data.Enable);

		uci_named_section(output, `wireless.${radio_name}`, 'wifi-device');
		uci_set_string(output, `wireless.${radio_name}.type`, 'mac80211');
		uci_set_boolean(output, `wireless.${radio_name}.disabled`, disabled);

		let band = wifi.band_to_uci(radio_data.OperatingFrequencyBand);
		uci_set_string(output, `wireless.${radio_name}.band`, band);

		let cap = capabilities.radios?.[band];
		if (cap?.path)
			uci_set_string(output, `wireless.${radio_name}.path`, cap.path);
		if (cap?.num_global_macaddr)
			uci_set_number(output, `wireless.${radio_name}.num_global_macaddr`, cap.num_global_macaddr);
		if (cap?.radio != null)
			uci_set_number(output, `wireless.${radio_name}.radio`, cap.radio);

		let phy_info = wifi.phy_for_band(band);
		let phy = phy_info?.phy;
		let band_idx = phy_info?.band_idx ?? 0;

		let channel = ubbf_to_int(radio_data.Channel);
		let auto_channel = ubbf_to_bool(radio_data.AutoChannelEnable);
		let requested_bw = radio_data.OperatingChannelBandwidth ?? '20MHz';

		if (auto_channel || channel == 0) {
			uci_set_string(output, `wireless.${radio_name}.channel`, 'auto');
		} else if (!wifi.channel_valid_for_bandwidth(phy, band_idx, channel, requested_bw)) {
			warn('Radio %s: channel %d invalid for %s, falling back to auto', radio_name, channel, requested_bw);
			uci_set_string(output, `wireless.${radio_name}.channel`, 'auto');
		} else {
			uci_set_number(output, `wireless.${radio_name}.channel`, channel);
		}

		let max_std = wifi.phy_max_standard(phy, band_idx);
		let max_bw = wifi.phy_max_bandwidth(phy, band_idx);

		let requested_std = wifi.standards_to_highest(radio_data.OperatingStandards);
		let htmode = wifi.clamp_htmode(requested_std, requested_bw, max_std, max_bw);
		uci_set_string(output, `wireless.${radio_name}.htmode`, htmode);

		if (radio_data.RegulatoryDomain) {
			let country = substr(radio_data.RegulatoryDomain, 0, 2);
			if (country)
				uci_set_string(output, `wireless.${radio_name}.country`, uc(country));
		}

		// A render can run before the phy is registered, and the power is
		// a percentage of a cap that is only known then. Write nothing in
		// that case: the radio keeps the driver default until the next
		// render, which is better than a power derived from a guess.
		let max_dbm = wifi.phy_max_txpower(phy, band_idx);
		if (max_dbm != null) {
			let txpower_pct = ubbf_to_int(radio_data.TransmitPower);
			let txpower_dbm = wifi.txpower_pct_to_dbm(txpower_pct, max_dbm);
			if (txpower_dbm != null)
				uci_set_number(output, `wireless.${radio_name}.txpower`, txpower_dbm);
		}

		if (ubbf_to_bool(radio_data.IEEE80211hEnabled))
			uci_set_boolean(output, `wireless.${radio_name}.doth`, true);

		// hostapd background-CAC keeps service alive across a DFS channel
		// switch. 2.4 GHz has no DFS; on 5/6 GHz the option is harmless when
		// the driver lacks the capability (hostapd silently ignores).
		if (band != '2g' && ubbf_to_bool(radio_data.X_UBBF_BackgroundDFSEnable))
			uci_list_string(output, `wireless.${radio_name}.hostapd_options`, 'enable_background_radar=1');

		let beacon = ubbf_to_int(radio_data.BeaconPeriod);
		if (beacon != null && beacon > 0)
			uci_set_number(output, `wireless.${radio_name}.beacon_int`, beacon);

		let dtim = ubbf_to_int(radio_data.DTIMPeriod);
		if (dtim != null && dtim > 0)
			uci_set_number(output, `wireless.${radio_name}.dtim_period`, dtim);

		let frag = ubbf_to_int(radio_data.FragmentationThreshold);
		if (frag != null && frag > 0)
			uci_set_number(output, `wireless.${radio_name}.frag`, frag);

		let rts = ubbf_to_int(radio_data.RTSThreshold);
		if (rts != null && rts > 0)
			uci_set_number(output, `wireless.${radio_name}.rts`, rts);

		let gi = radio_data.GuardInterval;
		if (gi == '400nsec')
			uci_set_boolean(output, `wireless.${radio_name}.short_gi`, true);

		return;
	}

	/**
	 * Finds access point data for a given SSID instance.
	 *
	 * @param {object} config - Configuration data
	 * @param {string} ssid_inst - SSID instance number
	 * @returns {object|null} Access point data or null if not found
	 */
	function ap_data_get(config, ssid_inst) {
		let aps = ubbf_instances(config, 'Device.WiFi.AccessPoint');
		for (let ap in aps) {
			if (!ap)
				continue;
			let ref = ap.SSIDReference;
			if (!ref)
				continue;
			let m = match(ref, /Device\.WiFi\.SSID\.(\d+)/);
			if (m && m[1] == ssid_inst)
				return ap;
		}
		return null;
	}

	/**
	 * Finds QoS shaper targeting a given SSID instance.
	 *
	 * @param {object} config - Configuration data
	 * @param {string} ssid_inst - SSID instance number
	 * @returns {object|null} Shaper data or null if not found
	 */
	function ssid_shaper_get(config, ssid_inst) {
		let shapers = ubbf_instances(config, 'Device.QoS.Shaper');
		let ssid_path = `Device.WiFi.SSID.${ssid_inst}`;

		for (let shaper in shapers) {
			if (!ubbf_to_bool(shaper.Enable))
				continue;
			if (shaper.Interface == ssid_path)
				return shaper;
		}
		return null;
	}

	/**
	 * Generates UCI wireless interface section for an SSID.
	 *
	 * @param {string} ssid_inst - SSID instance number
	 * @param {object} ssid_data - SSID data model object
	 * @returns {string} UCI batch output for wifi interface
	 */
	function generate_interface(ssid_inst, ssid_data) {

		let radio_name = ssid_to_radio(config, ssid_data);
		if (!radio_name)
			return;

		let ap = ap_data_get(config, ssid_inst);

		let disabled = !ubbf_to_bool(ssid_data.Enable);
		if (ap && !ubbf_to_bool(ap.Enable))
			disabled = true;

		let ssid_path = `Device.WiFi.SSID.${ssid_inst}`;
		let network = render_state.ssid?.[ssid_path]?.network;
		if (!network) {
			warn('SSID %s has no Network configured, skipping interface generation', ssid_data.SSID);
			return;
		}

		let security = ap?.Security;
		if (!security) {
			warn('SSID %s: Security configuration required, skipping', ssid_data.SSID);
			return;
		}

		let mode = security.ModeEnabled;
		let is_sae = match(mode, /WPA3/) && !match(mode, /Enterprise/);
		let is_enterprise = match(mode, /Enterprise/);
		if (!is_enterprise) {
			if (is_sae && !security.SAEPassphrase) {
				warn('SSID %s: %s requires SAEPassphrase, skipping', ssid_data.SSID, mode);
				return;
			}
			if (!is_sae && !security.PreSharedKey) {
				warn('SSID %s: %s requires PreSharedKey, skipping', ssid_data.SSID, mode);
				return;
			}
		}

		uci_section(output, 'wireless wifi-iface');
		uci_set_string(output, 'wireless.@wifi-iface[-1].device', radio_name);
		uci_set_string(output, 'wireless.@wifi-iface[-1].mode', 'ap');
		uci_set_boolean(output, 'wireless.@wifi-iface[-1].disabled', disabled);
		uci_set_string(output, 'wireless.@wifi-iface[-1].ssid', ssid_data.SSID);
		uci_set_number(output, 'wireless.@wifi-iface[-1].ubbf_ssid', ssid_inst);
		uci_set_string(output, 'wireless.@wifi-iface[-1].network', network);

		// Emit RNR on every BSS as soon as a co-located 6 GHz radio exists.
		// Clients on the 2.4/5 GHz side are the ones that need to learn about
		// the 6 GHz BSS out-of-band; the flag on the BSS's own radio lets an
		// ACS turn it off per radio if desired.
		let radio_data = ssid_to_radio_data(config, ssid_data);
		if (has_6ghz_radio && ubbf_to_bool(radio_data?.X_UBBF_ReducedNeighborReportEnable))
			uci_set_boolean(output, 'wireless.@wifi-iface[-1].rnr', true);

		let macaddr = ssid_data.MACAddress ?? ssid_data.BSSID;
		if (macaddr && macaddr != '')
			uci_set_string(output, 'wireless.@wifi-iface[-1].macaddr', macaddr);

		if (ap) {
			// Inject vendor IEs into beacons via hostapd vendor_elements.
			let vendor_payload = vendor_elements_concat(ap);
			if (vendor_payload != '')
				uci_set_string(output, 'wireless.@wifi-iface[-1].vendor_elements', vendor_payload);

			// Global 802.11u QoS Map Set, scoped to WMM-enabled BSSes only.
			if (qos_map_set_csv != '' && ubbf_to_bool(ap.WMMEnable))
				uci_set_string(output, 'wireless.@wifi-iface[-1].iw_qos_map_set', qos_map_set_csv);


			if (ap.SSIDAdvertisementEnabled != null && !ubbf_to_bool(ap.SSIDAdvertisementEnabled))
				uci_set_boolean(output, 'wireless.@wifi-iface[-1].hidden', true);

			if (ubbf_to_bool(ap.WMMEnable))
				uci_set_boolean(output, 'wireless.@wifi-iface[-1].wmm', true);

			if (ubbf_to_bool(ap.UAPSDEnable))
				uci_set_boolean(output, 'wireless.@wifi-iface[-1].wmm_apsd', true);

			let max_assoc = ubbf_to_int(ap.MaxAssociatedDevices);
			if (max_assoc != null && max_assoc > 0)
				uci_set_number(output, 'wireless.@wifi-iface[-1].maxassoc', max_assoc);

			if (ubbf_to_bool(ap.IsolationEnable))
				uci_set_boolean(output, 'wireless.@wifi-iface[-1].isolate', true);

			if (ubbf_to_bool(ap.MACAddressControlEnabled)) {
				let acl_mode = ap.MACAddressControlMode;
				if (acl_mode == 'DenyListed') {
					uci_set_string(output, 'wireless.@wifi-iface[-1].macfilter', 'deny');
					if (ap.DeniedMACAddress) {
						let macs = csv_to_list(ap.DeniedMACAddress);
						for (let mac in macs)
							uci_list_string(output, 'wireless.@wifi-iface[-1].maclist', mac);
					}
				} else {
					uci_set_string(output, 'wireless.@wifi-iface[-1].macfilter', 'allow');
					if (ap.AllowedMACAddress) {
						let macs = csv_to_list(ap.AllowedMACAddress);
						for (let mac in macs)
							uci_list_string(output, 'wireless.@wifi-iface[-1].maclist', mac);
					}
				}
			}

			let encryption = security_to_encryption(mode);
			uci_set_string(output, 'wireless.@wifi-iface[-1].encryption', encryption);

			if (is_enterprise) {
				if (security.RadiusServerIPAddr)
					uci_set_string(output, 'wireless.@wifi-iface[-1].auth_server', security.RadiusServerIPAddr);
				let auth_port = ubbf_to_int(security.RadiusServerPort);
				if (auth_port != null && auth_port > 0)
					uci_set_number(output, 'wireless.@wifi-iface[-1].auth_port', auth_port);
				if (security.RadiusSecret)
					uci_set_string(output, 'wireless.@wifi-iface[-1].auth_secret', security.RadiusSecret);
			} else {
				let key = is_sae ? security.SAEPassphrase : security.PreSharedKey;
				uci_set_string(output, 'wireless.@wifi-iface[-1].key', key);
			}

			let ieee80211w = security_to_ieee80211w(mode, security.MFPConfig);
			uci_set_number(output, 'wireless.@wifi-iface[-1].ieee80211w', ieee80211w);

			let rekey = ubbf_to_int(security.RekeyingInterval);
			if (rekey != null && rekey > 0)
				uci_set_number(output, 'wireless.@wifi-iface[-1].wpa_group_rekey', rekey);

			let accounting = ap.Accounting;
			if (accounting && ubbf_to_bool(accounting.Enable)) {
				if (accounting.ServerIPAddr)
					uci_set_string(output, 'wireless.@wifi-iface[-1].acct_server', accounting.ServerIPAddr);
				let acct_port = ubbf_to_int(accounting.ServerPort);
				if (acct_port != null && acct_port > 0)
					uci_set_number(output, 'wireless.@wifi-iface[-1].acct_port', acct_port);
				if (accounting.Secret)
					uci_set_string(output, 'wireless.@wifi-iface[-1].acct_secret', accounting.Secret);
			}

			let wps = ap.WPS;
			if (wps && ubbf_to_bool(wps.Enable)) {
				let methods = wps.ConfigMethodsEnabled ?? 'PushButton';
				if (index(methods, 'PushButton') >= 0)
					uci_set_boolean(output, 'wireless.@wifi-iface[-1].wps_pushbutton', true);
				let pin_requested = (index(methods, 'PIN') >= 0 && wps.PIN);
				if (pin_requested)
					uci_set_string(output, 'wireless.@wifi-iface[-1].wps_pin', wps.PIN);
				if (index(methods, 'Label') >= 0 || pin_requested)
					uci_set_boolean(output, 'wireless.@wifi-iface[-1].wps_label', true);
			}

			let ac_entries = ap.AC;
			if (ac_entries) {
				for (let ac_inst, ac_data in ac_entries) {
					let prefix = ac_to_wmm_prefix(ac_data.AccessCategory);
					if (!prefix)
						continue;

					let aifs = ubbf_to_int(ac_data.AIFSN);
					if (aifs != null)
						uci_set_number(output, `wireless.@wifi-iface[-1].wmm_ac_${prefix}_aifs`, aifs);

					let cwmin = ubbf_to_int(ac_data.ECWMin);
					if (cwmin != null)
						uci_set_number(output, `wireless.@wifi-iface[-1].wmm_ac_${prefix}_cwmin`, cwmin);

					let cwmax = ubbf_to_int(ac_data.ECWMax);
					if (cwmax != null)
						uci_set_number(output, `wireless.@wifi-iface[-1].wmm_ac_${prefix}_cwmax`, cwmax);

					let txop = ubbf_to_int(ac_data.TxOpMax);
					if (txop != null)
						uci_set_number(output, `wireless.@wifi-iface[-1].wmm_ac_${prefix}_txop_limit`, txop);

					let acm = ubbf_to_bool(ac_data.AckPolicy);
					uci_set_number(output, `wireless.@wifi-iface[-1].wmm_ac_${prefix}_acm`, acm ? 1 : 0);
				}
			}
		}

		let shaper = ssid_shaper_get(config, ssid_inst);
		if (shaper)
			uci_set_boolean(output, 'wireless.@wifi-iface[-1].ratelimit', true);

		return;
	}

	/**
	 * Generates UCI wireless MLO interface section.
	 *
	 * @param {object} mlo_group - MLO group with radios array, representative SSID/AP
	 *                             and the resolved security
	 * @returns {string} UCI batch output for MLO wifi interface
	 */
	function generate_mlo_interface(mlo_group) {

		let ssid_data = mlo_group.ssid_data;
		let ssid_inst = mlo_group.ssid_inst;
		let ap = mlo_group.ap;

		let disabled = !ubbf_to_bool(ssid_data.Enable);
		if (ap && !ubbf_to_bool(ap.Enable))
			disabled = true;

		let ssid_path = `Device.WiFi.SSID.${ssid_inst}`;
		let network = render_state.ssid?.[ssid_path]?.network;
		if (!network)
			return;

		let security = mlo_group.security;
		if (!security)
			return;

		let mode = security.ModeEnabled;
		let is_sae = match(mode, /WPA3/) && !match(mode, /Enterprise/);
		let is_enterprise = match(mode, /Enterprise/);
		if (!is_enterprise) {
			if (is_sae && !security.SAEPassphrase)
				return;
			if (!is_sae && !security.PreSharedKey)
				return;
		}

		uci_section(output, 'wireless wifi-iface');
		uci_set_boolean(output, 'wireless.@wifi-iface[-1].mlo', true);

		for (let radio_name in mlo_group.radios)
			uci_list_string(output, 'wireless.@wifi-iface[-1].device', radio_name);

		// MLO links span bands, so emit RNR whenever a 6 GHz radio exists on
		// the board; per-radio gating is not meaningful here.
		if (has_6ghz_radio)
			uci_set_boolean(output, 'wireless.@wifi-iface[-1].rnr', true);

		// Same vendor_elements injection as the single-link path.
		let mlo_vendor_payload = vendor_elements_concat(ap);
		if (mlo_vendor_payload != '')
			uci_set_string(output, 'wireless.@wifi-iface[-1].vendor_elements', mlo_vendor_payload);

		if (qos_map_set_csv != '' && ubbf_to_bool(ap?.WMMEnable))
			uci_set_string(output, 'wireless.@wifi-iface[-1].iw_qos_map_set', qos_map_set_csv);

		uci_set_string(output, 'wireless.@wifi-iface[-1].mode', 'ap');
		uci_set_boolean(output, 'wireless.@wifi-iface[-1].disabled', disabled);
		uci_set_string(output, 'wireless.@wifi-iface[-1].ssid', ssid_data.SSID);
		uci_set_number(output, 'wireless.@wifi-iface[-1].ubbf_ssid', ssid_inst);
		uci_set_string(output, 'wireless.@wifi-iface[-1].network', network);

		let encryption = security_to_encryption(mode);
		uci_set_string(output, 'wireless.@wifi-iface[-1].encryption', encryption);

		if (is_enterprise) {
			if (security.RadiusServerIPAddr)
				uci_set_string(output, 'wireless.@wifi-iface[-1].auth_server', security.RadiusServerIPAddr);
			let auth_port = ubbf_to_int(security.RadiusServerPort);
			if (auth_port != null && auth_port > 0)
				uci_set_number(output, 'wireless.@wifi-iface[-1].auth_port', auth_port);
			if (security.RadiusSecret)
				uci_set_string(output, 'wireless.@wifi-iface[-1].auth_secret', security.RadiusSecret);
		} else {
			let key = is_sae ? security.SAEPassphrase : security.PreSharedKey;
			uci_set_string(output, 'wireless.@wifi-iface[-1].key', key);
		}

		let ieee80211w = security_to_ieee80211w(mode, security.MFPConfig);
		uci_set_number(output, 'wireless.@wifi-iface[-1].ieee80211w', ieee80211w);

		if (ap) {
			if (ap.SSIDAdvertisementEnabled != null && !ubbf_to_bool(ap.SSIDAdvertisementEnabled))
				uci_set_boolean(output, 'wireless.@wifi-iface[-1].hidden', true);
			if (ubbf_to_bool(ap.WMMEnable))
				uci_set_boolean(output, 'wireless.@wifi-iface[-1].wmm', true);
			if (ubbf_to_bool(ap.UAPSDEnable))
				uci_set_boolean(output, 'wireless.@wifi-iface[-1].wmm_apsd', true);
		}

		return;
	}

	/**
	 * Resolves the one security configuration an AP MLD runs on all links.
	 *
	 * All APs affiliated with an AP MLD advertise the same RSNE apart from
	 * the AKM suite list and MFPR, and share at least one AKM (802.11be
	 * 12.6.2). WPA2-Personal and WPA3-Personal links, as a 6 GHz link
	 * forces, share none, so such a group runs WPA3-Personal-Transition:
	 * SAE is common to every link, and wifi-scripts drop PSK and require MFP
	 * on a 6 GHz link. TR-181 takes the transition passphrase from
	 * SAEPassphrase.
	 *
	 * @param {array} aps - AccessPoint objects affiliated with the group
	 * @returns {object|null} Security object for the AP MLD
	 */
	function mlo_security_resolve(aps) {
		const personal = [ 'WPA2-Personal', 'WPA3-Personal', 'WPA3-Personal-Transition' ];
		let modes = uniq(map(aps, (ap) => ap.Security?.ModeEnabled));

		if (length(modes) == 1)
			return aps[0].Security;

		if (length(filter(modes, (mode) => index(personal, mode) < 0))) {
			log_warn('AP MLD links mix security modes %s; using the first', join(', ', modes));
			return aps[0].Security;
		}

		let sae_ap = filter(aps, (ap) => ap.Security.ModeEnabled != 'WPA2-Personal')[0];
		let security = { ...sae_ap.Security, ModeEnabled: 'WPA3-Personal-Transition' };

		let ignored = filter(aps, (ap) => ap.Security.ModeEnabled == 'WPA2-Personal' &&
			ap.Security.PreSharedKey != security.SAEPassphrase);
		if (length(ignored))
			log_warn('AP MLD runs WPA3-Personal-Transition; %d WPA2-Personal link passphrase(s) differ and are ignored',
				 length(ignored));

		return security;
	}

	/**
	 * Resolves an AccessPoint to the AP MLD link it would be.
	 *
	 * @param {object} ap - AccessPoint object
	 * @returns {object|null} { ap, ssid_inst, ssid_data, radio, path } where
	 *                        path is the device path of the radio's wiphy
	 */
	function mlo_link_get(ap) {
		let m = match(ap.SSIDReference, /Device\.WiFi\.SSID\.(\d+)/);
		if (!m)
			return null;

		let ssid_inst = m[1];
		let ssid_data = ubbf_get(config, `Device.WiFi.SSID.${ssid_inst}`);
		if (!ssid_data)
			return null;

		let radio_data = ssid_to_radio_data(config, ssid_data);
		if (!radio_data?.Name)
			return null;

		let band = wifi.band_to_uci(radio_data.OperatingFrequencyBand);
		return { ap, ssid_inst, ssid_data, radio: radio_data.Name,
			 path: capabilities.radios?.[band]?.path };
	}

	/**
	 * Builds MLO groups from APMLDTemplate instances and linked AccessPoints.
	 *
	 * @returns {object} { groups: array of mlo_group, consumed: set of SSID instance strings }
	 */
	function mlo_groups_build() {
		let groups = [];
		let consumed = {};

		let templates = ubbf_instances(config, 'Device.WiFi.Templates.APMLDTemplate');
		if (length(templates) == 0)
			return { groups, consumed };

		let aps = ubbf_instances(config, 'Device.WiFi.AccessPoint');

		for (let tmpl in templates) {
			if (!tmpl || !ubbf_to_bool(tmpl.MLOEnable))
				continue;

			let tmpl_path = `Device.WiFi.Templates.APMLDTemplate.${tmpl['.instance']}`;
			let links = [];

			for (let ap in aps) {
				if (!ap || ap.APMLDTemplateRef != tmpl_path)
					continue;
				let link = mlo_link_get(ap);
				if (link)
					push(links, link);
			}

			let selected = wifi.mld_links_select(links, (link) => link.path);
			if (length(selected.rest) && length(selected.links) >= 2)
				log_warn('AP MLD %s spans wiphys; single-link BSS on %s', tmpl_path,
					 join(', ', map(selected.rest, (link) => link.radio)));

			// 802.11be Multi-Link Operation requires at least two affiliated links.
			if (length(selected.links) < 2)
				continue;

			for (let link in selected.links)
				consumed[link.ssid_inst] = true;

			let first = selected.links[0];
			push(groups, {
				radios: map(selected.links, (link) => link.radio),
				ssid_data: first.ssid_data,
				ssid_inst: first.ssid_inst,
				ap: first.ap,
				security: mlo_security_resolve(map(selected.links, (link) => link.ap))
			});
		}

		return { groups, consumed };
	}

	let radios = ubbf_instances(config, 'Device.WiFi.Radio');
	let ssids = ubbf_instances(config, 'Device.WiFi.SSID');

	if (length(radios) == 0 && length(ssids) == 0)
		return;

	let easymesh_network = ubbf_get(config, 'Device.WiFi.DataElements.Network');
	let easymesh_agent_enabled = ubbf_to_bool(easymesh_network?.X_UBBF_EasyMesh?.Agent?.Enable);

	let mlo = mlo_groups_build();


	for (let radio_data in radios) {
		if (!radio_data)
			continue;
		generate_radio(radio_data);
	}

	if (!easymesh_agent_enabled) {
		for (let group in mlo.groups)
			generate_mlo_interface(group);

		for (let ssid_data in ssids) {
			if (!ssid_data)
				continue;
			if (mlo.consumed[ssid_data['.instance']])
				continue;
			generate_interface(ssid_data['.instance'], ssid_data);
		}
	}
}
uci_comment(output, '# generated by wifi.uc');
render_config();
