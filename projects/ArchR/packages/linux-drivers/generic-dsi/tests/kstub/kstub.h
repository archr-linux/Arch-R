/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Just enough of the kernel API to compile panel-generic-dsi.c as a
 * userspace program. The DSI and DRM calls record what the driver does
 * (see harness.c); the string helpers follow lib/cmdline.c, lib/kstrtox.c,
 * lib/hexdump.c and lib/string_helpers.c of the kernel the project builds.
 */
#ifndef KSTUB_H
#define KSTUB_H

#include <ctype.h>
#include <errno.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef uint8_t u8;
typedef uint32_t u32;
typedef int gfp_t;
#define GFP_KERNEL 0
#define __must_check

#define container_of(ptr, type, member) \
	((type *)((char *)(ptr) - offsetof(type, member)))

/* ---- recording, implemented in harness.c ---------------------------- */
void rec(const char *fmt, ...);
void klog(const char *level, const char *fmt, ...);
int rec_write(const u8 *data, size_t len);

/* ---- memory --------------------------------------------------------- */
struct device_node {
	const char **lines;
	int nlines;
};

struct device {
	struct device_node *of_node;
	void *drvdata;
};

static inline void *devm_kzalloc(struct device *dev, size_t size, gfp_t gfp)
{
	(void)dev; (void)gfp;
	return calloc(1, size ? size : 1);
}
static inline char *kstrdup(const char *s, gfp_t gfp) { (void)gfp; return strdup(s); }
static inline void kfree(const void *p) { free((void *)p); }

#define dev_info(dev, ...) klog("info", __VA_ARGS__)
#define dev_warn(dev, ...) klog("warn", __VA_ARGS__)
#define dev_err(dev, ...)  klog("err", __VA_ARGS__)
#define dev_dbg(dev, ...)  do { (void)(dev); } while (0)

static inline void msleep(unsigned int ms) { rec("sleep %u", ms); }

/* ---- lib/string.c, lib/string_helpers.c ----------------------------- */
static inline char *skip_spaces(const char *str)
{
	while (isspace((unsigned char)*str))
		++str;
	return (char *)str;
}

static inline char *strim(char *s)
{
	size_t size;
	char *end;

	size = strlen(s);
	if (!size)
		return s;
	end = s + size - 1;
	while (end >= s && isspace((unsigned char)*end))
		end--;
	*(end + 1) = '\0';
	return skip_spaces(s);
}

/* ---- lib/vsprintf.c, lib/kstrtox.c ---------------------------------- */
static inline unsigned long long simple_strtoull(const char *cp, char **endp, unsigned int base)
{
	return strtoull(cp, endp, base);
}
static inline unsigned long simple_strtoul(const char *cp, char **endp, unsigned int base)
{
	return strtoul(cp, endp, base);
}
static inline long simple_strtol(const char *cp, char **endp, unsigned int base)
{
	return strtol(cp, endp, base);
}

/* kstrtouint: whole string must be a number, one trailing newline allowed. */
static inline int kstrtouint(const char *s, unsigned int base, unsigned int *res)
{
	unsigned long long v = 0;
	const char *p = s;

	if (*p == '+')
		p++;
	if (base == 16 && p[0] == '0' && (p[1] == 'x' || p[1] == 'X'))
		p += 2;
	if (base == 0) {
		if (p[0] == '0' && (p[1] == 'x' || p[1] == 'X')) { base = 16; p += 2; }
		else if (p[0] == '0') base = 8;
		else base = 10;
	}
	if (!*p || *p == '\n')
		return -EINVAL;
	for (; *p && *p != '\n'; p++) {
		unsigned int d;

		if (*p >= '0' && *p <= '9') d = *p - '0';
		else if (*p >= 'a' && *p <= 'f') d = *p - 'a' + 10;
		else if (*p >= 'A' && *p <= 'F') d = *p - 'A' + 10;
		else return -EINVAL;
		if (d >= base)
			return -EINVAL;
		v = v * base + d;
		if (v > 0xffffffffULL)
			return -ERANGE;
	}
	if (*p == '\n' && p[1])
		return -EINVAL;
	*res = (unsigned int)v;
	return 0;
}

