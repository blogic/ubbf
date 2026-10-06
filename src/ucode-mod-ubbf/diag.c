/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#include "ubbf.h"
#include <ctype.h>

/**
 * Adds an integer pair `<key>: "<v>"` to an output object.
 */
static void
add_int_str(uc_value_t *o, const char *key, long long v)
{
	char buf[24];
	snprintf(buf, sizeof(buf), "%lld", v);
	ucv_object_add(o, key, ucv_string_new(buf));
}

/**
 * Parses a curl `-w` style key:value output into an object.
 *
 * Each line of the form `key:value` becomes one entry. Used by the
 * Download/Upload TR-143 handlers that previously did a per-line
 * `match(line, /^([^:]+):(.+)$/)` regex pass.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: text)
 * @return       object of parsed metrics, possibly empty
 */
uc_value_t *
uc_ubbf_curl_w_metrics_parse(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *data = uc_fn_arg(0);
	uc_value_t *out = ucv_object_new(vm);
	const char *p, *line_start, *colon, *line_end;
	const char *end;

	if (ucv_type(data) != UC_STRING)
		return out;

	p = ucv_string_get(data);
	end = p + strlen(p);

	while (p < end) {
		line_start = p;
		while (p < end && *p != '\n') p++;
		line_end = p;
		if (p < end) p++;

		colon = memchr(line_start, ':', line_end - line_start);
		if (!colon || colon == line_start)
			continue;

		char key[64], val[256];
		size_t klen = colon - line_start;
		size_t vlen = line_end - (colon + 1);
		if (klen >= sizeof(key)) klen = sizeof(key) - 1;
		if (vlen >= sizeof(val)) vlen = sizeof(val) - 1;
		memcpy(key, line_start, klen); key[klen] = '\0';
		memcpy(val, colon + 1, vlen); val[vlen] = '\0';

		ucv_object_add(out, key, ucv_string_new(val));
	}

	return out;
}

/**
 * Expands a flat object whose keys may carry the `Result.<n>.<param>`
 * dotted form into a nested `Result.<n>` sub-object tree.
 *
 * Keys that do not match the `Result.<digit+>.<rest>` shape are copied
 * to the top level unchanged. This replaces the per-key regex + nested
 * object build that the ucode `diagnostic_results_persist` did per
 * IPPing/IPLayerCapacity/DNS diagnostic call.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: flat object)
 * @return       nested object
 */
uc_value_t *
uc_ubbf_diag_result_expand(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *flat = uc_fn_arg(0);
	uc_value_t *out = ucv_object_new(vm);
	uc_value_t *result_obj = NULL;

	if (ucv_type(flat) != UC_OBJECT)
		return out;

	ucv_object_foreach(flat, key, value) {
		if (strncmp(key, "Result.", 7) != 0) {
			ucv_object_add(out, key, ucv_get(value));
			continue;
		}
		const char *p = key + 7;
		if (!isdigit((unsigned char)*p)) {
			ucv_object_add(out, key, ucv_get(value));
			continue;
		}
		const char *idx_start = p;
		while (isdigit((unsigned char)*p)) p++;
		if (*p != '.' || p[1] == '\0') {
			ucv_object_add(out, key, ucv_get(value));
			continue;
		}

		char idx[16];
		size_t ilen = p - idx_start;
		if (ilen >= sizeof(idx)) ilen = sizeof(idx) - 1;
		memcpy(idx, idx_start, ilen);
		idx[ilen] = '\0';

		const char *param = p + 1;

		if (!result_obj) {
			result_obj = ucv_object_new(vm);
			ucv_object_add(out, "Result", result_obj);
		}

		uc_value_t *idx_obj = ucv_object_get(result_obj, idx, NULL);
		if (ucv_type(idx_obj) != UC_OBJECT) {
			idx_obj = ucv_object_new(vm);
			ucv_object_add(result_obj, idx, idx_obj);
		}
		ucv_object_add(idx_obj, param, ucv_get(value));
	}

	return out;
}

/**
 * Parses BusyBox/iputils ping output into a TR-143 IPPing result object.
 *
 * Recognises the host-resolution `(<ip>)` section, the `N packets
 * transmitted, N (packets )?received` summary line, and the round-trip
 * `min/avg/max(/mdev) = a/b/c` line. `count` supplies the expected
 * number of probes so the FailureCount field is sensible when the ping
 * fails to produce statistics.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: text, count)
 * @return       TR-143 IPPing object
 */
