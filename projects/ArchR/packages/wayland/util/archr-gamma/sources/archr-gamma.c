// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026-present ArchR (https://github.com/archr-linux/Arch-R)
//
// archr-gamma: holds the panel's gamma curve through sway
// (wlr-gamma-control-unstable-v1) for as long as it runs; the compositor
// drops the curve when the client goes. The curve comes from system.cfg:
//
//   display.gamma        0.50 to 2.00 (1.00 = the panel as it is)
//   display.temperature  2500 to 6500 K (6500 = neutral)
//
// SIGHUP reads them again and applies at once, so Settings can show each
// step while the user moves the value. At 1.00 and 6500 K it holds no
// curve at all: the panel's gamma table stays off, as without this program.
#define _GNU_SOURCE
#include <errno.h>
#include <math.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <wayland-client.h>

#include "wlr-gamma-control-unstable-v1-client-protocol.h"

#define MAX_OUTPUTS 4

static const char *config = "/storage/.config/system/configs/system.cfg";

struct output {
	struct wl_output *wl;
	struct zwlr_gamma_control_v1 *control;
	uint32_t size;
	int failed;
};

static struct zwlr_gamma_control_manager_v1 *manager;
static struct output outputs[MAX_OUTPUTS];
static int noutputs;
static volatile sig_atomic_t reload = 1;

static double gamma_value = 1.0;
static int temperature = 6500;

// sway's socket appears a moment after its unit starts: wait for it rather
// than fail the boot (and its error report) for being early.
static struct wl_display *connect_compositor(int seconds) {
	struct timespec pause = {0, 250 * 1000 * 1000};
	for (int n = 0; n < seconds * 4; n++) {
		struct wl_display *display = wl_display_connect(NULL);
		if (display)
			return display;
		nanosleep(&pause, NULL);
	}
	return NULL;
}

static void on_hup(int sig) {
	(void)sig;
	reload = 1;
}

// The last value of KEY in system.cfg, or NULL.
static char *setting(const char *key, char *buf, size_t len) {
	FILE *f = fopen(config, "r");
	char line[256];
	size_t klen = strlen(key);
	int found = 0;
	if (!f)
		return NULL;
	while (fgets(line, sizeof(line), f)) {
		if (strncmp(line, key, klen) == 0 && line[klen] == '=') {
			snprintf(buf, len, "%s", line + klen + 1);
			buf[strcspn(buf, "\r\n")] = 0;
			found = 1;
		}
	}
	fclose(f);
	return found ? buf : NULL;
}

static void read_settings(void) {
	char buf[64];
	char *end;
	gamma_value = 1.0;
	temperature = 6500;
	if (setting("display.gamma", buf, sizeof(buf))) {
		double g = strtod(buf, &end);
		if (end != buf && g >= 0.5 && g <= 2.0)
			gamma_value = g;
	}
	if (setting("display.temperature", buf, sizeof(buf))) {
		long t = strtol(buf, &end, 10);
		if (end != buf && t >= 2500 && t <= 6500)
			temperature = (int)t;
	}
}

// The white point of a colour temperature, each channel 0..1 (the usual
// blackbody fit), 6500 K and above being plain white.
static void white_point(int kelvin, double rgb[3]) {
	double t = kelvin / 100.0;
	if (kelvin >= 6500) {
		rgb[0] = rgb[1] = rgb[2] = 1;
		return;
	}
	rgb[0] = 255;
	rgb[1] = 99.4708025861 * log(t) - 161.1195681661;
	rgb[2] = t <= 19 ? 0 : 138.5177312231 * log(t - 10) - 305.0447927307;
	for (int i = 0; i < 3; i++) {
		rgb[i] /= 255.0;
		if (rgb[i] < 0)
			rgb[i] = 0;
		if (rgb[i] > 1)
			rgb[i] = 1;
	}
}

