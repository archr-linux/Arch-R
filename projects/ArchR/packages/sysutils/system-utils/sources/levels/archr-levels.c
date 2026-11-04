// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
//
// archr-levels: the one owner of the volume and backlight levels.
//
//   archr-levels                          serve (archr-levels.service)
//   archr-levels KIND [osd]               print the level, 0-100 (and show it)
//   archr-levels KIND N|+N|-N [osd]       set or step it, print the result
//   archr-levels KIND restore             apply the level again
//   archr-levels KIND hold up|down [osd]  a tap step now, then faster and
//                                         faster until "release"
//   archr-levels renew                    the button is still down
//   archr-levels release
//
// A hold lasts RENEW_MS after it starts or after the last "renew": the
// caller renews it while the button is down, so a lost release (the caller
// died) ends it by itself.
//
// KIND is volume, brightness (first backlight) or brightness2 (the second).
// Append "seq" to a KIND command to get "level sequence". Launcher notices
// carry that state version; the installed OSD still gets just "kind level".
// A level is what the user sees: volume follows a decibel scale and the
// backlight a 2.2 gamma above a legible minimum, so every step feels the
// same size. The daemon keeps one PulseAudio connection (a step costs one
// round trip, not a process) and writes system.cfg once a level settles.
// A sink that appears later (the card at boot, a profile switch) or a new
// default sink gets the level too, and a lost or refused connection (the
// server not up yet, or restarted) is retried on its own with a short
// backoff, the level applied again once it is back.
// Commands only talk to the daemon (systemd restarts it): without it they
// fail with a clear message instead of racing it for system.cfg.
//
// Hold speed, shared with the launcher's sliders: TAP on the press, then
// after HOLD_DELAY_MS 25 %/s, 50 %/s past 950 ms and 75 %/s past 1550 ms.
#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <stddef.h>
#include <math.h>
#include <poll.h>
#include <pulse/pulseaudio.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/eventfd.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

enum {
	TAP = 2,
	HOLD_DELAY_MS = 350,
	TICK_MS = 40,
	RENEW_MS = 400,
	SETTLE_MS = 1500,
	SCREENS = 2, /* the handhelds have one panel, a few two */
	BRIGHTNESS_MIN = 5,
};
static const double VOLUME_RANGE_DB = 50.0, GAMMA = 2.2;

extern char **environ;

struct level {
	char key[24];
	int screen; /* 0: volume, else the backlight's number */
	int value, saved;
	uint64_t seq; /* the version of this value, shared by replies and notices */
	int writing; /* the value the running writer saves, -1: none */
	int listed;  /* in system.cfg before the conversion */
};
static struct level levels[1 + SCREENS];
static pid_t writer;  /* the system.cfg write running, 0: none */
static int unmarked; /* converted levels not written yet (see migrate) */

static struct {
	struct level *level;
	int dir, show;
	long start, next, deadline;
} hold;

static const char *env_or(const char *name, const char *fallback)
{
	const char *v = getenv(name);
	return v && *v ? v : fallback;
}

static const char *socket_path(void)
{
	return env_or("ARCHR_LEVELS_SOCKET", "/run/archr-levels.sock");
}

static long now_ms(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000L + t.tv_nsec / 1000000;
}

/* The boot's clock keeps versions increasing even if the daemon restarts
 * while the launcher stays alive. The counter also covers equal clock ticks. */
static void stamp(struct level *l)
{
	static uint64_t last;
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	uint64_t now = (uint64_t)t.tv_sec * 1000000000 + t.tv_nsec;
	l->seq = last = now > last ? now : last + 1;
}

static int clamp(const struct level *l, long v)
{
	long min = l->screen ? BRIGHTNESS_MIN : 0;
	return v < min ? min : v > 100 ? 100 : v;
}

/* A number saved in system.cfg, read as get_setting reads a plain key. */
static int cfg_get(const char *key, long *value)
{
	FILE *f = fopen(env_or("ARCHR_LEVELS_CFG", "/storage/.config/system/configs/system.cfg"), "re");
	size_t len = strlen(key);
	char line[256];
	int found = 0;
	while (f && !found && fgets(line, sizeof line, f))
		if (!strncmp(line, key, len) && line[len] == '=') {
			char *end;
			long n = strtol(line + len + 1, &end, 10);
			if ((found = end != line + len + 1))
				*value = n;
		}
	if (f)
		fclose(f);
	return found;
}