/* ---- lib/hexdump.c -------------------------------------------------- */
static inline int hex_to_bin(unsigned char ch)
{
	if (ch >= '0' && ch <= '9') return ch - '0';
	ch = tolower(ch);
	if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
	return -1;
}
static inline int hex2bin(u8 *dst, const char *src, size_t count)
{
	while (count--) {
		int hi, lo;

		hi = hex_to_bin(*src++);
		if (hi < 0)
			return -EINVAL;
		lo = hex_to_bin(*src++);
		if (lo < 0)
			return -EINVAL;
		*dst++ = (hi << 4) | lo;
	}
	return 0;
}

/* ---- lib/cmdline.c -------------------------------------------------- */
static inline int get_range(char **str, int *pint, int n)
{
	int x, inc_counter, upper_range;

	(*str)++;
	upper_range = simple_strtol((*str), NULL, 0);
	inc_counter = upper_range - *pint;
	for (x = *pint; n && x < upper_range; x++, n--)
		*pint++ = x;
	return inc_counter;
}

static inline int get_option(char **str, int *pint)
{
	char *cur = *str;
	int value;

	if (!cur || !(*cur))
		return 0;
	if (*cur == '-')
		value = -simple_strtoull(++cur, str, 0);
	else
		value = simple_strtoull(cur, str, 0);
	if (pint)
		*pint = value;
	if (cur == *str)
		return 0;
	if (**str == ',') {
		(*str)++;
		return 2;
	}
	if (**str == '-')
		return 3;
	return 1;
}

static inline char *get_options(const char *str, int nints, int *ints)
{
	bool validate = (nints == 0);
	int res, i = 1;

	while (i < nints || validate) {
		int *pint = validate ? ints : ints + i;

		res = get_option((char **)&str, pint);
		if (res == 0)
			break;
		if (res == 3) {
			int n = validate ? 0 : nints - i;
			int range_nums;

			range_nums = get_range((char **)&str, pint, n);
			if (range_nums < 0)
				break;
			i += (range_nums - 1);
		}
		i++;
		if (res == 1)
			break;
	}
	ints[0] = i - 1;
	return (char *)str;
}

static inline char *next_arg(char *args, char **param, char **val)
{
	unsigned int i, equals = 0;
	int in_quote = 0, quoted = 0;

	if (*args == '"') {
		args++;
		in_quote = 1;
		quoted = 1;
	}

	for (i = 0; args[i]; i++) {
		if (isspace((unsigned char)args[i]) && !in_quote)
			break;
		if (equals == 0) {
			if (args[i] == '=')
				equals = i;
		}
		if (args[i] == '"')
			in_quote = !in_quote;
	}

	*param = args;
	if (!equals)
		*val = NULL;
	else {
		args[equals] = '\0';
		*val = args + equals + 1;
		if (**val == '"') {
			(*val)++;
			if (args[i-1] == '"')
				args[i-1] = '\0';
		}
	}
	if (quoted && i > 0 && args[i-1] == '"')
		args[i-1] = '\0';

	if (args[i]) {
		args[i] = '\0';
		args += i + 1;
	} else
		args += i;

	return skip_spaces(args);
}

/* ---- module glue ---------------------------------------------------- */
#define module_param(name, type, perm)
#define MODULE_PARM_DESC(name, desc)
#define MODULE_DEVICE_TABLE(type, name)
#define MODULE_AUTHOR(x)
#define MODULE_DESCRIPTION(x)
#define MODULE_LICENSE(x)
#define module_mipi_dsi_driver(drv)

struct of_device_id { const char *compatible; };

/* ---- errors --------------------------------------------------------- */
#define MAX_ERRNO 4095
#define IS_ERR(p) ((unsigned long)(p) >= (unsigned long)-MAX_ERRNO)
#define PTR_ERR(p) ((long)(p))
#ifndef EPROBE_DEFER
#define EPROBE_DEFER 517
#endif

/* ---- gpio, regulator, firmware, of ---------------------------------- */
struct gpio_desc { int value; };
enum gpiod_flags { GPIOD_OUT_LOW };
static struct gpio_desc stub_reset_gpio, stub_enable_gpio;
static inline struct gpio_desc *devm_gpiod_get_optional(struct device *dev, const char *id, enum gpiod_flags f)
{
	(void)dev; (void)f;
	return strcmp(id, "reset") == 0 ? &stub_reset_gpio : &stub_enable_gpio;
}
static inline void gpiod_set_value_cansleep(struct gpio_desc *d, int v)
{
	d->value = v;
	rec("gpio %s %d", d == &stub_reset_gpio ? "reset" : "enable", v);
}

