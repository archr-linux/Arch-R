// SPDX-License-Identifier: GPL-2.0
/*
 * Generic MIPI-DSI panel driver
 * Copyright (C) 2024 ArchR
 *
 * based on
 *
 * Rockteck jh057n00900 5.5" MIPI-DSI panel driver
 * Copyright (C) Purism SPC 2019
 */

#include <linux/delay.h>
#include <linux/gpio/consumer.h>
#include <linux/media-bus-format.h>
#include <linux/module.h>
#include <linux/firmware.h>
#include <linux/of.h>
#include <linux/regulator/consumer.h>

#include <video/display_timing.h>
#include <video/mipi_display.h>
#include <video/of_display_timing.h>
#include <video/videomode.h>

#include <drm/drm_mipi_dsi.h>
#include <drm/drm_modes.h>
#include <drm/drm_panel.h>

#define DRIVER_NAME "panel-generic-dsi"

static char *descfile = "";
module_param(descfile,charp,0660);
MODULE_PARM_DESC(descfile, "Panel description filename in firmware dir");

struct generic_panel_delays {
    int prepare;
    int reset;
    int init;
    int enable;
    int ready;
};

struct generic_panel_size {
    int width;
    int height;
};

struct generic_panel_mode {
    int clock;
    int horizontal[5];
    int vertical[5];
    int is_default;
    int hsync_high;
    int vsync_high;
    struct generic_panel_mode *prev;
};

#define DCS_PSEUDO_CMD_SEQ 0x10000

/*
 * Upper bound for one wait= step. The longest wait any known sequence
 * needs is 0x250 = 592 ms (eeclone, kept from the old hex reading).
 */
#define GENERIC_PANEL_MAX_WAIT_MS 1000

/*
 * Time between exit_sleep_mode (0x11) and the next command when the
 * driver sends 0x11 itself. MIPI DCS asks for 5 ms; ST7703 and NV3051D
 * datasheets ask for 120 ms.
 */
#define GENERIC_PANEL_SLEEP_OUT_MS 120
struct generic_panel_init_seq {
    int dcs;
    int len;
    int read;
    int wait;
    u8 *data;
    struct generic_panel_init_seq *link;
};

struct generic_panel {
    struct device *dev;
    struct drm_panel panel;
    struct gpio_desc *enable_gpio;
    struct gpio_desc *reset_gpio;
    struct regulator *vdd;
    struct regulator *iovcc;

    struct generic_panel_delays delays;
    struct generic_panel_size size;
    struct generic_panel_mode *modes;
    struct generic_panel_init_seq *iseq;
    bool seq_has_exit_sleep;
    bool seq_has_display_on;
    struct display_timing *timings;
    uint32_t num_timings;

    enum drm_panel_orientation orientation;
    bool prepared;
};


int load_panel_description(struct mipi_dsi_device *dsi, struct generic_panel *ctx);
int load_panel_description_line(char *data, struct mipi_dsi_device *dsi, struct generic_panel *ctx);
int load_globals(char *data, struct mipi_dsi_device *dsi, struct generic_panel *ctx);
int load_mode(char *data, struct mipi_dsi_device *dsi, struct generic_panel *ctx);
int load_init_seq(char *data, struct mipi_dsi_device *dsi, struct generic_panel *ctx);



