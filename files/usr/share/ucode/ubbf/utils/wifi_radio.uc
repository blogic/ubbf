'use strict';

const BAND_ORDER = [ '2g', '5g', '6g' ];

/**
 * Maps an IEEE 802.11 channel number plus TR-181 band label to a centre
 * frequency in MHz, for the bands UBBF radios run on.
 *
 * @param {string} band - TR-181 band ('2.4GHz', '5GHz', '6GHz')
 * @param {number} channel - Channel number
 * @returns {number} Centre frequency in MHz, 0 when the channel is out of the band's range
 */
export function channel_to_freq(band, channel) {
	if (band == '2.4GHz') {
		if (channel == 14)
			return 2484;
		if (channel >= 1 && channel <= 13)
			return 2407 + channel * 5;
	} else if (band == '5GHz') {
		if (channel >= 36 && channel <= 177)
			return 5000 + channel * 5;
	} else if (band == '6GHz') {
		if (channel >= 1 && channel <= 233)
			return 5950 + channel * 5;
	}
	return 0;
};

/**
 * Checks whether a radio can operate on a frequency.
 *
 * The frequency ranges are those nl80211 reports for the radio of a
 * multi-radio wiphy. A radio without ranges has the whole band of its wiphy.
 *
 * @param {object} radio - Capability radio with optional freq_ranges ([start, end] in kHz)
 * @param {number} freq - Centre frequency in MHz
 * @returns {boolean} True if the frequency lies in one of the radio's ranges
 */
export function radio_freq_usable(radio, freq) {
	if (!length(radio?.freq_ranges))
		return true;

	for (let range in radio.freq_ranges) {
		if (freq * 1000 >= range[0] && freq * 1000 <= range[1])
			return true;
	}

	return false;
};

/**
 * Lists the bands of a radio's frequency ranges. A range belongs to the
 * band it starts in, as umapd counts it, so a 5 GHz range that ends on
 * 6 GHz channel 2 gives no 6 GHz.
 *
 * @param {object} radio - Capability radio with optional freq_ranges
 * @returns {array} UCI band names, empty for a radio without ranges
 */
export function radio_bands(radio) {
	let bands = [];

	for (let range in radio?.freq_ranges ?? []) {
		let start = range[0] / 1000;
		let band = null;
		if (start >= 2400 && start < 2500)
			band = '2g';
		else if (start >= 5000 && start < 5900)
			band = '5g';
		else if (start >= 5900 && start < 7200)
			band = '6g';

		if (band && index(bands, band) < 0)
			push(bands, band);
	}

	return bands;
};

/**
 * Restricts a band of a PHY to the frequencies of one of its radios.
 *
 * @param {object} phy - PHY object from iwinfo
 * @param {number} band_idx - Band index into wiphy_bands
 * @param {object} radio - Capability radio with optional freq_ranges
 * @returns {object} The PHY itself, or a copy whose band holds only the radio's frequencies
 */
export function phy_radio_restrict(phy, band_idx, radio) {
	let band = phy?.wiphy_bands?.[band_idx];
	if (!band || !length(radio?.freq_ranges))
		return phy;

	let bands = [ ...phy.wiphy_bands ];
	bands[band_idx] = {
		...band,
		freqs: filter(band.freqs ?? [], (freq) => radio_freq_usable(radio, freq.freq))
	};

	return { ...phy, wiphy_bands: bands };
};

/**
 * @param {object} radio - Capability radio
 * @returns {number} Lowest frequency of the radio in kHz, 0 for a radio that has the whole band
 */
function radio_freq_low(radio) {
	let low = 0;

	for (let range in radio.freq_ranges ?? []) {
		if (!low || range[0] < low)
			low = range[0];
	}

	return low;
}

/**
 * Orders capability radios as the Device.WiFi.Radio instances list them.
 *
 * The first radio of each band comes in band order, so a device with one
 * radio per band keeps its instance numbers. Each further radio of a band
 * is appended in the same way. Within a band, radios go by their lowest
 * frequency, then by their position in the input.
 *
 * @param {array} radios - Capability radios, each with a band
 * @returns {array} The radios in instance order
 */
