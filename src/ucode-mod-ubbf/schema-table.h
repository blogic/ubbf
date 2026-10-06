/* SPDX-License-Identifier: GPL-2.0-only */
/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef UBBF_SCHEMA_TABLE_H
#define UBBF_SCHEMA_TABLE_H

#include <stdint.h>

/* Raise on any change to the records or the symbols below: schema.c skips a
 * schema-*.so built against another layout instead of misreading it. */
#define SCHEMA_TABLE_ABI	3

#define SCHEMA_NONE	0xffffffffu

/* All strings are offsets into ubbf_schema_pool, so a table carries no
 * pointers and needs no relocation: it stays in the read-only, file-backed
 * pages of its schema-*.so instead of becoming private memory of every
 * process. Both lookup records start with the pool offset of their key,
 * which table_record_find() in schema.c relies on. */

/* `max_instances` is SCHEMA_NONE when the table has no limit; `addable` is
 * 0 for a table the CPE maintains itself, which a controller may not add
 * rows to. */
struct schema_object {
	uint32_t id;
	uint32_t path;
	uint32_t member_first;
	uint32_t member_count;
	uint32_t default_first;
	uint32_t default_count;
	uint32_t max_instances;
	uint8_t addable;
};

/* `since` and `until` are TR-181 minor numbers (20 for 2.20), 0 for none:
 * the member exists from `since` on and is gone from `until` on. `info` is
 * the index of the member's rule in ubbf_schema_rules (SCHEMA_NONE for none)
 * for a parameter, and the pool offset of its JSON definition for a command
 * or an event. */
struct schema_member {
	uint32_t name;
	uint32_t type;
	uint32_t info;
	uint8_t kind;
	uint8_t proto;
	uint8_t since;
	uint8_t until;
};

struct schema_default {
	uint32_t name;
	uint32_t value;
};

/* A closed range; INT64_MIN or INT64_MAX stand for an open end. */
struct schema_range {
	int64_t lo;
	int64_t hi;
};

#define SCHEMA_RULE_MIN			0x0001
#define SCHEMA_RULE_MAX			0x0002
#define SCHEMA_RULE_MIN_LENGTH		0x0004
#define SCHEMA_RULE_MAX_LENGTH		0x0008
#define SCHEMA_RULE_LIST		0x0010
#define SCHEMA_RULE_LIST_MIN_LENGTH	0x0020
#define SCHEMA_RULE_LIST_MAX_LENGTH	0x0040
#define SCHEMA_RULE_SECURED		0x0080

/* What TR-181 allows for a parameter's value. In a list, the enum, the
 * number limits and the lengths apply to each item and the list lengths to
 * the whole value. `enum_first` indexes ubbf_schema_enums (pool offsets),
 * `range_first` and `length_first` index ubbf_schema_ranges. */
struct schema_rule {
	int64_t min;
	int64_t max;
	uint32_t min_length;
	uint32_t max_length;
	uint32_t list_min_length;
	uint32_t list_max_length;
	uint32_t enum_first;
	uint32_t range_first;
	uint32_t length_first;
	uint16_t enum_count;
	uint16_t range_count;
	uint16_t length_count;
	uint16_t flags;
};

/* The symbols every schema-*.so exports. */
extern const uint32_t ubbf_schema_abi;
extern const char ubbf_schema_pool[];
extern const struct schema_object ubbf_schema_objects[];
extern const uint32_t ubbf_schema_object_count;
extern const struct schema_member ubbf_schema_members[];
extern const struct schema_default ubbf_schema_defaults[];
extern const struct schema_rule ubbf_schema_rules[];
extern const struct schema_range ubbf_schema_ranges[];
extern const uint32_t ubbf_schema_enums[];

#endif
