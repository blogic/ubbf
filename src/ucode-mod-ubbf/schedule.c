/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

/*
 * Week schedules: Device.Schedules.Schedule rows, the inline
 * AccessControl.{i}.Schedule rows (until 2.21, same fields) and the
 * ScheduleRef references to them. Intervals are in seconds of the week,
 * Monday 00:00 local time being 0, so that a window past midnight,
 * InverseMode and several references follow one rule. ucode sees an
 * interval as `[ start, end ]`.
 */

#include "ubbf.h"
#include "bindings.h"

#include <ctype.h>
#include <inttypes.h>

#define DAY	86400
#define WEEK	(7 * DAY)

#define USP_ERR_INVALID_VALUE	7012

#define SCHEDULE_TABLE	"Device.Schedules.Schedule"

static const char *const days[] = {
	"Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"
};

struct ivs {
	size_t count;
	struct iv { int64_t s, e; } *list;
};

static void
ivs_push(struct ivs *v, int64_t s, int64_t e)
{
	v->list = xrealloc(v->list, (v->count + 1) * sizeof(*v->list));
	v->list[v->count].s = s;
	v->list[v->count++].e = e;
}

static int
iv_cmp(const void *a, const void *b)
{
	const struct iv *ia = a, *ib = b;

	return (ia->s > ib->s) - (ia->s < ib->s);
}

/* Merges the intervals that overlap or touch, sorted by start. */
static void
ivs_union(struct ivs *v)
{
	size_t n = 0;

	qsort(v->list, v->count, sizeof(*v->list), iv_cmp);

	for (size_t i = 0; i < v->count; i++) {
		if (n && v->list[i].s <= v->list[n - 1].e) {
			if (v->list[i].e > v->list[n - 1].e)
				v->list[n - 1].e = v->list[i].e;
			continue;
		}

		v->list[n++] = v->list[i];
	}

	v->count = n;
}

/* Replaces sorted intervals with the parts of the week they leave out. */
static void
ivs_complement(struct ivs *v)
{
	struct ivs out = { 0 };
	int64_t pos = 0;

	for (size_t i = 0; i < v->count; i++) {
		if (v->list[i].s > pos)
			ivs_push(&out, pos, v->list[i].s);
		pos = v->list[i].e;
	}

	if (pos < WEEK)
		ivs_push(&out, pos, WEEK);

	free(v->list);
	*v = out;
}

static void
ivs_from_value(struct ivs *v, uc_value_t *arr)
{
	for (size_t i = 0; i < ucv_array_length(arr); i++) {
		uc_value_t *iv = ucv_array_get(arr, i);

		if (ucv_type(iv) == UC_ARRAY)
			ivs_push(v, ucv_to_integer(ucv_array_get(iv, 0)),
				 ucv_to_integer(ucv_array_get(iv, 1)));
	}
}

static uc_value_t *
ivs_to_value(uc_vm_t *vm, const struct ivs *v)
{
	uc_value_t *arr = ucv_array_new(vm), *iv;

	for (size_t i = 0; i < v->count; i++) {
		iv = ucv_array_new(vm);
		ucv_array_push(iv, ucv_int64_new(v->list[i].s));
		ucv_array_push(iv, ucv_int64_new(v->list[i].e));
		ucv_array_push(arr, iv);
	}

	return arr;
}

/* StartTime `hh:mm` in seconds after midnight, or -1 when malformed. */
static int64_t
start_seconds(uc_value_t *val)
{
	const char *s;
	int h, m;

	if (ucv_type(val) != UC_STRING)
		return -1;

	s = ucv_string_get(val);
	if (strlen(s) != 5 || !isdigit((unsigned char)s[0]) || !isdigit((unsigned char)s[1]) ||
	    s[2] != ':' || !isdigit((unsigned char)s[3]) || !isdigit((unsigned char)s[4]))
		return -1;

	h = (s[0] - '0') * 10 + (s[1] - '0');
	m = (s[3] - '0') * 10 + (s[4] - '0');

	return (h > 23 || m > 59) ? -1 : h * 3600 + m * 60;
}

static int
day_index(const char *name)
{
	for (size_t i = 0; i < ARRAY_SIZE(days); i++)
		if (!strcmp(name, days[i]))
			return i;

	return -1;
}