uc_value_t *
uc_ubbf_ping_output_parse(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *data_val = uc_fn_arg(0);
	uc_value_t *count_val = uc_fn_arg(1);
	uc_value_t *out = ucv_object_new(vm);
	int count = (ucv_type(count_val) == UC_INTEGER) ? (int)ucv_int64_get(count_val) : 0;
	const char *data = NULL;
	const char *p, *q;
	int transmitted = 0, received = 0;
	double min_ms = 0, avg_ms = 0, max_ms = 0;
	bool have_rtt = false;
	const char *status = "Error_Other";

	ucv_object_add(out, "Status", ucv_string_new("Error_Other"));
	ucv_object_add(out, "IPAddressUsed", ucv_string_new(""));
	ucv_object_add(out, "SuccessCount", ucv_string_new("0"));
	add_int_str(out, "FailureCount", count);
	ucv_object_add(out, "AverageResponseTime", ucv_string_new("0"));
	ucv_object_add(out, "MinimumResponseTime", ucv_string_new("0"));
	ucv_object_add(out, "MaximumResponseTime", ucv_string_new("0"));
	ucv_object_add(out, "AverageResponseTimeDetailed", ucv_string_new("0"));
	ucv_object_add(out, "MinimumResponseTimeDetailed", ucv_string_new("0"));
	ucv_object_add(out, "MaximumResponseTimeDetailed", ucv_string_new("0"));

	if (ucv_type(data_val) != UC_STRING)
		return out;

	data = ucv_string_get(data_val);

	/* IP address: "(<ip>)" - take the first occurrence */
	p = strchr(data, '(');
	if (p) {
		q = strchr(p + 1, ')');
		if (q && q > p + 1) {
			char ipbuf[64];
			size_t n = q - p - 1;
			if (n < sizeof(ipbuf)) {
				memcpy(ipbuf, p + 1, n);
				ipbuf[n] = '\0';
				ucv_object_add(out, "IPAddressUsed",
					       ucv_string_new(ipbuf));
			}
		}
	}

	/* Statistics line */
	p = strstr(data, " packets transmitted");
	if (p) {
		const char *s = p;
		while (s > data && isdigit((unsigned char)s[-1])) s--;
		transmitted = (int)strtol(s, NULL, 10);
		p = strstr(p, "received");
		if (p) {
			const char *s2 = p;
			while (s2 > data && s2[-1] == ' ') s2--;
			if (s2 - 7 >= data && memcmp(s2 - 7, "packets", 7) == 0) {
				s2 -= 7;
				while (s2 > data && s2[-1] == ' ') s2--;
			}
			while (s2 > data && isdigit((unsigned char)s2[-1])) s2--;
			received = (int)strtol(s2, NULL, 10);
		}
	}

	/* RTT line */
	p = strstr(data, "min/avg/max");
	if (p) {
		p = strchr(p, '=');
		if (p && sscanf(p + 1, " %lf/%lf/%lf", &min_ms, &avg_ms, &max_ms) == 3)
			have_rtt = true;
	}

	if (received > 0)
		status = "Complete";

	/* without a statistics line the FailureCount fallback of `count`
	 * from above must survive */
	if (transmitted > 0) {
		add_int_str(out, "SuccessCount", received);
		add_int_str(out, "FailureCount", transmitted - received);
	}
	if (have_rtt) {
		add_int_str(out, "MinimumResponseTime", (long long)min_ms);
		add_int_str(out, "AverageResponseTime", (long long)avg_ms);
		add_int_str(out, "MaximumResponseTime", (long long)max_ms);
		add_int_str(out, "MinimumResponseTimeDetailed", (long long)(min_ms * 1000));
		add_int_str(out, "AverageResponseTimeDetailed", (long long)(avg_ms * 1000));
		add_int_str(out, "MaximumResponseTimeDetailed", (long long)(max_ms * 1000));
	}
	ucv_object_add(out, "Status", ucv_string_new(status));

	return out;
}

/**
 * Parses traceroute output into a TR-143 TraceRoute flat result object.
 *
 * Returns a single object with the top-level fields (`Status`,
 * `IPAddressUsed`, `ResponseTime`, `RouteHopsNumberOfEntries`) plus
 * per-hop `RouteHops.<N>.Host`, `RouteHops.<N>.HostAddress`,
 * `RouteHops.<N>.ErrorCode`, and `RouteHops.<N>.RTTimes` keys, ready to
 * be merged into the operation result map.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: text)
 * @return       flat object suitable for diag_result_expand
 */