int load_globals(char *data, struct mipi_dsi_device *dsi, struct generic_panel *ctx) {
    struct device *dev = &dsi->dev;
    char *param, *val;
    while (*data) {
        data = next_arg(data, &param, &val);
        if (!val) continue;
        if (strcmp(param, "delays") == 0) {
            int delays[] = {0, 5, 1, 25, 120, 50};
            get_options(val, 6, delays);
            ctx->delays.prepare     = delays[1];
            ctx->delays.reset       = delays[2];
            ctx->delays.init        = delays[3];
            ctx->delays.enable      = delays[4];
            ctx->delays.ready       = delays[5];
        } else if (strcmp(param, "size") == 0) {
            int size[] = {0, -1, -1};
            get_options(val, 3, size);
            ctx->size.width         = size[1];
            ctx->size.height        = size[2];
        } else if (strcmp(param, "format") == 0) {
            if (strcmp(val, "rgb888") == 0) {
                dsi->format = MIPI_DSI_FMT_RGB888;
            } else if (strcmp(val, "rgb666") == 0) {
                dsi->format = MIPI_DSI_FMT_RGB666;
            } else if (strcmp(val, "rgb666_packed") == 0) {
                dsi->format = MIPI_DSI_FMT_RGB666_PACKED;
            } else if (strcmp(val, "rgb565") == 0) {
                dsi->format = MIPI_DSI_FMT_RGB565;
            } else {
                dev_err(dev, "bad format %s\n", val);
                return -EINVAL;
            }
        } else if (strcmp(param, "lanes") == 0) {
            if (get_option(&val, &dsi->lanes) == 0) {
                dev_err(dev, "bad lanes %s\n", val);
                return -EINVAL;
            }
        } else if (strcmp(param, "flags") == 0) {
            int flags;
            if (get_option(&val, &flags) == 0) {
                dev_err(dev, "bad flags %s\n", val);
                return -EINVAL;
            }
            dsi->mode_flags = flags;
        } else {
            /* Unknown keys are skipped so newer descriptions still load. */
            dev_warn(dev, "unknown G param %s, ignored\n", param);
        }
    }
    return 0;
}


int load_mode(char *data, struct mipi_dsi_device *dsi, struct generic_panel *ctx) {
    struct device *dev = &dsi->dev;
    struct generic_panel_mode *mode;
    char *param, *val;

    mode = devm_kzalloc(dev, sizeof(*mode), GFP_KERNEL);
    if (!mode)
        return -ENOMEM;

    while (*data) {
        data = next_arg(data, &param, &val);
        if (!val) continue;
        if (strcmp(param, "clock") == 0) {
            if (get_option(&val, &mode->clock) == 0) {
                dev_err(dev, "bad clock %s\n", val);
                return -EINVAL;
            }
        } else if (strcmp(param, "horizontal") == 0) {
            get_options(val, 5, &mode->horizontal[0]);
            if (mode->horizontal[0] != 4) {
                dev_err(dev, "horizontal needs 4 values: %s\n", val);
                return -EINVAL;
            }
        } else if (strcmp(param, "vertical") == 0) {
            get_options(val, 5, &mode->vertical[0]);
            if (mode->vertical[0] != 4) {
                dev_err(dev, "vertical needs 4 values: %s\n", val);
                return -EINVAL;
            }
        } else if (strcmp(param, "default") == 0) {
            get_option(&val, &mode->is_default);
        } else if (strcmp(param, "hsync-active") == 0) {
            get_option(&val, &mode->hsync_high);
        } else if (strcmp(param, "vsync-active") == 0) {
            get_option(&val, &mode->vsync_high);
        } else {
            dev_warn(dev, "unknown M param %s, ignored\n", param);
        }
    }

    if ((mode->clock > 5000) && (mode->vertical[1] > 0) && (mode->horizontal[1] > 0)) {
        mode->prev = ctx->modes;
        ctx->modes = mode;
        dev_dbg(dev, "Mode %d %d %d  %p -> %p\n", mode->clock, mode->vertical[1], mode->horizontal[1], mode, mode->prev);
        return 0;
    }
    dev_err(dev, "mode needs clock > 5000 kHz, horizontal and vertical\n");
    return -EINVAL;
}

/*
 * wait= is decimal milliseconds, or hex with a 0x prefix. Descriptions
 * written before this rule (decimal digits read as hex by older drivers)
 * were rewritten with 0x so that they keep their old timing.
 */
