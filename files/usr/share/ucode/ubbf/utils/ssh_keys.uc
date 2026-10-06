'use strict';

// The key types the dropbear build supports: CONFIG_DROPBEAR_RSA,
// CONFIG_DROPBEAR_ED25519 and CONFIG_DROPBEAR_SK_ED25519. DSS and ECDSA
// are off in the build, so a key of those types could never log in.
export const KEY_TYPES = [ 'ssh-ed25519', 'ssh-rsa', 'sk-ssh-ed25519@openssh.com' ];

export const MIN_RSA_BITS = 2048;

// Fields of the wire-format blob of each key type, the type name included.
const BLOB_FIELDS = {
	'ssh-ed25519': 2,
	'ssh-rsa': 3,
	'sk-ssh-ed25519@openssh.com': 3
};

function u32_get(buf, off) {
	return (ord(buf, off) << 24) | (ord(buf, off + 1) << 16) |
	       (ord(buf, off + 2) << 8) | ord(buf, off + 3);
}

/**
 * Splits an SSH wire-format key blob into its length-prefixed fields.
 *
 * @param {string} blob - Decoded key blob
 * @returns {string[]|null} The fields, or null when the blob is truncated
 */
function blob_fields(blob) {
	let fields = [];
	let len = length(blob);

	for (let off = 0; off < len;) {
		if (off + 4 > len)
			return null;

		let field_len = u32_get(blob, off);
		off += 4;
		if (off + field_len > len)
			return null;

		push(fields, substr(blob, off, field_len));
		off += field_len;
	}

	return fields;
}

/**
 * Returns the size in bits of an SSH mpint.
 *
 * @param {string} mpint - Big-endian two's complement bytes
 * @returns {number} Bits from the highest set bit down
 */
function mpint_bits(mpint) {
	let len = length(mpint);
	let i = 0;

	while (i < len && ord(mpint, i) == 0)
		i++;
	if (i == len)
		return 0;

	let bits = (len - i) * 8;
	for (let top = ord(mpint, i); !(top & 0x80); top <<= 1)
		bits--;

	return bits;
}

/**
 * Checks an authorized_keys line against the accepted key types and the
 * minimum RSA size. Rejects embedded newlines, options prefixes
 * (command=, from=, ...) and blobs whose type does not match the line.
 *
 * @param {string} key - Candidate key line
 * @param {string[]} accepted - Accepted key types
 * @param {number} min_rsa_bits - Minimum RSA modulus size
 * @returns {boolean} true if the key may be deployed
 */
export function key_acceptable(key, accepted, min_rsa_bits) {
	if (type(key) != 'string' || key == '' || length(key) > 8192)
		return false;
	if (match(key, /[\r\n]/))
		return false;

	let m = match(key, /^([a-z0-9@.-]+)[ \t]+([A-Za-z0-9+\/=]+)([ \t]+[ -~]*)?$/);
	if (!m || index(accepted, m[1]) < 0)
		return false;

	let fields = blob_fields(b64dec(m[2]) ?? '');
	if (!fields || fields[0] != m[1] || length(fields) != BLOB_FIELDS[m[1]])
		return false;

	// An ssh-rsa blob holds the type, the public exponent and the modulus.
	if (m[1] == 'ssh-rsa' && mpint_bits(fields[2]) < min_rsa_bits)
		return false;

	return true;
};
