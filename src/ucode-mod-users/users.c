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
static uc_value_t *
uc_passwd_get_by_uid(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *uid = uc_fn_arg(0);

	if (ucv_type(uid) != UC_INTEGER)
		return NULL;

	return pw_to_object(vm, getpwuid((uid_t)ucv_int64_get(uid)));
}

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
static uc_value_t *
uc_shadow_get_by_name(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name = uc_fn_arg(0);

	if (ucv_type(name) != UC_STRING)
		return NULL;

	return sp_to_object(vm, getspnam(ucv_string_get(name)));
}

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
 * strdup() all strings because ucv_string_get() returns pointers to inline
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
	pw.pw_name = strdup(ucv_string_get(v));

	pw.pw_passwd = strdup("x");

	v = ucv_object_get(obj, "uid", NULL);
	pw.pw_uid = v ? (uid_t)ucv_int64_get(v) : 0;

	v = ucv_object_get(obj, "gid", NULL);
	pw.pw_gid = v ? (gid_t)ucv_int64_get(v) : 0;

	v = ucv_object_get(obj, "gecos", NULL);
	pw.pw_gecos = strdup((v && ucv_type(v) == UC_STRING) ? ucv_string_get(v) : "");

	v = ucv_object_get(obj, "home", NULL);
	pw.pw_dir = strdup((v && ucv_type(v) == UC_STRING) ? ucv_string_get(v) : "/");

	v = ucv_object_get(obj, "shell", NULL);
	pw.pw_shell = strdup((v && ucv_type(v) == UC_STRING) ? ucv_string_get(v) : "");

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
	sp.sp_namp = strdup(ucv_string_get(v));

	v = ucv_object_get(obj, "hash", NULL);
	sp.sp_pwdp = strdup((v && ucv_type(v) == UC_STRING) ? ucv_string_get(v) : "!");

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
	gr.gr_name = strdup(ucv_string_get(v));

	gr.gr_passwd = strdup("x");

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
			mem[i] = strdup((v && ucv_type(v) == UC_STRING) ? ucv_string_get(v) : "");
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

/*
 * Atomically write an array of entries to a file.
 * Uses lckpwdf() for advisory locking, writes to .tmp, fsync, rename.
 */
static uc_value_t *
atomic_write(uc_vm_t *vm, const char *path, uc_value_t *entries,
             int (*writer)(uc_value_t *, FILE *), mode_t mode)
{
	char tmp_path[256];
	FILE *fp;
	size_t i, n;
	int fd;

	if (!entries || ucv_type(entries) != UC_ARRAY)
		return ucv_boolean_new(false);

	snprintf(tmp_path, sizeof(tmp_path), "%s.tmp", path);

	if (lckpwdf() != 0)
		return ucv_boolean_new(false);

	fd = open(tmp_path, O_WRONLY | O_CREAT | O_TRUNC, mode);
	if (fd < 0) {
		ulckpwdf();
		return ucv_boolean_new(false);
	}

	fp = fdopen(fd, "w");
	if (!fp) {
		close(fd);
		unlink(tmp_path);
		ulckpwdf();
		return ucv_boolean_new(false);
	}

	n = ucv_array_length(entries);
	for (i = 0; i < n; i++) {
		if (writer(ucv_array_get(entries, i), fp) != 0) {
			fclose(fp);
			unlink(tmp_path);
			ulckpwdf();
			return ucv_boolean_new(false);
		}
	}

	fflush(fp);
	fsync(fileno(fp));
	fclose(fp);

	if (rename(tmp_path, path) != 0) {
		unlink(tmp_path);
		ulckpwdf();
		return ucv_boolean_new(false);
	}

	ulckpwdf();

	return ucv_boolean_new(true);
}

/* passwd_set(entries) - atomically replace /etc/passwd */
static uc_value_t *
uc_passwd_set(uc_vm_t *vm, size_t nargs)
{
	return atomic_write(vm, "/etc/passwd", uc_fn_arg(0), object_to_pw, 0644);
}

/* shadow_set(entries) - atomically replace /etc/shadow */
static uc_value_t *
uc_shadow_set(uc_vm_t *vm, size_t nargs)
{
	return atomic_write(vm, "/etc/shadow", uc_fn_arg(0), object_to_sp, 0600);
}

