#!/usr/bin/python3
"""
Arch R - Panel Detection Wizard

Runs on first boot (or after X-button reset) to let the user select
their display panel. Provides audio feedback (beeps) for blind selection
and visual feedback on tty1 for users who already have the correct panel.

Flow:
  1. Check /boot/panel-confirmed — if valid (>1 byte), exit immediately
  2. Read variant from /etc/archr/variant (original or clone)
  3. Initialize audio (speaker, 60% volume)
  4. Cycle through panels (most common first):
     - Show panel name on tty1
     - Play N beeps (N = position in list: Panel 0=1 beep, Panel 1=2 beeps, etc.)
     - Wait 15s for input: A=confirm, B/DPAD_DOWN=next
  5. On confirm: write panel.txt + panel-confirmed → sync → reboot
  6. After 2 full cycles without confirm: auto-confirm default

Panel selection is persistent:
  - panel.txt: U-Boot reads PanelDTB variable (pre-merged DTB name)
  - panel-confirmed: marker file (>1 byte = confirmed, ≤1 byte = reset)
  - Hold X during boot to reset (U-Boot overwrites panel-confirmed with 1 byte)
"""

import math
import os
import select
import struct
import subprocess
import sys
import time
from pathlib import Path

try:
    import evdev
    from evdev import ecodes
except ImportError:
    print("ERROR: python-evdev not installed")
    sys.exit(1)

# --- Paths ---
BOOT_DIR = Path("/boot")
PANEL_TXT = BOOT_DIR / "panel.txt"
PANEL_CONFIRMED = BOOT_DIR / "panel-confirmed"
VARIANT_FILE = Path("/etc/archr/variant")

# --- Buttons (from rk3326-odroid-go.dtsi gpio-keys) ---
BTN_A = ecodes.BTN_EAST         # 305 — A button (confirm)
BTN_B = ecodes.BTN_SOUTH        # 304 — B button (next)
BTN_X = ecodes.BTN_NORTH        # 307 — X button (reset panel selection)
BTN_DOWN = ecodes.BTN_DPAD_DOWN # 545 — D-pad down (next, alternative)

# --- Audio ---
BEEP_FREQ = 880        # Hz
BEEP_DURATION = 0.12   # seconds
BEEP_GAP = 0.15        # seconds between beeps
SAMPLE_RATE = 44100

# --- Timing ---
WAIT_PER_PANEL = 15    # seconds to wait for input per panel
MAX_CYCLES = 2         # auto-confirm default after this many full cycles

# --- Panel definitions per variant ---
# (panel_num, dtb_name, friendly_name)
# Empty dtb_name = default panel (hardcoded in base DTB kernel.dtb, no overlay)
# Non-empty dtb_name = pre-merged DTB with overlay applied at build-time
# Order: numerical (beep count = position in list, Panel 0 = 1 beep, etc.)

# R36S Original — 6 panels, default is Panel 4-V22 (~60% of units)
# Beeps: Panel 0=1, Panel 1=2, Panel 2=3, Panel 3=4, Panel 4=5, Panel 5=6
PANELS_ORIGINAL = [
    ("0",    "kernel-panel0.dtb",   "Panel 0"),
    ("1",    "kernel-panel1.dtb",   "Panel 1-V10"),
    ("2",    "kernel-panel2.dtb",   "Panel 2-V12"),
    ("3",    "kernel-panel3.dtb",   "Panel 3-V20"),
    ("4",    "",                    "Panel 4-V22 (Default)"),
    ("5",    "kernel-panel5.dtb",   "Panel 5-V22 Q8"),
]

# R36S Clone — 12 panels, default is Clone 8 ST7703 (G80CA-MB)
# Beeps: Clone 1=1, Clone 2=2, ..., Clone 10=10, R36 Max=11, RX6S=12
PANELS_CLONE = [
    ("C1",   "kernel-clone1.dtb",     "Clone 1 (ST7703)"),
    ("C2",   "kernel-clone2.dtb",     "Clone 2 (ST7703)"),
    ("C3",   "kernel-clone3.dtb",     "Clone 3 (NV3051D)"),
    ("C4",   "kernel-clone4.dtb",     "Clone 4 (NV3051D)"),
    ("C5",   "kernel-clone5.dtb",     "Clone 5 (ST7703)"),
    ("C6",   "kernel-clone6.dtb",     "Clone 6 (NV3051D)"),
    ("C7",   "kernel-clone7.dtb",     "Clone 7 (JD9365DA)"),
    ("C8",   "",                      "Clone 8 ST7703 G80CA (Default)"),
    ("C9",   "kernel-clone9.dtb",     "Clone 9 (NV3051D)"),
    ("C10",  "kernel-clone10.dtb",    "Clone 10 (ST7703)"),
    ("MAX",  "kernel-r36max.dtb",     "R36 Max (720x720)"),
    ("RX6S", "kernel-rx6s.dtb",       "RX6S (NV3051D)"),
]


def get_variant():
    """Read variant from /etc/archr/variant (written by build-image.sh)."""
    try:
        return VARIANT_FILE.read_text().strip()
    except FileNotFoundError:
        # Fallback: detect via eMMC presence
        if os.path.exists('/sys/block/mmcblk1'):
            return "original"
        return "clone"


