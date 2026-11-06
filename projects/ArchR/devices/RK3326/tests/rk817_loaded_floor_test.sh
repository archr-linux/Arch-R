#!/bin/bash
# SPDX-License-Identifier: GPL-2.0
# Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
#
# Host test for patch 045 (a columb counter found under its loaded voltage):
# builds the plain-C decision block out of the patch, with the ocv lookup
# the kernel does, over the R36S battery table in the device tree.
#   bash projects/ArchR/devices/RK3326/tests/rk817_loaded_floor_test.sh
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PATCH=$(ls "${HERE}"/../patches/linux/045-*.patch)
DTSI="${HERE}/../linux/dts/rockchip/rk3326-gameconsole-r3xs.dtsi"
TMP=$(mktemp -d)
trap 'rm -rf "${TMP}"' EXIT

# The patch's block between its markers, '+' column dropped.
sed -n '/^+\/\* rk817-loaded-begin/,/^+\/\* rk817-loaded-end/p' "${PATCH}" | sed 's/^+//' >"${TMP}/block.h"
[ -s "${TMP}/block.h" ] || { echo "FAIL no decision block in ${PATCH}"; exit 1; }

# The table, "<ocv capacity>" pairs, as the device tree states it.
sed -n '/ocv-capacity-table-0/,/>;/p' "${DTSI}" | grep -o '<[0-9]* [0-9]*>' | tr -d '<>' |
  awk '{printf "{%s, %s},\n", $1, $2}' >"${TMP}/table.h"

cat >"${TMP}/test.c" <<'C'
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include "block.h"

struct ocv { int ocv, cap; };
static const struct ocv table[] = {
#include "table.h"
};
#define LEN ((int)(sizeof(table) / sizeof(table[0])))

/* power_supply_ocv2cap_simple of the kernel, percent in, percent out. */
static int ocv2cap(int ocv)
{
	int i, hi, lo;

	for (i = 0; i < LEN; i++)
		if (ocv > table[i].ocv)
			break;
	if (i == 0)
		return table[0].cap;
	if (i == LEN)
		return table[LEN - 1].cap;
	hi = i - 1;
	lo = i;
	return table[lo].cap + (long long)(ocv - table[lo].ocv) *
	       (table[hi].cap - table[lo].cap) / (table[hi].ocv - table[lo].ocv);
}

static int failed;
static void check(const char *what, long got, long want)
{
	if (got == want) {
		printf("ok   %s\n", what);
	} else {
		printf("FAIL %s: got %ld, want %ld\n", what, got, want);
		failed = 1;
	}
}

/* Polls until the block says raise, at most n; 0 when it never does. */
static int polls_to_raise(int soc, int volt_uv, int n)
{
	int polls = 0, i, floor = ocv2cap(volt_uv) * 1000;

	for (i = 1; i <= n; i++)
		if (rk817_soc_under_floor(soc, floor, &polls))
			return i;
	return 0;
}

int main(void)
{
	int polls = 0;

	/* The issue: 3.85 V in the pack, 0% on the screen. */
	check("3.85 V maps to over 60%", ocv2cap(3850000) > 60, 1);
	check("0% at 3.85 V is raised after the polls required", polls_to_raise(0, 3850000, 100), RK817_LOADED_POLLS);
	check("0% at 3.90 V is raised", polls_to_raise(0, 3900000, 100) > 0, 1);

	/* Not a flat battery: 3.58 V is the table's 5%. */
	check("0% at 3.58 V is left (the pack is empty)", polls_to_raise(0, 3580000, 100), 0);
	check("3% at 3.58 V is left", polls_to_raise(3000, 3580000, 100), 0);

	/* A counter near the voltage is left, either side of it. */
	check("70% at 3.85 V is left", polls_to_raise(70000, 3850000, 100), 0);
	check("100% at 3.85 V is left (the loaded floor says nothing against it)", polls_to_raise(100000, 3850000, 100), 0);
	check("65% at 3.85 V (gap under 10%) is left", polls_to_raise(65000, 3850000, 100), 0);

	/* One good poll in the middle starts the count over. */
	polls = 0;
	for (int i = 0; i < RK817_LOADED_POLLS - 1; i++)
		rk817_soc_under_floor(0, 70000, &polls);
	check("a poll back in line", rk817_soc_under_floor(70000, 70000, &polls), 0);
	check("... clears the count", polls, 0);
	check("... so the next low poll is the first again", rk817_soc_under_floor(0, 70000, &polls), 0);

	/* The kernel lookup clamps at both ends of the table. */
	check("above the table: 100%", ocv2cap(4300000), 100);
	check("below the table: 0%", ocv2cap(3000000), 0);

	return failed;
}
C
gcc -Wall -Werror -I"${TMP}" -o "${TMP}/test" "${TMP}/test.c" || exit 1
"${TMP}/test"
