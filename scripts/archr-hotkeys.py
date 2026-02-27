#!/usr/bin/python3
"""
Arch R - Hotkey Daemon (replaces dArkOS ogage)
Listens for input events and handles:
  - KEY_VOLUMEUP/KEY_VOLUMEDOWN → ALSA volume adjust (from gpio-keys-vol)
  - MODE + VOL_UP/VOL_DOWN → brightness adjust
  - Headphone jack insertion → audio path toggle (from rk817 codec)

Volume device (gpio-keys-vol) is grabbed exclusively.
Gamepad device (gpio-keys) is monitored passively (ES keeps receiving events).
"""

import os
import sys
import time
import subprocess
import re
import select

try:
    import evdev
    from evdev import ecodes
except ImportError:
    print("ERROR: python-evdev not installed. Install with: pacman -S python-evdev")
    sys.exit(1)

# Volume step (percentage per key press)
VOL_STEP = 5
# Brightness step (percentage per key press)
BRIGHT_STEP = 5
# Minimum interval between volume/brightness actions (seconds)
# adc-keys autorepeat fires at ~30Hz — throttle to ~3 events/sec
VOL_THROTTLE = 0.3
# Minimum brightness percentage (prevent black screen)
BRIGHT_MIN = 5
# Brightness persistence file
BRIGHT_SAVE = "/home/archr/.config/archr/brightness"
VOL_SAVE = "/home/archr/.config/archr/volume"

# ALSA simple mixer control name for rk817 BSP codec volume
# Raw control is "DAC Playback Volume" (numid=8), but ALSA simple mixer maps it to "DAC"
# amixer sset 'DAC Playback Volume' FAILS — must use simple name 'DAC'
# "Playback Path" is an enum (SPK/HP/OFF), NOT a volume control
ALSA_VOL_CTRL = "DAC"

# rk817 codec volume range: ALSA reports [0, 255] but codec rejects values > 252
# Writing > 252 causes "Volume out of range" and can ZERO the volume!
# Use percentage clamping: 0-98% stays within [0, 249] (safe margin)
VOL_MAX_PCT = 98
VOL_MIN_PCT = 0


# Log to BOOT partition (FAT32) — persistent across reboots, readable from PC
# /tmp is tmpfs and lost on power off, making debugging impossible
LOGFILE = "/boot/archr-hotkeys.log"


def log(msg):
    """Append to log file for debugging."""
    try:
        with open(LOGFILE, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {msg}\n")
            f.flush()
    except Exception:
        pass


def run_cmd(cmd):
    """Run a shell command, log output for debugging."""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, timeout=5, text=True)
        if result.returncode != 0:
            log(f"CMD FAIL [{result.returncode}]: {cmd}")
            if result.stderr:
                log(f"  stderr: {result.stderr.strip()}")
        else:
            if result.stdout:
                log(f"  stdout: {result.stdout.strip()[:200]}")
        return result.returncode
    except Exception as e:
        log(f"CMD ERROR: {cmd} -> {e}")
        return -1


def get_volume_pct():
    """Read current DAC volume percentage from sysfs-style amixer output."""
    try:
        r = subprocess.run(
            f"amixer sget '{ALSA_VOL_CTRL}'",
            shell=True, capture_output=True, text=True, timeout=3
        )
        if r.returncode == 0:
            m = re.search(r'\[(\d+)%\]', r.stdout)
            if m:
                return int(m.group(1))
    except Exception:
        pass
    return -1


def set_volume_pct(pct):
    """Set DAC volume to exact percentage (with clamping for rk817 codec safety)."""
    pct = max(VOL_MIN_PCT, min(VOL_MAX_PCT, pct))
    rc = run_cmd(f"amixer -q sset '{ALSA_VOL_CTRL}' {pct}%")
    if rc != 0:
        log(f"VOL set {pct}% failed, fallback numid=8")
        # Convert percentage to raw value (0-249 safe range for codec max 252)
        raw = (pct * 249) // 100
        run_cmd(f"amixer cset numid=8 {raw},{raw}")
    return pct