static int parse_wait(struct device *dev, const char *val, int *wait)
{
    unsigned int ms;
    int ret;

    if (val[0] == '0' && (val[1] == 'x' || val[1] == 'X'))
        ret = kstrtouint(val + 2, 16, &ms);
    else
        ret = kstrtouint(val, 10, &ms);
    if (ret) {
        dev_err(dev, "bad wait %s\n", val);
        return -EINVAL;
    }
    if (ms > GENERIC_PANEL_MAX_WAIT_MS) {
        dev_err(dev, "wait %s is %u ms, more than %d ms\n", val, ms, GENERIC_PANEL_MAX_WAIT_MS);
        return -EINVAL;
    }
    *wait = ms;
    return 0;
}

static int parse_hex_bytes(struct device *dev, const char *what, const char *val,
        u8 **out, int *len)
{
    size_t n = strlen(val);

    if (n == 0 || (n & 1)) {
        dev_err(dev, "bad %s %s: needs an even number of hex digits\n", what, val);
        return -EINVAL;
    }
    *len = n >> 1;
    *out = devm_kzalloc(dev, *len, GFP_KERNEL);
    if (!*out)
        return -ENOMEM;
    if (hex2bin(*out, val, *len) != 0) {
        dev_err(dev, "bad %s %s\n", what, val);
        return -EINVAL;
    }
    return 0;
}

int load_init_seq(char *data, struct mipi_dsi_device *dsi, struct generic_panel *ctx) {
    struct device *dev = &dsi->dev;
    struct generic_panel_init_seq *item;
    char *param, *val;

    unsigned int num;
    int ret;

    item = devm_kzalloc(dev, sizeof(*item), GFP_KERNEL);
    if (!item)
        return -ENOMEM;
    item->dcs = -1;
    item->len = 0;
    item->read = 0;
    item->wait = 0;

    while (*data) {
        data = next_arg(data, &param, &val);
        if (!val) continue;
        if (strcmp(param, "dcs") == 0) {
            if (kstrtouint(val, 16, &num) || num > 0xff) {
                dev_err(dev, "bad dcs %s\n", val);
                return -EINVAL;
            }
            item->dcs = num;
        } else if (strcmp(param, "data") == 0) {
            ret = parse_hex_bytes(dev, "data", val, &item->data, &item->len);
            if (ret)
                return ret;
        } else if (strcmp(param, "seq") == 0) {
            item->dcs = DCS_PSEUDO_CMD_SEQ;
            ret = parse_hex_bytes(dev, "seq", val, &item->data, &item->len);
            if (ret)
                return ret;
            dev_dbg(dev, "loaded seq len=%d %s\n", item->len, val);
        } else if (strcmp(param, "read") == 0) {
            if (kstrtouint(val, 16, &num)) {
                dev_err(dev, "bad read %s\n", val);
                return -EINVAL;
            }
            item->read = num;
        } else if (strcmp(param, "wait") == 0) {
            ret = parse_wait(dev, val, &item->wait);
            if (ret)
                return ret;
        } else {
            dev_warn(dev, "unknown I param %s, ignored\n", param);
        }
    }

    if (item->dcs < 0) {
        dev_err(dev, "init step needs seq= or dcs=\n");
        return -EINVAL;
    }

    item->link = ctx->iseq;
    ctx->iseq = item;
    return 0;
}

/*
 * data   is a null-terminated string of panel description
 */
int load_panel_description_line(char *data, struct mipi_dsi_device *dsi, struct generic_panel *ctx) {
    size_t pos;

    data = skip_spaces(data);
    for (pos = 0; data[pos] != 0; pos ++) {
        if ((data[pos] == '#') || data[pos] == '\n') {
            data[pos] = 0;
            break;
        }
    }
    data = strim(data);
    if (data[0] == 0) return 0;

    switch (data[0]) {
        case 'G':
            return load_globals(data+1, dsi, ctx);
        case 'M':
            return load_mode(data+1, dsi, ctx);
        case 'I':
            return load_init_seq(data+1, dsi, ctx);
        default:
            dev_err(&dsi->dev, "unknown line type '%c'\n", data[0]);
            return -EINVAL;
    }
}

