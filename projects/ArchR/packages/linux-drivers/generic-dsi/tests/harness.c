// SPDX-License-Identifier: GPL-2.0
/*
 * Userspace tests for panel-generic-dsi.c. The driver source is compiled
 * as is (DRIVER_SRC) against tests/kstub, whose DSI calls are recorded
 * here so the tests can check what reaches the panel and in what order.
 *
 *   harness                 run the built-in tests
 *   harness lines FILE      probe with FILE as panel_description (one
 *                           string per line); exit 0 if it loads
 */
#include "kstub.h"
#include DRIVER_SRC

/* ---- recording ------------------------------------------------------ */
#define MAX_EVENTS 512
static char events[MAX_EVENTS][96];
static int nevents;
static char logbuf[16384];
static size_t loglen;
static int writes;
static int fail_write_at;	/* 1-based write that returns -EIO, 0 = never */
static struct drm_display_mode modes[32];
static int nmodes;

void rec(const char *fmt, ...)
{
	va_list ap;

	if (nevents >= MAX_EVENTS)
		return;
	va_start(ap, fmt);
	vsnprintf(events[nevents++], sizeof(events[0]), fmt, ap);
	va_end(ap);
}

void klog(const char *level, const char *fmt, ...)
{
	va_list ap;

	loglen += snprintf(logbuf + loglen, sizeof(logbuf) - loglen, "%s: ", level);
	va_start(ap, fmt);
	loglen += vsnprintf(logbuf + loglen, sizeof(logbuf) - loglen, fmt, ap);
	va_end(ap);
	if (loglen >= sizeof(logbuf))
		loglen = sizeof(logbuf) - 1;
}

int rec_write(const u8 *data, size_t len)
{
	char hex[80] = "";
	size_t i;

	for (i = 0; i < len && i < 32; i++)
		sprintf(hex + 2 * i, "%02x", data[i]);
	writes++;
	if (writes == fail_write_at) {
		rec("W %s FAIL", hex);
		return -EIO;
	}
	rec("W %s", hex);
	return (int)len;
}

void rec_mode(const struct drm_display_mode *mode)
{
	if (nmodes < 32)
		modes[nmodes++] = *mode;
}

static void reset_state(void)
{
	nevents = 0;
	loglen = 0;
	logbuf[0] = 0;
	writes = 0;
	fail_write_at = 0;
	nmodes = 0;
	stub_vdd.count = 0;
	stub_iovcc.count = 0;
	stub_reset_gpio.value = -1;
	stub_enable_gpio.value = -1;
}

/* ---- helpers -------------------------------------------------------- */
static int failures;
#define CHECK(cond, ...) do { \
	if (!(cond)) { \
		failures++; \
		printf("  FAIL %s:%d: ", __func__, __LINE__); \
		printf(__VA_ARGS__); \
		printf("\n"); \
	} \
} while (0)

static struct mipi_dsi_device *new_dsi(const char **lines, int n)
{
	struct mipi_dsi_device *dsi = calloc(1, sizeof(*dsi));
	struct device_node *np = calloc(1, sizeof(*np));

	np->lines = lines;
	np->nlines = n;
	dsi->dev.of_node = np;
	return dsi;
}

static int probe(const char **lines, int n, struct generic_panel **out)
{
	struct mipi_dsi_device *dsi = new_dsi(lines, n);
	int ret;

	reset_state();
	ret = generic_panel_probe(dsi);
	*out = ret == 0 ? mipi_dsi_get_drvdata(dsi) : NULL;
	return ret;
}

/* "W 11 sleep 150 W 29 ..." of what prepare() did after the reset pulse */
static void events_string(char *out, size_t size)
{
	size_t len = 0;
	int i;

	out[0] = 0;
	for (i = 0; i < nevents; i++) {
		if (strncmp(events[i], "gpio", 4) == 0)
			continue;
		len += snprintf(out + len, size - len, "%s%s", len ? " | " : "", events[i]);
		if (len >= size)
			break;
	}
}

static int count_events(const char *ev)
{
	int i, n = 0;

	for (i = 0; i < nevents; i++)
		if (strcmp(events[i], ev) == 0)
			n++;
	return n;
}

static int index_of(const char *ev)
{
	int i;

	for (i = 0; i < nevents; i++)
		if (strcmp(events[i], ev) == 0)
			return i;
	return -1;
}

