'use strict';

// The key types the dropbear build supports: CONFIG_DROPBEAR_RSA,
// CONFIG_DROPBEAR_ED25519 and CONFIG_DROPBEAR_SK_ED25519. DSS and ECDSA
// are off in the build, so a key of those types could never log in.
export const KEY_TYPES = [ 'ssh-ed25519', 'ssh-rsa', 'sk-ssh-ed25519@openssh.com' ];

export const MIN_RSA_BITS = 2048;