def get_panels(variant):
    """Return panel list for this variant."""
    if variant == "clone":
        return PANELS_CLONE
    return PANELS_ORIGINAL


def is_confirmed():
    """Check if panel selection is already confirmed."""
    if not PANEL_CONFIRMED.exists():
        return False
    return PANEL_CONFIRMED.stat().st_size > 1


def generate_beep_wav(freq=BEEP_FREQ, duration=BEEP_DURATION):
    """Generate a short sine wave beep as WAV data (16-bit mono PCM)."""
    n = int(SAMPLE_RATE * duration)
    samples = b''.join(
        struct.pack('<h', int(16384 * math.sin(2 * math.pi * freq * i / SAMPLE_RATE)))
        for i in range(n)
    )
    hdr = struct.pack(
        '<4sI4s4sIHHIIHH4sI',
        b'RIFF', 36 + len(samples), b'WAVE',
        b'fmt ', 16, 1, 1, SAMPLE_RATE, SAMPLE_RATE * 2, 2, 16,
        b'data', len(samples)
    )
    return hdr + samples


def play_beeps(count, wav_data):
    """Play N beeps with gaps between them."""
    for i in range(count):
        try:
            subprocess.run(
                ["aplay", "-q", "-"],
                input=wav_data, timeout=2,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        except Exception:
            pass
        if i < count - 1:
            time.sleep(BEEP_GAP)


def play_confirm_sound(wav_data):
    """Play 3 rapid high beeps for confirmation feedback."""
    for _ in range(3):
        try:
            subprocess.run(
                ["aplay", "-q", "-"],
                input=wav_data, timeout=2,
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )
        except Exception:
            pass
        time.sleep(0.08)


def write_tty(msg):
    """Write message to tty1 (visible only if current panel is correct)."""
    try:
        with open("/dev/tty1", "w") as tty:
            tty.write("\033[2J\033[H")    # clear screen
            tty.write("\033[1;37m")       # bright white
            tty.write("=" * 42 + "\n")
            tty.write("  Arch R - Panel Detection\n")
            tty.write("=" * 42 + "\n\n")
            tty.write(f"  {msg}\n\n")
            tty.write("  A = Confirm this panel\n")
            tty.write("  B = Try next panel\n\n")
            tty.write("  (auto-advances in 15s)\n")
            tty.write("\033[0m")
            tty.flush()
    except Exception:
        pass


def find_gamepad():
    """Find gpio-keys gamepad input device."""
    for path in evdev.list_devices():
        try:
            dev = evdev.InputDevice(path)
            caps = dev.capabilities().get(ecodes.EV_KEY, [])
            if BTN_A in caps and BTN_B in caps:
                return dev
        except Exception:
            continue
    return None


def is_x_held(dev):
    """Check if X button is currently held down (for panel reset).

    Works on any board — uses evdev (kernel input), not raw GPIO.
    Original: X = GPIO1_PA7, Clone: X = GPIO3_PC2, but evdev
    abstracts this to BTN_NORTH regardless of hardware.
    """
    try:
        active = dev.active_keys()
        return BTN_X in active
    except Exception:
        return False


def reset_panel():
    """Reset panel selection (triggered by holding X during boot)."""
    log_boot("X held — resetting panel selection")
    # Truncate panel-confirmed to trigger wizard
    try:
        fd = os.open(str(PANEL_CONFIRMED), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
        os.write(fd, b'\x00')
        os.fsync(fd)
        os.close(fd)
        dir_fd = os.open(str(PANEL_CONFIRMED.parent), os.O_RDONLY)
        os.fsync(dir_fd)
        os.close(dir_fd)
    except Exception:
        pass


def wait_for_button(dev, timeout):
    """Wait for A or B button press. Returns 'A', 'B', or None (timeout)."""
    # Drain pending events
    while dev.read_one():
        pass

    deadline = time.monotonic() + timeout
    while True:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            return None

        r, _, _ = select.select([dev], [], [], min(remaining, 0.5))
        if not r:
            continue

        for event in dev.read():
            if event.type != ecodes.EV_KEY or event.value != 1:
                continue
            if event.code == BTN_A:
                return 'A'
            if event.code in (BTN_B, BTN_DOWN):
                return 'B'

    return None


def fsync_write(path, data):
    """Write data to file with explicit fsync (critical for FAT32 on SD card).

    Path.write_text() doesn't fsync — data stays in page cache.
    If power is cut before writeback completes, the file is lost.
    """
    fd = os.open(str(path), os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o644)
    os.write(fd, data.encode())
    os.fsync(fd)
    os.close(fd)
    # Also fsync the directory to persist the directory entry itself
    dir_fd = os.open(str(path.parent), os.O_RDONLY)
    os.fsync(dir_fd)
    os.close(dir_fd)


def write_panel_config(panel_num, dtb_name):
    """Write panel.txt for U-Boot to load on next boot."""
    content = f"PanelNum={panel_num}\n"
    if dtb_name:
        content += f"PanelDTB={dtb_name}\n"
    else:
        content += "PanelDTB=\n"
    fsync_write(PANEL_TXT, content)


def confirm_panel():
    """Write panel-confirmed marker (content > 1 byte = confirmed)."""
    fsync_write(PANEL_CONFIRMED, "confirmed\n")


def init_audio():
    """Initialize audio output for panel detection beeps."""
    try:
        subprocess.run(
            ["amixer", "-q", "sset", "Playback Path", "SPK"],
            timeout=3, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
        subprocess.run(
            ["amixer", "-q", "sset", "DAC", "60%"],
            timeout=3, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except Exception:
        pass


def wait_for_boot_mount():
    """Wait for /boot to be mounted (FAT32 partition with panel files)."""
    for _ in range(30):
        if os.path.ismount("/boot"):
            return True
        time.sleep(1)
    return False


def log_boot(msg):
    """Log to /boot for persistent debugging (survives tmpfs /var/log)."""
    try:
        with open("/boot/panel-detect.log", "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {msg}\n")
    except Exception:
        pass


def main():
    # Ensure /boot is mounted before checking panel-confirmed
    if not os.path.ismount("/boot"):
        wait_for_boot_mount()

    log_boot(f"start: /boot mounted={os.path.ismount('/boot')}")
    log_boot(f"  panel-confirmed exists={PANEL_CONFIRMED.exists()}")
    if PANEL_CONFIRMED.exists():
        log_boot(f"  panel-confirmed size={PANEL_CONFIRMED.stat().st_size}")

    # Find gamepad input device (needed for X-button check AND wizard)
    gamepad = None
    for _ in range(10):
        gamepad = find_gamepad()
        if gamepad:
            break
        time.sleep(1)

    # Check if X is held — reset panel selection (works on any board via evdev)
    if gamepad and is_x_held(gamepad):
        reset_panel()
        log_boot("panel reset by X button")

    # Quick exit if panel already confirmed
    if is_confirmed():
        log_boot("confirmed — exiting")
        sys.exit(0)

    log_boot("NOT confirmed — starting wizard")

    # Determine variant and panel list
    variant = get_variant()
    panels = get_panels(variant)
    default_panel = next((p for p in panels if not p[1]), panels[0])  # Default = empty dtb_name

    print(f"Arch R Panel Detection Wizard starting (variant: {variant})...")
    print(f"  {len(panels)} panels available, default: {default_panel[2]}")

    # Initialize audio
    init_audio()

    # Generate beep WAVs
    beep = generate_beep_wav()
    intro_beep = generate_beep_wav(freq=660, duration=0.3)
    confirm_beep = generate_beep_wav(freq=1100, duration=0.1)

    if not gamepad:
        print("WARNING: Gamepad not found — auto-confirming default panel")
        write_panel_config(default_panel[0], default_panel[1])
        confirm_panel()
        subprocess.run(["sync"])
        sys.exit(0)

    print(f"  Gamepad: {gamepad.name} ({gamepad.path})")

    # Intro: 2 long beeps to signal wizard is running
    play_beeps(2, intro_beep)
    time.sleep(0.5)

    # Panel selection loop
    for cycle in range(MAX_CYCLES):
        for idx, (panel_num, dtb_name, name) in enumerate(panels):
            # Write panel config (ready for confirm)
            write_panel_config(panel_num, dtb_name)

            # Visual feedback on tty1
            position = f"[{idx + 1}/{len(panels)}]"
            if cycle > 0:
                position += f" (cycle {cycle + 1})"
            write_tty(f"{position} {name}")

            # Audio feedback: N beeps (panel number + 1)
            beep_count = idx + 1
            play_beeps(beep_count, beep)

            print(f"  {position} {name} — waiting...")

            # Wait for button input
            result = wait_for_button(gamepad, WAIT_PER_PANEL)

            if result == 'A':
                print(f"  CONFIRMED: {name}")
                play_confirm_sound(confirm_beep)
                confirm_panel()
                subprocess.run(["sync"])
                if dtb_name:
                    # Non-default panel: pre-merged DTB loaded on next boot
                    write_tty(f"Confirmed: {name}\n\n  Press RESET to apply.")
                    print(f"  Non-default panel — waiting for RESET")
                    # Hold here until user presses RESET (no timeout)
                    while True:
                        time.sleep(60)
                else:
                    # Default panel: kernel.dtb used, continue booting
                    write_tty(f"Confirmed: {name}")
                    print(f"  Default panel — continuing boot")
                    sys.exit(0)

            elif result == 'B':
                print(f"  NEXT (B pressed)")
                continue

            else:
                print(f"  TIMEOUT — advancing")
                continue

    # After MAX_CYCLES without confirmation: auto-confirm default
    print(f"  No selection made — auto-confirming default {default_panel[2]}")
    write_panel_config(default_panel[0], default_panel[1])
    write_tty(f"Auto-confirmed: {default_panel[2]}")
    play_confirm_sound(generate_beep_wav(freq=440, duration=0.2))
    confirm_panel()
    subprocess.run(["sync"])


if __name__ == "__main__":
    main()