/* group_set(entries) - atomically replace /etc/group */
static uc_value_t *
uc_group_set(uc_vm_t *vm, size_t nargs)
{
	return atomic_write(vm, "/etc/group", uc_fn_arg(0), object_to_gr, 0644);
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

static const char *static_users[] = {
	"root", "nobody", "daemon", "bin", "sys", "sync",
	"mail", "www-data", "operator", "ftp", "sshd", "ntp",
	"dnsmasq", "logd", "ubus", NULL
};

static const char *static_groups[] = {
	"root", "wheel", "adm", "admin", "nogroup", "daemon",
	"bin", "sys", "shadow", "utmp", "mail", "ftp",
	"network", "users", NULL
};

static const char *role_groups[] = {
	"root", "wheel", "admin", "adm", "users", "docker", "lxc", NULL
};

#define MIN_DYNAMIC_ID 1000

static bool
str_in_list(const char *s, const char **list)
{
	for (int i = 0; list[i]; i++)
		if (strcmp(s, list[i]) == 0)
			return true;
	return false;
}

static uc_value_t *
uc_is_static_user(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name = uc_fn_arg(0);
	uc_value_t *uid_val = uc_fn_arg(1);

	if (ucv_type(uid_val) == UC_INTEGER && ucv_int64_get(uid_val) < MIN_DYNAMIC_ID)
		return ucv_boolean_new(true);

	if (ucv_type(name) == UC_STRING && str_in_list(ucv_string_get(name), static_users))
		return ucv_boolean_new(true);

	return ucv_boolean_new(false);
}

static uc_value_t *
uc_is_static_group(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name = uc_fn_arg(0);
	uc_value_t *gid_val = uc_fn_arg(1);

	if (ucv_type(gid_val) == UC_INTEGER && ucv_int64_get(gid_val) < MIN_DYNAMIC_ID)
		return ucv_boolean_new(true);

	if (ucv_type(name) == UC_STRING && str_in_list(ucv_string_get(name), static_groups))
		return ucv_boolean_new(true);

	return ucv_boolean_new(false);
}

static uc_value_t *
uc_is_role_group(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *name = uc_fn_arg(0);

	if (ucv_type(name) != UC_STRING)
		return ucv_boolean_new(false);

	return ucv_boolean_new(str_in_list(ucv_string_get(name), role_groups));
}

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
uc_user_groups_find(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *username_val = uc_fn_arg(0);
	uc_value_t *groups = uc_fn_arg(1);
	const char *username;
	uc_value_t *result;

	if (ucv_type(username_val) != UC_STRING || ucv_type(groups) != UC_ARRAY)
		return ucv_array_new(vm);

	username = ucv_string_get(username_val);
	result = ucv_array_new(vm);

	for (size_t i = 0; i < ucv_array_length(groups); i++) {
		uc_value_t *gr = ucv_array_get(groups, i);
		uc_value_t *members = ucv_object_get(gr, "members", NULL);

		if (ucv_type(members) != UC_ARRAY)
			continue;

		for (size_t j = 0; j < ucv_array_length(members); j++) {
			uc_value_t *m = ucv_array_get(members, j);

			if (ucv_type(m) == UC_STRING &&
			    strcmp(ucv_string_get(m), username) == 0) {
				ucv_array_push(result, ucv_get(gr));
				break;
			}
		}
	}

	return result;
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

static uc_value_t *
uc_credentials_check(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *username_val = uc_fn_arg(0);
	uc_value_t *password_val = uc_fn_arg(1);
	const char *username, *password;
	struct spwd *sp;
	char *computed;

	if (ucv_type(username_val) != UC_STRING ||
	    ucv_type(password_val) != UC_STRING)
		return ucv_string_new("Credentials_Bad_Requested_Username_Not_Supported");

	username = ucv_string_get(username_val);
	password = ucv_string_get(password_val);

	sp = getspnam(username);
	if (!sp)
		return ucv_string_new("Credentials_Bad_Requested_Username_Not_Supported");

	if (!sp->sp_pwdp || !*sp->sp_pwdp ||
	    strcmp(sp->sp_pwdp, "*") == 0 || strcmp(sp->sp_pwdp, "!") == 0)
		return ucv_string_new("Credentials_Bad_Requested_Password_Incorrect");

	if (sp->sp_pwdp[0] == '!')
		return ucv_string_new("Credentials_Bad_Requested_Password_Incorrect");

	errno = 0;
	computed = crypt(password, sp->sp_pwdp);
	if (!computed || errno != 0 || strcmp(computed, sp->sp_pwdp) != 0)
		return ucv_string_new("Credentials_Bad_Requested_Password_Incorrect");

	return ucv_string_new("Credentials_Good");
}

static uc_value_t *
uc_user_add(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *username_val = uc_fn_arg(0);
	uc_value_t *uid_val = uc_fn_arg(1);
	uc_value_t *gid_val = uc_fn_arg(2);
	uc_value_t *home_val = uc_fn_arg(3);
	uc_value_t *shell_val = uc_fn_arg(4);
	uc_value_t *pw_entries, *sp_entries, *new_pw, *new_sp;
	int64_t uid, gid;

	if (ucv_type(username_val) != UC_STRING)
		return ucv_boolean_new(false);

	pw_entries = uc_passwd_get_all(vm, 0);
	sp_entries = uc_shadow_get_all(vm, 0);
	if (!pw_entries || !sp_entries)
		return ucv_boolean_new(false);

	uid = ucv_type(uid_val) == UC_INTEGER ? ucv_int64_get(uid_val) : 0;
	gid = ucv_type(gid_val) == UC_INTEGER ? ucv_int64_get(gid_val) : 0;

	if (uid == 0) {
		uid = MIN_DYNAMIC_ID;
		for (size_t i = 0; i < ucv_array_length(pw_entries); i++) {
			uc_value_t *pw = ucv_array_get(pw_entries, i);
			uc_value_t *u = ucv_object_get(pw, "uid", NULL);
			int64_t eu = u ? ucv_int64_get(u) : 0;
			if (eu >= uid)
				uid = eu + 1;
		}
	}

	new_pw = ucv_object_new(vm);
	ucv_object_add(new_pw, "username", ucv_get(username_val));
	ucv_object_add(new_pw, "uid", ucv_int64_new(uid));
	ucv_object_add(new_pw, "gid", ucv_int64_new(gid));
	ucv_object_add(new_pw, "gecos", ucv_string_new(""));
	ucv_object_add(new_pw, "home",
		       (ucv_type(home_val) == UC_STRING) ? ucv_get(home_val) : ucv_string_new("/var"));
	ucv_object_add(new_pw, "shell",
		       (ucv_type(shell_val) == UC_STRING) ? ucv_get(shell_val) : ucv_string_new("/bin/false"));
	ucv_array_push(pw_entries, new_pw);

	new_sp = ucv_object_new(vm);
	ucv_object_add(new_sp, "username", ucv_get(username_val));
	ucv_object_add(new_sp, "hash", ucv_string_new("!"));
	ucv_object_add(new_sp, "lastchanged", ucv_int64_new(0));
	ucv_object_add(new_sp, "min", ucv_int64_new(0));
	ucv_object_add(new_sp, "max", ucv_int64_new(99999));
	ucv_object_add(new_sp, "warn", ucv_int64_new(7));
	ucv_object_add(new_sp, "inactive", ucv_int64_new(-1));
	ucv_object_add(new_sp, "expire", ucv_int64_new(-1));
	ucv_array_push(sp_entries, new_sp);

	uc_value_t *r1 = atomic_write(vm, "/etc/passwd", pw_entries, object_to_pw, 0644);
	uc_value_t *r2 = atomic_write(vm, "/etc/shadow", sp_entries, object_to_sp, 0600);

	bool ok = ucv_boolean_get(r1) && ucv_boolean_get(r2);
	ucv_put(r1);
	ucv_put(r2);
	ucv_put(pw_entries);
	ucv_put(sp_entries);

	return ucv_boolean_new(ok);
}

static uc_value_t *
uc_user_del(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *username_val = uc_fn_arg(0);
	uc_value_t *pw_entries, *sp_entries, *gr_entries;
	uc_value_t *new_pw, *new_sp;
	const char *username;

	if (ucv_type(username_val) != UC_STRING)
		return ucv_boolean_new(false);

	username = ucv_string_get(username_val);

	pw_entries = uc_passwd_get_all(vm, 0);
	sp_entries = uc_shadow_get_all(vm, 0);
	gr_entries = uc_group_get_all(vm, 0);

	new_pw = ucv_array_new(vm);
	for (size_t i = 0; i < ucv_array_length(pw_entries); i++) {
		uc_value_t *pw = ucv_array_get(pw_entries, i);
		uc_value_t *n = ucv_object_get(pw, "username", NULL);
		if (n && ucv_type(n) == UC_STRING && strcmp(ucv_string_get(n), username) == 0)
			continue;
		ucv_array_push(new_pw, ucv_get(pw));
	}

	new_sp = ucv_array_new(vm);
	for (size_t i = 0; i < ucv_array_length(sp_entries); i++) {
		uc_value_t *sp = ucv_array_get(sp_entries, i);
		uc_value_t *n = ucv_object_get(sp, "username", NULL);
		if (n && ucv_type(n) == UC_STRING && strcmp(ucv_string_get(n), username) == 0)
			continue;
		ucv_array_push(new_sp, ucv_get(sp));
	}

	for (size_t i = 0; i < ucv_array_length(gr_entries); i++) {
		uc_value_t *gr = ucv_array_get(gr_entries, i);
		uc_value_t *members = ucv_object_get(gr, "members", NULL);
		uc_value_t *new_members = ucv_array_new(vm);

		if (ucv_type(members) == UC_ARRAY) {
			for (size_t j = 0; j < ucv_array_length(members); j++) {
				uc_value_t *m = ucv_array_get(members, j);
				if (ucv_type(m) == UC_STRING &&
				    strcmp(ucv_string_get(m), username) == 0)
					continue;
				ucv_array_push(new_members, ucv_get(m));
			}
		}
		ucv_object_add(gr, "members", new_members);
	}

	uc_value_t *r1 = atomic_write(vm, "/etc/passwd", new_pw, object_to_pw, 0644);
	uc_value_t *r2 = atomic_write(vm, "/etc/shadow", new_sp, object_to_sp, 0600);
	uc_value_t *r3 = atomic_write(vm, "/etc/group", gr_entries, object_to_gr, 0644);

	bool ok = ucv_boolean_get(r1) && ucv_boolean_get(r2) && ucv_boolean_get(r3);
	ucv_put(r1);
	ucv_put(r2);
	ucv_put(r3);
	ucv_put(pw_entries);
	ucv_put(sp_entries);
	ucv_put(gr_entries);
	ucv_put(new_pw);
	ucv_put(new_sp);

	return ucv_boolean_new(ok);
}

static uc_value_t *
uc_user_update_field(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *username_val = uc_fn_arg(0);
	uc_value_t *field_val = uc_fn_arg(1);
	uc_value_t *value_val = uc_fn_arg(2);
	uc_value_t *entries;

	if (ucv_type(username_val) != UC_STRING ||
	    ucv_type(field_val) != UC_STRING)
		return ucv_boolean_new(false);

	entries = uc_passwd_get_all(vm, 0);
	if (!entries)
		return ucv_boolean_new(false);

	const char *username = ucv_string_get(username_val);
	const char *field = ucv_string_get(field_val);

	for (size_t i = 0; i < ucv_array_length(entries); i++) {
		uc_value_t *pw = ucv_array_get(entries, i);
		uc_value_t *n = ucv_object_get(pw, "username", NULL);

		if (!n || ucv_type(n) != UC_STRING || strcmp(ucv_string_get(n), username) != 0)
			continue;

		ucv_object_add(pw, field, ucv_get(value_val));
		uc_value_t *r = atomic_write(vm, "/etc/passwd", entries, object_to_pw, 0644);
		bool ok = ucv_boolean_get(r);
		ucv_put(r);
		ucv_put(entries);
		return ucv_boolean_new(ok);
	}

	ucv_put(entries);
	return ucv_boolean_new(false);
}

static uc_value_t *
uc_shadow_update_hash(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *username_val = uc_fn_arg(0);
	uc_value_t *hash_val = uc_fn_arg(1);
	uc_value_t *entries;

	if (ucv_type(username_val) != UC_STRING ||
	    ucv_type(hash_val) != UC_STRING)
		return ucv_boolean_new(false);

	entries = uc_shadow_get_all(vm, 0);
	if (!entries)
		return ucv_boolean_new(false);

	const char *username = ucv_string_get(username_val);

	for (size_t i = 0; i < ucv_array_length(entries); i++) {
		uc_value_t *sp = ucv_array_get(entries, i);
		uc_value_t *n = ucv_object_get(sp, "username", NULL);

		if (!n || ucv_type(n) != UC_STRING || strcmp(ucv_string_get(n), username) != 0)
			continue;

		ucv_object_add(sp, "hash", ucv_get(hash_val));
		uc_value_t *r = atomic_write(vm, "/etc/shadow", entries, object_to_sp, 0600);
		bool ok = ucv_boolean_get(r);
		ucv_put(r);
		ucv_put(entries);
		return ucv_boolean_new(ok);
	}

	ucv_put(entries);
	return ucv_boolean_new(false);
}

static uc_value_t *
uc_shadow_set_locked(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *username_val = uc_fn_arg(0);
	uc_value_t *locked_val = uc_fn_arg(1);
	uc_value_t *entries;
	bool locked;

	if (ucv_type(username_val) != UC_STRING)
		return ucv_boolean_new(false);

	locked = ucv_boolean_get(locked_val);

	entries = uc_shadow_get_all(vm, 0);
	if (!entries)
		return ucv_boolean_new(false);

	const char *username = ucv_string_get(username_val);

	for (size_t i = 0; i < ucv_array_length(entries); i++) {
		uc_value_t *sp = ucv_array_get(entries, i);
		uc_value_t *n = ucv_object_get(sp, "username", NULL);
		uc_value_t *h;
		const char *hash;

		if (!n || ucv_type(n) != UC_STRING || strcmp(ucv_string_get(n), username) != 0)
			continue;

		h = ucv_object_get(sp, "hash", NULL);
		hash = (h && ucv_type(h) == UC_STRING) ? ucv_string_get(h) : "";

		if (locked && hash[0] != '!') {
			char new_hash[256];
			snprintf(new_hash, sizeof(new_hash), "!%s", hash);
			ucv_object_add(sp, "hash", ucv_string_new(new_hash));
		} else if (!locked && hash[0] == '!') {
			ucv_object_add(sp, "hash", ucv_string_new(hash + 1));
		}

		uc_value_t *r = atomic_write(vm, "/etc/shadow", entries, object_to_sp, 0600);
		bool ok = ucv_boolean_get(r);
		ucv_put(r);
		ucv_put(entries);
		return ucv_boolean_new(ok);
	}

	ucv_put(entries);
	return ucv_boolean_new(false);
}

static uc_value_t *
uc_group_add(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *groupname_val = uc_fn_arg(0);
	uc_value_t *gid_val = uc_fn_arg(1);
	uc_value_t *entries, *new_gr;
	int64_t gid;

	if (ucv_type(groupname_val) != UC_STRING)
		return ucv_boolean_new(false);

	entries = uc_group_get_all(vm, 0);
	if (!entries)
		return ucv_boolean_new(false);

	gid = (ucv_type(gid_val) == UC_INTEGER) ? ucv_int64_get(gid_val) : 0;

	if (gid == 0) {
		gid = MIN_DYNAMIC_ID;
		for (size_t i = 0; i < ucv_array_length(entries); i++) {
			uc_value_t *gr = ucv_array_get(entries, i);
			uc_value_t *g = ucv_object_get(gr, "gid", NULL);
			int64_t eg = g ? ucv_int64_get(g) : 0;
			if (eg >= gid)
				gid = eg + 1;
		}
	}

	new_gr = ucv_object_new(vm);
	ucv_object_add(new_gr, "groupname", ucv_get(groupname_val));
	ucv_object_add(new_gr, "gid", ucv_int64_new(gid));
	ucv_object_add(new_gr, "members", ucv_array_new(vm));
	ucv_array_push(entries, new_gr);

	uc_value_t *r = atomic_write(vm, "/etc/group", entries, object_to_gr, 0644);
	bool ok = ucv_boolean_get(r);
	ucv_put(r);
	ucv_put(entries);
	return ucv_boolean_new(ok);
}

static uc_value_t *
uc_group_del(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *groupname_val = uc_fn_arg(0);
	uc_value_t *entries, *filtered;

	if (ucv_type(groupname_val) != UC_STRING)
		return ucv_boolean_new(false);

	entries = uc_group_get_all(vm, 0);
	if (!entries)
		return ucv_boolean_new(false);

	const char *groupname = ucv_string_get(groupname_val);
	filtered = ucv_array_new(vm);

	for (size_t i = 0; i < ucv_array_length(entries); i++) {
		uc_value_t *gr = ucv_array_get(entries, i);
		uc_value_t *n = ucv_object_get(gr, "groupname", NULL);
		if (n && ucv_type(n) == UC_STRING && strcmp(ucv_string_get(n), groupname) == 0)
			continue;
		ucv_array_push(filtered, ucv_get(gr));
	}

	uc_value_t *r = atomic_write(vm, "/etc/group", filtered, object_to_gr, 0644);
	bool ok = ucv_boolean_get(r);
	ucv_put(r);
	ucv_put(entries);
	ucv_put(filtered);
	return ucv_boolean_new(ok);
}

static uc_value_t *
uc_group_members_update(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *groupname_val = uc_fn_arg(0);
	uc_value_t *members_val = uc_fn_arg(1);
	uc_value_t *entries;

	if (ucv_type(groupname_val) != UC_STRING ||
	    ucv_type(members_val) != UC_ARRAY)
		return ucv_boolean_new(false);

	entries = uc_group_get_all(vm, 0);
	if (!entries)
		return ucv_boolean_new(false);

	const char *groupname = ucv_string_get(groupname_val);

	for (size_t i = 0; i < ucv_array_length(entries); i++) {
		uc_value_t *gr = ucv_array_get(entries, i);
		uc_value_t *n = ucv_object_get(gr, "groupname", NULL);

		if (!n || ucv_type(n) != UC_STRING || strcmp(ucv_string_get(n), groupname) != 0)
			continue;

		ucv_object_add(gr, "members", ucv_get(members_val));
		uc_value_t *r = atomic_write(vm, "/etc/group", entries, object_to_gr, 0644);
		bool ok = ucv_boolean_get(r);
		ucv_put(r);
		ucv_put(entries);
		return ucv_boolean_new(ok);
	}

	ucv_put(entries);
	return ucv_boolean_new(false);
}

static const uc_function_list_t global_fns[] = {
	{ "passwd_get_all",		uc_passwd_get_all },
	{ "passwd_get_by_name",		uc_passwd_get_by_name },
	{ "passwd_get_by_uid",		uc_passwd_get_by_uid },
	{ "shadow_get_all",		uc_shadow_get_all },
	{ "shadow_get_by_name",		uc_shadow_get_by_name },
	{ "group_get_all",		uc_group_get_all },
	{ "group_get_by_name",		uc_group_get_by_name },
	{ "passwd_set",			uc_passwd_set },
	{ "shadow_set",			uc_shadow_set },
	{ "group_set",			uc_group_set },
	{ "crypt",			uc_crypt },
	{ "is_static_user",		uc_is_static_user },
	{ "is_static_group",		uc_is_static_group },
	{ "is_role_group",		uc_is_role_group },
	{ "shells_get",			uc_shells_get },
	{ "user_groups_find",		uc_user_groups_find },
	{ "password_hash",		uc_password_hash },
	{ "credentials_check",		uc_credentials_check },
	{ "user_add",			uc_user_add },
	{ "user_del",			uc_user_del },
	{ "user_update_field",		uc_user_update_field },
	{ "shadow_update_hash",		uc_shadow_update_hash },
	{ "shadow_set_locked",		uc_shadow_set_locked },
	{ "group_add",			uc_group_add },
	{ "group_del",			uc_group_del },
	{ "group_members_update",	uc_group_members_update },
};

void
uc_module_init(uc_vm_t *vm, uc_value_t *scope)
{
	uc_function_list_register(scope, global_fns);
}