static int apply(struct output *o) {
	size_t bytes = (size_t)o->size * 3 * sizeof(uint16_t);
	int fd = memfd_create("archr-gamma", MFD_CLOEXEC);
	uint16_t *ramp;
	double white[3];
	if (fd < 0)
		return -1;
	if (ftruncate(fd, (off_t)bytes) < 0) {
		close(fd);
		return -1;
	}
	ramp = mmap(NULL, bytes, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
	if (ramp == MAP_FAILED) {
		close(fd);
		return -1;
	}
	white_point(temperature, white);
	for (uint32_t i = 0; i < o->size; i++) {
		double v = o->size > 1 ? (double)i / (o->size - 1) : 1.0;
		v = pow(v, 1.0 / gamma_value);
		for (int c = 0; c < 3; c++) {
			double out = v * white[c] * 65535.0;
			ramp[c * o->size + i] = (uint16_t)(out < 0 ? 0 : out > 65535 ? 65535 : out);
		}
	}
	munmap(ramp, bytes);
	zwlr_gamma_control_v1_set_gamma(o->control, fd);
	close(fd);
	return 0;
}

static void gamma_size(void *data, struct zwlr_gamma_control_v1 *c, uint32_t size) {
	(void)c;
	((struct output *)data)->size = size;
}

static void gamma_failed(void *data, struct zwlr_gamma_control_v1 *c) {
	(void)c;
	((struct output *)data)->failed = 1;
	fprintf(stderr, "archr-gamma: the compositor refused the gamma curve\n");
}

static const struct zwlr_gamma_control_v1_listener gamma_listener = {
	.gamma_size = gamma_size,
	.failed = gamma_failed,
};

static void global(void *data, struct wl_registry *r, uint32_t name, const char *iface, uint32_t version) {
	(void)data;
	(void)version;
	if (strcmp(iface, zwlr_gamma_control_manager_v1_interface.name) == 0)
		manager = wl_registry_bind(r, name, &zwlr_gamma_control_manager_v1_interface, 1);
	else if (strcmp(iface, wl_output_interface.name) == 0 && noutputs < MAX_OUTPUTS)
		outputs[noutputs++].wl = wl_registry_bind(r, name, &wl_output_interface, 1);
}

static void global_remove(void *data, struct wl_registry *r, uint32_t name) {
	(void)data;
	(void)r;
	(void)name;
}

static const struct wl_registry_listener registry_listener = {
	.global = global,
	.global_remove = global_remove,
};

int main(int argc, char **argv) {
	struct wl_display *display;
	struct sigaction sa = {0};
	if (argc > 1)
		config = argv[1];
	sa.sa_handler = on_hup;
	sigaction(SIGHUP, &sa, NULL);

	display = connect_compositor(60);
	if (!display) {
		fprintf(stderr, "archr-gamma: no compositor\n");
		return 1;
	}
	wl_registry_add_listener(wl_display_get_registry(display), &registry_listener, NULL);
	wl_display_roundtrip(display);
	if (!manager || noutputs == 0) {
		fprintf(stderr, "archr-gamma: the compositor has no gamma control\n");
		return 1;
	}
	for (;;) {
		struct pollfd pfd = {.fd = wl_display_get_fd(display), .events = POLLIN};
		if (reload) {
			int ok = 0;
			reload = 0;
			read_settings();
			if (gamma_value == 1.0 && temperature >= 6500) {
				// The panel as it is: let go of the curve.
				for (int i = 0; i < noutputs; i++) {
					if (outputs[i].control)
						zwlr_gamma_control_v1_destroy(outputs[i].control);
					outputs[i].control = NULL;
					outputs[i].size = 0;
					outputs[i].failed = 0;
				}
				wl_display_flush(display);
				fprintf(stderr, "archr-gamma: default curve, nothing held\n");
			} else {
				int asked = 0;
				for (int i = 0; i < noutputs; i++) {
					if (outputs[i].control)
						continue;
					outputs[i].control = zwlr_gamma_control_manager_v1_get_gamma_control(manager, outputs[i].wl);
					zwlr_gamma_control_v1_add_listener(outputs[i].control, &gamma_listener, &outputs[i]);
					asked = 1;
				}
				if (asked)
					wl_display_roundtrip(display);
				for (int i = 0; i < noutputs; i++)
					if (outputs[i].control && !outputs[i].failed && outputs[i].size > 0 && apply(&outputs[i]) == 0)
						ok++;
				wl_display_flush(display);
				if (ok == 0) {
					fprintf(stderr, "archr-gamma: no output takes a gamma curve\n");
					return 1;
				}
				fprintf(stderr, "archr-gamma: gamma %.2f, %d K\n", gamma_value, temperature);
			}
		}
		if (poll(&pfd, 1, -1) < 0) {
			if (errno == EINTR)
				continue;
			return 1;
		}
		if (wl_display_dispatch(display) < 0)
			return 1;
	}
}
