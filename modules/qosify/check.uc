'use strict';

// Included with { qosify_check } as the scope, by handler.uc in the agent
// and by render.uc in apply. The set handlers refuse a value that these
// checks fail, and the render skips it, because a value can also reach the
// render without a set handler, for example from a restored configuration.
// Each function is added to that object.
//
// The values follow what the qosify daemon accepts: codepoints[] and
// qosify_map_dscp_value() in map.c, cmd_add_qdisc() in interface.c,
// qosify_map_set_port() in map.c.

const check = qosify_check;

const DSCP_CODEPOINTS = [
	'CS0', 'CS1', 'CS2', 'CS3', 'CS4', 'CS5', 'CS6', 'CS7',
	'AF11', 'AF12', 'AF13', 'AF21', 'AF22', 'AF23',
	'AF31', 'AF32', 'AF33', 'AF41', 'AF42', 'AF43',
	'EF', 'VA', 'NQB', 'LE', 'DF'
];

const MODES = [ 'besteffort', 'precedence', 'diffserv3', 'diffserv4', 'diffserv8' ];

const MATCH_TYPES = [ 'Exact', 'Suffix', 'Regex' ];

// The daemon builds a `tc` command line from the rate and runs it through
// `sh -c`, so only a plain tc rate may pass.
const RATE_PATTERN = /^[0-9]+(\.[0-9]+)?([KkMmGgTt]i?(bit|bps)|bit|bps)?$/;

const CLASS_NAME_PATTERN = /^[A-Za-z][A-Za-z0-9_]*$/;

/**
 * Strips the `+` that makes a DSCP value a fallback.
 *
 * @param {string} value - DSCP value as written
 * @returns {string} The value without the prefix
 */
function dscp_base(value) {
	return (substr(value, 0, 1) == '+') ? substr(value, 1) : value;
}

/**
 * Reports whether a value names a DSCP codepoint: a name or 0 to 63.
 *
 * @param {string} value - DSCP value, optionally with a `+` prefix
 * @returns {boolean}
 */
check.dscp_codepoint_valid = function(value) {
	if (type(value) != 'string')
		return false;

	let v = dscp_base(value);
	if (index(DSCP_CODEPOINTS, v) >= 0)
		return true;

	return !!match(v, /^[0-9]+$/) && +v < 64;
};

/**
 * Reports whether a value is a DSCP mark: a codepoint or the Name of a
 * DSCPMap row.
 *
 * @param {string} value - DSCP value, optionally with a `+` prefix
 * @param {array} classes - Names of the DSCPMap rows
 * @returns {boolean}
 */
check.dscp_mark_valid = function(value, classes) {
	if (check.dscp_codepoint_valid(value))
		return true;

	return type(value) == 'string' && index(classes ?? [], dscp_base(value)) >= 0;
};

/**
 * Returns the UCI section name, which is also the daemon's class name, of
 * a DSCPMap row. The prefix keeps a class apart from the `defaults` and
 * `interface` sections of the same package.
 *
 * @param {string} name - DSCPMap Name
 * @returns {string} Section name
 */
check.class_section = function(name) {
	return 'class_' + name;
};

/**
 * Translates a DSCP mark into the form the daemon reads.
 *
 * @param {string} value - DSCP mark as stored
 * @param {array} classes - Names of the rendered DSCPMap rows
 * @returns {string} The mark, with a class name replaced by its section
 */
check.dscp_mark_render = function(value, classes) {
	let v = dscp_base(value);
	if (index(classes ?? [], v) < 0)
		return value;

	return ((v == value) ? '' : '+') + check.class_section(v);
};

/**
 * Reports whether a value can be a DSCPMap Name: a letter, then letters,
 * digits and `_`, the characters of a UCI section name.
 *
 * @param {string} value - Name
 * @returns {boolean}
 */
check.class_name_valid = function(value) {
	return type(value) == 'string' && !!match(value, CLASS_NAME_PATTERN);
};

/**
 * Reports whether a value is a tc rate, such as `100mbit`, or empty.
 *
 * @param {string} value - Rate
 * @returns {boolean}
 */
check.rate_valid = function(value) {
	return value == null || value == '' || (type(value) == 'string' && !!match(value, RATE_PATTERN));
};

/**
 * Reports whether a value is a cake diffserv mode.
 *
 * @param {string} value - Mode
 * @returns {boolean}
 */
check.mode_valid = function(value) {
	return index(MODES, value) >= 0;
};

/**
 * Reports whether a value is a DNSClassifier MatchType.
 *
 * @param {string} value - MatchType
 * @returns {boolean}
 */
check.match_type_valid = function(value) {
	return index(MATCH_TYPES, value) >= 0;
};

/**
 * Reports whether a value is a protocol the daemon classifies: TCP (6),
 * UDP (17) or -1 for any.
 *
 * @param {string} value - Protocol number as stored
 * @returns {boolean}
 */
check.protocol_valid = function(value) {
	return index([ '-1', '6', '17' ], `${value}`) >= 0;
};

/**
 * Reports whether a value is a port the daemon accepts, or -1 for none.
 *
 * @param {string} value - Port as stored
 * @returns {boolean}
 */
check.port_valid = function(value) {
	let s = `${value}`;
	if (s == '-1')
		return true;

	return !!match(s, /^[0-9]+$/) && +s >= 1 && +s <= 65534;
};

/**
 * Reports whether a value is one IPv4 or IPv6 address, or empty. The
 * daemon matches one remote address, with inet_pton(), so a prefix fails.
 *
 * @param {string} value - Address as stored
 * @returns {boolean}
 */
check.address_valid = function(value) {
	if (value == null || value == '')
		return true;

	return type(value) == 'string' && index(value, '/') < 0 && iptoarr(value) != null;
};

/**
 * Reports whether a value compiles as a POSIX extended regular expression,
 * as the daemon compiles it with regcomp().
 *
 * @param {string} value - Expression
 * @returns {boolean}
 */
check.regex_valid = function(value) {
	if (type(value) != 'string' || value == '')
		return false;

	try {
		regexp(value);
		return true;
	}
	catch (e) {
		return false;
	}
};
