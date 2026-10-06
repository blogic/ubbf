/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include <ucode/module.h>

#include <pwd.h>
#include <grp.h>
#include <shadow.h>
#include <crypt.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#include "rate_limit.h"

/* Convert a struct passwd to a ucode object */
static uc_value_t *
pw_to_object(uc_vm_t *vm, struct passwd *pw)
{
	uc_value_t *obj;

	if (!pw)
		return NULL;

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "username", ucv_string_new(pw->pw_name));
	ucv_object_add(obj, "uid", ucv_int64_new(pw->pw_uid));
	ucv_object_add(obj, "gid", ucv_int64_new(pw->pw_gid));
	ucv_object_add(obj, "gecos", ucv_string_new(pw->pw_gecos ? pw->pw_gecos : ""));
	ucv_object_add(obj, "home", ucv_string_new(pw->pw_dir ? pw->pw_dir : "/"));
	ucv_object_add(obj, "shell", ucv_string_new(pw->pw_shell ? pw->pw_shell : ""));

	return obj;
}

/* Convert a struct spwd to a ucode object */
static uc_value_t *
sp_to_object(uc_vm_t *vm, struct spwd *sp)
{
	uc_value_t *obj;

	if (!sp)
		return NULL;

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "username", ucv_string_new(sp->sp_namp));
	ucv_object_add(obj, "hash", ucv_string_new(sp->sp_pwdp ? sp->sp_pwdp : ""));
	ucv_object_add(obj, "lastchanged", ucv_int64_new(sp->sp_lstchg));
	ucv_object_add(obj, "min", ucv_int64_new(sp->sp_min));
	ucv_object_add(obj, "max", ucv_int64_new(sp->sp_max));
	ucv_object_add(obj, "warn", ucv_int64_new(sp->sp_warn));
	ucv_object_add(obj, "inactive", ucv_int64_new(sp->sp_inact));
	ucv_object_add(obj, "expire", ucv_int64_new(sp->sp_expire));

	return obj;
}

/* Convert a struct group to a ucode object */
static uc_value_t *
gr_to_object(uc_vm_t *vm, struct group *gr)
{
	uc_value_t *obj, *members;
	int i;

	if (!gr)
		return NULL;

	obj = ucv_object_new(vm);
	ucv_object_add(obj, "groupname", ucv_string_new(gr->gr_name));
	ucv_object_add(obj, "gid", ucv_int64_new(gr->gr_gid));

	members = ucv_array_new(vm);
	if (gr->gr_mem) {
		for (i = 0; gr->gr_mem[i]; i++)
			ucv_array_push(members, ucv_string_new(gr->gr_mem[i]));
	}
	ucv_object_add(obj, "members", members);

	return obj;
}

/* passwd_get_all() - iterate all /etc/passwd entries */
static uc_value_t *
uc_passwd_get_all(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arr;
	struct passwd *pw;

	arr = ucv_array_new(vm);

	setpwent();
	while ((pw = getpwent()) != NULL)
		ucv_array_push(arr, pw_to_object(vm, pw));
	endpwent();

	return arr;
}

/* passwd_get_by_name(name) - lookup by username */
static uc_value_t *
uc_passwd_get_by_name(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name = uc_fn_arg(0);

	if (ucv_type(name) != UC_STRING)
		return NULL;

	return pw_to_object(vm, getpwnam(ucv_string_get(name)));
}

/* passwd_get_by_uid(uid) - lookup by UID */
/* shadow_get_all() - iterate all /etc/shadow entries via fgetspent() */
static uc_value_t *
uc_shadow_get_all(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arr;
	struct spwd *sp;
	FILE *fp;

	fp = fopen("/etc/shadow", "r");
	if (!fp)
		return NULL;

	arr = ucv_array_new(vm);
	while ((sp = fgetspent(fp)) != NULL)
		ucv_array_push(arr, sp_to_object(vm, sp));
	fclose(fp);

	return arr;
}