/**
 * Adds the active intervals of a schedule row. Without Day the window
 * repeats on every day, without Duration it lasts until midnight, and a
 * window past midnight continues on the next day.
 *
 * @return  false when the row cannot be used: no StartTime (a daily
 *          allowance) or a malformed one
 */
static bool
row_intervals(uc_vm_t *vm, uc_value_t *row, struct ivs *out)
{
	int64_t start = start_seconds(ucv_object_get(row, "StartTime", NULL));
	uc_value_t *day = ucv_object_get(row, "Day", NULL), *names, *name;
	struct ivs v = { 0 };
	int64_t duration, s, e;
	bool on[7] = { false };
	bool any = false;
	int d;

	if (start < 0)
		return false;

	if (!value_to_int(ucv_object_get(row, "Duration", NULL), &duration) || duration <= 0)
		duration = DAY - start;
	if (duration > WEEK)
		duration = WEEK;

	names = csv_list_new(vm, ucv_type(day) == UC_STRING ? ucv_string_get(day) : NULL, "");
	for (size_t i = 0; i < ucv_array_length(names); i++) {
		name = ucv_array_get(names, i);
		d = day_index(ucv_string_get(name));
		if (d >= 0)
			on[d] = any = true;
	}
	ucv_put(names);

	for (d = 0; d < 7; d++) {
		if (any && !on[d])
			continue;

		s = (int64_t)d * DAY + start;
		e = s + duration;

		ivs_push(&v, s, e < WEEK ? e : WEEK);
		if (e > WEEK)
			ivs_push(&v, 0, e - WEEK);
	}

	ivs_union(&v);
	if (value_to_bool(ucv_object_get(row, "InverseMode", NULL)))
		ivs_complement(&v);

	for (size_t i = 0; i < v.count; i++)
		ivs_push(out, v.list[i].s, v.list[i].e);
	free(v.list);

	return true;
}

/**
 * Splits intervals at midnight into fw4 time windows. Days with the same
 * times share one window. stop_time is inclusive, as for nft meta hour.
 */
static uc_value_t *
windows_new(uc_vm_t *vm, const struct ivs *v)
{
	uc_value_t *out = ucv_array_new(vm), *by_time = ucv_object_new(vm), *win, *weekdays;
	char start[64], stop[64], key[132];
	int64_t s, e, day, a, b;

	for (size_t i = 0; i < v->count; i++) {
		for (s = v->list[i].s; s < v->list[i].e; s = e) {
			day = s / DAY;
			e = (v->list[i].e < (day + 1) * DAY) ? v->list[i].e : (day + 1) * DAY;
			a = s - day * DAY;
			b = e - day * DAY - 1;

			snprintf(start, sizeof(start), "%02" PRId64 ":%02" PRId64 ":%02" PRId64,
				 a / 3600, (a % 3600) / 60, a % 60);
			snprintf(stop, sizeof(stop), "%02" PRId64 ":%02" PRId64 ":%02" PRId64,
				 b / 3600, (b % 3600) / 60, b % 60);
			snprintf(key, sizeof(key), "%s-%s", start, stop);

			win = ucv_object_get(by_time, key, NULL);
			if (!win) {
				win = ucv_object_new(vm);
				ucv_object_add(win, "start_time", ucv_string_new(start));
				ucv_object_add(win, "stop_time", ucv_string_new(stop));
				ucv_object_add(win, "weekdays", ucv_array_new(vm));
				ucv_object_add(by_time, key, ucv_get(win));
				ucv_array_push(out, win);
			}

			weekdays = ucv_object_get(win, "weekdays", NULL);
			ucv_array_push(weekdays, (day >= 0 && day < 7) ? ucv_string_new(days[day]) : NULL);
		}
	}

	ucv_put(by_time);

	return out;
}

/**
 * Returns the interval that contains a point in time, also across the end
 * of the week: an interval that ends with the week continues into one that
 * starts the week.
 */
static bool
ivs_at(const struct ivs *v, int64_t now, struct iv *out)
{
	for (size_t n = 0; n < v->count; n++) {
		if (now < v->list[n].s || now >= v->list[n].e)
			continue;

		*out = v->list[n];
		if (v->list[n].e == WEEK && n > 0 && v->list[0].s == 0)
			out->e = WEEK + v->list[0].e;

		return true;
	}

	return false;
}