def save_volume():
    """Save current volume percentage for persistence across reboots."""
    try:
        r = subprocess.run(
            f"amixer sget '{ALSA_VOL_CTRL}'",
            shell=True, capture_output=True, text=True, timeout=3
        )
        if r.returncode == 0:
            m = re.search(r'\[(\d+)%\]', r.stdout)
            if m:
                os.makedirs(os.path.dirname(VOL_SAVE), exist_ok=True)
                with open(VOL_SAVE, "w") as f:
                    f.write(m.group(1))
    except Exception:
        pass


def volume_up():
    cur = get_volume_pct()
    if cur < 0:
        cur = 80  # assume default if read fails
    new = min(cur + VOL_STEP, VOL_MAX_PCT)
    log(f"VOL+ {cur}% -> {new}%")
    set_volume_pct(new)
    save_volume()


def volume_down():
    cur = get_volume_pct()
    if cur < 0:
        cur = 80
    new = max(cur - VOL_STEP, VOL_MIN_PCT)
    log(f"VOL- {cur}% -> {new}%")
    set_volume_pct(new)
    save_volume()


def get_brightness_pct():
    """Read current brightness as percentage from sysfs."""
    try:
        with open("/sys/class/backlight/backlight/brightness") as f:
            cur = int(f.read().strip())
        with open("/sys/class/backlight/backlight/max_brightness") as f:
            mx = int(f.read().strip())
        return (cur * 100) // mx if mx > 0 else 50
    except Exception:
        return 50


def save_brightness():
    """Save current brightness value for persistence across reboots."""
    try:
        with open("/sys/class/backlight/backlight/brightness") as f:
            val = f.read().strip()
        os.makedirs(os.path.dirname(BRIGHT_SAVE), exist_ok=True)
        with open(BRIGHT_SAVE, "w") as f:
            f.write(val)
    except Exception:
        pass


def brightness_up():
    log("BRIGHT+ brightnessctl s +3%")
    run_cmd(f"brightnessctl -q s +{BRIGHT_STEP}%")
    save_brightness()


def brightness_down():
    if get_brightness_pct() <= BRIGHT_MIN:
        return
    log(f"BRIGHT- brightnessctl s {BRIGHT_STEP}%-")
    run_cmd(f"brightnessctl -q s {BRIGHT_STEP}%-")
    # Clamp: if we went below minimum, set to minimum
    if get_brightness_pct() < BRIGHT_MIN:
        run_cmd(f"brightnessctl -q s {BRIGHT_MIN}%")
    save_brightness()


def speaker_toggle(headphone_in):
    if headphone_in:
        run_cmd("amixer -q sset 'Playback Path' HP")
    else:
        run_cmd("amixer -q sset 'Playback Path' SPK")


def find_devices():
    """Find and categorize input devices."""
    vol_dev = None    # gpio-keys-vol (grab: exclusive volume control)
    pad_dev = None    # gpio-keys (no grab: monitor MODE button passively)
    sw_dev = None     # headphone jack (switch events)

    for path in evdev.list_devices():
        try:
            dev = evdev.InputDevice(path)
            name = dev.name.lower()
            caps = dev.capabilities()

            if 'gpio-keys' in name or 'adc-keys' in name:
                # Distinguish vol device from gamepad by checking for KEY_VOLUMEUP
                key_caps = caps.get(ecodes.EV_KEY, [])
                if ecodes.KEY_VOLUMEUP in key_caps:
                    vol_dev = dev
                elif ecodes.BTN_SOUTH in key_caps or ecodes.BTN_DPAD_UP in key_caps:
                    pad_dev = dev

            # Headphone jack switch events (from rk817 or similar codec)
            if ecodes.EV_SW in caps:
                sw_dev = dev

        except Exception:
            continue

    return vol_dev, pad_dev, sw_dev


