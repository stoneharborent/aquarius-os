#!/usr/bin/bash
# Run inside the finished image, with its own labwc and Quickshell. No host
# desktop or hardware is used. The desktop loads the production lock component.
set -euo pipefail
shell=/usr/share/aquarius/shell
record=/usr/share/aquarius/shell-build.txt
grep -qx 'status=installed' "$record"
grep -qx "commit=${EXPECT_SHELL_REF:?exact shell pin required}" "$record"
for entry in shell.qml greeter.qml; do test -s "$shell/$entry"; done
work=$(mktemp -d)
compositor_pid=''
qs_pid=''
cleanup() {
    if [ -n "$qs_pid" ]; then kill "$qs_pid" 2>/dev/null || true; fi
    if [ -n "$compositor_pid" ]; then kill "$compositor_pid" 2>/dev/null || true; fi
    cat "$work"/*.log 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT
export XDG_RUNTIME_DIR="$work/run" XDG_CONFIG_HOME="$work/config"
export XDG_CACHE_HOME="$work/cache" XDG_STATE_HOME="$work/state"
mkdir -m 700 "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$work/labwc"
printf '<labwc_config/>\n' > "$work/labwc/rc.xml"
export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_RENDERER=pixman
export WLR_LIBINPUT_NO_DEVICES=1 QT_QPA_PLATFORM=wayland
export QT_QUICK_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1 NO_COLOR=1
unset WAYLAND_DISPLAY DISPLAY QS_CONFIG_PATH
labwc -C "$work/labwc" > "$work/compositor.log" 2>&1 &
compositor_pid=$!
for ((i=0; i<100; i++)); do
    kill -0 "$compositor_pid"
    for socket in "$XDG_RUNTIME_DIR"/wayland-*; do
        if [ -S "$socket" ]; then export WAYLAND_DISPLAY="${socket##*/}"; break; fi
    done
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then break; fi
    sleep 0.1
done
: "${WAYLAND_DISPLAY:?labwc did not create a socket}"
for entry in shell greeter; do
    qs --no-color --log-times -p "$shell/$entry.qml" > "$work/$entry.log" 2>&1 &
    qs_pid=$!
    for ((i=0; i<20; i++)); do
        sleep 1
        kill -0 "$compositor_pid"
        kill -0 "$qs_pid"
    done
    # These indicate broken QML regardless of missing hardware/services.
    if grep -Ei 'Failed to load configuration|is not a type|is not installed|is not a namespace|Type .* unavailable|Cannot assign|Unable to assign|Non-existent attached object|Invalid property assignment|Invalid attached property|Duplicate (signal|property|method) name|Expected token|Unexpected token|Syntax error|Could not open config file|ReferenceError|TypeError' "$work/$entry.log"; then
        exit 1
    fi
    grep -q 'Configuration Loaded' "$work/$entry.log"
    kill "$qs_pid"
    wait "$qs_pid" || true
    qs_pid=''
    echo "Loaded $entry from the finished image at $EXPECT_SHELL_REF"
done