export function radios_order(radios) {
	let entries = [];
	for (let i = 0; i < length(radios); i++)
		push(entries, { radio: radios[i], pos: i, low: radio_freq_low(radios[i]),
				band_pos: index(BAND_ORDER, radios[i].band) });

	let in_band = sort([ ...entries ], (a, b) =>
		(a.band_pos - b.band_pos) || (a.low - b.low) || (a.pos - b.pos));

	let count = {};
	for (let entry in in_band) {
		entry.rank = count[entry.radio.band] ?? 0;
		count[entry.radio.band] = entry.rank + 1;
	}

	return map(sort(entries, (a, b) => (a.rank - b.rank) || (a.band_pos - b.band_pos)),
		   (entry) => entry.radio);
};

/**
 * Checks whether a wifi-device path names a wiphy of board.json.
 *
 * @param {string|array} wiphy_path - Path or paths of the board.json wlan entry
 * @param {string} path - Path of the wifi-device section
 * @param {boolean} suffix - Also accept a section path that ends in the wiphy's
 *                           path, as wifi detection does
 * @returns {boolean} True if the path names the wiphy
 */
function wiphy_path_match(wiphy_path, path, suffix) {
	for (let p in (type(wiphy_path) == 'array' ? wiphy_path : [ wiphy_path ])) {
		if (p == path || (suffix && p && substr(path, -length(p)) == p))
			return true;
	}

	return false;
}

/**
 * Checks whether a wifi-device section belongs to a wiphy the device has.
 *
 * Detection keeps the section of a wiphy whose path changed and adds one
 * for the new path, so a section can name a wiphy that is gone. Without
 * a board.json wlan list, every section counts.
 *
 * @param {object} board - Parsed board.json
 * @param {string} path - Path of the wifi-device section
 * @returns {boolean} True unless board.json lists wiphys and none has the path
 */
function wiphy_present(board, path) {
	if (!length(board?.wlan))
		return true;

	for (let phy_name, phy_data in board.wlan) {
		if (wiphy_path_match(phy_data.path, path, true))
			return true;
	}

	return false;
}

/**
 * Adds what board.json knows about a radio's wiphy: its name, the modes of
 * the band and, for a radio of a multi-radio wiphy, its frequency ranges.
 *
 * @param {object} radio - Capability radio with path, band and optional radio index
 * @param {object} board - Parsed board.json
 */
function radio_wiphy_add(radio, board) {
	for (let phy_name, phy_data in board?.wlan) {
		if (!wiphy_path_match(phy_data.path, radio.path, false))
			continue;

		radio.phy = phy_name;

		let band_info = phy_data.info?.bands?.[uc(radio.band)];
		if (band_info?.modes)
			radio.modes = band_info.modes;

		if (radio.radio == null)
			break;

		let wiphy_radio = filter(phy_data.info?.radios ?? [], (r) => r.index == radio.radio)[0];
		if (length(wiphy_radio?.freq_ranges))
			radio.freq_ranges = wiphy_radio.freq_ranges;

		break;
	}
}

/**
 * Lists the radios of the device, one per wifi-device section.
 *
 * @param {object} board - Parsed board.json
 * @param {object} wireless_config - The wireless UCI package, by section name
 * @returns {array} Capability radios in section order
 */
export function radios_extract(board, wireless_config) {
	let radios = [];

	for (let section_name, section_data in wireless_config) {
		if (section_data['.type'] != 'wifi-device')
			continue;

		let path = section_data.path;
		let band = section_data.band;
		if (!path || !band || index(BAND_ORDER, band) < 0)
			continue;
		if (!wiphy_present(board, path))
			continue;

		let radio = { band, path, name: section_name };

		if (section_data.radio != null)
			radio.radio = int(section_data.radio);
		if (section_data.num_global_macaddr)
			radio.num_global_macaddr = int(section_data.num_global_macaddr);

		radio_wiphy_add(radio, board);
		push(radios, radio);
	}

	return radios;
};

