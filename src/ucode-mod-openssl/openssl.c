/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <ucode/module.h>

#include <openssl/x509.h>
#include <openssl/x509v3.h>
#include <openssl/pem.h>
#include <openssl/bio.h>
#include <openssl/bn.h>
#include <openssl/obj_mac.h>
#include <openssl/objects.h>

#include <dirent.h>
#include <sys/stat.h>
#include <string.h>
#include <time.h>

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
x509_to_object(uc_vm_t *vm, X509 *cert)
{
	uc_value_t *obj;
	const ASN1_INTEGER *serial_asn1;
	BIGNUM *bn;
	char *serial_hex;
	char name_buf[512];
	const char *algo;
	char *time_str;
	GENERAL_NAMES *sans;
	int nid;

	if (!cert)
		return NULL;

	obj = ucv_object_new(vm);

	serial_asn1 = X509_get_serialNumber(cert);
	bn = ASN1_INTEGER_to_BN(serial_asn1, NULL);
	if (bn) {
		serial_hex = BN_bn2hex(bn);
		if (serial_hex) {
			ucv_object_add(obj, "serial", ucv_string_new(serial_hex));
			OPENSSL_free(serial_hex);
		}
		BN_free(bn);
	}

	X509_NAME_oneline(X509_get_issuer_name(cert), name_buf, sizeof(name_buf));
	ucv_object_add(obj, "issuer", ucv_string_new(name_buf));

	X509_NAME_oneline(X509_get_subject_name(cert), name_buf, sizeof(name_buf));
	ucv_object_add(obj, "subject", ucv_string_new(name_buf));

	nid = X509_get_signature_nid(cert);
	algo = OBJ_nid2ln(nid);
	ucv_object_add(obj, "signature_algorithm", ucv_string_new(algo ? algo : ""));

	time_str = asn1_time_to_iso8601(X509_get0_notBefore(cert));
	ucv_object_add(obj, "not_before", ucv_string_new(time_str ? time_str : ""));

	time_str = asn1_time_to_iso8601(X509_get0_notAfter(cert));
	ucv_object_add(obj, "not_after", ucv_string_new(time_str ? time_str : ""));

	sans = X509_get_ext_d2i(cert, NID_subject_alt_name, NULL, NULL);
	if (sans) {
		char san_buf[2048] = {};
		int offset = 0;

		for (int i = 0; i < sk_GENERAL_NAME_num(sans); i++) {
			GENERAL_NAME *gen = sk_GENERAL_NAME_value(sans, i);
			const char *prefix = NULL;
			const char *value = NULL;
			char ip_buf[64];

			switch (gen->type) {
			case GEN_DNS:
				prefix = "DNS";
				value = (const char *)ASN1_STRING_get0_data(gen->d.dNSName);
				break;
			case GEN_EMAIL:
				prefix = "email";
				value = (const char *)ASN1_STRING_get0_data(gen->d.rfc822Name);
				break;
			case GEN_IPADD: {
				int len = ASN1_STRING_length(gen->d.iPAddress);
				const unsigned char *data = ASN1_STRING_get0_data(gen->d.iPAddress);

				prefix = "IP";
				if (len == 4)
					snprintf(ip_buf, sizeof(ip_buf), "%d.%d.%d.%d",
						 data[0], data[1], data[2], data[3]);
				else if (len == 16)
					snprintf(ip_buf, sizeof(ip_buf),
						 "%02x%02x:%02x%02x:%02x%02x:%02x%02x:"
						 "%02x%02x:%02x%02x:%02x%02x:%02x%02x",
						 data[0], data[1], data[2], data[3],
						 data[4], data[5], data[6], data[7],
						 data[8], data[9], data[10], data[11],
						 data[12], data[13], data[14], data[15]);
				else
					ip_buf[0] = '\0';
				value = ip_buf;
				break;
			}
			default:
				break;
			}

			if (!prefix || !value)
				continue;

			int written = snprintf(san_buf + offset, sizeof(san_buf) - offset,
					       "%s%s:%s", offset ? "," : "", prefix, value);
			if (written < 0 || (size_t)(offset + written) >= sizeof(san_buf))
				break;
			offset += written;
		}

		ucv_object_add(obj, "subject_alt", ucv_string_new(san_buf));
		GENERAL_NAMES_free(sans);
	} else {
		ucv_object_add(obj, "subject_alt", ucv_string_new(""));
	}

	return obj;
}

static uc_value_t *
uc_cert_parse_file(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *path_arg = uc_fn_arg(0);
	uc_value_t *arr;
	BIO *bio;
	X509 *cert;

	if (ucv_type(path_arg) != UC_STRING)
		return NULL;

	bio = BIO_new_file(ucv_string_get(path_arg), "r");
	if (!bio)
		return NULL;

	arr = ucv_array_new(vm);

	while ((cert = PEM_read_bio_X509(bio, NULL, NULL, NULL)) != NULL) {
		uc_value_t *obj = x509_to_object(vm, cert);

		X509_free(cert);
		if (obj)
			ucv_array_push(arr, obj);
	}

	BIO_free(bio);

	if (!ucv_array_length(arr)) {
		ucv_put(arr);
		return NULL;
	}

	return arr;
}

static uc_value_t *
uc_cert_parse_pem(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *pem_arg = uc_fn_arg(0);
	uc_value_t *arr;
	BIO *bio;
	X509 *cert;

	if (ucv_type(pem_arg) != UC_STRING)
		return NULL;

	bio = BIO_new_mem_buf(ucv_string_get(pem_arg), ucv_string_length(pem_arg));
	if (!bio)
		return NULL;

	arr = ucv_array_new(vm);

	while ((cert = PEM_read_bio_X509(bio, NULL, NULL, NULL)) != NULL) {
		uc_value_t *obj = x509_to_object(vm, cert);

		X509_free(cert);
		if (obj)
			ucv_array_push(arr, obj);
	}

	BIO_free(bio);

	if (!ucv_array_length(arr)) {
		ucv_put(arr);
		return NULL;
	}

	return arr;
}

static uc_value_t *
uc_cert_parse_dir(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *dir_arg = uc_fn_arg(0);
	uc_value_t *arr;
	DIR *dir;
	struct dirent *entry;

	if (ucv_type(dir_arg) != UC_STRING)
		return NULL;

	dir = opendir(ucv_string_get(dir_arg));
	if (!dir)
		return NULL;

	arr = ucv_array_new(vm);

	while ((entry = readdir(dir)) != NULL) {
		char path[PATH_MAX];
		struct stat st;
		BIO *bio;
		X509 *cert;

		if (entry->d_name[0] == '.')
			continue;

		snprintf(path, sizeof(path), "%s/%s",
			 ucv_string_get(dir_arg), entry->d_name);

		if (lstat(path, &st) < 0 || !S_ISREG(st.st_mode))
			continue;

		bio = BIO_new_file(path, "r");
		if (!bio)
			continue;

		while ((cert = PEM_read_bio_X509(bio, NULL, NULL, NULL)) != NULL) {
			uc_value_t *obj = x509_to_object(vm, cert);

			X509_free(cert);
			if (!obj)
				continue;

			ucv_object_add(obj, "filename", ucv_string_new(entry->d_name));
			ucv_array_push(arr, obj);
		}

		BIO_free(bio);
	}

	closedir(dir);

	return arr;
}

static const uc_function_list_t global_fns[] = {
	{ "cert_parse_file",	uc_cert_parse_file },
	{ "cert_parse_pem",	uc_cert_parse_pem },
	{ "cert_parse_dir",	uc_cert_parse_dir },
};

void
uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_function_list_register(scope, global_fns);
}
