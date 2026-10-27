/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Logging of the data model: syslog through libubox ulog (and stderr on a
 * terminal), and a udebug ring of 64 KiB / 512 entries, large enough for
 * the trace of a TR-181 get cycle and an operation after it without
 * committing much RAM. One logger per process serves the C core and the
 * ucode handlers.
 */

#include "ubbf.h"
#include "bindings.h"

#include <stdarg.h>
#include <syslog.h>
#include <unistd.h>

#include <libubox/udebug.h>
#include <libubox/ulog.h>

#define LOG_RING_SIZE		(64 * 1024)
#define LOG_RING_ENTRIES	512

static struct udebug log_udebug;
static struct udebug_buf log_ring;
static struct udebug_buf_meta log_ring_meta;
static bool log_initialized;
static bool log_ring_ready;

/**
 * Opens the log once per process: syslog as `ident` in the daemon
 * facility, and the udebug ring of that name.
 *
 * Messages go to stderr as well only on a terminal: procd logs the stderr
 * of a service that sets `stderr 1`, so a daemon that wrote both channels
 * had each line twice in logread, the copy at `daemon.err`.
 *
 * @param ident  syslog identifier and ring name
 */
void
ubbf_log_init(const char *ident)
{
	char *name;

	if (log_initialized || !ident)
		return;

	/* ulog_open() and the ring keep the pointer. */
	name = xstrdup(ident);
	log_initialized = true;

	ulog_open(isatty(STDERR_FILENO) ? ULOG_SYSLOG | ULOG_STDIO : ULOG_SYSLOG,
		  LOG_DAEMON, name);

	udebug_init(&log_udebug);
	udebug_auto_connect(&log_udebug, NULL);

	if (udebug_buf_init(&log_ring, LOG_RING_ENTRIES, LOG_RING_SIZE))
		return;

	log_ring_meta.name = name;
	log_ring_meta.format = UDEBUG_FORMAT_STRING;
	udebug_buf_add(&log_udebug, &log_ring, &log_ring_meta);
	log_ring_ready = true;
}

/**
 * Writes one message to syslog and to the udebug ring.
 *
 * The ring is not ready before ubbf_log_init(), or when its memory could
 * not be set up; the message then goes to syslog only.
 *
 * @param priority  syslog priority; LOG_DEBUG adds the `DEBUG: ` prefix
 * @param msg       message without a trailing newline
 * @param len       length of `msg`
 */
static void
log_write(int priority, const char *msg, size_t len)
{
	const char *prefix = (priority == LOG_DEBUG) ? "DEBUG: " : "";

	/* ulog terminates syslog and stderr lines with the newline; the ring
	 * stores discrete entries and its reader adds the framing. */
	ulog(priority, "%s%.*s\n", prefix, (int)len, msg);

	if (!log_ring_ready)
		return;

	udebug_entry_init(&log_ring);
	udebug_entry_append(&log_ring, prefix, strlen(prefix));
	udebug_entry_append(&log_ring, msg, len);
	udebug_entry_add(&log_ring);
}

/**
 * Logs a printf-style message from C code.
 *
 * @param priority  syslog priority (LOG_DEBUG adds the `DEBUG: ` prefix)
 * @param fmt       printf format
 */
void
ubbf_log(int priority, const char *fmt, ...)
{
	char *msg;
	va_list ap;
	int len;

	va_start(ap, fmt);
	len = xvasprintf(&msg, fmt, ap);
	va_end(ap);

	if (len < 0)
		return;

	log_write(priority, msg, len);
	free(msg);
}

/**
 * Formats the arguments of a binding as the ucode sprintf() does and logs
 * the result.
 *
 * @param vm        ucode VM context
 * @param nargs     number of arguments: format, then its values
 * @param priority  syslog priority
 * @return          null
 */
static uc_value_t *
log_formatted(uc_vm_t *vm, size_t nargs, int priority)
{
	static uc_cfn_ptr_t uc_sprintf;
	uc_value_t *str;

	if (!uc_sprintf)
		uc_sprintf = uc_stdlib_function("sprintf");

	str = uc_sprintf(vm, nargs);
	if (ucv_type(str) != UC_STRING) {
		ucv_put(str);
		return NULL;
	}

	log_write(priority, ucv_string_get(str), ucv_string_length(str));
	ucv_put(str);
	return NULL;
}

