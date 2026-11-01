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
//   archr-levels release
//
// KIND is volume, brightness (first backlight) or brightnessN (the Nth).
// A level is what the user sees: volume follows a decibel scale and the
// backlight a 2.2 gamma above a legible minimum, so every step feels the
// same size. The daemon keeps one PulseAudio connection (a step costs one
// round trip, not a process) and writes system.cfg once a level settles.
// Commands only talk to the daemon (systemd restarts it): without it they
// fail with a clear message instead of racing it for system.cfg.
//
// Hold speed, shared with the launcher's sliders: TAP on the press, then
// after HOLD_DELAY_MS 25 %/s, 50 %/s past 950 ms and 75 %/s past 1550 ms.
#define _GNU_SOURCE
#include <dirent.h>
#include <dlfcn.h>
#include <errno.h>
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
	HOLD_MAX_MS = 8000,
	SETTLE_MS = 1500,
	SCREENS = 9,
	BRIGHTNESS_MIN = 5,
};
static const double VOLUME_RANGE_DB = 50.0, GAMMA = 2.2;

extern char **environ;

struct level {
	char key[24];
	int screen; /* 0: volume, else the backlight's number */
	int value, saved;
};
static struct level levels[1 + SCREENS];
static int savers; /* writes to system.cfg still running */