int panel_description_foreach(struct mipi_dsi_device *dsi, struct generic_panel *ctx,
        int (*handle_line)(char*, struct mipi_dsi_device*, struct generic_panel*));

int panel_description_foreach(struct mipi_dsi_device *dsi, struct generic_panel *ctx,
        int (*handle_line)(char*, struct mipi_dsi_device*, struct generic_panel*))
{
    struct device *dev = &dsi->dev;
    const struct firmware *fw;
    int ret;

    if (strlen(descfile) > 0) {
        ret = request_firmware(&fw, descfile, dev);
        if (ret) {
            dev_err(dev, "No config file found (error=%d)\n", ret);
            return -1;
        }

        size_t pos = 0, size = fw->size;
        char *data = (char *)fw->data;

        while (pos < size) {
            while ((pos < size) && (data[pos] != '\n')) pos++;

            if (pos < size) pos++;
            data[pos - 1] = 0;

            ret = handle_line(data, dsi, ctx);
            if (ret < 0) {
                dev_err(dev, "%s: bad line \"%s\": %d\n", descfile, data, ret);
                release_firmware(fw);
                return ret;
            }

            data = &data[pos];
            size = size - pos;
            pos = 0;
        }

        release_firmware(fw);
    } else {
        //ret = of_drm_get_panel_orientation(dev->of_node, &ctx->orientation);
        const char *line;
        char * buf;
        size_t linescnt, i;

        linescnt = of_property_count_strings(dev->of_node, "panel_description");
        if (linescnt < 1) {
            dev_err(dev, "failed to read panel_description from device tree %ld\n", linescnt);
            return -1;
        }

        for (i = 0; i < linescnt; i++) {
            ret = of_property_read_string_index(dev->of_node, "panel_description", i, &line);
            if (ret < 0) {
                dev_err(dev, "failed to read panel_description[%ld] from device tree %d\n", i, ret);
                return -1;
            }
            buf = kstrdup(line, GFP_KERNEL);
            if (!buf) {
                dev_err(dev, "kstrdup(of desc line) failed\n");
                return -1;
            }

            dev_dbg(dev, "desc[%ld]: %s", i, line);
            ret = handle_line(buf, dsi, ctx);
            kfree(buf);
            if (ret < 0) {
                dev_err(dev, "panel_description[%ld] \"%s\": %d\n", i, line, ret);
                return ret;
            }
        }
    }
    return 0;
}

int load_panel_description(struct mipi_dsi_device *dsi, struct generic_panel *ctx) {
    int ret;

    ret = panel_description_foreach(dsi, ctx, &load_panel_description_line);
    if (ret < 0) { return ret; }

    // Reverse iseq
    struct generic_panel_init_seq *rev = ctx->iseq, *fwd = NULL, *tmp = NULL;
    while (rev) {
        tmp = rev;
        rev = tmp->link;
        tmp->link = fwd;
        fwd = tmp;
    }
    ctx->iseq = fwd;

    /*
     * Most vendor sequences already end with exit_sleep_mode (0x11) and
     * set_display_on (0x29). prepare() sends only the ones missing, so
     * they are neither repeated nor sent in the wrong order.
     */
    for (tmp = ctx->iseq; tmp; tmp = tmp->link) {
        int cmd;

        if (tmp->read > 0)
            continue;
        if (tmp->dcs == DCS_PSEUDO_CMD_SEQ)
            cmd = tmp->len > 0 ? tmp->data[0] : -1;
        else
            cmd = tmp->dcs;
        if (cmd == MIPI_DCS_EXIT_SLEEP_MODE)
            ctx->seq_has_exit_sleep = true;
        else if (cmd == MIPI_DCS_SET_DISPLAY_ON)
            ctx->seq_has_display_on = true;
    }
    dev_info(&dsi->dev, "exit_sleep from %s, display_on from %s\n",
             ctx->seq_has_exit_sleep ? "sequence" : "driver",
             ctx->seq_has_display_on ? "sequence" : "driver");

    return 0;
}