/* true if event `ev` comes right after the first `first` */
static int followed_by(const char *first, const char *ev)
{
	int i = index_of(first);

	return i >= 0 && i + 1 < nevents && strcmp(events[i + 1], ev) == 0;
}

#define N(a) ((int)(sizeof(a) / sizeof((a)[0])))
#define G_LINE "G size=71,71 delays=100,50,20,200,20 format=rgb888 lanes=4 flags=0xe03"
#define M_LINE "M clock=40000 horizontal=640,120,120,120 vertical=480,17,5,13 default=1"

/* ---- tests ---------------------------------------------------------- */

/* Overlay that already ends in 11/29 (every generated overlay does). */
static void test_sequence_with_11_29_is_not_repeated(void)
{
	const char *lines[] = { G_LINE, M_LINE, "I seq=b9f11283",
		"I seq=11 wait=0x96", "I seq=29 wait=0x32" };
	struct generic_panel *ctx;
	char ev[2048];

	CHECK(probe(lines, N(lines), &ctx) == 0, "probe failed: %s", logbuf);
	if (!ctx)
		return;
	nevents = 0;
	CHECK(ctx->panel.funcs->prepare(&ctx->panel) == 0, "prepare failed: %s", logbuf);
	events_string(ev, sizeof(ev));
	CHECK(count_events("W 11") == 1, "0x11 sent %d times: %s", count_events("W 11"), ev);
	CHECK(count_events("W 29") == 1, "0x29 sent %d times: %s", count_events("W 29"), ev);
	CHECK(index_of("W 11") >= 0 && index_of("W 11") < index_of("W 29"), "11 not before 29: %s", ev);
	CHECK(followed_by("W 11", "sleep 150"), "no 150 ms after 0x11: %s", ev);
	CHECK(followed_by("W 29", "sleep 50"), "no 50 ms after 0x29: %s", ev);
}

/* Overlay without 11/29: the driver sends 11, waits, then 29. */
static void test_driver_sends_11_wait_29_when_missing(void)
{
	const char *lines[] = { G_LINE, M_LINE, "I seq=b9f11283" };
	struct generic_panel *ctx;
	char ev[2048];
	int i11, i29;

	CHECK(probe(lines, N(lines), &ctx) == 0, "probe failed: %s", logbuf);
	if (!ctx)
		return;
	nevents = 0;
	CHECK(ctx->panel.funcs->prepare(&ctx->panel) == 0, "prepare failed: %s", logbuf);
	events_string(ev, sizeof(ev));
	i11 = index_of("W 11");
	i29 = index_of("W 29");
	CHECK(count_events("W 11") == 1 && count_events("W 29") == 1, "not one each: %s", ev);
	CHECK(i11 >= 0 && i29 > i11, "order is not 11 then 29: %s", ev);
	CHECK(i11 >= 0 && i29 > i11 + 1 && strncmp(events[i11 + 1], "sleep ", 6) == 0 &&
	      atoi(events[i11 + 1] + 6) >= 5, "no wait between 11 and 29: %s", ev);
	CHECK(index_of("W b9f11283") < i11, "vendor sequence not first: %s", ev);
}

static void test_wait_is_decimal_or_0x(void)
{
	const char *lines[] = { G_LINE, M_LINE, "I seq=11 wait=250", "I seq=29 wait=0x250" };
	struct generic_panel *ctx;
	char ev[2048];

	CHECK(probe(lines, N(lines), &ctx) == 0, "probe failed: %s", logbuf);
	if (!ctx)
		return;
	nevents = 0;
	ctx->panel.funcs->prepare(&ctx->panel);
	events_string(ev, sizeof(ev));
	CHECK(followed_by("W 11", "sleep 250"), "wait=250 is not 250 ms: %s", ev);
	CHECK(followed_by("W 29", "sleep 592"), "wait=0x250 is not 592 ms: %s", ev);
}