/* Seconds until the intervals next change between active and inactive,
 * 0 when the state never changes. */
static int64_t
ivs_time_left(const struct ivs *v, int64_t now)
{
	struct iv cur;

	if (!v->count || (v->count == 1 && v->list[0].s == 0 && v->list[0].e == WEEK))
		return 0;

	if (ivs_at(v, now, &cur))
		return cur.e - now;

	for (size_t i = 0; i < v->count; i++)
		if (v->list[i].s > now)
			return v->list[i].s - now;

	return WEEK - now + v->list[0].s;
}

static uc_value_t *
schedule_row(uc_value_t *rows, uc_value_t *ref)
{
	int64_t n = (ucv_type(ref) == UC_STRING)
		? tr181_ref_instance(ucv_string_get(ref), SCHEDULE_TABLE) : -1;
	char key[24];

	snprintf(key, sizeof(key), "%" PRId64, n > 0 ? n : 0);

	return ucv_object_get(rows, key, NULL);
}

/**
 * Adds the intervals of the schedules that a ScheduleRef list names.
 * Disabled rows, rows that cannot be used and all rows while
 * Device.Schedules.Enable is false count as not referenced.
 *
 * @return  false when nothing is scheduled
 */
static bool
refs_intervals_add(uc_vm_t *vm, uc_value_t *config, uc_value_t *refs, struct ivs *out)
{
	uc_value_t *schedules = navigate_by_path(vm, config, "Device.Schedules");
	uc_value_t *enable = ucv_object_get(schedules, "Enable", NULL), *list, *ref, *row;
	bool used = false;

	if (!ucv_is_truish(schedules) || (enable && !value_to_bool(enable)))
		return false;

	list = csv_list_new(vm, ucv_type(refs) == UC_STRING ? ucv_string_get(refs) : NULL, "");

	for (size_t i = 0; i < ucv_array_length(list); i++) {
		ref = ucv_array_get(list, i);
		row = schedule_row(ucv_object_get(schedules, "Schedule", NULL), ref);

		if (ucv_is_truish(row) && value_to_bool(ucv_object_get(row, "Enable", NULL)) &&
		    row_intervals(vm, row, out))
			used = true;
	}

	ucv_put(list);

	return used;
}

/**
 * ucode: `start_time_valid(value)`, whether a StartTime value is empty or
 * `hh:mm`.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: StartTime value)
 * @return       boolean
 */
uc_value_t *
uc_ubbf_start_time_valid(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *val = uc_fn_arg(0), *empty = ucv_string_new("");
	bool valid = !val || loose_equal(val, empty) || start_seconds(val) >= 0;

	ucv_put(empty);

	return ucv_boolean_new(valid);
}

/**
 * ucode: `intervals_union(list)`, the intervals merged where they overlap
 * or touch, sorted.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: intervals)
 * @return       intervals
 */
uc_value_t *
uc_ubbf_intervals_union(uc_vm_t *vm, size_t nargs)
{
	struct ivs v = { 0 };
	uc_value_t *out;

	ivs_from_value(&v, uc_fn_arg(0));
	ivs_union(&v);
	out = ivs_to_value(vm, &v);
	free(v.list);

	return out;
}

/**
 * ucode: `intervals_complement(iv)`, the parts of the week that sorted
 * intervals leave out.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: intervals from
 *               intervals_union())
 * @return       intervals
 */
uc_value_t *
uc_ubbf_intervals_complement(uc_vm_t *vm, size_t nargs)
{
	struct ivs v = { 0 };
	uc_value_t *out;

	ivs_from_value(&v, uc_fn_arg(0));
	ivs_complement(&v);
	out = ivs_to_value(vm, &v);
	free(v.list);

	return out;
}

/**
 * ucode: `schedule_intervals(row)`, the active intervals of a schedule
 * row, see row_intervals().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: row with Day, StartTime,
 *               Duration, InverseMode)
 * @return       intervals, or null when the row cannot be used
 */
uc_value_t *
uc_ubbf_schedule_intervals(uc_vm_t *vm, size_t nargs)
{
	struct ivs v = { 0 };
	uc_value_t *out = NULL;

	if (row_intervals(vm, uc_fn_arg(0), &v))
		out = ivs_to_value(vm, &v);
	free(v.list);

	return out;
}