static inline struct generic_panel *panel_to_generic_panel(struct drm_panel *panel)
{
    return container_of(panel, struct generic_panel, panel);
}

static int generic_panel_init_sequence(struct generic_panel *ctx)
{
    struct mipi_dsi_device *dsi = to_mipi_dsi_device(ctx->dev);
    struct device *dev = ctx->dev;
    int ret;
    int step = 0;

    struct generic_panel_init_seq *iseq = ctx->iseq;
    while (iseq) {
        if (iseq->read > 0) {
            u8 readbuf[8];
            if (iseq->read > 8) { iseq->read = 8; }
            ret = mipi_dsi_generic_read(dsi, iseq->data, iseq->len, &readbuf[0], iseq->read);
            if (ret < 0) {
                dev_err(ctx->dev, "failed to read: %d\n", ret);
            } else {
                for (int i = 0; i < ret; i++) {
                    dev_info(ctx->dev, "read[%d]: %02x\n", i, readbuf[i]);
                }
            }
        } else {
            int cmd;

            if (iseq->dcs == DCS_PSEUDO_CMD_SEQ) {
                cmd = iseq->len > 0 ? iseq->data[0] : -1;
                ret = mipi_dsi_dcs_write_buffer(dsi, iseq->data, iseq->len);
            } else {
                cmd = iseq->dcs;
                ret = mipi_dsi_dcs_write(dsi, iseq->dcs, iseq->data, iseq->len);
            }
            dev_dbg(dev, "iseq %d cmd %02x len=%d -> %d\n", step, cmd, iseq->len, ret);
            if (ret < 0) {
                dev_err(dev, "init step %d (cmd 0x%02x, %d bytes) failed: %d\n",
                        step, cmd, iseq->len, ret);
                return ret;
            }
        }
        if (iseq->wait) {
            msleep(iseq->wait);
        }
        iseq = iseq->link;
        step++;
    }

    dev_dbg(dev, "Panel init sequence done\n");

    return 0;
}

static int generic_panel_unprepare(struct drm_panel *panel)
{
    struct generic_panel *ctx = panel_to_generic_panel(panel);
    struct mipi_dsi_device *dsi = to_mipi_dsi_device(ctx->dev);
    int ret;

    if (!ctx->prepared)
        return 0;

    /*
     * Both DCS writes below are best-effort: a failure here (DSI bus
     * busy/timeout, which is more likely to happen right as the rest of
     * the pipeline is changing state during suspend) must not abort the
     * power-down that follows. Bailing out here used to leave the panel
     * powered on with ctx->prepared still true, which also made the next
     * prepare() a no-op - so a single failed DCS write during suspend
     * could leave the screen stuck on/corrupted until reboot instead of
     * just for that one suspend cycle.
     */
    ret = mipi_dsi_dcs_set_display_off(dsi);
    if (ret < 0)
        dev_err(ctx->dev, "failed to set display off: %d\n", ret);

    ret = mipi_dsi_dcs_enter_sleep_mode(dsi);
    if (ret < 0)
        dev_err(ctx->dev, "failed to enter sleep mode: %d\n", ret);

    if (ctx->enable_gpio) { gpiod_set_value_cansleep(ctx->enable_gpio, 0); }
    gpiod_set_value_cansleep(ctx->reset_gpio, 1);

    regulator_disable(ctx->iovcc);
    regulator_disable(ctx->vdd);

    ctx->prepared = false;

    return 0;
}