/* shadow_get_by_name(name) - lookup by username */
/* group_get_all() - iterate all /etc/group entries */
static uc_value_t *
uc_group_get_all(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arr;
	struct group *gr;

	arr = ucv_array_new(vm);

	setgrent();
	while ((gr = getgrent()) != NULL)
		ucv_array_push(arr, gr_to_object(vm, gr));
	endgrent();

	return arr;
}

/* group_get_by_name(name) - lookup by group name */
static uc_value_t *
uc_group_get_by_name(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name = uc_fn_arg(0);

	if (ucv_type(name) != UC_STRING)
		return NULL;

	return gr_to_object(vm, getgrnam(ucv_string_get(name)));
}

/*
 * Convert a ucode object back to struct passwd fields and write with putpwent().
 * xstrdup() all strings because ucv_string_get() returns pointers to inline
 * storage inside uc_string_t that can be invalidated by libucode internals.
 * Returns 0 on success, -1 on failure.
 */
static int
object_to_pw(uc_value_t *obj, FILE *fp)
{
	struct passwd pw = { 0 };
	uc_value_t *v;
	int ret;

	v = ucv_object_get(obj, "username", NULL);
	if (!v || ucv_type(v) != UC_STRING)
		return -1;
	pw.pw_name = xstrdup(ucv_string_get(v));

	pw.pw_passwd = xstrdup("x");

	v = ucv_object_get(obj, "uid", NULL);
	pw.pw_uid = v ? (uid_t)ucv_int64_get(v) : 0;

	v = ucv_object_get(obj, "gid", NULL);
	pw.pw_gid = v ? (gid_t)ucv_int64_get(v) : 0;

	v = ucv_object_get(obj, "gecos", NULL);
	pw.pw_gecos = xstrdup((v && ucv_type(v) == UC_STRING) ? ucv_string_get(v) : "");

	v = ucv_object_get(obj, "home", NULL);
	pw.pw_dir = xstrdup((v && ucv_type(v) == UC_STRING) ? ucv_string_get(v) : "/");

	v = ucv_object_get(obj, "shell", NULL);
	pw.pw_shell = xstrdup((v && ucv_type(v) == UC_STRING) ? ucv_string_get(v) : "");

	ret = putpwent(&pw, fp);

	free(pw.pw_name);
	free(pw.pw_passwd);
	free(pw.pw_gecos);
	free(pw.pw_dir);
	free(pw.pw_shell);

	return ret;
}

/*
 * Convert a ucode object back to struct spwd fields and write with putspent().
 * Returns 0 on success, -1 on failure.
 */
static int
object_to_sp(uc_value_t *obj, FILE *fp)
{
	struct spwd sp = { 0 };
	uc_value_t *v;
	int ret;

	v = ucv_object_get(obj, "username", NULL);
	if (!v || ucv_type(v) != UC_STRING)
		return -1;
	sp.sp_namp = xstrdup(ucv_string_get(v));

	v = ucv_object_get(obj, "hash", NULL);
	sp.sp_pwdp = xstrdup((v && ucv_type(v) == UC_STRING) ? ucv_string_get(v) : "!");

	v = ucv_object_get(obj, "lastchanged", NULL);
	sp.sp_lstchg = v ? ucv_int64_get(v) : -1;

	v = ucv_object_get(obj, "min", NULL);
	sp.sp_min = v ? ucv_int64_get(v) : -1;

	v = ucv_object_get(obj, "max", NULL);
	sp.sp_max = v ? ucv_int64_get(v) : -1;

	v = ucv_object_get(obj, "warn", NULL);
	sp.sp_warn = v ? ucv_int64_get(v) : -1;

	v = ucv_object_get(obj, "inactive", NULL);
	sp.sp_inact = v ? ucv_int64_get(v) : -1;

	v = ucv_object_get(obj, "expire", NULL);
	sp.sp_expire = v ? ucv_int64_get(v) : -1;

	ret = putspent(&sp, fp);

	free(sp.sp_namp);
	free(sp.sp_pwdp);

	return ret;
}