/**
 * ucode: `log_init(ident)`. See ubbf_log_init().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: ident string)
 * @return       null
 */
uc_value_t *
uc_ubbf_log_init(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *ident = uc_fn_arg(0);

	if (ucv_type(ident) == UC_STRING)
		ubbf_log_init(ucv_string_get(ident));

	return NULL;
}

/**
 * ucode: `log_debug(fmt, ...args)`, the message with a `DEBUG: ` prefix.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments: sprintf() format and values
 * @return       null
 */
uc_value_t *
uc_ubbf_log_debug(uc_vm_t *vm, size_t nargs)
{
	return log_formatted(vm, nargs, LOG_DEBUG);
}

/**
 * ucode: `log_info(fmt, ...args)`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments: sprintf() format and values
 * @return       null
 */
uc_value_t *
uc_ubbf_log_info(uc_vm_t *vm, size_t nargs)
{
	return log_formatted(vm, nargs, LOG_INFO);
}

/**
 * ucode: `log_warn(fmt, ...args)`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments: sprintf() format and values
 * @return       null
 */
uc_value_t *
uc_ubbf_log_warn(uc_vm_t *vm, size_t nargs)
{
	return log_formatted(vm, nargs, LOG_WARNING);
}

/**
 * ucode: `log_err(fmt, ...args)`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments: sprintf() format and values
 * @return       null
 */
uc_value_t *
uc_ubbf_log_err(uc_vm_t *vm, size_t nargs)
{
	return log_formatted(vm, nargs, LOG_ERR);
}

/**
 * ucode: `log_exception(path, e)`, the path, the message and the source
 * line of the innermost frame, one log line each. Deeper frames are left
 * out to keep the operator's log short; the udebug ring or a debugger
 * gives the full backtrace.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: path, exception object)
 * @return       null
 */
uc_value_t *
uc_ubbf_log_exception(uc_vm_t *vm, size_t nargs)
{
	char *path_str = ucv_to_string(vm, uc_fn_arg(0));

	exception_log(vm, path_str, uc_fn_arg(1));
	free(path_str);

	return NULL;
}

/**
 * Logs an exception object as log_exception() does.
 *
 * @param vm     ucode VM context
 * @param where  the path or the handler that raised it
 * @param e      exception object
 */
void
exception_log(uc_vm_t *vm, const char *where, uc_value_t *e)
{
	uc_value_t *frame = ucv_array_get(ucv_object_get(e, "stacktrace", NULL), 0);
	uc_value_t *context = ucv_object_get(frame, "context", NULL);
	char *e_str = ucv_to_string(vm, e);
	char *context_str = ucv_to_string(vm, context);
	char *text, *line, *next;

	ubbf_log(LOG_ERR, "EXCEPTION at path: %s", where);

	xasprintf(&text, "Exception: %s\n%s", e_str, context_str);
	for (line = text; line; line = next) {
		next = strchr(line, '\n');
		if (next)
			*next++ = '\0';
		log_write(LOG_ERR, line, strlen(line));
	}

	free(text);
	free(context_str);
	free(e_str);
}

/**
 * Logs the exception that a call into the VM raised and clears it, for a
 * caller that goes on without the result. uc_vm_call() clears a pending
 * exception itself, so one that nobody takes would vanish at the next
 * call, or reach the script only when no call follows.
 *
 * @param vm     ucode VM context
 * @param where  the path or the handler that raised it
 * @return       true when an exception was raised
 */
bool
exception_log_clear(uc_vm_t *vm, const char *where)
{
	uc_value_t *e;

	if (vm->exception.type == EXCEPTION_NONE)
		return false;

	e = uc_vm_exception_object(vm);
	exception_log(vm, where, e);
	ucv_put(e);

	vm->exception.type = EXCEPTION_NONE;
	ucv_put(vm->exception.stacktrace);
	vm->exception.stacktrace = NULL;
	free(vm->exception.message);
	vm->exception.message = NULL;

	return true;
}