static int generic_panel_prepare(struct drm_panel *panel)
{
    struct generic_panel *ctx = panel_to_generic_panel(panel);
    struct mipi_dsi_device *dsi = to_mipi_dsi_device(ctx->dev);
    int ret;

    if (ctx->prepared) {
        return 0;
    }

    ret = regulator_enable(ctx->vdd);
    if (ret < 0) {
        dev_err(ctx->dev, "Failed to enable vdd supply: %d\n", ret);
        return ret;
    }

    ret = regulator_enable(ctx->iovcc);
    if (ret < 0) {
        dev_err(ctx->dev, "Failed to enable iovcc supply: %d\n", ret);
        goto disable_vdd;
    }

    if (ctx->enable_gpio) { gpiod_set_value_cansleep(ctx->enable_gpio, 1); }
    msleep(ctx->delays.prepare);

    gpiod_set_value_cansleep(ctx->reset_gpio, 1);
    msleep(ctx->delays.reset);
    gpiod_set_value_cansleep(ctx->reset_gpio, 0);

    msleep(ctx->delays.init);

    ret = generic_panel_init_sequence(ctx);
    if (ret < 0) {
        dev_err(ctx->dev, "Panel init sequence failed: %d\n", ret);
        goto disable_iovcc;
    }

    if (!ctx->seq_has_exit_sleep) {
        ret = mipi_dsi_dcs_exit_sleep_mode(dsi);
        if (ret < 0) {
            dev_err(ctx->dev, "Failed to exit sleep mode: %d\n", ret);
            goto disable_iovcc;
        }
        msleep(GENERIC_PANEL_SLEEP_OUT_MS);
    }

    if (!ctx->seq_has_display_on) {
        ret = mipi_dsi_dcs_set_display_on(dsi);
        if (ret < 0) {
            dev_err(ctx->dev, "Failed to set display on: %d\n", ret);
            goto disable_iovcc;
        }
    }

    msleep(ctx->delays.enable);

    //msleep(ctx->delays.ready);

    ctx->prepared = true;

    return 0;

disable_iovcc:
    regulator_disable(ctx->iovcc);
disable_vdd:
    regulator_disable(ctx->vdd);
    return ret;
}

/* drm_display_mode template without clock as it is variable */
static const struct drm_display_mode mode_template = { };

static unsigned int panel_simple_get_timings_modes(struct generic_panel *ctx,
						   struct drm_connector *connector)
{
	struct drm_display_mode *mode;
	const struct display_timing *dt = ctx->timings;
	struct videomode vm;

	videomode_from_timing(dt, &vm);
	mode = drm_mode_create(connector->dev);
	if (!mode) {
		dev_err(ctx->dev, "failed to add mode %ux%u\n",
			dt->hactive.typ, dt->vactive.typ);
		return -EINVAL;
	}

	drm_display_mode_from_videomode(&vm, mode);

	mode->type |= DRM_MODE_TYPE_DRIVER;
	mode->type |= DRM_MODE_TYPE_PREFERRED;

	drm_mode_probed_add(connector, mode);

	return 0;
}

static int generic_panel_get_modes(struct drm_panel *panel,
                struct drm_connector *connector)
{
    struct generic_panel *ctx = panel_to_generic_panel(panel);
    struct drm_display_mode mode_tmp;
    struct drm_display_mode *mode;
    struct generic_panel_mode *genmode = ctx->modes;
    int ret;

    if (ctx->num_timings) {
	ret = panel_simple_get_timings_modes(ctx, connector);
	if (ret)
		return ret;
    }