/* A failed vendor write is logged and the sequence goes on. */
static void test_write_failure_is_logged_and_skipped(void)
{
	const char *lines[] = { G_LINE, M_LINE, "I seq=b9f11283", "I seq=b480",
		"I seq=cc0b", "I seq=11 wait=0x96", "I seq=29 wait=0x32" };
	struct generic_panel *ctx;
	char ev[2048];
	int ret;

	CHECK(probe(lines, N(lines), &ctx) == 0, "probe failed: %s", logbuf);
	if (!ctx)
		return;
	nevents = 0;
	writes = 0;
	fail_write_at = 2;
	ret = ctx->panel.funcs->prepare(&ctx->panel);
	events_string(ev, sizeof(ev));
	CHECK(ret == 0, "prepare returned %d: %s", ret, ev);
	CHECK(writes == 5, "%d writes, want all 5: %s", writes, ev);
	CHECK(strstr(logbuf, "warn: init step 1 (cmd 0xb4, 2 bytes) failed: -5") != NULL,
	      "failure not logged: %s", logbuf);
	CHECK(ctx->prepared, "panel not prepared");
}

/* The driver's own 0x11 failing powers the panel down like unprepare. */
static void test_driver_exit_sleep_failure_powers_off(void)
{
	const char *lines[] = { G_LINE, M_LINE, "I seq=b9f11283" };
	struct generic_panel *ctx;
	char ev[2048];
	int ret;

	CHECK(probe(lines, N(lines), &ctx) == 0, "probe failed: %s", logbuf);
	if (!ctx)
		return;
	nevents = 0;
	writes = 0;
	fail_write_at = 2;	/* b9f11283, then the driver's 0x11 */
	ret = ctx->panel.funcs->prepare(&ctx->panel);
	events_string(ev, sizeof(ev));
	CHECK(ret == -EIO, "prepare returned %d, want -EIO: %s", ret, ev);
	CHECK(count_events("W 29") == 0, "0x29 sent after 0x11 failed: %s", ev);
	CHECK(stub_enable_gpio.value == 0, "enable gpio %d, want 0", stub_enable_gpio.value);
	CHECK(stub_reset_gpio.value == 1, "reset gpio %d, want 1 (asserted)", stub_reset_gpio.value);
	{
		int i, g[2] = { -1, -1 }, ng = 0;

		for (i = index_of("W 11 FAIL"); i >= 0 && i < nevents; i++)
			if (strncmp(events[i], "gpio", 4) == 0 && ng < 2)
				g[ng++] = i;
		CHECK(ng == 2 && strcmp(events[g[0]], "gpio enable 0") == 0 &&
		      strcmp(events[g[1]], "gpio reset 1") == 0,
		      "after the failure want enable=0 then reset=1 (%d gpio events)", ng);
	}
	CHECK(stub_vdd.count == 0 && stub_iovcc.count == 0, "supplies left on (%d, %d)",
	      stub_vdd.count, stub_iovcc.count);
	CHECK(!ctx->prepared, "panel marked prepared after a failure");
}

/* "seq=2901" is a register write (rgb20s page select), not display_on. */
static void test_register_write_2901_is_not_display_on(void)
{
	const char *lines[] = { G_LINE, M_LINE, "I seq=ff3052", "I seq=2901",
		"I seq=11 wait=0x96" };
	struct generic_panel *ctx;
	char ev[2048];

	CHECK(probe(lines, N(lines), &ctx) == 0, "probe failed: %s", logbuf);
	if (!ctx)
		return;
	nevents = 0;
	ctx->panel.funcs->prepare(&ctx->panel);
	events_string(ev, sizeof(ev));
	CHECK(count_events("W 2901") == 1, "page write missing: %s", ev);
	CHECK(count_events("W 11") == 1, "0x11 sent %d times: %s", count_events("W 11"), ev);
	CHECK(count_events("W 29") == 1 && index_of("W 29") > index_of("W 11"),
	      "driver did not send 0x29 after 0x11: %s", ev);
}

/* 0x29 without 0x11 in the sequence: the driver sends 11, waits, 29. */
static void test_29_without_11_gets_11_wait_29(void)
{
	const char *lines[] = { G_LINE, M_LINE, "I seq=b9f11283", "I seq=29 wait=0x32" };
	struct generic_panel *ctx;
	char ev[2048];
	int i11, last29 = -1, i;

	CHECK(probe(lines, N(lines), &ctx) == 0, "probe failed: %s", logbuf);
	if (!ctx)
		return;
	nevents = 0;
	ctx->panel.funcs->prepare(&ctx->panel);
	events_string(ev, sizeof(ev));
	i11 = index_of("W 11");
	for (i = 0; i < nevents; i++)
		if (strcmp(events[i], "W 29") == 0)
			last29 = i;
	CHECK(i11 >= 0 && i11 + 1 < nevents && strcmp(events[i11 + 1], "sleep 120") == 0,
	      "no 11 + 120 ms: %s", ev);
	CHECK(last29 > i11, "no 0x29 after the driver's 0x11: %s", ev);
}

