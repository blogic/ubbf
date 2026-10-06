/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * ubbf-logd: forwards the logd ring and network syslog input to files and
 * remote syslog servers, as the TR-181 Device.Syslog render describes in
 * its JSON config.
 */

#include <signal.h>
#include <stdio.h>
#include <syslog.h>
#include <unistd.h>

#include <libubox/ulog.h>
#include <libubox/uloop.h>

#include "config.h"
#include "ubus.h"

static int
usage(const char *prog)
{
	fprintf(stderr, "Usage: %s [-c <config>]\n", prog);

	return 1;
}

int
main(int argc, char **argv)
{
	const char *path = NULL;
	int ch;

	while ((ch = getopt(argc, argv, "c:")) != -1) {
		switch (ch) {
		case 'c':
			path = optarg;
			break;

		default:
			return usage(argv[0]);
		}
	}

	signal(SIGPIPE, SIG_IGN);
	ulog_open(ULOG_SYSLOG, LOG_DAEMON, "ubbf-logd");
	uloop_init();

	config_init(path);
	config_reload(NULL);
	logd_ubus_init();

	uloop_run();

	logd_ubus_done();
	config_free();
	uloop_done();
	ulog_close();

	return 0;
}