static struct {
	struct level *level;
	int dir, show;
	long start, next;
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
	else if (!strncmp(kind, "brightness", 10) && kind[10] >= '2' && kind[10] <= '9' && !kind[11])
		screen = kind[10] - '0';
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
			snprintf(l->key, sizeof l->key, "display.brightness%d", screen);
		l->value = l->saved = read_saved(l);
	} else if (l->value == l->saved && hold.level != l && !savers) {
		/* Settled: the file is the truth (a reset or a restore may have changed it). */
		l->value = l->saved = read_saved(l);
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
	X(pa_context_set_sink_volume_by_name) X(pa_operation_unref) X(pa_sw_volume_from_dB) X(pa_cvolume_set)
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

static void push_volume(void);

/* One change in flight: the newest level goes out when the last is done. */
static void sink_set(pa_context *c, int ok, void *u)
{
	(void)c, (void)ok, (void)u;
	if (--busy == 0 && queued)
		push_volume();
}

/* A one-channel volume sets every channel of whichever sink is the default. */
static void push_volume(void)
{
	pa_cvolume cv;
	dl_pa_cvolume_set(&cv, 1, target);
	pa_operation *op = dl_pa_context_set_sink_volume_by_name(ctx, "@DEFAULT_SINK@", &cv, sink_set, NULL);
	queued = 0;
	if (op) {
		busy++;
		dl_pa_operation_unref(op);
	}
}

static void state_changed(pa_context *c, void *u)
{
	(void)u;
	pa_context_state_t s = dl_pa_context_get_state(c);
	if (s == PA_CONTEXT_READY && queued)
		push_volume();
	else if (!PA_CONTEXT_IS_GOOD(s))
		busy = 0;
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
	} else if (!PA_CONTEXT_IS_GOOD(s)) {
		if (ctx)
			dl_pa_context_unref(ctx);
		ctx = dl_pa_context_new(dl_pa_threaded_mainloop_get_api(ml), "archr-levels");
		if (ctx) {
			dl_pa_context_set_state_callback(ctx, state_changed, NULL);
			if (dl_pa_context_connect(ctx, NULL, PA_CONTEXT_NOAUTOSPAWN, NULL) < 0)
				queued = 0;
		}
	}
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

static void osd(const struct level *l)
{
	struct sockaddr_un to = { .sun_family = AF_UNIX };
	snprintf(to.sun_path, sizeof to.sun_path, "%s/archr-osd.sock", env_or("XDG_RUNTIME_DIR", "/run"));
	char text[32];
	int n = snprintf(text, sizeof text, "%s %d", l->screen ? "brightness" : "volume", l->value);
	int fd = socket(AF_UNIX, SOCK_DGRAM | SOCK_CLOEXEC | SOCK_NONBLOCK, 0);
	if (fd >= 0) {
		sendto(fd, text, n, 0, (struct sockaddr *)&to, sizeof to);
		close(fd);
	}
}

static int store(const char *key, int number, int wait)
{
	char value[8];
	snprintf(value, sizeof value, "%d", number);
	const char *saver = getenv("ARCHR_LEVELS_SAVER");
	char *custom[] = { (char *)saver, (char *)key, value, NULL };
	char *system[] = { "/bin/bash", "-c", ". /etc/profile.d/001-functions && set_setting \"$1\" \"$2\"",
			   "archr-levels", (char *)key, value, NULL };
	char **argv = saver ? custom : system;
	pid_t pid;
	if (posix_spawn(&pid, argv[0], NULL, NULL, argv, environ) != 0)
		return 0;
	if (wait)
		waitpid(pid, NULL, 0);
	else
		savers++;
	return 1;
}

static void save(struct level *l, int wait)
{
	if (l->key[0] && l->value != l->saved && store(l->key, l->value, wait))
		l->saved = l->value;
}

/* Levels saved before these curves (a linear backlight, PulseAudio's cubic
 * volume percent) are converted once, so screen and sound stay as they were. */
static void migrate(void)
{
	long old;
	if (!cfg_get("levels.perceptual", &old)) {
		static const char *kinds[] = { "volume", "brightness", "brightness2", "brightness3", "brightness4",
					       "brightness5", "brightness6", "brightness7", "brightness8", "brightness9" };
		for (size_t i = 0; i < sizeof kinds / sizeof *kinds; i++) {
			struct level *l = find(kinds[i]);
			if (!cfg_get(l->key, &old))
				continue;
			double f = old / 100.0;
			if (l->screen)
				old = lround(5 + 95 * pow(f > 0.05 ? (f - 0.05) / 0.95 : 0, 1 / GAMMA));
			else
				old = old <= 0 ? 0 : fmax(1, lround(100 + 100 * 60 * log10(f) / VOLUME_RANGE_DB));
			l->value = clamp(l, old);
			save(l, 1);
		}
		store("levels.perceptual", 1, 1);
	}
}

/* ---- commands ---- */

static void apply(struct level *l, long value, int show)
{
	l->value = clamp(l, value);
	if (l->screen)
		set_brightness(l->screen, l->value);
	else
		set_volume(l->value);
	if (show)
		osd(l);
}

/* Returns the level after the command, or -1 when it is malformed. */
static int command(char *text)
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
	struct level *l = n ? find(word[0]) : NULL;
	if (!l)
		return -1;
	int show = n > 1 && !strcmp(word[n - 1], "osd");
	n -= show;
	if (n == 1) {
		if (show)
			osd(l);
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
		hold.start = now, hold.next = now + HOLD_DELAY_MS;
		return l->value;
	}
	if (n != 2)
		return -1;
	char *end;
	errno = 0;
	long v = strtol(word[1], &end, 10);
	if (end == word[1] || *end || errno)
		return -1;
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
	apply(l, before + hold.dir * (held < 950 ? 1 : held < 1550 ? 2 : 3), hold.show);
	if (l->value == before || held > HOLD_MAX_MS)
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
	migrate();
	ready_for_systemd();
	struct sigaction sa = { .sa_handler = stop };
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);
	long settle = 0;
	while (!stopping) {
		long now = now_ms(), wake = -1;
		if (hold.level)
			wake = hold.next;
		if (settle && (wake < 0 || settle < wake))
			wake = settle;
		struct pollfd p = { .fd = fd, .events = POLLIN };
		int ready = poll(&p, 1, wake < 0 ? -1 : wake > now ? (int)(wake - now) : 0);
		while (savers && waitpid(-1, NULL, WNOHANG) > 0)
			savers--;
		now = now_ms();
		if (ready > 0) {
			char text[128];
			struct sockaddr_un from;
			socklen_t from_len = sizeof from;
			ssize_t n = recvfrom(fd, text, sizeof text - 1, 0, (struct sockaddr *)&from, &from_len);
			if (n >= 0) {
				text[n] = 0;
				int level = command(text);
				char reply[16];
				int r = level < 0 ? snprintf(reply, sizeof reply, "error") : snprintf(reply, sizeof reply, "%d", level);
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
			for (int i = 0; i <= SCREENS; i++)
				save(&levels[i], 0);
			settle = 0;
		}
	}
	for (int i = 0; i <= SCREENS; i++)
		save(&levels[i], 1);
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
	char text[128] = "", reply[16];
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
		fprintf(stderr, "usage: archr-levels [volume|brightness[N] [N|+N|-N|restore|hold up|down] [osd] | release]\n");
		return 1;
	}
	if (strcmp(argv[1], "release"))
		puts(reply);
	return 0;
}