uc_value_t *
uc_ubbf_traceroute_output_parse(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *data_val = uc_fn_arg(0);
	uc_value_t *out = ucv_object_new(vm);
	const char *data;
	const char *line_start, *line_end;
	long long total_time = 0;
	int hop_count = 0;
	char ipbuf[64] = "";
	char key[48], host[80], addr[64];

	ucv_object_add(out, "Status", ucv_string_new("Error_Other"));
	ucv_object_add(out, "IPAddressUsed", ucv_string_new(""));
	ucv_object_add(out, "ResponseTime", ucv_string_new("0"));

	if (ucv_type(data_val) != UC_STRING)
		return out;

	data = ucv_string_get(data_val);

	const char *p = data;
	while (*p) {
		line_start = p;
		while (*p && *p != '\n') p++;
		line_end = p;
		if (*p) p++;

		while (line_start < line_end &&
		       (*line_start == ' ' || *line_start == '\t'))
			line_start++;
		if (line_start == line_end)
			continue;

		size_t llen = line_end - line_start;
		char buf[1024];
		if (llen >= sizeof(buf))
			llen = sizeof(buf) - 1;
		memcpy(buf, line_start, llen);
		buf[llen] = '\0';

		/* Header: "traceroute to <name> (<ip>)..." */
		if (!ipbuf[0] && strncmp(buf, "traceroute to ", 14) == 0) {
			char *open = strchr(buf, '(');
			char *close = open ? strchr(open + 1, ')') : NULL;
			if (open && close && close > open + 1) {
				size_t n = close - open - 1;
				if (n >= sizeof(ipbuf)) n = sizeof(ipbuf) - 1;
				memcpy(ipbuf, open + 1, n);
				ipbuf[n] = '\0';
			}
			continue;
		}

		/* Hop line: "<num>  <host> (<addr>)  <rtt> ms ..." */
		const char *q = buf;
		while (*q == ' ') q++;
		if (!isdigit((unsigned char)*q))
			continue;
		int hop_num = (int)strtol(q, (char **)&q, 10);
		while (*q == ' ' || *q == '\t') q++;

		host[0] = '\0';
		addr[0] = '\0';
		long long rtt = 0;
		int error_code = 0;

		/* lost leading probes print as '*' before the responder;
		 * skip them so partial loss still yields host and rtt */
		while (*q == '*' || *q == ' ' || *q == '\t')
			q++;

		const char *open = strchr(q, '(');
		const char *close = open ? strchr(open + 1, ')') : NULL;
		if (open && close && close > open + 1) {
			size_t hn = open - q;
			while (hn > 0 && (q[hn - 1] == ' ' || q[hn - 1] == '\t'))
				hn--;
			if (hn >= sizeof(host)) hn = sizeof(host) - 1;
			memcpy(host, q, hn);
			host[hn] = '\0';
			size_t an = close - open - 1;
			if (an >= sizeof(addr)) an = sizeof(addr) - 1;
			memcpy(addr, open + 1, an);
			addr[an] = '\0';
		} else if (isdigit((unsigned char)*q)) {
			size_t an = 0;
			while (q[an] && (isdigit((unsigned char)q[an]) || q[an] == '.'))
				an++;
			if (an >= sizeof(addr)) an = sizeof(addr) - 1;
			memcpy(addr, q, an);
			addr[an] = '\0';
			strcpy(host, addr);
		}

		/* Sum the rtt values: split "ms" boundaries, parse trailing number per part. */
		double sum = 0;
		int times = 0;
		const char *part_start = q;
		const char *ms;
		while ((ms = strstr(part_start, "ms")) != NULL) {
			const char *r = ms;
			while (r > part_start && (r[-1] == ' ' || r[-1] == '\t'))
				r--;
			const char *ns = r;
			while (ns > part_start &&
			       (isdigit((unsigned char)ns[-1]) || ns[-1] == '.'))
				ns--;
			if (ns < r) {
				sum += strtod(ns, NULL);
				times++;
			}
			part_start = ms + 2;
		}
		if (times > 0) {
			rtt = (long long)(sum / times);
			total_time += rtt;
		} else {
			/* no probe on this hop answered */
			error_code = 1;
		}

		snprintf(key, sizeof(key), "RouteHops.%d.Host", hop_num);
		ucv_object_add(out, key, ucv_string_new(host));
		snprintf(key, sizeof(key), "RouteHops.%d.HostAddress", hop_num);
		ucv_object_add(out, key, ucv_string_new(addr));
		snprintf(key, sizeof(key), "RouteHops.%d.ErrorCode", hop_num);
		add_int_str(out, key, error_code);
		snprintf(key, sizeof(key), "RouteHops.%d.RTTimes", hop_num);
		add_int_str(out, key, rtt);
		hop_count++;
	}

	if (ipbuf[0])
		ucv_object_add(out, "IPAddressUsed", ucv_string_new(ipbuf));
	if (hop_count > 0)
		ucv_object_add(out, "Status", ucv_string_new("Complete"));
	add_int_str(out, "ResponseTime", total_time);
	add_int_str(out, "RouteHopsNumberOfEntries", hop_count);

	return out;
}