    while (genmode) {
        dev_dbg(ctx->dev, "gen mode %d %dx%d\n", genmode->clock, genmode->horizontal[1], genmode->vertical[1]);

        mode_tmp = mode_template;

        mode_tmp.clock          = genmode->clock;

        mode_tmp.hdisplay       = genmode->horizontal[1];
        mode_tmp.hsync_start    = mode_tmp.hdisplay + genmode->horizontal[2];
        mode_tmp.hsync_end      = mode_tmp.hsync_start + genmode->horizontal[3];
        mode_tmp.htotal         = mode_tmp.hsync_end + genmode->horizontal[4];

        mode_tmp.vdisplay       = genmode->vertical[1];
        mode_tmp.vsync_start    = mode_tmp.vdisplay + genmode->vertical[2];
        mode_tmp.vsync_end      = mode_tmp.vsync_start + genmode->vertical[3];
        mode_tmp.vtotal         = mode_tmp.vsync_end + genmode->vertical[4];

        mode_tmp.width_mm       = ctx->size.width;
        mode_tmp.height_mm      = ctx->size.height;

        // Active-low sync unless the mode line says hsync-active=1 /
        // vsync-active=1. Every panel tested so far (R36s orig, new-3,
        // new-4; rgb10s) works with active-low.
        mode_tmp.flags          = (genmode->hsync_high ? DRM_MODE_FLAG_PHSYNC : DRM_MODE_FLAG_NHSYNC) |
                                  (genmode->vsync_high ? DRM_MODE_FLAG_PVSYNC : DRM_MODE_FLAG_NVSYNC);

        mode = drm_mode_duplicate(connector->dev, &mode_tmp);
        if (!mode) {
            dev_err(ctx->dev, "Failed to add mode %u\n",
                drm_mode_vrefresh(mode));
            return -ENOMEM;
        }
        drm_mode_set_name(mode);

        mode->type = DRM_MODE_TYPE_DRIVER;
        if (genmode->is_default && !ctx->num_timings) { mode->type |= DRM_MODE_TYPE_PREFERRED; };

        drm_mode_probed_add(connector, mode);

        genmode = genmode->prev;
    }

    connector->display_info.width_mm = ctx->size.width;
    connector->display_info.height_mm = ctx->size.height;


    /*
     * TODO: Remove once all drm drivers call
     * drm_connector_set_orientation_from_panel()
     */
    drm_connector_set_panel_orientation(connector, ctx->orientation);

    return 1;
}

static enum drm_panel_orientation generic_panel_get_orientation(struct drm_panel *panel)
{
    struct generic_panel *ctx = panel_to_generic_panel(panel);

    return ctx->orientation;
}

static const struct drm_panel_funcs generic_panel_funcs = {
    .unprepare  = generic_panel_unprepare,
    .prepare    = generic_panel_prepare,
    .get_modes  = generic_panel_get_modes,
    .get_orientation = generic_panel_get_orientation,
};