/**
 * ucode: `intervals_to_windows(iv)`, the fw4 time windows of intervals,
 * see windows_new().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: intervals from
 *               intervals_union())
 * @return       windows `{ start_time, stop_time, weekdays }`
 */
uc_value_t *
uc_ubbf_intervals_to_windows(uc_vm_t *vm, size_t nargs)
{
	struct ivs v = { 0 };
	uc_value_t *out;

	ivs_from_value(&v, uc_fn_arg(0));
	out = windows_new(vm, &v);
	free(v.list);

	return out;
}

/**
 * ucode: `week_seconds(tm)`, a localtime() result in seconds after Monday
 * 00:00.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: localtime() result)
 * @return       seconds of the week
 */
uc_value_t *
uc_ubbf_week_seconds(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *tm = uc_fn_arg(0);
	int64_t wday = ucv_to_integer(ucv_object_get(tm, "wday", NULL));

	return ucv_int64_new(((wday + 6) % 7) * DAY +
			     ucv_to_integer(ucv_object_get(tm, "hour", NULL)) * 3600 +
			     ucv_to_integer(ucv_object_get(tm, "min", NULL)) * 60 +
			     ucv_to_integer(ucv_object_get(tm, "sec", NULL)));
}

/**
 * ucode: `intervals_active(iv, now)`, whether a point in time is inside
 * the intervals.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: intervals, seconds of the
 *               week)
 * @return       boolean
 */
uc_value_t *
uc_ubbf_intervals_active(uc_vm_t *vm, size_t nargs)
{
	struct ivs v = { 0 };
	struct iv cur;
	bool active;

	ivs_from_value(&v, uc_fn_arg(0));
	active = ivs_at(&v, ucv_to_integer(uc_fn_arg(1)), &cur);
	free(v.list);

	return ucv_boolean_new(active);
}

static uc_value_t *
state_new(uc_vm_t *vm, const char *status, int64_t time_left)
{
	uc_value_t *state = ucv_object_new(vm);

	ucv_object_add(state, "status", ucv_string_new(status));
	ucv_object_add(state, "time_left", ucv_int64_new(time_left));

	return state;
}

/**
 * ucode: `schedule_state(row, stack_enabled, now)`, Status and TimeLeft of
 * a Device.Schedules.Schedule row.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: row, value of
 *               Device.Schedules.Enable, seconds of the week)
 * @return       `{ status, time_left }`
 */
uc_value_t *
uc_ubbf_schedule_state(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *row = uc_fn_arg(0), *state;
	int64_t now = ucv_to_integer(uc_fn_arg(2));
	struct ivs v = { 0 };
	struct iv cur;

	if (!value_to_bool(ucv_object_get(row, "Enable", NULL)))
		return state_new(vm, "Inactive", 0);
	if (!ucv_is_truish(uc_fn_arg(1)))
		return state_new(vm, "StackDisabled", 0);
	if (!row_intervals(vm, row, &v))
		return state_new(vm, "Error", 0);

	state = state_new(vm, ivs_at(&v, now, &cur) ? "Active" : "Inactive",
			  ivs_time_left(&v, now));
	free(v.list);

	return state;
}

/**
 * ucode: `refs_intervals(config, refs)`, the union of the intervals of the
 * schedules that a ScheduleRef list names, see refs_intervals_add().
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (2 expected: config tree, ScheduleRef
 *               value)
 * @return       intervals, or null when nothing is scheduled
 */
uc_value_t *
uc_ubbf_refs_intervals(uc_vm_t *vm, size_t nargs)
{
	struct ivs v = { 0 };
	uc_value_t *out = NULL;

	if (refs_intervals_add(vm, uc_fn_arg(0), uc_fn_arg(1), &v)) {
		ivs_union(&v);
		out = ivs_to_value(vm, &v);
	}
	free(v.list);

	return out;
}

/**
 * ucode: `schedule_windows(config, refs, inline_rows, installed)`, the fw4
 * time windows of an object from its ScheduleRef and its inline schedule
 * rows. A ScheduleRef counts only when the schedules module is installed.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (4 expected: config tree, ScheduleRef
 *               value, array of inline rows or null, whether the schedules
 *               module is installed)
 * @return       windows, or null when the object is not scheduled
 */
