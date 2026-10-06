'use strict';

// TR-181 Device.Firewall.Chain.{i}.Rule.{i}.ExpiryDate: when a rule
// expires, the device terminates it and deletes the Rule entry. fw4
// stop_date ends the match; these helpers find the entries to delete.

const EXPIRY_NEVER = '9999-12-31T23:59:59Z';
const EXPIRY_UNKNOWN = '0001-01-01T00:00:00Z';

/**
 * Returns the expiry of a rule as Unix time.
 *
 * @param {object} rule - Rule object
 * @returns {number|null} Unix time, or null when the rule does not expire
 */
function rule_expiry(rule) {
	let value = rule?.ExpiryDate;
	if (type(value) != 'string' || value == '' || value == EXPIRY_NEVER || value == EXPIRY_UNKNOWN)
		return null;

	let t = usp_datetime_to_unix(value);
	return (t > 0) ? t : null;
}

/**
 * Calls fn(path, expiry) for each rule with an expiry.
 *
 * @param {object} config - Configuration tree
 * @param {function} fn - Called with the rule's object path and Unix time
 */
function rules_with_expiry(config, fn) {
	for (let chain_key, chain in config?.Device?.Firewall?.Chain) {
		if (type(chain?.Rule) != 'object')
			continue;

		for (let rule_key, rule in chain.Rule) {
			let t = rule_expiry(rule);
			if (t != null)
				fn(`Device.Firewall.Chain.${chain_key}.Rule.${rule_key}.`, t);
		}
	}
}

/**
 * Lists the rules whose ExpiryDate has passed.
 *
 * @param {object} config - Configuration tree
 * @param {number} now - Unix time
 * @returns {array} Object paths of the expired rules
 */
export function firewall_rules_expired(config, now) {
	let paths = [];
	rules_with_expiry(config, (path, t) => { if (t <= now) push(paths, path); });
	return paths;
};

/**
 * Returns the next time a rule expires.
 *
 * @param {object} config - Configuration tree
 * @param {number} now - Unix time
 * @returns {number|null} Unix time, or null when no rule expires later
 */
export function firewall_expiry_next(config, now) {
	let next = null;
	rules_with_expiry(config, (path, t) => { if (t > now && (next == null || t < next)) next = t; });
	return next;
};