/*
 * Convert a ucode object back to struct group fields and write with putgrent().
 * Returns 0 on success, -1 on failure.
 */
static int
object_to_gr(uc_value_t *obj, FILE *fp)
{
	struct group gr = { 0 };
	uc_value_t *v, *members;
	char **mem = NULL;
	size_t i, n = 0;
	int ret;

	v = ucv_object_get(obj, "groupname", NULL);
	if (!v || ucv_type(v) != UC_STRING)
		return -1;
	gr.gr_name = xstrdup(ucv_string_get(v));

	gr.gr_passwd = xstrdup("x");

	v = ucv_object_get(obj, "gid", NULL);
	gr.gr_gid = v ? (gid_t)ucv_int64_get(v) : 0;

	members = ucv_object_get(obj, "members", NULL);
	if (members && ucv_type(members) == UC_ARRAY) {
		n = ucv_array_length(members);
		mem = calloc(n + 1, sizeof(char *));
		if (!mem) {
			free(gr.gr_name);
			free(gr.gr_passwd);
			return -1;
		}
		for (i = 0; i < n; i++) {
			v = ucv_array_get(members, i);
			mem[i] = xstrdup((v && ucv_type(v) == UC_STRING) ? ucv_string_get(v) : "");
		}
		mem[n] = NULL;
	}

	gr.gr_mem = mem;
	ret = putgrent(&gr, fp);

	for (i = 0; i < n; i++)
		free(mem[i]);
	free(mem);
	free(gr.gr_name);
	free(gr.gr_passwd);

	return ret;
}

struct account_file {
	const char *key;
	const char *path;
	int (*writer)(uc_value_t *, FILE *);
	mode_t mode;
	char tmp_path[256];
	bool written;
};

/*
 * Writes the entries to <path>.tmp and syncs it. Every step is checked: a
 * full file system often fails only at fflush(), and a file renamed over
 * /etc/passwd after that would be empty. The caller holds lckpwdf().
 */
static bool
tmp_write(struct account_file *f, uc_value_t *entries)
{
	size_t i, n;
	FILE *fp;
	int fd;
	bool ok;

	snprintf(f->tmp_path, sizeof(f->tmp_path), "%s.tmp", f->path);

	fd = open(f->tmp_path, O_WRONLY | O_CREAT | O_TRUNC, f->mode);
	if (fd < 0)
		return false;

	fp = fdopen(fd, "w");
	if (!fp) {
		close(fd);
		unlink(f->tmp_path);
		return false;
	}

	ok = true;
	n = ucv_array_length(entries);
	for (i = 0; ok && i < n; i++)
		ok = (f->writer(ucv_array_get(entries, i), fp) == 0);

	ok = ok && fflush(fp) == 0 && fsync(fileno(fp)) == 0;
	ok = (fclose(fp) == 0) && ok;

	if (!ok)
		unlink(f->tmp_path);

	return ok;
}

/* Makes the renames into /etc durable. */
static void
etc_sync(void)
{
	int fd = open("/etc", O_RDONLY | O_DIRECTORY);

	if (fd >= 0) {
		fsync(fd);
		close(fd);
	}
}

/*
 * Replaces the account files given in `files` together: all temporary files
 * are written first, and only when every one is complete are they renamed,
 * so a failure leaves all of the old files in place.
 */
static bool
accounts_write(struct account_file *files, size_t count, uc_value_t *entries[])
{
	size_t i;
	bool ok = true;

	if (lckpwdf() != 0)
		return false;

	for (i = 0; ok && i < count; i++) {
		files[i].written = false;
		if (!entries[i])
			continue;
		ok = tmp_write(&files[i], entries[i]);
		files[i].written = ok;
	}

	for (i = 0; i < count; i++) {
		if (!files[i].written)
			continue;
		if (!ok || rename(files[i].tmp_path, files[i].path) != 0) {
			unlink(files[i].tmp_path);
			ok = false;
		}
	}

	if (ok)
		etc_sync();

	ulckpwdf();
	return ok;
}