static int read_saved(struct level *l)
{
	long v = l->screen ? 50 : 60;
	cfg_get(l->key, &v);
	return clamp(l, v);
}

static struct level *find(const char *kind)
{
	int screen;
	if (!strcmp(kind, "volume"))
		screen = 0;
	else if (!strcmp(kind, "brightness"))
		screen = 1;
	else if (!strcmp(kind, "brightness2"))
		screen = 2;
	else
		return NULL;
	struct level *l = &levels[screen];
	if (!l->key[0]) {
		l->screen = screen;
		if (screen == 0)
			strcpy(l->key, "audio.volume");
		else if (screen == 1)
			strcpy(l->key, "display.brightness");
		else
			strcpy(l->key, "display.brightness2");
		l->value = l->saved = read_saved(l);
		stamp(l);
	} else if (l->value == l->saved && hold.level != l && !writer && !unmarked) {
		/* Settled: the file is the truth (a reset or a restore may have changed it). */
		int saved = read_saved(l);
		if (saved != l->value) {
			l->value = l->saved = saved;
			stamp(l);
		}
	}
	return l;
}

/* ---- volume: one PulseAudio connection, the newest level wins ---- */

/* libpulse is loaded only to change the volume: a client stays a small,
 * quick process (the library and its dependencies cost ~10 ms to load). */
#define PULSE(X)                                                                                        \
	X(pa_threaded_mainloop_new) X(pa_threaded_mainloop_start) X(pa_threaded_mainloop_lock)          \
	X(pa_threaded_mainloop_unlock) X(pa_threaded_mainloop_get_api) X(pa_context_new)                \
	X(pa_context_set_state_callback) X(pa_context_connect) X(pa_context_get_state) X(pa_context_unref) \
	X(pa_context_get_sink_info_by_name) X(pa_context_set_sink_volume_by_index)                       \
	X(pa_operation_unref) X(pa_sw_volume_from_dB) X(pa_cvolume_set)                                 \
	X(pa_context_set_subscribe_callback) X(pa_context_subscribe)
#define DECLARE(f) static __typeof__(f) *dl_##f;
PULSE(DECLARE)

