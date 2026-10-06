/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <ucode/module.h>

#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/pem.h>
#include <openssl/bio.h>
#include <openssl/bn.h>
#include <openssl/obj_mac.h>
#include <openssl/objects.h>

#include <arpa/inet.h>
#include <string.h>
#include <time.h>

/* TR-181 SubjectAlt is a list of at most 256 characters. */
#define SUBJECT_ALT_MAX	256

static char *
asn1_time_to_iso8601(const ASN1_TIME *t)
{
	static char buf[32];
	struct tm tm = {};

	if (!t || !ASN1_TIME_to_tm(t, &tm))
		return NULL;

	strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tm);

	return buf;
}

static uc_value_t *
bio_to_string(BIO *bio)
{
	char *data;
	long len = BIO_get_mem_data(bio, &data);

	return ucv_string_new_length(data, len > 0 ? len : 0);
}

/* RFC 4514 string form, which keeps UTF-8 instead of escaping it. */
static uc_value_t *
x509_name_to_string(const X509_NAME *name)
{
	BIO *bio = BIO_new(BIO_s_mem());
	uc_value_t *rv;

	if (!bio)
		return NULL;

	X509_NAME_print_ex(bio, name, 0, XN_FLAG_RFC2253 & ~ASN1_STRFLGS_ESC_MSB);
	rv = bio_to_string(bio);
	BIO_free(bio);

	return rv;
}

static uc_value_t *
x509_fingerprint(X509 *cert)
{
	unsigned char md[EVP_MAX_MD_SIZE];
	char hex[EVP_MAX_MD_SIZE * 2 + 1];
	unsigned int len = 0;

	if (!X509_digest(cert, EVP_sha256(), md, &len))
		return NULL;

	for (unsigned int i = 0; i < len; i++)
		snprintf(hex + i * 2, 3, "%02x", md[i]);

	return ucv_string_new_length(hex, len * 2);
}

static uc_value_t *
x509_serial(X509 *cert)
{
	BIGNUM *bn = ASN1_INTEGER_to_BN(X509_get_serialNumber(cert), NULL);
	uc_value_t *rv = NULL;
	char *hex;

	if (!bn)
		return NULL;

	hex = BN_bn2hex(bn);
	if (hex) {
		rv = ucv_string_new(hex);
		OPENSSL_free(hex);
	}

	BN_free(bn);

	return rv;
}

/*
 * Writes one SubjectAlt item as "<prefix>:<value>" to buf. A comma in the
 * value becomes %2C, because the comma separates the items of the list.
 */
static size_t
san_item_format(char *buf, size_t size, const char *prefix,
		const unsigned char *value, size_t value_len)
{
	size_t len = snprintf(buf, size, "%s:", prefix);

	for (size_t i = 0; i < value_len && len + 4 < size; i++) {
		if (value[i] == ',')
			len += snprintf(buf + len, size - len, "%%2C");
		else if (value[i])
			buf[len++] = value[i];
	}

	buf[len] = '\0';

	return len;
}

static size_t
san_name_format(char *buf, size_t size, const GENERAL_NAME *gen)
{
	const ASN1_STRING *str;
	const char *prefix;
	char ip[INET6_ADDRSTRLEN];
	int family;

	switch (gen->type) {
	case GEN_DNS:
		prefix = "DNS";
		str = gen->d.dNSName;
		break;

	case GEN_EMAIL:
		prefix = "email";
		str = gen->d.rfc822Name;
		break;

	case GEN_URI:
		prefix = "URI";
		str = gen->d.uniformResourceIdentifier;
		break;

	case GEN_IPADD:
		switch (ASN1_STRING_length(gen->d.iPAddress)) {
		case 4:
			family = AF_INET;
			break;
		case 16:
			family = AF_INET6;
			break;
		default:
			return 0;
		}

		if (!inet_ntop(family, ASN1_STRING_get0_data(gen->d.iPAddress), ip, sizeof(ip)))
			return 0;

		return san_item_format(buf, size, "IP", (const unsigned char *)ip, strlen(ip));

	default:
		return 0;
	}

	return san_item_format(buf, size, prefix, ASN1_STRING_get0_data(str),
			       ASN1_STRING_length(str));
}

/* Items that do not fit into the 256 characters of the list are left out. */
static uc_value_t *
x509_subject_alt(X509 *cert)
{
	GENERAL_NAMES *sans = X509_get_ext_d2i(cert, NID_subject_alt_name, NULL, NULL);
	char list[SUBJECT_ALT_MAX + 1] = "";
	char item[SUBJECT_ALT_MAX + 1];
	size_t len = 0;

	for (int i = 0; sans && i < sk_GENERAL_NAME_num(sans); i++) {
		size_t item_len = san_name_format(item, sizeof(item), sk_GENERAL_NAME_value(sans, i));

		if (!item_len || len + (len ? 1 : 0) + item_len > SUBJECT_ALT_MAX)
			continue;

		len += snprintf(list + len, sizeof(list) - len, "%s%s", len ? "," : "", item);
	}

	GENERAL_NAMES_free(sans);

	return ucv_string_new_length(list, len);
}

