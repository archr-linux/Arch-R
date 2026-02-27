#!/bin/bash

#==============================================================================
# Arch R - EmulationStation Launch Script (boot-optimized)
# Critical path: exports → audio init → ES start (~200ms overhead)
# Everything else runs in background parallel with ES SDL init
#==============================================================================

# Boot timeline: log uptime at each key point
_bt() { echo "[TIMELINE $(cut -d' ' -f1 /proc/uptime)s] $1" >> /home/archr/es-timeline.txt; }
: > /home/archr/es-timeline.txt
_bt "script_start (uid=$(id -u))"

# Root guard: ES must run as archr, never as root
if [ "$(id -u)" = "0" ]; then
    exec su -l archr -c "$(printf '%q ' "$0" "$@")"
fi

_bt "after_root_guard"

# Blank screen immediately (hide login text)
printf '\033[2J\033[H\033[?25l\033[30;40m' > /dev/tty1 2>/dev/null

export HOME=/home/archr
export SDL_ASSERT="always_ignore"
export TERM=linux
export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export SDL_VIDEODRIVER=KMSDRM
export SDL_VIDEO_DRIVER=KMSDRM
export SDL_GAMECONTROLLERCONFIG_FILE="/etc/archr/gamecontrollerdb.txt"
export SDL_AUDIODRIVER=alsa
export SDL_LOG_PRIORITY=error
export SDL_LOGGING="*=error"
export MESA_NO_ERROR=1
export MESA_SHADER_CACHE_DIR="$HOME/.cache/mesa_shader_cache"
export MESA_SHADER_CACHE_MAX_SIZE=128M
export MESA_DISK_CACHE_SINGLE_FILE=1

# === SYNCHRONOUS: Audio + brightness init ===
_bt "before_amixer"
amixer -q sset 'Playback Path' SPK 2>/dev/null
# Restore saved volume (default 80% on first boot)
VOL_SAVE="$HOME/.config/archr/volume"
if [ -f "$VOL_SAVE" ]; then
    amixer -q sset 'DAC' "$(cat "$VOL_SAVE")%" 2>/dev/null
else
    amixer -q sset 'DAC' 80% 2>/dev/null
fi
_bt "after_amixer"