static int load_pulse(void)
{
	static int loaded = -1;
	if (loaded < 0) {
		void *lib = dlopen("libpulse.so.0", RTLD_NOW);
		loaded = lib != NULL;
#define RESOLVE(f)                                                     \
	if (lib && !(dl_##f = (__typeof__(f) *)dlsym(lib, #f))) \
		loaded = 0;
		PULSE(RESOLVE)
	}
	return loaded;
}

static pa_threaded_mainloop *ml;
static pa_context *ctx;
static pa_volume_t target;
static int queued, busy; /* a level waits for the connection; requests in flight */
/* The connection failed or was refused: the main loop connects again after
 * retry_ms (100 ms, doubling to 2 s while it keeps failing). wake_fd stops
 * its poll so it notices. All of these are under the mainloop lock. */
static int lost, wake_fd = -1;
static long retry_at, retry_ms;

enum { RETRY_FIRST_MS = 100, RETRY_MAX_MS = 2000 };

static void push_volume(void);

/* One change in flight: the newest level goes out when the last is done.
 * Answers from a context already replaced are not ours to count. */
static void sink_set(pa_context *c, int ok, void *u)
{
	(void)ok, (void)u;
	if (c == ctx && --busy == 0 && queued)
		push_volume();
}

/* The level on every channel of the default sink. A one-channel volume is
 * not spread over the others by every server: PipeWire's pulse server sets
 * the first channel only and leaves the rest where they were. */
static void sink_found(pa_context *c, const pa_sink_info *i, int eol, void *u)
{
	(void)u;
	if (c != ctx)
		return;
	if (!eol && i) {
		pa_cvolume cv;
		dl_pa_cvolume_set(&cv, i->volume.channels ? i->volume.channels : 1, target);
		pa_operation *op = dl_pa_context_set_sink_volume_by_index(c, i->index, &cv, sink_set, NULL);
		if (op) {
			busy++;
			dl_pa_operation_unref(op);
		}
		return;
	}
	if (--busy == 0 && queued)
		push_volume();
}

/* Whichever sink is the default when the request arrives. */
static void push_volume(void)
{
	pa_operation *op = dl_pa_context_get_sink_info_by_name(ctx, "@DEFAULT_SINK@", sink_found, NULL);
	queued = 0;
	if (op) {
		busy++;
		dl_pa_operation_unref(op);
	}
}

/* A sink that appears, or a new default, starts at the session's remembered
 * or default volume, not at the level: the card's sink can show up after the
 * boot's restore, and a profile switch makes a new one. Give it the level. */
static void sink_event(pa_context *c, pa_subscription_event_type_t t, uint32_t index, void *u)
{
	(void)c, (void)index, (void)u;
	int facility = t & PA_SUBSCRIPTION_EVENT_FACILITY_MASK, type = t & PA_SUBSCRIPTION_EVENT_TYPE_MASK;
	if ((facility == PA_SUBSCRIPTION_EVENT_SINK && type == PA_SUBSCRIPTION_EVENT_NEW) ||
	    (facility == PA_SUBSCRIPTION_EVENT_SERVER && type == PA_SUBSCRIPTION_EVENT_CHANGE)) {
		queued = 1;
		if (!busy)
			push_volume();
	}
}

static void connection_lost(void)
{
	busy = 0;
	if (!lost) {
		lost = 1;
		retry_ms = retry_ms ? (retry_ms * 2 > RETRY_MAX_MS ? RETRY_MAX_MS : retry_ms * 2) : RETRY_FIRST_MS;
		retry_at = now_ms() + retry_ms;
		uint64_t one = 1;
		if (wake_fd >= 0 && write(wake_fd, &one, sizeof one) < 0) {
			/* the counter is full: the main loop is awake anyway */
		}
	}
}

static void state_changed(pa_context *c, void *u)
{
	(void)u;
	if (c != ctx)
		return;
	pa_context_state_t s = dl_pa_context_get_state(c);
	if (s == PA_CONTEXT_READY) {
		retry_ms = 0;
		dl_pa_context_set_subscribe_callback(c, sink_event, NULL);
		pa_operation *op = dl_pa_context_subscribe(c, PA_SUBSCRIPTION_MASK_SINK | PA_SUBSCRIPTION_MASK_SERVER, NULL, NULL);
		if (op)
			dl_pa_operation_unref(op);
		/* A new connection may face a restarted server: the level again. */
		queued = 1;
		push_volume();
	} else if (!PA_CONTEXT_IS_GOOD(s))
		connection_lost();
}

/* A new context; the lock is held. */
static void connect_pulse(void)
{
	if (ctx)
		dl_pa_context_unref(ctx);
	lost = 0;
	busy = 0;
	ctx = dl_pa_context_new(dl_pa_threaded_mainloop_get_api(ml), "archr-levels");
	if (!ctx) {
		connection_lost();
		return;
	}
	dl_pa_context_set_state_callback(ctx, state_changed, NULL);
	if (dl_pa_context_connect(ctx, NULL, PA_CONTEXT_NOAUTOSPAWN, NULL) < 0)
		connection_lost();
}

/* Main loop: when the connection is to be tried again, -1 if never. */
static long pulse_retry(long now)
{
	long wake = -1;
	if (!ml)
		return -1;
	dl_pa_threaded_mainloop_lock(ml);
	if (lost && now >= retry_at)
		connect_pulse();
	if (lost)
		wake = retry_at;
	dl_pa_threaded_mainloop_unlock(ml);
	return wake;
}

static void set_volume(int level)
{
	if (!ml) {
		if (!load_pulse())
			return;
		ml = dl_pa_threaded_mainloop_new();
		if (!ml || dl_pa_threaded_mainloop_start(ml) < 0) {
			ml = NULL;
			return;
		}
	}
	dl_pa_threaded_mainloop_lock(ml);
	target = level ? dl_pa_sw_volume_from_dB(-VOLUME_RANGE_DB * (100 - level) / 100.0) : PA_VOLUME_MUTED;
	queued = 1;
	pa_context_state_t s = ctx ? dl_pa_context_get_state(ctx) : PA_CONTEXT_FAILED;
	if (s == PA_CONTEXT_READY) {
		if (!busy)
			push_volume();
	} else if (!ctx) {
		connect_pulse();
	}
	/* Connecting, or waiting for the retry: the level goes out once ready. */
	dl_pa_threaded_mainloop_unlock(ml);
}

/* ---- backlight ---- */

static int visible(const struct dirent *e)
{
	return e->d_name[0] != '.';
}

static long read_long(const char *dir, const char *name)
{
	char path[PATH_MAX], text[32];
	snprintf(path, sizeof path, "%s/%s", dir, name);
	FILE *f = fopen(path, "re");
	long v = f && fgets(text, sizeof text, f) ? strtol(text, NULL, 10) : -1;
	if (f)
		fclose(f);
	return v;
}

static void set_brightness(int screen, int level)
{
	const char *base = env_or("ARCHR_LEVELS_BACKLIGHT", "/sys/class/backlight");
	struct dirent **list;
	int count = scandir(base, &list, visible, alphasort);
	char dir[PATH_MAX] = "";
	for (int i = 0; i < count; i++) {
		if (i == screen - 1)
			snprintf(dir, sizeof dir, "%s/%s", base, list[i]->d_name);
		free(list[i]);
	}
	if (count >= 0)
		free(list);
	long max = dir[0] ? read_long(dir, "max_brightness") : -1;
	if (max <= 0)
		return;
	double x = (level - BRIGHTNESS_MIN) / (100.0 - BRIGHTNESS_MIN);
	long raw = lround(max * (BRIGHTNESS_MIN / 100.0 + (1 - BRIGHTNESS_MIN / 100.0) * pow(x, GAMMA)));
	char path[PATH_MAX];
	snprintf(path, sizeof path, "%s/brightness", dir);
	FILE *f = fopen(path, "we");
	if (f) {
		fprintf(f, "%ld\n", raw < 1 ? 1 : raw > max ? max : raw);
		fclose(f);
	}
}

/* ---- pill and persistence ---- */

static void notice(const struct level *l, int show)
{
	int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
	if (fd < 0)
		return;
	const char *names[] = { "archr-osd.sock", "archr-launcher-levels.sock" };
	for (int i = show ? 0 : 1; i < 2; i++) {
		struct sockaddr_un to = { .sun_family = AF_UNIX };
		snprintf(to.sun_path, sizeof to.sun_path, "%s/%s", env_or("XDG_RUNTIME_DIR", "/run"), names[i]);
		char text[64];
		const char *kind = l->screen ? "brightness" : "volume";
		if (i && l->screen == 2)
			kind = "brightness2";
		int n = snprintf(text, sizeof text, "%s %d", kind, l->value);
		if (i)
			n += snprintf(text + n, sizeof text - n, " %" PRIu64, l->seq);
		sendto(fd, text, n, MSG_DONTWAIT, (struct sockaddr *)&to, sizeof to);
	}
	close(fd);
}

/* Writes key/value pairs into system.cfg in one atomic replacement, under
 * the same lock as set_setting. Returns the writer's pid, or -1. */
static const char WRITER[] =
	". \"${ARCHR_LEVELS_FUNCTIONS:-/etc/profile.d/001-functions}\" || exit 1\n"
	"if [ ! -e \"${J_CONF}\" ]; then\n"
	"  mkdir -p \"${J_CONF%/*}\" && cp -f /usr/config/system/configs/system.cfg \"${J_CONF}\" || exit 1\n"
	"fi\n"
	"pairs=() keys=\n"
	"while [ $# -ge 2 ]; do pairs+=(\"$1=$2\"); keys=\"${keys}|${1//./\\\\.}\"; shift 2; done\n"
	"levels_cfg() {\n"
	"  grep -v -E \"^(${keys#|})=\" \"${J_CONF}\"\n"
	"  [ $? -le 1 ] || return 1\n"
	"  printf '%s\\n' \"${pairs[@]}\"\n"
	"}\n"
	"rewrite_config levels_cfg\n";

static pid_t store(char **pairs, int count)
{
	char *argv[4 + 2 * (2 + SCREENS) + 1] = { "/bin/bash", "-c", (char *)WRITER, "archr-levels" };
	int n = 4;
	for (int i = 0; i < count && i < 2 * (2 + SCREENS); i++)
		argv[n++] = pairs[i];
	argv[n] = NULL;
	pid_t pid;
	return posix_spawn(&pid, argv[0], NULL, NULL, argv, environ) ? -1 : pid;
}

/* Saves every level that changed, in one write. Before the conversion is
 * written (unmarked) that is every level the file had, plus the mark, so
 * the old levels are never saved alone and converted twice. A level counts
 * as saved only once the writer succeeds; a failed write is tried again at
 * the next settle. */
static void flush(void)
{
	char *pairs[2 * (2 + SCREENS)], values[1 + SCREENS][8];
	int n = 0;
	if (writer)
		return;
	for (int i = 0; i <= SCREENS; i++) {
		struct level *l = &levels[i];
		l->writing = -1;
		if (!l->key[0] || (unmarked ? !l->listed : l->value == l->saved))
			continue;
		l->writing = l->value;
		snprintf(values[i], sizeof values[i], "%d", l->value);
		pairs[n++] = l->key;
		pairs[n++] = values[i];
	}
	if (unmarked) {
		pairs[n++] = "levels.perceptual";
		pairs[n++] = "1";
	}
	if (n && (writer = store(pairs, n)) < 0)
		writer = 0;
}

/* The writer ended (status from waitpid): returns 1 on success. */
static int written(int status)
{
	int ok = WIFEXITED(status) && !WEXITSTATUS(status);
	for (int i = 0; i <= SCREENS; i++) {
		if (ok && levels[i].writing >= 0)
			levels[i].saved = levels[i].writing;
		levels[i].writing = -1;
	}
	if (ok)
		unmarked = 0;
	writer = 0;
	return ok;
}

/* Waits for the running write, if any. */
static int finish(void)
{
	int status;
	if (!writer)
		return 1;
	return waitpid(writer, &status, 0) == writer ? written(status) : (writer = 0);
}

/* Levels saved before these curves (a linear backlight, PulseAudio's cubic
 * volume percent) are converted once, so screen and sound stay as they were.
 * The converted levels and the levels.perceptual mark go out in one atomic
 * write: an interrupted conversion leaves the old file whole. Until it is
 * written the levels live in memory only and every settle tries again. */
static void migrate(void)
{
	static const char *const kinds[] = { "volume", "brightness", "brightness2" };
	long old;
	if (cfg_get("levels.perceptual", &old))
		return;
	for (size_t i = 0; i < sizeof kinds / sizeof *kinds; i++) {
		struct level *l = find(kinds[i]);
		if (!(l->listed = cfg_get(l->key, &old)))
			continue;
		double f = old / 100.0;
		if (l->screen)
			old = lround(5 + 95 * pow(f > 0.05 ? (f - 0.05) / 0.95 : 0, 1 / GAMMA));
		else
			old = old <= 0 ? 0 : fmax(1, lround(100 + 100 * 60 * log10(f) / VOLUME_RANGE_DB));
		l->value = clamp(l, old);
		stamp(l);
	}
	unmarked = 1;
	flush();
	if (!finish())
		fprintf(stderr, "archr-levels: could not save the converted levels; retrying\n");
}

/* ---- commands ---- */

static void apply(struct level *l, long value, int show)
{
	l->value = clamp(l, value);
	stamp(l);
	if (l->screen)
		set_brightness(l->screen, l->value);
	else
		set_volume(l->value);
	notice(l, show);
}

/* Returns the level after the command, or -1 when it is malformed. */
static int command(char *text, struct level **snapshot, int *sequenced)
{
	char *word[5], *save_ptr;
	int n = 0;
	for (char *w = strtok_r(text, " \t\n", &save_ptr); w; w = strtok_r(NULL, " \t\n", &save_ptr))
		if (n < 5)
			word[n++] = w;
		else
			return -1;
	if (n == 1 && !strcmp(word[0], "release")) {
		hold.level = NULL;
		return 0;
	}
	if (n == 1 && !strcmp(word[0], "renew")) {
		hold.deadline = now_ms() + RENEW_MS;
		return 0;
	}
	*sequenced = n > 1 && !strcmp(word[n - 1], "seq");
	n -= *sequenced;
	struct level *l = n ? find(word[0]) : NULL;
	if (!l)
		return -1;
	*snapshot = l;
	int show = n > 1 && !strcmp(word[n - 1], "osd");
	n -= show;
	if (n == 1) {
		if (show)
			notice(l, show);
		return l->value;
	}
	if (n == 2 && !strcmp(word[1], "restore")) {
		apply(l, l->value, show);
		return l->value;
	}
	if (n == 3 && !strcmp(word[1], "hold")) {
		int dir = !strcmp(word[2], "up") ? 1 : !strcmp(word[2], "down") ? -1 : 0;
		if (!dir)
			return -1;
		apply(l, l->value + dir * TAP, show);
		long now = now_ms();
		hold.level = l, hold.dir = dir, hold.show = show;
		hold.start = now, hold.next = now + HOLD_DELAY_MS, hold.deadline = now + RENEW_MS;
		return l->value;
	}
	if (n != 2)
		return -1;
	char *end;
	errno = 0;
	long v = strtol(word[1], &end, 10);
	if (end == word[1] || *end || errno)
		return -1;
	/* Far beyond any level: a huge step cannot overflow the sum. */
	v = v < -1000 ? -1000 : v > 1000 ? 1000 : v;
	if (word[1][0] == '+' || word[1][0] == '-')
		v += l->value;
	if (hold.level == l)
		hold.level = NULL;
	apply(l, v, show);
	return l->value;
}

static void hold_tick(long now)
{
	struct level *l = hold.level;
	long held = now - hold.start;
	int before = l->value;
	if (now >= hold.deadline) {
		hold.level = NULL;
		return;
	}
	apply(l, before + hold.dir * (held < 950 ? 1 : held < 1550 ? 2 : 3), hold.show);
	if (l->value == before)
		hold.level = NULL;
	else
		hold.next += TICK_MS;
}

static socklen_t address(struct sockaddr_un *a)
{
	*a = (struct sockaddr_un){ .sun_family = AF_UNIX };
	snprintf(a->sun_path, sizeof a->sun_path, "%s", socket_path());
	return sizeof *a;
}

static volatile sig_atomic_t stopping;
static void stop(int sig)
{
	(void)sig;
	stopping = 1;
}

/* Type=notify: units ordered after this one find the socket answering. */
static void ready_for_systemd(void)
{
	const char *path = getenv("NOTIFY_SOCKET");
	struct sockaddr_un to = { .sun_family = AF_UNIX };
	if (!path || !*path || strlen(path) >= sizeof to.sun_path)
		return;
	memcpy(to.sun_path, path, strlen(path));
	if (to.sun_path[0] == '@')
		to.sun_path[0] = 0;
	int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (fd >= 0) {
		sendto(fd, "READY=1", 7, 0, (struct sockaddr *)&to,
		       offsetof(struct sockaddr_un, sun_path) + strlen(path));
		close(fd);
	}
}

static int serve(void)
{
	struct sockaddr_un a;
	socklen_t len = address(&a);
	int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (fd < 0 || !connect(fd, (struct sockaddr *)&a, len)) {
		fprintf(stderr, "archr-levels: already running on %s\n", a.sun_path);
		return 1;
	}
	close(fd);
	unlink(a.sun_path);
	fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	if (fd < 0 || bind(fd, (struct sockaddr *)&a, len) < 0 || chmod(a.sun_path, 0600) < 0) {
		perror(a.sun_path);
		return 1;
	}
	wake_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
	migrate();
	ready_for_systemd();
	struct sigaction sa = { .sa_handler = stop };
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);
	long settle = unmarked ? now_ms() + SETTLE_MS : 0;
	while (!stopping) {
		long now = now_ms(), wake = -1;
		if (hold.level)
			wake = hold.next;
		if (settle && (wake < 0 || settle < wake))
			wake = settle;
		if (writer && (wake < 0 || now + 100 < wake))
			wake = now + 100; /* to collect the writer */
		long retry = pulse_retry(now);
		if (retry >= 0 && (wake < 0 || retry < wake))
			wake = retry;
		struct pollfd p[2] = { { .fd = fd, .events = POLLIN }, { .fd = wake_fd, .events = POLLIN } };
		int ready = poll(p, wake_fd >= 0 ? 2 : 1, wake < 0 ? -1 : wake > now ? (int)(wake - now) : 0);
		if (wake_fd >= 0 && (p[1].revents & POLLIN)) {
			uint64_t count;
			if (read(wake_fd, &count, sizeof count) < 0) {
				/* nothing to drain */
			}
		}
		ready = ready > 0 && (p[0].revents & POLLIN);
		int status;
		if (writer && waitpid(writer, &status, WNOHANG) == writer && !written(status))
			settle = now_ms() + SETTLE_MS;
		now = now_ms();
		if (ready > 0) {
			char text[128];
			struct sockaddr_un from;
			socklen_t from_len = sizeof from;
			ssize_t n = recvfrom(fd, text, sizeof text - 1, 0, (struct sockaddr *)&from, &from_len);
			if (n >= 0) {
				text[n] = 0;
				struct level *snapshot = NULL;
				int sequenced = 0;
				int level = command(text, &snapshot, &sequenced);
				char reply[64];
				int r;
				if (level < 0)
					r = snprintf(reply, sizeof reply, "error");
				else if (sequenced && snapshot)
					r = snprintf(reply, sizeof reply, "%d %" PRIu64, level, snapshot->seq);
				else
					r = snprintf(reply, sizeof reply, "%d", level);
				if (from_len > sizeof(sa_family_t))
					sendto(fd, reply, r, MSG_DONTWAIT, (struct sockaddr *)&from, from_len);
				if (level >= 0)
					settle = now + SETTLE_MS;
			}
		}
		if (hold.level && now >= hold.next) {
			hold_tick(now);
			settle = now + SETTLE_MS;
		}
		if (settle && now >= settle && !hold.level) {
			/* A write still running: look again once it ends. */
			settle = writer ? now + SETTLE_MS : 0;
			flush();
		}
	}
	finish();
	flush();
	finish();
	unlink(a.sun_path);
	return 0;
}

/* Asks the daemon: 0 answered, -1 not running, -2 no answer. */
static int ask(const char *text, char *reply, size_t size)
{
	struct sockaddr_un a, self = { .sun_family = AF_UNIX };
	socklen_t len = address(&a);
	int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC, 0);
	/* An autobound abstract name: the daemon's answer comes back to it. */
	if (fd < 0 || bind(fd, (struct sockaddr *)&self, sizeof(sa_family_t)) < 0) {
		if (fd >= 0)
			close(fd);
		return -1;
	}
	if (sendto(fd, text, strlen(text), 0, (struct sockaddr *)&a, len) < 0) {
		close(fd);
		return -1;
	}
	struct pollfd p = { .fd = fd, .events = POLLIN };
	ssize_t n = poll(&p, 1, 2000) > 0 ? recv(fd, reply, size - 1, 0) : -1;
	close(fd);
	if (n < 0)
		return -2;
	reply[n] = 0;
	return 0;
}

int main(int argc, char **argv)
{
	if (argc < 2)
		return serve();
	char text[128] = "", reply[64];
	for (int i = 1; i < argc; i++)
		if (snprintf(text + strlen(text), sizeof text - strlen(text), "%s%s", i > 1 ? " " : "", argv[i]) < 0)
			return 1;
	int asked = ask(text, reply, sizeof reply);
	if (asked < 0) {
		fprintf(stderr, "archr-levels: %s %s (archr-levels.service)\n",
			asked == -1 ? "the daemon is not running on" : "no answer from", socket_path());
		return 1;
	}
	if (!strcmp(reply, "error")) {
		fprintf(stderr, "usage: archr-levels [volume|brightness[N] [N|+N|-N|restore|hold up|down] [osd] [seq] | renew | release]\n");
		return 1;
	}
	if (strcmp(argv[1], "release") && strcmp(argv[1], "renew"))
		puts(reply);
	return 0;
}
