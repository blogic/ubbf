/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * File transfers with curl for the TR-143 diagnostics and the DeviceInfo
 * uploads and downloads. curl runs without a shell; the credentials go
 * through a config file, because a `-u` argument is visible in the process
 * list and in the logged command.
 */

#include "ubbf.h"
#include "bindings.h"

#include <inttypes.h>
#include <syslog.h>
#include <unistd.h>

#define CURL_TRANSFER_TIMEOUT_S	1800

/* Developer and test images carry this file, and the testbed drives their
 * transfers against a lab HTTPS endpoint whose CA the image does not have.
 * Production images lack the file and keep the certificate check. */
#define DEVELOPER_SENTINEL	"/etc/ubbf/developer"

const struct constval curl_vals[] = {
	{ "CURL_TRANSFER_TIMEOUT_S", CURL_TRANSFER_TIMEOUT_S },
};

const size_t curl_vals_count = ARRAY_SIZE(curl_vals);

/* The argument list of curl, and the same command as the shell would see
 * it, for the log. */
struct curl_cmd {
	char **argv;
	size_t argc;
	uc_stringbuf_t *log;
};

static void
cmd_raw(struct curl_cmd *cmd, const char *word)
{
	cmd->argv = xrealloc(cmd->argv, (cmd->argc + 2) * sizeof(*cmd->argv));
	cmd->argv[cmd->argc++] = xstrdup(word);
	cmd->argv[cmd->argc] = NULL;

	ucv_stringbuf_printf(cmd->log, "%s%s", (cmd->argc > 1) ? " " : "", word);
}

/* A value as shell_escape() quotes it: null is ''. */
static void
cmd_value(uc_vm_t *vm, struct curl_cmd *cmd, uc_value_t *val)
{
	char *text = val ? ucv_to_string(vm, val) : xstrdup("");

	cmd->argv = xrealloc(cmd->argv, (cmd->argc + 2) * sizeof(*cmd->argv));
	cmd->argv[cmd->argc++] = text;
	cmd->argv[cmd->argc] = NULL;

	ucv_stringbuf_printf(cmd->log, "%s", " ");
	if (val)
		shell_quote_append(vm, cmd->log, val);
	else
		ucv_stringbuf_printf(cmd->log, "%s", "''");
}

static void
cmd_text(uc_vm_t *vm, struct curl_cmd *cmd, const char *text)
{
	uc_value_t *val = ucv_string_new(text);

	cmd_value(vm, cmd, val);
	ucv_put(val);
}

static void
cmd_free(struct curl_cmd *cmd)
{
	for (size_t i = 0; i < cmd->argc; i++)
		free(cmd->argv[i]);
	free(cmd->argv);
}

static void
cmd_headers_add(uc_vm_t *vm, struct curl_cmd *cmd, uc_value_t *headers)
{
	char *value, *header;

	/* ucode sprintf('%s', null) gives "(null)" */
	ucv_object_foreach(headers, name, val) {
		value = val ? ucv_to_string(vm, val) : xstrdup("(null)");
		xasprintf(&header, "%s: %s", name, value);
		cmd_raw(cmd, "-H");
		cmd_text(vm, cmd, header);
		free(header);
		free(value);
	}
}

static void
cmd_seconds_add(struct curl_cmd *cmd, const char *flag, uc_value_t *opts, const char *name)
{
	uc_value_t *val = ucv_object_get(opts, name, NULL);
	char buf[24];

	if (!ucv_is_truish(val))
		return;

	snprintf(buf, sizeof(buf), "%" PRId64, ucv_to_integer(val));
	cmd_raw(cmd, flag);
	cmd_raw(cmd, buf);
}

/* The URL goes after --url: as a bare argument, a value that starts with
 * '-' would be read as a curl option. */