enum { ACCOUNT_GROUP, ACCOUNT_PASSWD, ACCOUNT_SHADOW };

static struct account_file account_files[] = {
	[ACCOUNT_GROUP] = { "group", "/etc/group", object_to_gr, 0644 },
	[ACCOUNT_PASSWD] = { "passwd", "/etc/passwd", object_to_pw, 0644 },
	[ACCOUNT_SHADOW] = { "shadow", "/etc/shadow", object_to_sp, 0600 },
};

/* Replaces one account file, the one at `index` in account_files. */
static uc_value_t *
atomic_write(uc_vm_t *vm, size_t index, uc_value_t *entries)
{
	uc_value_t *list[ARRAY_SIZE(account_files)] = { NULL };

	if (ucv_type(entries) != UC_ARRAY)
		return ucv_boolean_new(false);

	list[index] = entries;
	return ucv_boolean_new(accounts_write(account_files, ARRAY_SIZE(account_files), list));
}

/*
 * accounts_set({ group, passwd, shadow }) - replaces the given account
 * files together; a missing key leaves that file as it is.
 */
static uc_value_t *
uc_accounts_set(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *arg = uc_fn_arg(0);
	uc_value_t *list[ARRAY_SIZE(account_files)] = { NULL };
	size_t i;

	if (ucv_type(arg) != UC_OBJECT)
		return ucv_boolean_new(false);

	for (i = 0; i < ARRAY_SIZE(account_files); i++) {
		uc_value_t *v = ucv_object_get(arg, account_files[i].key, NULL);

		if (v && ucv_type(v) != UC_ARRAY)
			return ucv_boolean_new(false);
		list[i] = v;
	}

	return ucv_boolean_new(accounts_write(account_files, ARRAY_SIZE(account_files), list));
}

/* passwd_set(entries) - atomically replace /etc/passwd */
static uc_value_t *
uc_passwd_set(uc_vm_t *vm, size_t nargs)
{
	return atomic_write(vm, ACCOUNT_PASSWD, uc_fn_arg(0));
}

/* shadow_set(entries) - atomically replace /etc/shadow */
static uc_value_t *
uc_shadow_set(uc_vm_t *vm, size_t nargs)
{
	return atomic_write(vm, ACCOUNT_SHADOW, uc_fn_arg(0));
}

/* group_set(entries) - atomically replace /etc/group */
static uc_value_t *
uc_group_set(uc_vm_t *vm, size_t nargs)
{
	return atomic_write(vm, ACCOUNT_GROUP, uc_fn_arg(0));
}

/* crypt(phrase, setting) - POSIX password hashing */
static uc_value_t *
uc_crypt(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *phrase = uc_fn_arg(0);
	uc_value_t *setting = uc_fn_arg(1);
	char *hash;

	if (ucv_type(phrase) != UC_STRING || ucv_type(setting) != UC_STRING)
		return NULL;

	errno = 0;
	hash = crypt(ucv_string_get(phrase), ucv_string_get(setting));

	if (hash == NULL || errno != 0)
		return NULL;

	return ucv_string_new(hash);
}

/* ---- high-level user management ---------------------------------------- */

static uc_value_t *
uc_shells_get(uc_vm_t *vm, size_t nargs)
{
	FILE *fp;
	char line[256];
	uc_value_t *arr;

	fp = fopen("/etc/shells", "r");
	if (!fp)
		goto fallback;

	arr = ucv_array_new(vm);

	while (fgets(line, sizeof(line), fp)) {
		char *s = line, *e;

		while (*s == ' ' || *s == '\t') s++;

		e = s + strlen(s) - 1;
		while (e > s && (*e == '\n' || *e == '\r' || *e == ' '))
			*e-- = '\0';

		if (*s == '\0' || *s == '#')
			continue;

		ucv_array_push(arr, ucv_string_new(s));
	}

	fclose(fp);

	if (ucv_array_length(arr) > 0)
		return arr;

	ucv_put(arr);

fallback:
	arr = ucv_array_new(vm);
	ucv_array_push(arr, ucv_string_new("/bin/sh"));
	ucv_array_push(arr, ucv_string_new("/bin/ash"));
	return arr;
}