# === BACKGROUND: Everything else runs parallel with ES SDL init (~2s window) ===
(
    # NOTE: fb0 blank removed — archr-splash.service writes splash to fb0,
    # which persists until ES takes DRM master via KMSDRM.

    # Permissions + governors (single sudo)
    sudo sh -c '/usr/local/bin/perfmax; chmod 666 /dev/tty1 /dev/dri/* /sys/class/backlight/backlight/brightness' 2>/dev/null

    # Brightness restore
    BRIGHT_SAVE="$HOME/.config/archr/brightness"
    if [ -f "$BRIGHT_SAVE" ]; then
        brightnessctl -q s "$(cat "$BRIGHT_SAVE")" 2>/dev/null
    else
        brightnessctl -q s 60% 2>/dev/null
    fi

    # Shader cache dir
    mkdir -p "$MESA_SHADER_CACHE_DIR" 2>/dev/null
    mkdir -p "$XDG_RUNTIME_DIR"

    # drirc
    [ ! -f "$HOME/.drirc" ] && echo '<?xml version="1.0"?><driconf/>' > "$HOME/.drirc" 2>/dev/null

    # ES config setup
    mkdir -p "$HOME/.emulationstation"
    for cfg in es_systems.cfg es_input.cfg; do
        [ ! -f "$HOME/.emulationstation/$cfg" ] && [ -f "/etc/emulationstation/$cfg" ] && \
            ln -sf "/etc/emulationstation/$cfg" "$HOME/.emulationstation/$cfg"
    done

    # Settings fix (single sed pass)
    CFG="$HOME/.emulationstation/es_settings.cfg"
    if [ -f "$CFG" ]; then
        sed -i \
            -e 's|<settings>|<config>|; s|</settings>|</config>|' \
            -e 's|"LogLevel" value="[^"]*"|"LogLevel" value="error"|' \
            -e 's|"AudioDevice" value="[^"]*"|"AudioDevice" value="DAC"|' \
            "$CFG"
        C=$(< "$CFG")
        ADDS=""
        [[ "$C" == *'"HideWindow"'* ]] || ADDS="${ADDS}\n  <bool name=\"HideWindow\" value=\"true\" />"
        [[ "$C" == *'"AudioDevice"'* ]] || ADDS="${ADDS}\n  <string name=\"AudioDevice\" value=\"DAC\" />"
        [[ "$C" == *'"AudioCard"'* ]] || ADDS="${ADDS}\n  <string name=\"AudioCard\" value=\"default\" />"
        [[ "$C" == *'"EnableSounds"'* ]] || ADDS="${ADDS}\n  <bool name=\"EnableSounds\" value=\"true\" />"
        [ -n "$ADDS" ] && sed -i "s|<config>|<config>$ADDS|" "$CFG"
    fi

    # Theme music symlinks (only if empty)
    MUSIC_DIR="$HOME/.emulationstation/music"
    mkdir -p "$MUSIC_DIR"
    if [ -z "$(ls -A "$MUSIC_DIR" 2>/dev/null)" ] && [ -f "$CFG" ]; then
        ACTIVE_THEME=$(grep -oP 'name="ThemeSet" value="\K[^"]+' "$CFG" 2>/dev/null)
        if [ -n "$ACTIVE_THEME" ] && [ -d "$HOME/.emulationstation/themes/$ACTIVE_THEME" ]; then
            find "$HOME/.emulationstation/themes/$ACTIVE_THEME" -maxdepth 4 \( -name '*.ogg' -o -name '*.mp3' \) 2>/dev/null | while read snd; do
                ln -sf "$snd" "$MUSIC_DIR/$(basename "$snd")" 2>/dev/null
            done
        fi
    fi

    # Battery SVG placeholders
    if [ -d "$HOME/.emulationstation/themes" ]; then
        for theme in "$HOME/.emulationstation/themes"/*/; do
            [ -d "$theme/_art" ] || continue
            BATT_DIR="$theme/_art/battery"
            [ ! -f "$BATT_DIR/full.svg" ] || continue
            mkdir -p "$BATT_DIR"
            for icon in incharge full 75 50 25 empty; do
                echo '<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>' > "$BATT_DIR/$icon.svg"
            done
        done
    fi

    # Panfrost module check
    [ ! -d /sys/module/panfrost ] && sudo modprobe panfrost 2>/dev/null
) &

# === Default ES settings (first boot only) ===
if [ ! -f "$HOME/.emulationstation/es_settings.cfg" ]; then
    mkdir -p "$HOME/.emulationstation"
    cat > "$HOME/.emulationstation/es_settings.cfg" << 'SETTINGS_EOF'
<?xml version="1.0"?>
<config>
  <int name="MaxVRAM" value="150" />
  <bool name="HideWindow" value="true" />
  <string name="LogLevel" value="error" />
  <string name="AudioCard" value="default" />
  <string name="AudioDevice" value="DAC" />
  <bool name="EnableSounds" value="true" />
  <string name="ScreenSaverBehavior" value="black" />
  <string name="TransitionStyle" value="instant" />
  <string name="SaveGamelistsMode" value="on exit" />
  <bool name="DrawClock" value="false" />
  <bool name="QuickSystemSelect" value="false" />
  <string name="CollectionSystemsAuto" value="favorites,recent" />
  <string name="FolderViewMode" value="always" />
</config>
SETTINGS_EOF
fi

# ES directory
esdir="$(dirname "$0")"
DEBUGLOG="$HOME/es-debug.log"
[ -f "$DEBUGLOG" ] && mv -f "$DEBUGLOG" "${DEBUGLOG}.prev" 2>/dev/null

# === MAIN LOOP ===
CRASH_COUNT=0
while true; do
    rm -f /tmp/es-restart /tmp/es-sysrestart /tmp/es-shutdown

    _bt "before_es_binary"
    "$esdir/emulationstation" "$@" >> "$DEBUGLOG" 2>&1
    ret=$?

    if [ -f /tmp/es-restart ]; then
        CRASH_COUNT=0
        continue
    fi
    if [ -f /tmp/es-sysrestart ]; then
        rm -f /tmp/es-sysrestart
        systemctl reboot
        break
    fi
    if [ -f /tmp/es-shutdown ]; then
        rm -f /tmp/es-shutdown
        sudo /usr/local/bin/pmic-poweroff 2>/dev/null
        systemctl poweroff
        break
    fi
    if [ $ret -ne 0 ]; then
        CRASH_COUNT=$((CRASH_COUNT + 1))
        [ $CRASH_COUNT -ge 5 ] && break
        printf '\033[2J\033[H\033[?25l\033[30;40m' > /dev/tty1 2>/dev/null
        sleep 0.5
        continue
    fi
    break
done

sudo /usr/local/bin/perfnorm 2>/dev/null
exit $ret