static int generic_panel_probe(struct mipi_dsi_device *dsi)
{
    struct device *dev = &dsi->dev;
    struct generic_panel *ctx;
    struct display_timing dt = {0};
    struct display_timing *timing;
    int ret;

    ctx = devm_kzalloc(dev, sizeof(*ctx), GFP_KERNEL);
    if (!ctx)
        return -ENOMEM;

    ctx->enable_gpio = devm_gpiod_get_optional(dev, "enable", GPIOD_OUT_LOW);
    if (IS_ERR(ctx->enable_gpio)) {
        dev_err(dev, "cannot get enable gpio\n");
	ctx->enable_gpio = NULL;
    }

    ctx->reset_gpio = devm_gpiod_get_optional(dev, "reset", GPIOD_OUT_LOW);
    if (IS_ERR(ctx->reset_gpio)) {
        dev_err(dev, "cannot get reset gpio\n");
        return PTR_ERR(ctx->reset_gpio);
    }

    ctx->vdd = devm_regulator_get(dev, "vdd");
    if (IS_ERR(ctx->vdd)) {
        ret = PTR_ERR(ctx->vdd);
        if (ret != -EPROBE_DEFER)
            dev_err(dev, "Failed to request vdd regulator: %d\n", ret);
        return ret;
    }

    ctx->iovcc = devm_regulator_get(dev, "iovcc");
    if (IS_ERR(ctx->iovcc)) {
        ret = PTR_ERR(ctx->iovcc);
        if (ret != -EPROBE_DEFER)
            dev_err(dev, "Failed to request iovcc regulator: %d\n", ret);
        return ret;
    }

    ret = of_drm_get_panel_orientation(dev->of_node, &ctx->orientation);
    if (ret < 0) {
        dev_err(dev, "%pOF: failed to get orientation %d\n", dev->of_node, ret);
        return ret;
    }

    if (!of_get_display_timing(dev->of_node, "panel-timing", &dt)) {
    	timing = devm_kzalloc(dev, sizeof(*timing), GFP_KERNEL);
    	if (!timing)
    		return -ENOMEM;
    	memcpy(timing, &dt, sizeof(*timing));
    	ctx->timings = timing;
    	ctx->num_timings = 1;
    } else {
	    dev_dbg(dev, "no panel-timing node, using mode lines only\n");
    }

    mipi_dsi_set_drvdata(dsi, ctx);

    ctx->dev = dev;

    // Some defaults
    dsi->lanes = 1;
    dsi->format = MIPI_DSI_FMT_RGB888;
    dsi->mode_flags = MIPI_DSI_MODE_VIDEO | MIPI_DSI_MODE_VIDEO_BURST |
              MIPI_DSI_MODE_LPM | MIPI_DSI_MODE_NO_EOT_PACKET |
              MIPI_DSI_CLOCK_NON_CONTINUOUS;

    ret = load_panel_description(dsi, ctx);
    if (ret < 0) {
        dev_err(dev, "Failed to load panel description\n");
        return ret;
    }

    mipi_dsi_set_drvdata(dsi, ctx);

    dev_info(dev, "lanes %d, format %d, mode %lx\n", dsi->lanes, dsi->format, dsi->mode_flags);

    drm_panel_init(&ctx->panel, &dsi->dev, &generic_panel_funcs,
               DRM_MODE_CONNECTOR_DSI);

    ret = drm_panel_of_backlight(&ctx->panel);
    if (ret)
        return ret;

    drm_panel_add(&ctx->panel);

    ret = mipi_dsi_attach(dsi);
    if (ret < 0) {
        dev_err(dev, "mipi_dsi_attach failed: %d\n", ret);
        drm_panel_remove(&ctx->panel);
        return ret;
    }

    return 0;
}

static void generic_panel_shutdown(struct mipi_dsi_device *dsi)
{
    struct generic_panel *ctx = mipi_dsi_get_drvdata(dsi);

    drm_panel_unprepare(&ctx->panel);

    drm_panel_disable(&ctx->panel);
}

static void generic_panel_remove(struct mipi_dsi_device *dsi)
{
    struct generic_panel *ctx = mipi_dsi_get_drvdata(dsi);
    int ret;

    generic_panel_shutdown(dsi);

    ret = mipi_dsi_detach(dsi);
    if (ret < 0)
        dev_err(&dsi->dev, "Failed to detach from DSI host: %d\n", ret);

    drm_panel_remove(&ctx->panel);
}

static const struct of_device_id generic_panel_of_match[] = {
    { .compatible = "archr,generic-dsi" },
    /* Also bind to overlays produced by ROCKNIX (overlay_server, nightly
     * builds, dtbo-overlay branch) so users can flash ArchR with a DTBO
     * generated upstream and have the panel come up. The init sequence
     * and panel_description format are identical between the two — only
     * the compatible string differs. */
    { .compatible = "rocknix,generic-dsi" },
    { /* sentinel */ }
};
MODULE_DEVICE_TABLE(of, generic_panel_of_match);

static struct mipi_dsi_driver generic_panel_driver = {
    .driver = {
        .name = DRIVER_NAME,
        .of_match_table = generic_panel_of_match,
    },
    .probe  = generic_panel_probe,
    .remove = generic_panel_remove,
    .shutdown = generic_panel_shutdown,
};
module_mipi_dsi_driver(generic_panel_driver);

MODULE_AUTHOR("Danil Zagoskin <z@gosk.in>");
MODULE_DESCRIPTION("DRM driver for generic MIPI DSI panel");
MODULE_LICENSE("GPL v2");