static void
object_time_add(uc_value_t *obj, const char *key, const ASN1_TIME *t)
{
	char *time_str = asn1_time_to_iso8601(t);

	if (time_str)
		ucv_object_add(obj, key, ucv_string_new(time_str));
}

static uc_value_t *
x509_to_object(uc_vm_t *vm, X509 *cert)
{
	uc_value_t *obj = ucv_object_new(vm);
	const char *algo = OBJ_nid2ln(X509_get_signature_nid(cert));

	ucv_object_add(obj, "fingerprint", x509_fingerprint(cert));
	ucv_object_add(obj, "serial", x509_serial(cert));
	ucv_object_add(obj, "issuer", x509_name_to_string(X509_get_issuer_name(cert)));
	ucv_object_add(obj, "subject", x509_name_to_string(X509_get_subject_name(cert)));
	ucv_object_add(obj, "signature_algorithm", ucv_string_new(algo ? algo : ""));
	object_time_add(obj, "not_before", X509_get0_notBefore(cert));
	object_time_add(obj, "not_after", X509_get0_notAfter(cert));
	ucv_object_add(obj, "subject_alt", x509_subject_alt(cert));

	return obj;
}

static uc_value_t *
x509_to_pem_object(uc_vm_t *vm, X509 *cert)
{
	BIO *bio = BIO_new(BIO_s_mem());
	uc_value_t *obj;

	if (!bio)
		return NULL;

	if (!PEM_write_bio_X509(bio, cert)) {
		BIO_free(bio);
		return NULL;
	}

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "fingerprint", x509_fingerprint(cert));
	ucv_object_add(obj, "pem", bio_to_string(bio));
	BIO_free(bio);

	return obj;
}

/*
 * Converts each certificate of a PEM file. The read loop ends with
 * PEM_R_NO_START_LINE on the error queue of the thread; it is cleared, so
 * that a later SSL_get_error() of the process does not report it.
 */
static uc_value_t *
pem_file_convert(uc_vm_t *vm, size_t nargs,
		 uc_value_t *(*convert)(uc_vm_t *, X509 *))
{
	uc_value_t *path_arg = uc_fn_arg(0);
	uc_value_t *arr;
	BIO *bio;
	X509 *cert;

	if (ucv_type(path_arg) != UC_STRING)
		return NULL;

	bio = BIO_new_file(ucv_string_get(path_arg), "r");
	if (!bio) {
		ERR_clear_error();
		return NULL;
	}

	arr = ucv_array_new(vm);

	while ((cert = PEM_read_bio_X509(bio, NULL, NULL, NULL)) != NULL) {
		uc_value_t *obj = convert(vm, cert);

		X509_free(cert);
		if (obj)
			ucv_array_push(arr, obj);
	}

	BIO_free(bio);
	ERR_clear_error();

	if (!ucv_array_length(arr)) {
		ucv_put(arr);
		return NULL;
	}

	return arr;
}

static uc_value_t *
uc_cert_parse_file(uc_vm_t *vm, size_t nargs)
{
	return pem_file_convert(vm, nargs, x509_to_object);
}

static uc_value_t *
uc_cert_pem_read(uc_vm_t *vm, size_t nargs)
{
	return pem_file_convert(vm, nargs, x509_to_pem_object);
}

/*
 * Refuses every passphrase, so that an encrypted key fails to load instead
 * of OpenSSL prompting on the console of the daemon.
 */
static int
pem_no_passphrase(char *buf, int size, int rwflag, void *u)
{
	return 0;
}

/*
 * Reports whether a PEM file holds a certificate, a private key, and
 * whether the key belongs to the first certificate. The PEM readers skip
 * the blocks of other types, so the order of the blocks in the file does
 * not matter.
 */
static uc_value_t *
uc_key_check(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_arg = uc_fn_arg(0);
	EVP_PKEY *key = NULL;
	X509 *cert = NULL;
	uc_value_t *obj;
	const char *path;
	BIO *bio;

	if (ucv_type(path_arg) != UC_STRING)
		return NULL;

	path = ucv_string_get(path_arg);

	bio = BIO_new_file(path, "r");
	if (!bio) {
		ERR_clear_error();
		return NULL;
	}
	cert = PEM_read_bio_X509(bio, NULL, pem_no_passphrase, NULL);
	BIO_free(bio);

	bio = BIO_new_file(path, "r");
	if (bio) {
		key = PEM_read_bio_PrivateKey(bio, NULL, pem_no_passphrase, NULL);
		BIO_free(bio);
	}

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "certificate", ucv_boolean_new(cert != NULL));
	ucv_object_add(obj, "key", ucv_boolean_new(key != NULL));
	ucv_object_add(obj, "match",
		       ucv_boolean_new(cert && key && X509_check_private_key(cert, key) == 1));

	X509_free(cert);
	EVP_PKEY_free(key);
	ERR_clear_error();

	return obj;
}

static const uc_function_list_t global_fns[] = {
	{ "cert_parse_file",	uc_cert_parse_file },
	{ "cert_pem_read",	uc_cert_pem_read },
	{ "key_check",		uc_key_check },
};

void
uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_function_list_register(scope, global_fns);
}