/**
 * Finds the capability radio a Device.WiFi.Radio instance runs on.
 *
 * A band with one radio maps to it whatever the instance's Name. Where a
 * band has several radios, the Name, which is the wifi-device section the
 * radio was detected as, tells them apart.
 *
 * @param {array} radios - Capability radios
 * @param {string} band - UCI band of the instance ('2g', '5g', '6g')
 * @param {string} name - Name of the instance
 * @returns {object|null} Capability radio, or null when none matches
 */
export function radio_capability_find(radios, band, name) {
	let candidates = filter(type(radios) == 'array' ? radios : [], (radio) => radio.band == band);
	if (length(candidates) == 1)
		return candidates[0];

	return filter(candidates, (radio) => radio.name == name)[0];
};

/**
 * Checks whether a radio has a frequency between two others.
 *
 * @param {object} radio - Capability radio with optional freq_ranges ([start, end] in kHz)
 * @param {number} low - Lower edge in MHz
 * @param {number} high - Upper edge in MHz
 * @returns {boolean} True if a range of the radio overlaps low to high, or the radio has no ranges
 */
export function radio_freq_overlaps(radio, low, high) {
	if (!length(radio?.freq_ranges))
		return true;

	for (let range in radio.freq_ranges) {
		if (range[0] < high * 1000 && range[1] > low * 1000)
			return true;
	}

	return false;
};

const TR181_BAND_UCI = { '2.4GHz': '2g', '5GHz': '5g', '6GHz': '6g' };

// U-NII sub-bands of the DataElements Band values, as edges in MHz
const DE_BANDS = {
	'2.4': { band: '2.4GHz' },
	'5': { band: '5GHz' },
	'5_UNII_1': { band: '5GHz', edges: [ [ 5150, 5250 ] ] },
	'5_UNII_2': { band: '5GHz', edges: [ [ 5250, 5350 ], [ 5470, 5725 ] ] },
	'5_UNII_3': { band: '5GHz', edges: [ [ 5725, 5850 ] ] },
	'5_UNII_4': { band: '5GHz', edges: [ [ 5850, 5925 ] ] },
	'6': { band: '6GHz' },
	'6_UNII_5': { band: '6GHz', edges: [ [ 5925, 6425 ] ] },
	'6_UNII_6': { band: '6GHz', edges: [ [ 6425, 6525 ] ] },
	'6_UNII_7': { band: '6GHz', edges: [ [ 6525, 6875 ] ] },
	'6_UNII_8': { band: '6GHz', edges: [ [ 6875, 7125 ] ] }
};

/**
 * Finds the Device.WiFi.Radio instance for a DataElements Band value.
 *
 * The first instance of the band whose radio covers the sub-band wins.
 * Where none covers it, the first instance of the band does. An unknown
 * value stands for 2.4 GHz.
 *
 * @param {object} radios - Device.WiFi.Radio instances by instance number
 * @param {array} cap_radios - Capability radios
 * @param {string} de_band - DataElements Band value, for example '5_UNII_3'
 * @returns {string|null} Instance number, or null when the band has no instance
 */
export function radio_instance_for_band(radios, cap_radios, de_band) {
	let target = DE_BANDS[de_band] ?? DE_BANDS['2.4'];
	let uci_band = TR181_BAND_UCI[target.band];
	let first;

	for (let inst in sort(keys(radios ?? {}), (a, b) => +a - +b)) {
		let radio = radios[inst];
		if (radio?.OperatingFrequencyBand != target.band)
			continue;

		first ??= inst;
		let cap = radio_capability_find(cap_radios, uci_band, radio.Name);
		if (!target.edges || length(filter(target.edges, (e) => radio_freq_overlaps(cap, e[0], e[1]))))
			return inst;
	}

	return first;
};
