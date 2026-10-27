'use strict';

// Intervals are in seconds of the week, Monday 00:00 local time being 0, so
// that a window past midnight, InverseMode and several references follow
// one rule. The inline AccessControl.{i}.Schedule rows (until 2.21) have the
// same fields as Device.Schedules.Schedule and use the same code.

import * as ubbf from 'ubbf';

const DAY = 86400;
const WEEK = 7 * DAY;
const DAYS = [ 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday' ];
const TABLE = 'Device.Schedules.Schedule';

/**
 * Converts a StartTime value to seconds after midnight.
 *
 * @param {string} value - StartTime in hh:mm format
 * @returns {number|null} Seconds after midnight, or null when malformed
 */
function start_seconds(value) {
	let m = match(value ?? '', /^([01][0-9]|2[0-3]):([0-5][0-9])$/);
	return m ? +m[1] * 3600 + +m[2] * 60 : null;
}

/**
 * Tells whether a StartTime value is valid: empty or hh:mm.
 *
 * @param {string} value - StartTime value
 * @returns {boolean} True when the value is valid
 */
export function start_time_valid(value) {
	return value == null || value == '' || start_seconds(value) != null;
};

/**
 * Merges intervals that overlap or touch.
 *
 * @param {array} list - Intervals as [ start, end ]
 * @returns {array} Sorted intervals without overlaps
 */
export function intervals_union(list) {
	let out = [];

	for (let iv in sort([ ...list ], (a, b) => a[0] - b[0])) {
		let last = out[-1];
		if (last && iv[0] <= last[1])
			last[1] = max(last[1], iv[1]);
		else
			push(out, [ iv[0], iv[1] ]);
	}

	return out;
};

/**
 * Returns the parts of the week that the intervals do not cover.
 *
 * @param {array} iv - Intervals from intervals_union()
 * @returns {array} The complement in the week
 */
export function intervals_complement(iv) {
	let out = [];
	let pos = 0;

	for (let i in iv) {
		if (i[0] > pos)
			push(out, [ pos, i[0] ]);
		pos = i[1];
	}

	if (pos < WEEK)
		push(out, [ pos, WEEK ]);

	return out;
};

/**
 * Returns the active intervals of a schedule row. Without Day, the window
 * repeats on every day. Without Duration, it lasts until midnight. A window
 * past midnight continues on the next day.
 *
 * @param {object} row - Row with Day, StartTime, Duration, InverseMode
 * @returns {array|null} Intervals, or null when the row cannot be used:
 *     no StartTime (a daily allowance) or a malformed one
 */
export function schedule_intervals(row) {
	let start = start_seconds(row?.StartTime);
	if (start == null)
		return null;

	let duration = ubbf.to_int(row.Duration) ?? 0;
	if (duration <= 0)
		duration = DAY - start;
	duration = min(duration, WEEK);

	let days = filter(map(ubbf.csv_to_list(row.Day, ''), (d) => index(DAYS, d)), (d) => d >= 0);
	if (!length(days))
		days = [ 0, 1, 2, 3, 4, 5, 6 ];

	let list = [];
	for (let d in days) {
		let s = d * DAY + start;
		let e = s + duration;

		push(list, [ s, min(e, WEEK) ]);
		if (e > WEEK)
			push(list, [ 0, e - WEEK ]);
	}

	let iv = intervals_union(list);
	return ubbf.to_bool(row.InverseMode) ? intervals_complement(iv) : iv;
};

/**
 * Formats seconds after midnight as HH:MM:SS.
 *
 * @param {number} secs - Seconds after midnight
 * @returns {string} Time of day
 */
function time_format(secs) {
	return sprintf('%02d:%02d:%02d', secs / 3600, (secs % 3600) / 60, secs % 60);
}

/**
 * Splits intervals at midnight into fw4 time windows. Days with the same
 * times share one window. stop_time is inclusive, as for nft meta hour.
 *
 * @param {array} iv - Intervals from intervals_union()
 * @returns {array} Windows as { start_time, stop_time, weekdays }
 */
export function intervals_to_windows(iv) {
	let by_time = {};
	let order = [];

	for (let i in iv) {
		for (let s = i[0]; s < i[1];) {
			let day = s / DAY;
			let e = min(i[1], (day + 1) * DAY);
			let key = sprintf('%s-%s', time_format(s - day * DAY), time_format(e - day * DAY - 1));

			if (!by_time[key]) {
				by_time[key] = [];
				push(order, key);
			}
			push(by_time[key], DAYS[day]);
			s = e;
		}
	}

	return map(order, (key) => {
		let t = split(key, '-');
		return { start_time: t[0], stop_time: t[1], weekdays: by_time[key] };
	});
};

/**
 * Converts a localtime() result to seconds of the week.
 *
 * @param {object} tm - Result of localtime()
 * @returns {number} Seconds after Monday 00:00
 */
export function week_seconds(tm) {
	return ((tm.wday + 6) % 7) * DAY + tm.hour * 3600 + tm.min * 60 + tm.sec;
};

/**
 * Returns the interval that contains a point in time, also across the end
 * of the week.
 *
 * @param {array} iv - Intervals from intervals_union()
 * @param {number} now - Seconds of the week
 * @returns {array|null} The containing interval, its end extended past WEEK
 *     when the week wraps, or null
 */
function interval_at(iv, now) {
	for (let n = 0; n < length(iv); n++) {
		let i = iv[n];
		if (now < i[0] || now >= i[1])
			continue;
		if (i[1] == WEEK && n > 0 && iv[0][0] == 0)
			return [ i[0], WEEK + iv[0][1] ];
		return i;
	}

	return null;
}

/**
 * Tells whether a point in time is inside the intervals.
 *
 * @param {array} iv - Intervals from intervals_union()
 * @param {number} now - Seconds of the week
 * @returns {boolean} True when active
 */
export function intervals_active(iv, now) {
	return interval_at(iv, now) != null;
};

/**
 * Returns the seconds until the intervals next change between active and
 * inactive.
 *
 * @param {array} iv - Intervals from intervals_union()
 * @param {number} now - Seconds of the week
 * @returns {number} Seconds, 0 when the state never changes
 */
function intervals_time_left(iv, now) {
	if (!length(iv) || (length(iv) == 1 && iv[0][0] == 0 && iv[0][1] == WEEK))
		return 0;

	let cur = interval_at(iv, now);
	if (cur)
		return cur[1] - now;

	for (let i in iv)
		if (i[0] > now)
			return i[0] - now;

	return WEEK - now + iv[0][0];
}

/**
 * Returns Status and TimeLeft of a Device.Schedules.Schedule row.
 *
 * @param {object} row - Schedule row
 * @param {boolean} stack_enabled - Value of Device.Schedules.Enable
 * @param {number} now - Seconds of the week, see week_seconds()
 * @returns {object} { status, time_left }
 */
export function schedule_state(row, stack_enabled, now) {
	if (!ubbf.to_bool(row?.Enable))
		return { status: 'Inactive', time_left: 0 };
	if (!stack_enabled)
		return { status: 'StackDisabled', time_left: 0 };

	let iv = schedule_intervals(row);
	if (iv == null)
		return { status: 'Error', time_left: 0 };

	return {
		status: intervals_active(iv, now) ? 'Active' : 'Inactive',
		time_left: intervals_time_left(iv, now)
	};
};

/**
 * Returns the union of the intervals of the schedules that a ScheduleRef
 * list names. Disabled rows, rows that cannot be used and all rows while
 * Device.Schedules.Enable is false count as not referenced.
 *
 * @param {object} config - Configuration tree
 * @param {string} refs - ScheduleRef value
 * @returns {array|null} Intervals, or null when nothing is scheduled
 */
export function refs_intervals(config, refs) {
	let schedules = config?.Device?.Schedules;
	if (!schedules || !ubbf.to_bool(schedules.Enable ?? 'true'))
		return null;

	let list = [];
	let used = 0;

	for (let ref in ubbf.csv_to_list(refs, '')) {
		let row = schedules.Schedule?.[sprintf('%d', ubbf.tr181_ref_parse(ref, TABLE) ?? 0)];
		if (!row || !ubbf.to_bool(row.Enable))
			continue;

		let iv = schedule_intervals(row);
		if (iv == null)
			continue;

		used++;
		push(list, ...iv);
	}

	return used ? intervals_union(list) : null;
};

/**
 * Returns the fw4 time windows of an object from its ScheduleRef and from
 * inline schedule rows. A ScheduleRef counts only when the schedules module
 * is installed.
 *
 * @param {object} config - Configuration tree
 * @param {string} refs - ScheduleRef value
 * @param {array} inline_rows - Inline schedule rows, or null
 * @param {boolean} installed - True when the schedules module is installed
 * @returns {array|null} Windows from intervals_to_windows(), or null when
 *     the object is not scheduled
 */
export function schedule_windows(config, refs, inline_rows, installed) {
	let list = [];
	let used = false;

	let iv = installed ? refs_intervals(config, refs) : null;
	if (iv != null) {
		used = true;
		push(list, ...iv);
	}

	for (let row in inline_rows ?? []) {
		iv = ubbf.to_bool(row.Enable) ? schedule_intervals(row) : null;
		if (iv == null)
			continue;
		used = true;
		push(list, ...iv);
	}

	return used ? intervals_to_windows(intervals_union(list)) : null;
};

/**
 * Checks a ScheduleRef value: each item must name an existing
 * Device.Schedules.Schedule row, which needs the schedules module.
 *
 * @param {string} value - ScheduleRef value
 * @param {object} root - Configuration tree of the write
 * @param {boolean} installed - True when the schedules module is registered
 * @returns {number} 0, or -USP_ERR_INVALID_VALUE to refuse
 */
export function schedule_refs_check(value, root, installed) {
	let refs = ubbf.csv_to_list(value, '');
	if (!length(refs))
		return 0;
	if (!installed)
		return -USP_ERR_INVALID_VALUE;

	let rows = root?.Device?.Schedules?.Schedule ?? {};
	for (let ref in refs) {
		let n = ubbf.tr181_ref_parse(ref, TABLE);
		if (n == null || !rows[sprintf('%d', n)])
			return -USP_ERR_INVALID_VALUE;
	}

	return 0;
};

/**
 * Returns a set handler that checks ScheduleRef and passes every other
 * parameter to the set handler of the model entry.
 *
 * @param {function|null} set - Set handler of the entry
 * @param {function} installed - Returns true when the schedules module is
 *     registered; asked at write time
 * @returns {function} Set handler
 */
export function schedule_ref_set(set, installed) {
	return (ctx) => (ctx.param == 'ScheduleRef')
		? schedule_refs_check(ctx.value, ctx.root, installed())
		: (set ? set(ctx) : 0);
};

/**
 * Removes the items of ScheduleRef values that name a schedule row that
 * does not exist: TR-181 makes ScheduleRef a strong reference, so a deleted
 * row leaves every list that named it.
 *
 * @param {object} node - Configuration subtree, changed in place
 * @param {object} rows - Device.Schedules.Schedule rows of the tree
 * @returns {boolean} True when a value changed
 */
function refs_prune_node(node, rows) {
	let changed = false;

	for (let key, value in node) {
		if (type(value) == 'object') {
			changed = refs_prune_node(value, rows) || changed;
			continue;
		}
		if (key != 'ScheduleRef' || type(value) != 'string' || value == '')
			continue;

		let refs = ubbf.csv_to_list(value, '');
		let kept = filter(refs,
			(ref) => rows[sprintf('%d', ubbf.tr181_ref_parse(ref, TABLE) ?? 0)] != null);
		if (length(kept) == length(refs))
			continue;

		node[key] = join(',', kept);
		changed = true;
	}

	return changed;
}

/**
 * Removes the references to deleted schedule rows from the whole
 * configuration.
 *
 * @param {object} config - Configuration tree, changed in place
 * @returns {boolean} True when a value changed
 */
export function schedule_refs_prune(config) {
	return refs_prune_node(config, config?.Device?.Schedules?.Schedule ?? {});
};