struct regulator { int count; };
static struct regulator stub_vdd, stub_iovcc;
static inline struct regulator *devm_regulator_get(struct device *dev, const char *id)
{
	(void)dev;
	return strcmp(id, "vdd") == 0 ? &stub_vdd : &stub_iovcc;
}
static inline int regulator_enable(struct regulator *r) { r->count++; return 0; }
static inline int regulator_disable(struct regulator *r) { r->count--; return 0; }

struct firmware { size_t size; const u8 *data; };
static inline int request_firmware(const struct firmware **fw, const char *name, struct device *dev)
{
	(void)fw; (void)name; (void)dev;
	return -ENOENT;
}
static inline void release_firmware(const struct firmware *fw) { (void)fw; }

static inline int of_property_count_strings(const struct device_node *np, const char *name)
{
	(void)name;
	return np->nlines;
}
static inline int of_property_read_string_index(const struct device_node *np, const char *name,
		int index, const char **out)
{
	(void)name;
	if (index >= np->nlines)
		return -ENODATA;
	*out = np->lines[index];
	return 0;
}

/* ---- video ---------------------------------------------------------- */
struct timing_entry { u32 min, typ, max; };
struct display_timing { struct timing_entry hactive, vactive; };
struct videomode { int unused; };
static inline int of_get_display_timing(const struct device_node *np, const char *name, struct display_timing *dt)
{
	(void)np; (void)name; (void)dt;
	return -ENOENT;
}
static inline void videomode_from_timing(const struct display_timing *dt, struct videomode *vm) { (void)dt; (void)vm; }

#define MIPI_DCS_ENTER_SLEEP_MODE 0x10
#define MIPI_DCS_EXIT_SLEEP_MODE  0x11
#define MIPI_DCS_SET_DISPLAY_OFF  0x28
#define MIPI_DCS_SET_DISPLAY_ON   0x29

/* ---- mipi dsi ------------------------------------------------------- */
enum mipi_dsi_pixel_format {
	MIPI_DSI_FMT_RGB888, MIPI_DSI_FMT_RGB666, MIPI_DSI_FMT_RGB666_PACKED, MIPI_DSI_FMT_RGB565,
};
#define MIPI_DSI_MODE_VIDEO           (1UL << 0)
#define MIPI_DSI_MODE_VIDEO_BURST     (1UL << 1)
#define MIPI_DSI_MODE_NO_EOT_PACKET   (1UL << 9)
#define MIPI_DSI_CLOCK_NON_CONTINUOUS (1UL << 10)
#define MIPI_DSI_MODE_LPM             (1UL << 11)

struct mipi_dsi_device {
	struct device dev;
	unsigned int lanes;
	enum mipi_dsi_pixel_format format;
	unsigned long mode_flags;
};
#define to_mipi_dsi_device(d) container_of(d, struct mipi_dsi_device, dev)
static inline void mipi_dsi_set_drvdata(struct mipi_dsi_device *dsi, void *data) { dsi->dev.drvdata = data; }
static inline void *mipi_dsi_get_drvdata(struct mipi_dsi_device *dsi) { return dsi->dev.drvdata; }
static inline int mipi_dsi_attach(struct mipi_dsi_device *dsi) { (void)dsi; return 0; }
static inline int mipi_dsi_detach(struct mipi_dsi_device *dsi) { (void)dsi; return 0; }

static inline long mipi_dsi_dcs_write_buffer(struct mipi_dsi_device *dsi, const void *data, size_t len)
{
	(void)dsi;
	return rec_write(data, len);
}
static inline long mipi_dsi_dcs_write(struct mipi_dsi_device *dsi, u8 cmd, const void *data, size_t len)
{
	u8 buf[256];

	(void)dsi;
	buf[0] = cmd;
	if (len > sizeof(buf) - 1)
		return -EINVAL;
	if (len)
		memcpy(buf + 1, data, len);
	return rec_write(buf, len + 1);
}
static inline int mipi_dsi_dcs_cmd(u8 cmd) { return rec_write(&cmd, 1); }
static inline int mipi_dsi_dcs_exit_sleep_mode(struct mipi_dsi_device *dsi) { (void)dsi; return mipi_dsi_dcs_cmd(MIPI_DCS_EXIT_SLEEP_MODE); }
static inline int mipi_dsi_dcs_enter_sleep_mode(struct mipi_dsi_device *dsi) { (void)dsi; return mipi_dsi_dcs_cmd(MIPI_DCS_ENTER_SLEEP_MODE); }
static inline int mipi_dsi_dcs_set_display_on(struct mipi_dsi_device *dsi) { (void)dsi; return mipi_dsi_dcs_cmd(MIPI_DCS_SET_DISPLAY_ON); }
static inline int mipi_dsi_dcs_set_display_off(struct mipi_dsi_device *dsi) { (void)dsi; return mipi_dsi_dcs_cmd(MIPI_DCS_SET_DISPLAY_OFF); }
static inline long mipi_dsi_generic_read(struct mipi_dsi_device *dsi, const void *params, size_t n,
		void *data, size_t size)
{
	(void)dsi; (void)params; (void)n; (void)data; (void)size;
	rec("read");
	return 0;
}