static void
cmd_build(uc_vm_t *vm, struct curl_cmd *cmd, const char *op, uc_value_t *url, uc_value_t *path,
	  uc_value_t *opts, const char *config_path)
{
	uc_value_t *fmt = ucv_object_get(opts, "format_string", NULL);
	char *text, *body;

	cmd_raw(cmd, "curl");
	cmd_raw(cmd, "--fail");
	cmd_raw(cmd, "--silent");

	if (ucv_is_truish(ucv_object_get(opts, "insecure", NULL)))
		cmd_raw(cmd, "-k");

	if (config_path) {
		cmd_raw(cmd, "-K");
		cmd_text(vm, cmd, config_path);
	}

	cmd_seconds_add(cmd, "--max-time", opts, "timeout");
	cmd_seconds_add(cmd, "--connect-timeout", opts, "connect_timeout");

	if (ucv_is_truish(ucv_object_get(opts, "ipv4_only", NULL)))
		cmd_raw(cmd, "--ipv4");
	else if (ucv_is_truish(ucv_object_get(opts, "ipv6_only", NULL)))
		cmd_raw(cmd, "--ipv6");

	if (ucv_is_truish(ucv_object_get(opts, "headers", NULL)))
		cmd_headers_add(vm, cmd, ucv_object_get(opts, "headers", NULL));

	if (ucv_is_truish(fmt)) {
		cmd_raw(cmd, "-w");
		cmd_value(vm, cmd, fmt);
	}

	if (!strcmp(op, "download")) {
		cmd_raw(cmd, "-o");
		cmd_value(vm, cmd, path);
	} else if (!strcmp(op, "upload")) {
		cmd_raw(cmd, "-T");
		cmd_value(vm, cmd, path);
	} else {
		cmd_raw(cmd, "--show-error");
		cmd_raw(cmd, "-X");
		cmd_raw(cmd, op);
		cmd_raw(cmd, "--data-binary");
		text = path ? ucv_to_string(vm, path) : xstrdup("null");
		xasprintf(&body, "@%s", text);
		cmd_text(vm, cmd, body);
		free(body);
		free(text);
	}

	cmd_raw(cmd, "--url");
	cmd_value(vm, cmd, url);
}

/* The logged command with the user info of each URL masked: the text
 * between "://" and an '@' before any '/', '\'' or ' ' becomes "***". */
static char *
log_mask(const char *cmd)
{
	uc_stringbuf_t *sb = ucv_stringbuf_new();
	const char *p = cmd, *scheme, *host;
	uc_value_t *res;
	char *out;
	size_t n;

	while ((scheme = strstr(p, "://")) != NULL) {
		host = scheme + 3;
		n = strcspn(host, "/@' ");
		if (host[n] != '@') {
			ucv_stringbuf_addstr(sb, p, host - p);
			p = host;
			continue;
		}

		ucv_stringbuf_addstr(sb, p, scheme - p);
		ucv_stringbuf_addstr(sb, "://***@", 7);
		p = host + n + 1;
	}
	ucv_stringbuf_addstr(sb, p, strlen(p));

	res = ucv_stringbuf_finish(sb);
	out = xstrdup(ucv_string_get(res));
	ucv_put(res);

	return out;
}

static uc_value_t *
result_new(uc_vm_t *vm, bool ok, int64_t exitcode, uc_value_t *output, uc_value_t *metrics)
{
	uc_value_t *res = ucv_object_new(vm);

	ucv_object_add(res, "success", ucv_boolean_new(ok));
	ucv_object_add(res, "exitcode", ucv_int64_new(exitcode));
	ucv_object_add(res, "output", output);
	ucv_object_add(res, "metrics", metrics);

	return res;
}

static uc_value_t *
result_failed(uc_vm_t *vm, const char *why)
{
	return result_new(vm, false, -1, ucv_string_new(why), NULL);
}

/* Runs curl. exitcode is the exit code of curl: 0 on a clean exit, a
 * positive curl exit code on failure, -1 when curl did not run or ended by
 * a signal. */
static uc_value_t *
curl_execute(uc_vm_t *vm, struct curl_cmd *cmd, uc_value_t *opts)
{
	uc_value_t *output, *metrics = NULL;
	char *masked, *out;
	int status;

	ucv_stringbuf_printf(cmd->log, "%s", " 2>&1");
	output = ucv_stringbuf_finish(cmd->log);
	cmd->log = NULL;
	masked = log_mask(ucv_string_get(output));
	ucv_put(output);
	ubbf_log(LOG_INFO, "curl: %s", masked);
	free(masked);

	out = spawn_output(cmd->argv, &status);
	if (!out)
		return result_failed(vm, "Failed to execute curl");

	output = ucv_string_new(out);
	free(out);

	if (ucv_is_truish(ucv_object_get(opts, "format_string", NULL)))
		metrics = curl_metrics_new(vm, output);

	return result_new(vm, status == 0, status, output, metrics);
}