def main():
    print("Arch R Hotkey Daemon starting...")

    # Wait for input devices to appear
    vol_dev, pad_dev, sw_dev = None, None, None
    for attempt in range(30):
        vol_dev, pad_dev, sw_dev = find_devices()
        if vol_dev:
            break
        time.sleep(1)

    if not vol_dev:
        print("ERROR: Volume input device (gpio-keys-vol) not found!")
        sys.exit(1)

    # Grab volume device exclusively (we handle volume events)
    vol_dev.grab()
    print(f"  Volume: {vol_dev.name} ({vol_dev.path}) [grabbed]")

    # Monitor gamepad passively for MODE button (brightness hotkey)
    devices = [vol_dev]
    if pad_dev:
        # DO NOT grab — ES needs this device for gamepad input
        print(f"  Gamepad: {pad_dev.name} ({pad_dev.path}) [passive]")
        devices.append(pad_dev)

    if sw_dev and sw_dev not in devices:
        print(f"  Switch: {sw_dev.name} ({sw_dev.path}) [passive]")
        devices.append(sw_dev)

    # Track MODE button state for brightness hotkey combo
    mode_held = False
    # Throttle: last time a volume/brightness action was executed
    last_vol_action = 0.0

    print("Hotkey daemon ready.")
    # Clear previous log on fresh start
    try:
        with open(LOGFILE, "w") as f:
            f.write(f"{time.strftime('%H:%M:%S')} === Daemon started (fresh) ===\n")
    except Exception:
        pass
    log(f"  vol_dev: {vol_dev.name} ({vol_dev.path})")
    if pad_dev:
        log(f"  pad_dev: {pad_dev.name} ({pad_dev.path})")

    # Startup amixer diagnostic — confirm volume control works from daemon context
    log("--- Startup ALSA diagnostic ---")
    r = subprocess.run("amixer sget 'DAC' 2>&1", shell=True, capture_output=True, text=True, timeout=5)
    log(f"  amixer sget 'DAC' rc={r.returncode}")
    for line in r.stdout.strip().split('\n'):
        log(f"    {line}")
    if r.stderr.strip():
        log(f"  stderr: {r.stderr.strip()}")
    # Volume NOT set here — user's saved volume is restored by emulationstation.sh
    log("--- End ALSA diagnostic ---")

    try:
        while True:
            r, _, _ = select.select(devices, [], [], 2.0)

            for dev in r:
                try:
                    for event in dev.read():
                        if event.type == ecodes.EV_KEY:
                            key = event.code
                            val = event.value  # 1=press, 0=release, 2=repeat
                            # Log ALL key events for debugging
                            keyname = ecodes.KEY.get(key, ecodes.BTN.get(key, f"?{key}"))
                            valname = {0: "UP", 1: "DOWN", 2: "REPEAT"}.get(val, f"?{val}")
                            log(f"KEY: {keyname}({key}) {valname} dev={dev.name} mode={mode_held}")

                            # Track MODE button from gamepad (passive)
                            if key == ecodes.BTN_MODE:
                                if val == 1:
                                    mode_held = True
                                elif val == 0:
                                    mode_held = False

                            # Volume keys (grabbed): accept press + repeat,
                            # but throttle to max ~3 events/sec (300ms interval).
                            # adc-keys autorepeat fires at ~30Hz natively.
                            elif key == ecodes.KEY_VOLUMEUP and val in (1, 2):
                                now = time.monotonic()
                                if now - last_vol_action >= VOL_THROTTLE:
                                    last_vol_action = now
                                    if mode_held:
                                        brightness_up()
                                    else:
                                        volume_up()

                            elif key == ecodes.KEY_VOLUMEDOWN and val in (1, 2):
                                now = time.monotonic()
                                if now - last_vol_action >= VOL_THROTTLE:
                                    last_vol_action = now
                                    if mode_held:
                                        brightness_down()
                                    else:
                                        volume_down()

                        # Headphone jack switch
                        elif event.type == ecodes.EV_SW:
                            if event.code == ecodes.SW_HEADPHONE_INSERT:
                                speaker_toggle(event.value == 1)

                except OSError:
                    # Device disconnected
                    pass

    except KeyboardInterrupt:
        pass
    finally:
        try:
            vol_dev.ungrab()
        except Exception:
            pass
        print("Hotkey daemon stopped.")


if __name__ == "__main__":
    main()
