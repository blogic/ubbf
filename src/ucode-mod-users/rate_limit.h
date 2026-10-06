/* SPDX-License-Identifier: GPL-2.0-only */

/* Copyright (C) 2026 John Crispin <john@phrozen.org> */

#ifndef USERS_RATE_LIMIT_H
#define USERS_RATE_LIMIT_H

#include <ucode/lib.h>
#include <ucode/vm.h>

uc_value_t *uc_ubbf_rate_limit_check(uc_vm_t *vm, size_t nargs);

#endif