struct mipi_dsi_driver {
	struct { const char *name; const struct of_device_id *of_match_table; } driver;
	int (*probe)(struct mipi_dsi_device *dsi);
	void (*remove)(struct mipi_dsi_device *dsi);
	void (*shutdown)(struct mipi_dsi_device *dsi);
};

/* ---- drm ------------------------------------------------------------ */
#define DRM_MODE_FLAG_PHSYNC (1 << 0)
#define DRM_MODE_FLAG_NHSYNC (1 << 1)
#define DRM_MODE_FLAG_PVSYNC (1 << 2)
#define DRM_MODE_FLAG_NVSYNC (1 << 3)
#define DRM_MODE_TYPE_PREFERRED (1 << 3)
#define DRM_MODE_TYPE_DRIVER    (1 << 6)
#define DRM_MODE_CONNECTOR_DSI 16

enum drm_panel_orientation { DRM_MODE_PANEL_ORIENTATION_UNKNOWN = -1 };

struct drm_device { int unused; };
struct drm_display_mode {
	int clock;
	int hdisplay, hsync_start, hsync_end, htotal;
	int vdisplay, vsync_start, vsync_end, vtotal;
	int width_mm, height_mm;
	unsigned int flags, type;
};
struct drm_connector {
	struct drm_device *dev;
	struct { unsigned int width_mm, height_mm; } display_info;
};
struct drm_panel;
struct drm_panel_funcs {
	int (*unprepare)(struct drm_panel *panel);
	int (*prepare)(struct drm_panel *panel);
	int (*get_modes)(struct drm_panel *panel, struct drm_connector *connector);
	enum drm_panel_orientation (*get_orientation)(struct drm_panel *panel);
};
struct drm_panel { const struct drm_panel_funcs *funcs; struct device *dev; };

void rec_mode(const struct drm_display_mode *mode);

static inline struct drm_display_mode *drm_mode_create(struct drm_device *dev) { (void)dev; return calloc(1, sizeof(struct drm_display_mode)); }
static inline struct drm_display_mode *drm_mode_duplicate(struct drm_device *dev, const struct drm_display_mode *m)
{
	struct drm_display_mode *n = drm_mode_create(dev);

	*n = *m;
	return n;
}
static inline void drm_mode_set_name(struct drm_display_mode *m) { (void)m; }
static inline int drm_mode_vrefresh(const struct drm_display_mode *m) { (void)m; return 0; }
static inline void drm_mode_probed_add(struct drm_connector *c, struct drm_display_mode *m) { (void)c; rec_mode(m); free(m); }
static inline void drm_display_mode_from_videomode(const struct videomode *vm, struct drm_display_mode *m) { (void)vm; (void)m; }
static inline int drm_connector_set_panel_orientation(struct drm_connector *c, enum drm_panel_orientation o) { (void)c; (void)o; return 0; }
static inline int of_drm_get_panel_orientation(const struct device_node *np, enum drm_panel_orientation *o)
{
	(void)np;
	*o = DRM_MODE_PANEL_ORIENTATION_UNKNOWN;
	return 0;
}
static inline void drm_panel_init(struct drm_panel *p, struct device *dev, const struct drm_panel_funcs *f, int type)
{
	(void)type;
	p->funcs = f;
	p->dev = dev;
}
static inline int drm_panel_of_backlight(struct drm_panel *p) { (void)p; return 0; }
static inline void drm_panel_add(struct drm_panel *p) { (void)p; }
static inline void drm_panel_remove(struct drm_panel *p) { (void)p; }
static inline int drm_panel_unprepare(struct drm_panel *p) { return p->funcs->unprepare(p); }
static inline int drm_panel_disable(struct drm_panel *p) { (void)p; return 0; }

#endif /* KSTUB_H */