static uc_value_t *
uc_password_hash(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *plaintext_val = uc_fn_arg(0);
	const char *plaintext;
	unsigned char randbuf[16];
	char salt[17], setting[24], *hash;
	static const char charset[] =
		"abcdefghijklmnopqrstuvwxyz"
		"ABCDEFGHIJKLMNOPQRSTUVWXYZ"
		"0123456789./";
	FILE *fp;

	if (ucv_type(plaintext_val) != UC_STRING)
		return NULL;

	plaintext = ucv_string_get(plaintext_val);

	fp = fopen("/dev/urandom", "r");
	if (!fp || fread(randbuf, 1, 16, fp) != 16) {
		if (fp) fclose(fp);
		return NULL;
	}
	fclose(fp);

	for (int i = 0; i < 16; i++)
		salt[i] = charset[randbuf[i] % 64];
	salt[16] = '\0';

	snprintf(setting, sizeof(setting), "$6$%s$", salt);

	errno = 0;
	hash = crypt(plaintext, setting);
	if (!hash || errno != 0)
		return NULL;

	return ucv_string_new(hash);
}

/* A SHA-512 crypt setting, the scheme of uc_password_hash(). An unknown
 * account and a locked or empty entry run crypt() against it, so that every
 * path costs one crypt() and the response time does not tell which
 * accounts exist. */
#define CREDENTIALS_DUMMY_SETTING "$6$Ub8fDummySalt000$"

static bool
shadow_hash_usable(const char *hash)
{
	return hash && *hash && strcmp(hash, "*") != 0 && hash[0] != '!';
}

static uc_value_t *
uc_credentials_check(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *username_val = uc_fn_arg(0);
	uc_value_t *password_val = uc_fn_arg(1);
	const char *username, *password, *hash;
	struct spwd *sp;
	char *computed;
	bool usable;

	if (ucv_type(username_val) != UC_STRING ||
	    ucv_type(password_val) != UC_STRING)
		return ucv_string_new("Credentials_Bad_Requested_Username_Not_Supported");

	username = ucv_string_get(username_val);
	password = ucv_string_get(password_val);

	sp = getspnam(username);
	hash = sp ? sp->sp_pwdp : NULL;
	usable = shadow_hash_usable(hash);

	errno = 0;
	computed = crypt(password, usable ? hash : CREDENTIALS_DUMMY_SETTING);

	if (!sp)
		return ucv_string_new("Credentials_Bad_Requested_Username_Not_Supported");

	if (!usable || !computed || errno != 0 || strcmp(computed, hash) != 0)
		return ucv_string_new("Credentials_Bad_Requested_Password_Incorrect");

	return ucv_string_new("Credentials_Good");
}

static const uc_function_list_t global_fns[] = {
	{ "passwd_get_all",		uc_passwd_get_all },
	{ "passwd_get_by_name",		uc_passwd_get_by_name },
	{ "shadow_get_all",		uc_shadow_get_all },
	{ "group_get_all",		uc_group_get_all },
	{ "group_get_by_name",		uc_group_get_by_name },
	{ "passwd_set",			uc_passwd_set },
	{ "shadow_set",			uc_shadow_set },
	{ "accounts_set",		uc_accounts_set },
	{ "group_set",			uc_group_set },
	{ "crypt",			uc_crypt },
	{ "shells_get",			uc_shells_get },
	{ "password_hash",		uc_password_hash },
	{ "credentials_check",		uc_credentials_check },
	{ "rate_limit_check",		uc_ubbf_rate_limit_check },
};

void
uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_function_list_register(scope, global_fns);
}