static void test_force_continuous_clock(void)
{
	const char *lines[] = { G_LINE, M_LINE, "I seq=11" };
	struct generic_panel *ctx;
	struct mipi_dsi_device *dsi;

	force_continuous_clock = true;
	CHECK(probe(lines, N(lines), &ctx) == 0, "probe failed: %s", logbuf);
	force_continuous_clock = false;
	if (!ctx)
		return;
	dsi = to_mipi_dsi_device(ctx->dev);
	CHECK(dsi->mode_flags == 0xa03, "mode_flags %#lx, want 0xa03", dsi->mode_flags);
	CHECK(probe(lines, N(lines), &ctx) == 0 && to_mipi_dsi_device(ctx->dev)->mode_flags == 0xe03,
	      "default changed the flags");
}

/* A bad line is skipped with a warning naming it; the rest still loads. */
static void test_malformed_lines_are_skipped(void)
{
	static const char *bad[] = {
		"I seq=b9f",			/* odd number of digits */
		"I seq=zz",			/* not hex */
		"I seq=",			/* empty */
		"I wait=10",			/* no command */
		"I seq=11 wait=15x",		/* not a number */
		"I dcs=1ff",			/* not a byte */
		"M clock=40000 horizontal=640,120,120 vertical=480,17,5,13",
		"M clock=abc horizontal=640,120,120,120 vertical=480,17,5,13",
		"M horizontal=640,120,120,120 vertical=480,17,5,13",
		"X what",
	};
	int i;

	for (i = 0; i < N(bad); i++) {
		const char *lines[] = { G_LINE, M_LINE, "I seq=11 wait=0x96", bad[i] };
		struct generic_panel *ctx;
		struct generic_panel_mode *m;
		struct generic_panel_init_seq *it;
		int ret = probe(lines, N(lines), &ctx), nm = 0, ns = 0;

		CHECK(ret == 0, "\"%s\" failed the probe (ret %d): %s", bad[i], ret, logbuf);
		CHECK(strstr(logbuf, "panel_description[3]") != NULL && strstr(logbuf, "skipped") != NULL,
		      "\"%s\": warning does not name the line: %s", bad[i], logbuf);
		if (!ctx)
			continue;
		for (m = ctx->modes; m; m = m->prev)
			nm++;
		for (it = ctx->iseq; it; it = it->link)
			ns++;
		CHECK(nm == 1 && ns == 1, "\"%s\": %d modes, %d steps, want 1 and 1", bad[i], nm, ns);
	}
}

static void test_bad_g_value_keeps_default(void)
{
	const char *lines[] = { "G format=rgb999 lanes=4 flags=0xe03", M_LINE, "I seq=11" };
	struct generic_panel *ctx;

	CHECK(probe(lines, N(lines), &ctx) == 0, "probe failed: %s", logbuf);
	if (ctx)
		CHECK(to_mipi_dsi_device(ctx->dev)->lanes == 4, "values after the bad one lost");
	CHECK(strstr(logbuf, "bad format rgb999") != NULL, "no warning: %s", logbuf);
}

static void test_long_wait_is_cut_to_the_limit(void)
{
	const char *lines[] = { G_LINE, M_LINE, "I seq=11 wait=1500", "I seq=29" };
	struct generic_panel *ctx;
	char ev[2048];

	CHECK(probe(lines, N(lines), &ctx) == 0, "probe failed: %s", logbuf);
	CHECK(strstr(logbuf, "cut to 1000 ms") != NULL, "no warning: %s", logbuf);
	if (!ctx)
		return;
	nevents = 0;
	ctx->panel.funcs->prepare(&ctx->panel);
	events_string(ev, sizeof(ev));
	CHECK(followed_by("W 11", "sleep 1000"), "wait not cut to 1000 ms: %s", ev);
}

static void test_probe_fails_only_with_nothing_usable(void)
{
	const char *none[] = { G_LINE, "M clock=abc", "I seq=zz" };
	const char *only_steps[] = { G_LINE, "M clock=abc", "I seq=11" };
	const char *only_mode[] = { G_LINE, M_LINE, "I seq=zz" };
	struct generic_panel *ctx;

	CHECK(probe(none, N(none), &ctx) < 0, "loaded with no mode and no step");
	CHECK(probe(only_steps, N(only_steps), &ctx) == 0, "failed with init steps left: %s", logbuf);
	CHECK(probe(only_mode, N(only_mode), &ctx) == 0, "failed with a mode left: %s", logbuf);
}