/* curl config syntax: a double-quoted value with backslash escapes. */
static char *
config_quote(const char *value)
{
	uc_stringbuf_t *sb = ucv_stringbuf_new();
	uc_value_t *res;
	char *out;

	ucv_stringbuf_addstr(sb, "\"", 1);
	for (const char *p = value; *p; p++) {
		switch (*p) {
		case '\\': ucv_stringbuf_addstr(sb, "\\\\", 2); break;
		case '"': ucv_stringbuf_addstr(sb, "\\\"", 2); break;
		case '\t': ucv_stringbuf_addstr(sb, "\\t", 2); break;
		case '\n': ucv_stringbuf_addstr(sb, "\\n", 2); break;
		case '\r': ucv_stringbuf_addstr(sb, "\\r", 2); break;
		case '\v': ucv_stringbuf_addstr(sb, "\\v", 2); break;
		default: ucv_stringbuf_addstr(sb, p, 1); break;
		}
	}
	ucv_stringbuf_addstr(sb, "\"", 1);

	res = ucv_stringbuf_finish(sb);
	out = xstrdup(ucv_string_get(res));
	ucv_put(res);

	return out;
}

/* Writes `user = "<user>:<password>"` to a new file of mode 0600. */
static bool
credentials_file_write(uc_vm_t *vm, uc_value_t *opts, char *path, size_t len)
{
	uc_value_t *pass = ucv_object_get(opts, "password", NULL);
	char *user = ucv_to_string(vm, ucv_object_get(opts, "username", NULL));
	char *password = pass ? ucv_to_string(vm, pass) : xstrdup("");
	char *userpass, *quoted;
	bool ok = false;
	FILE *fp;

	if (tmpfile_create("curl", ".conf", path, len)) {
		xasprintf(&userpass, "%s:%s", user, password);
		quoted = config_quote(userpass);

		fp = fopen(path, "w");
		ok = fp && fprintf(fp, "user = %s\n", quoted) >= 0;
		if (fp && fclose(fp))
			ok = false;
		if (!ok)
			unlink(path);

		free(quoted);
		free(userpass);
	}

	free(user);
	free(password);

	return ok;
}

static uc_value_t *
curl_transfer(uc_vm_t *vm, const char *op, uc_value_t *url, uc_value_t *path, uc_value_t *opts)
{
	struct curl_cmd cmd = { .log = ucv_stringbuf_new() };
	char config[256];
	bool creds = ucv_is_truish(ucv_object_get(opts, "username", NULL));
	uc_value_t *res;

	if (creds && !credentials_file_write(vm, opts, config, sizeof(config))) {
		ucv_put(ucv_stringbuf_finish(cmd.log));
		return result_failed(vm, "Failed to write curl credentials");
	}

	cmd_build(vm, &cmd, op, url, path, opts, creds ? config : NULL);
	res = curl_execute(vm, &cmd, opts);
	cmd_free(&cmd);

	if (creds)
		unlink(config);

	return res;
}

/**
 * ucode: `curl_insecure_allowed()`, whether a transfer may skip the TLS
 * certificate check: only on a developer image.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (none expected)
 * @return       boolean
 */
uc_value_t *
uc_ubbf_curl_insecure_allowed(uc_vm_t *vm, size_t nargs)
{
	struct stat st;

	return ucv_boolean_new(stat(DEVELOPER_SENTINEL, &st) == 0);
}

/**
 * ucode: `curl_exit_to_status(exitcode)`, the TR-143 DiagnosticsState of a
 * curl exit code for Download and Upload diagnostics.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: exit code)
 * @return       status string, Error_Other for an unmapped code
 */
uc_value_t *
uc_ubbf_curl_exit_to_status(uc_vm_t *vm, size_t nargs)
{
	static const struct {
		const char *code;
		const char *status;
	} statuses[] = {
		{ "0", "Complete" }, { "6", "Error_CannotResolveHostName" },
		{ "7", "Error_InitConnectionFailed" }, { "18", "Error_IncorrectSize" },
		{ "22", "Error_NoResponse" }, { "28", "Error_Timeout" },
	};
	uc_value_t *map = ucv_object_new(vm), *status;

	for (size_t i = 0; i < ARRAY_SIZE(statuses); i++)
		ucv_object_add(map, statuses[i].code, ucv_string_new(statuses[i].status));

	/* ucv_key_get() turns the code into a key as ucode indexing does */
	status = ucv_key_get(vm, map, uc_fn_arg(0));
	ucv_put(map);

	return status ? status : ucv_string_new("Error_Other");
}

/**
 * ucode: `curl_download(url, output_path, opts)`, downloads a file.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: source URL, local path,
 *               options: username, password, timeout, connect_timeout,
 *               ipv4_only, ipv6_only, headers, format_string, insecure)
 * @return       `{ success, exitcode, output, metrics }`
 */
uc_value_t *
uc_ubbf_curl_download(uc_vm_t *vm, size_t nargs)
{
	return curl_transfer(vm, "download", uc_fn_arg(0), uc_fn_arg(1), uc_fn_arg(2));
}

