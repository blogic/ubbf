'use strict';

import { radio_address_derive } from 'ubbf';

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
 * @param {number} freq - Frequency in MHz
 * @returns {string|null} UCI band of the frequency, as umapd counts it
 */
function freq_band(freq) {
	if (freq >= 2400 && freq < 2500)
		return '2g';
	if (freq >= 5000 && freq < 5900)
		return '5g';
	if (freq >= 5900 && freq < 7200)
		return '6g';
	if (freq >= 57000)
		return '60g';
	return null;
}

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
		let band = freq_band(range[0] / 1000);
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

/**
 * @param {number} freq - Centre frequency of a channel in MHz
 * @returns {string|null} UCI band of the channel, with the edges of umapd's
 *                        frequencyToBand() in rrmd/opclass.uc
 */
function channel_freq_band(freq) {
	if (freq >= 2412 && freq <= 2484)
		return '2g';
	if ((freq >= 4910 && freq <= 4980) || (freq >= 5170 && freq <= 5885))
		return '5g';
	if (freq >= 5925 && freq <= 7125)
		return '6g';
	if (freq >= 57000 && freq <= 71000)
		return '60g';
	return null;
}

// The order of the bands in umapd's band bits
const BAND_BIT = { '2g': 1, '5g': 2, '60g': 4, '6g': 8 };

/**
 * @param {string} mac - MAC address, colon separated
 * @returns {array|null} Its six octets, or null when it is no MAC address
 */
function mac_octets(mac) {
	let bytes = mac ? hexdec(mac, ':') : null;
	if (length(bytes) != 6)
		return null;

	let octets = [];
	for (let i = 0; i < 6; i++)
		push(octets, ord(bytes, i));
	return octets;
}

/**
 * Lists the radios of a wiphy as umapd counts them (wiphy_radios_get() in
 * rrmd/opclass.uc): one entry per band of each nl80211 radio, or one per
 * band of a wiphy that names no radios. Within a band, rank orders the
 * entries by the lowest start of their ranges.
 *
 * @param {object} phy - Entry of the nl80211 wiphy dump
 * @returns {array} Entries { band, index, low, rank }
 */
export function wiphy_radios_get(phy) {
	let entries = [];

	for (let radio in phy?.radios ?? []) {
		let by_band = {};
		for (let range in radio?.freq_ranges ?? []) {
			let band = freq_band(range.start / 1000);
			if (!band)
				continue;
			by_band[band] ??= { band, index: radio.index, low: range.start };
			by_band[band].low = min(by_band[band].low, range.start);
		}
		push(entries, ...values(by_band));
	}

	if (!length(entries)) {
		for (let wiphy_band in phy?.wiphy_bands ?? []) {
			let band = channel_freq_band(wiphy_band?.freqs?.[0]?.freq);
			if (band)
				push(entries, { band, index: null, low: 0 });
		}
	}

	let count = {};
	for (let entry in sort([ ...entries ], (a, b) => (BAND_BIT[a.band] - BAND_BIT[b.band]) ||
			       (a.low - b.low) || ((a.index ?? 0) - (b.index ?? 0)))) {
		entry.rank = count[entry.band] ?? 0;
		count[entry.band] = entry.rank + 1;
	}

	return entries;
};

/**
 * @param {string} mac - MAC address of the wiphy
 * @param {string} band - UCI band name
 * @param {number} rank - Rank of the radio in the band
 * @returns {string} Key of the radio in radio_addresses_assign()
 */
export function radio_address_key(mac, band, rank) {
	return rank ? `${lc(mac)}/${band}/${rank}` : `${lc(mac)}/${band}`;
};

/**
 * @param {string} mac - MAC address of the wiphy
 * @param {object} taken - Addresses in use, as keys
 * @returns {string|null} The next address of the wiphy's locally administered
 *                        space, counting the last octet up, that is not taken
 */
function radio_address_next(mac, taken) {
	let octets = mac_octets(mac);
	if (!octets)
		return null;

	let last = octets[5];
	octets[0] |= 0x02;
	for (let offset = 1; offset <= 256; offset++) {
		octets[5] = (last + offset) & 0xff;
		let address = sprintf('%02x:%02x:%02x:%02x:%02x:%02x', ...octets);
		if (!taken[address])
			return address;
	}

	return null;
}

/**
 * Assigns a unique identifier to every radio of the device, as umapd does
 * (radio_addresses_assign() in rrmd/opclass.uc), so that a radio keeps its
 * identifier with and without EasyMesh.
 *
 * The first radio of each band takes its derived value unless that is
 * another wiphy's address or a value an earlier radio took. Those radios,
 * then the further radios of a band, take the next free address of their
 * wiphy's locally administered space.
 *
 * @param {array} wiphys - { mac, radios } per wiphy, radios from wiphy_radios_get()
 * @returns {object} Identifiers by radio_address_key()
 */
export function radio_addresses_assign(wiphys) {
	let pairs = [];
	let further = [];
	let permanent = {};

	for (let wiphy in wiphys) {
		let mac = lc(wiphy.mac);
		permanent[mac] = true;

		for (let radio in wiphy.radios) {
			let value = radio_address_derive(mac, radio.band);
			if (radio.rank > 0)
				push(further, { mac, band: radio.band, rank: radio.rank });
			else if (value)
				push(pairs, { mac, band: radio.band, rank: 0, value });
		}
	}

	let order = (a, b) => ((a.mac < b.mac) ? -1 : ((a.mac > b.mac) ? 1 : 0)) ||
		(BAND_BIT[a.band] - BAND_BIT[b.band]) || (a.rank - b.rank);
	sort(pairs, order);
	sort(further, order);

	let taken = { ...permanent };
	for (let pair in pairs)
		taken[pair.value] = true;

	let claimed = {};
	let moved = [];
	let assigned = {};

	for (let pair in pairs) {
		if (pair.value != pair.mac && (permanent[pair.value] || claimed[pair.value])) {
			push(moved, pair);
			continue;
		}
		claimed[pair.value] = true;
		assigned[radio_address_key(pair.mac, pair.band, 0)] = pair.value;
	}

	for (let radio in [ ...moved, ...further ]) {
		let address = radio_address_next(radio.mac, taken);
		if (address == null)
			continue;
		taken[address] = true;
		assigned[radio_address_key(radio.mac, radio.band, radio.rank)] = address;
	}

	return assigned;
};