static void test_unknown_keys_and_comments_are_tolerated(void)
{
	const char *lines[] = { "G name size=71,71 delays=100,50,20,200,20 format=rgb888 lanes=4 flags=0xe03 future=1",
		M_LINE " # native fps=77.669903", "", "  # comment only",
		"M clock=27650 horizontal=640,188,9,190 vertical=480,13,41,5 future=1",
		"I seq=11 wait=0x96 future=1 # orig_cmd=0x5" };
	struct generic_panel *ctx;

	CHECK(probe(lines, N(lines), &ctx) == 0, "probe failed: %s", logbuf);
}

static void test_sync_polarity(void)
{
	const char *lines[] = { G_LINE,
		"M clock=40000 horizontal=640,120,120,120 vertical=480,17,5,13 hsync-active=1 default=1",
		"M clock=27650 horizontal=640,188,9,190 vertical=480,13,41,5",
		"I seq=11" };
	struct generic_panel *ctx;
	struct drm_connector conn = { 0 };
	int i, seen = 0;

	CHECK(probe(lines, N(lines), &ctx) == 0, "probe failed: %s", logbuf);
	if (!ctx)
		return;
	ctx->panel.funcs->get_modes(&ctx->panel, &conn);
	for (i = 0; i < nmodes; i++) {
		unsigned int want = modes[i].clock == 40000 ?
			(DRM_MODE_FLAG_PHSYNC | DRM_MODE_FLAG_NVSYNC) :
			(DRM_MODE_FLAG_NHSYNC | DRM_MODE_FLAG_NVSYNC);
		CHECK(modes[i].flags == want, "mode %d: flags %#x, want %#x",
		      modes[i].clock, modes[i].flags, want);
		seen++;
	}
	CHECK(seen == 2, "%d modes", seen);
}

static int load_file(const char *path)
{
	static char *lines[4096];
	char buf[4096];
	int n = 0, ret;
	FILE *f = fopen(path, "r");
	struct generic_panel *ctx;

	if (!f) {
		perror(path);
		return 2;
	}
	while (n < N(lines) && fgets(buf, sizeof(buf), f)) {
		buf[strcspn(buf, "\n")] = 0;
		lines[n++] = strdup(buf);
	}
	fclose(f);
	ret = probe((const char **)lines, n, &ctx);
	if (ret < 0) {
		printf("%s", logbuf);
		return 1;
	}
	nevents = 0;
	ret = ctx->panel.funcs->prepare(&ctx->panel);
	printf("%d lines, prepare %d, %d writes, waits:", n, ret, writes);
	for (int i = 0; i < nevents; i++)
		if (strncmp(events[i], "sleep ", 6) == 0 && i > 0 && events[i - 1][0] == 'W')
			printf(" %s=%s", events[i - 1] + 2, events[i] + 6);
	printf("\n");
	return ret < 0;
}

int main(int argc, char **argv)
{
	if (argc == 3 && strcmp(argv[1], "lines") == 0)
		return load_file(argv[2]);

#define RUN(t) do { int before = failures; t(); printf("%s %s\n", failures == before ? "PASS" : "FAIL", #t); } while (0)
	RUN(test_sequence_with_11_29_is_not_repeated);
	RUN(test_driver_sends_11_wait_29_when_missing);
	RUN(test_wait_is_decimal_or_0x);
	RUN(test_write_failure_is_logged_and_skipped);
	RUN(test_driver_exit_sleep_failure_powers_off);
	RUN(test_register_write_2901_is_not_display_on);
	RUN(test_29_without_11_gets_11_wait_29);
	RUN(test_force_continuous_clock);
	RUN(test_malformed_lines_are_skipped);
	RUN(test_bad_g_value_keeps_default);
	RUN(test_long_wait_is_cut_to_the_limit);
	RUN(test_probe_fails_only_with_nothing_usable);
	RUN(test_unknown_keys_and_comments_are_tolerated);
	RUN(test_sync_polarity);
	printf("%d check(s) failed\n", failures);
	return failures ? 1 : 0;
}