/**
 * ucode: `curl_send(method, url, body_path, opts)`, sends a file as the
 * body of an HTTP POST or PUT, as is, with the headers in opts.headers.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (4 expected: 'POST' or 'PUT', target
 *               URL, local file with the body, options)
 * @return       `{ success, exitcode, output, metrics }`
 */
uc_value_t *
uc_ubbf_curl_send(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *method = uc_fn_arg(0), *res;
	char *text, *why;

	if (value_loose_is(method, "POST"))
		return curl_transfer(vm, "POST", uc_fn_arg(1), uc_fn_arg(2), uc_fn_arg(3));
	if (value_loose_is(method, "PUT"))
		return curl_transfer(vm, "PUT", uc_fn_arg(1), uc_fn_arg(2), uc_fn_arg(3));

	text = ucv_to_string(vm, method);
	xasprintf(&why, "unsupported method %s", text);
	res = result_failed(vm, why);
	free(why);
	free(text);

	return res;
}

static uc_value_t *
info_or(uc_value_t *info, const char *name)
{
	uc_value_t *val = ucv_object_get(info, name, NULL);

	return val ? ucv_get(val) : ucv_string_new("unknown");
}

/* With a trailing '/', the caller asks for a device-qualified file name:
 * the base name gets the time, ManufacturerOUI and SerialNumber in front,
 * so a shared upload endpoint can tell the files of the devices apart. A
 * URL without it is the full target. */
static uc_value_t *
upload_url_build(uc_vm_t *vm, uc_value_t *url, uc_value_t *path)
{
	uc_value_t *info = deviceinfo_value(vm), *oui, *serial, *res;
	const char *base, *u = ucv_string_get(url);
	char *o, *s, *p, *full;

	if (ucv_type(url) != UC_STRING || !*u || u[strlen(u) - 1] != '/')
		return ucv_get(url);

	oui = info_or(info, "ManufacturerOUI");
	serial = info_or(info, "SerialNumber");
	o = ucv_to_string(vm, oui);
	s = ucv_to_string(vm, serial);
	p = ucv_to_string(vm, path);
	base = strrchr(p, '/') ? strrchr(p, '/') + 1 : p;

	xasprintf(&full, "%s%" PRId64 "-%s-%s-%s", u, (int64_t)time(NULL), o, s, base);
	res = ucv_string_new(full);

	free(full);
	free(p);
	free(s);
	free(o);
	ucv_put(oui);
	ucv_put(serial);

	return res;
}

static void
header_set(uc_value_t *headers, const char *name, uc_value_t *val)
{
	if (ucv_is_truish(val))
		ucv_object_add(headers, name, ucv_get(val));
}

/* The extension header: the file extension without a leading '.'. */
static void
extension_header_set(uc_vm_t *vm, uc_value_t *headers, uc_value_t *ext)
{
	char *text, *name;

	if (!ucv_is_truish(ext))
		return;

	text = ucv_to_string(vm, ext);
	name = text + (*text == '.');
	if (*name)
		ucv_object_add(headers, "X-ubbf-extension", ucv_string_new(name));
	free(text);
}

/**
 * ucode: `curl_upload(url, input_path, opts)`, uploads a file with the
 * identity of the device in X-ubbf-* headers.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: target URL, local file,
 *               options as curl_download() takes them plus command_key and
 *               extension)
 * @return       `{ success, exitcode, output, metrics, url }`, url being the
 *               URL the file went to (see upload_url_build())
 */
uc_value_t *
uc_ubbf_curl_upload(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *opts = uc_fn_arg(2), *info = deviceinfo_value(vm), *headers, *copy, *url, *res;

	headers = ucv_object_new(vm);
	ucv_object_foreach(ucv_object_get(opts, "headers", NULL), name, val)
		ucv_object_add(headers, name, ucv_get(val));

	header_set(headers, "X-ubbf-oui", ucv_object_get(info, "ManufacturerOUI", NULL));
	header_set(headers, "X-ubbf-serial", ucv_object_get(info, "SerialNumber", NULL));
	header_set(headers, "X-ubbf-key", ucv_object_get(opts, "command_key", NULL));
	extension_header_set(vm, headers, ucv_object_get(opts, "extension", NULL));

	copy = ucv_object_new(vm);
	ucv_object_foreach(opts, key, v)
		ucv_object_add(copy, key, ucv_get(v));
	ucv_object_add(copy, "headers", headers);

	url = upload_url_build(vm, uc_fn_arg(0), uc_fn_arg(1));
	res = curl_transfer(vm, "upload", url, uc_fn_arg(1), copy);
	ucv_object_add(res, "url", url);
	ucv_put(copy);

	return res;
}