uc_value_t *
uc_ubbf_schedule_windows(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *rows = uc_fn_arg(2), *row, *out = NULL;
	struct ivs v = { 0 };
	bool used = false;

	if (ucv_is_truish(uc_fn_arg(3)))
		used = refs_intervals_add(vm, uc_fn_arg(0), uc_fn_arg(1), &v);

	for (size_t i = 0; i < ucv_array_length(rows); i++) {
		row = ucv_array_get(rows, i);
		if (value_to_bool(ucv_object_get(row, "Enable", NULL)) && row_intervals(vm, row, &v))
			used = true;
	}

	if (used) {
		ivs_union(&v);
		out = windows_new(vm, &v);
	}
	free(v.list);

	return out;
}

/**
 * ucode: `schedule_refs_check(value, root, installed)`, the check of a
 * ScheduleRef value: each item must name an existing
 * Device.Schedules.Schedule row, which needs the schedules module.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (3 expected: ScheduleRef value, config
 *               tree of the write, whether the schedules module is
 *               registered)
 * @return       0, or -USP_ERR_INVALID_VALUE to refuse
 */
uc_value_t *
uc_ubbf_schedule_refs_check(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *value = uc_fn_arg(0), *refs, *rows, *ref;
	int64_t rc = 0;

	refs = csv_list_new(vm, ucv_type(value) == UC_STRING ? ucv_string_get(value) : NULL, "");
	if (ucv_array_length(refs) && !ucv_is_truish(uc_fn_arg(2)))
		rc = -USP_ERR_INVALID_VALUE;

	rows = navigate_by_path(vm, uc_fn_arg(1), SCHEDULE_TABLE);
	for (size_t i = 0; !rc && i < ucv_array_length(refs); i++) {
		ref = ucv_array_get(refs, i);
		if (tr181_ref_instance(ucv_string_get(ref), SCHEDULE_TABLE) <= 0 ||
		    !ucv_is_truish(schedule_row(rows, ref)))
			rc = -USP_ERR_INVALID_VALUE;
	}

	ucv_put(refs);

	return ucv_int64_new(rc);
}

/**
 * Removes the items of the ScheduleRef values below a node that name a
 * schedule row that does not exist.
 *
 * @return  true when a value changed
 */
static bool
refs_prune_node(uc_vm_t *vm, uc_value_t *node, uc_value_t *rows)
{
	uc_value_t *refs, *ref;
	uc_stringbuf_t *kept;
	bool changed = false;
	size_t n;

	ucv_object_foreach(node, key, value) {
		if (ucv_type(value) == UC_OBJECT) {
			changed = refs_prune_node(vm, value, rows) || changed;
			continue;
		}

		if (strcmp(key, "ScheduleRef") || ucv_type(value) != UC_STRING ||
		    !ucv_string_length(value))
			continue;

		refs = csv_list_new(vm, ucv_string_get(value), "");
		kept = ucv_stringbuf_new();
		n = 0;

		for (size_t i = 0; i < ucv_array_length(refs); i++) {
			ref = ucv_array_get(refs, i);
			if (!schedule_row(rows, ref))
				continue;

			if (n++)
				ucv_stringbuf_addstr(kept, ",", 1);
			ucv_stringbuf_addstr(kept, ucv_string_get(ref), ucv_string_length(ref));
		}

		if (n == ucv_array_length(refs)) {
			ucv_put(ucv_stringbuf_finish(kept));
		} else {
			ucv_object_add(node, key, ucv_stringbuf_finish(kept));
			changed = true;
		}

		ucv_put(refs);
	}

	return changed;
}

/**
 * ucode: `schedule_refs_prune(config)`, the removal of the references to
 * deleted schedule rows from the whole configuration: TR-181 makes
 * ScheduleRef a strong reference, so a deleted row leaves every list that
 * named it.
 *
 * @param vm     ucode VM context
 * @param nargs  number of arguments (1 expected: config tree, changed in
 *               place)
 * @return       true when a value changed
 */
uc_value_t *
uc_ubbf_schedule_refs_prune(uc_vm_t *vm, size_t nargs)
{
	uc_value_t *config = uc_fn_arg(0);

	return ucv_boolean_new(refs_prune_node(vm, config,
					       navigate_by_path(vm, config, SCHEDULE_TABLE)));
}
