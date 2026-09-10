#!/usr/bin/bash
# ==============================================================================
# STEP 5.6 — The AquariusOS app icons
# ==============================================================================
# Up to here the machine has our colours, our fonts, our wallpaper and our two
# desktops — and GNOME's app icons. This step is where the nine icons Royce
# actually looks at every day become ours: the Editor, the Writer, Files,
# Settings, the Console, the app chooser, the welcome window, and the two
# DaVinci Resolve buttons.
#
# ------------------------------------------------------------------------------
# WHAT THIS STEP ACTUALLY DOES — WHICH IS ALMOST NOTHING, ON PURPOSE
# ------------------------------------------------------------------------------
# The icons are not made here. They were drawn on the Mac by
# branding/render-app-icons.sh, committed, and copied into the image at step 5
# along with everything else under system_files/. By the time this script runs
# they are already at:
#
#     /usr/share/icons/Aquarius-Ice/          the light set — the default
#     /usr/share/icons/Aquarius-Midnight/     the dark set — built, not yet used
#
# So this step INSPECTS. It reads every file back and refuses to build an image
# where an icon is missing, is the wrong size, or is named something no program
# will ever ask for. That sounds like a small thing to spend a build step on;
# it is not. A missing icon is not an error anywhere — our themes say
# `Inherits=Adwaita,hicolor`, so anything we fail to provide falls silently
# through to GNOME's own artwork and the machine looks *fine*. It just is not
# AquariusOS. There is no red text to find. This is the red text.
#
# ------------------------------------------------------------------------------
# WHY THE PICTURES ARE COMMITTED RATHER THAN MADE DURING THIS BUILD
# ------------------------------------------------------------------------------
# Same decision, same reasons, as the logo (branding/render-logo-png.sh) and the
# boot splash (branding/render-plymouth-assets.sh): the pictures are drawn on
# the Mac, looked at by a person, and committed. Doing it here instead would
# mean installing a drawing program into an operating system that has no other
# use for one, spending build minutes redrawing pictures nobody edited, and
# giving up the ability to review an icon before it ships. The renderer's own
# header explains it at length.
#
# ------------------------------------------------------------------------------
# WHY THERE IS NO gtk-update-icon-cache HERE
# ------------------------------------------------------------------------------
# A "cache" in an icon theme is one file that lists what the folders contain, so
# that a program can find an icon without reading every folder. It is a SPEED
# optimisation and nothing else: with no cache, GTK reads the folders, finds
# everything, and draws exactly the same desktop.
#
# We do not build one, for three reasons and in this order:
#
#   1. This repo does not build one for /usr/share/icons/hicolor either — the
#      folder our own logo has lived in since the start. Adding the habit for
#      two folders and not the third is how things drift.
#   2. ⚠️ GTK DECIDES WHETHER TO TRUST A CACHE BY COMPARING CLOCKS: if the
#      folder looks newer than the cache file, the cache is ignored. The tool
#      that packages a bootable image FLATTENS every file's clock to the same
#      value — the same fact that gave this project its "contents, never
#      timestamps" rule (build_files/aq-lib.sh). A shipped cache is therefore a
#      file whose usefulness depends on exactly the thing we know is unreliable
#      here. At best it works; at worst it is ignored; it can never be wrong in
#      a way that shows.
#   3. Twelve files in each theme is nothing to read.
#
# What this step does instead is check that no STALE cache is lying around, so
# that if somebody adds one later they cannot leave a half-made one behind.
#
# ------------------------------------------------------------------------------
# ⚠️ TODO — NOT THIS REPO'S JOB: SWITCHING TO THE DARK ICONS
# ------------------------------------------------------------------------------
# Aquarius-Midnight is built, installed, checked, and nothing ever selects it.
# That is on purpose. Following the desktop's light/dark setting is the SHELL's
# job — the aquarius-shell repository already watches the colour scheme, and the
# image has no business trying to do it a second time from a different place.
#
#   TODO (aquarius-shell): when the shell switches the colour scheme to dark, it
#   should also set org.gnome.desktop.interface icon-theme to
#   'Aquarius-Midnight', and back to 'Aquarius-Ice' when it goes light. Both
#   themes are already in the image; this is a one-setting change with no image
#   work behind it.
#
# Until that lands, a person who wants the dark icons sets them by hand:
#     gsettings set org.gnome.desktop.interface icon-theme 'Aquarius-Midnight'
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

ICONS_ROOT="/usr/share/icons"
DEFAULT_THEME="Aquarius-Ice"
DARK_THEME="Aquarius-Midnight"
LOOK_OVERRIDE="/usr/share/glib-2.0/schemas/zz1-aquarius-10-look.gschema.override"
GDM_LOOK="/etc/dconf/db/gdm.d/02-aquarius-look"
APPS_DIR="/usr/share/applications"
AUTOSTART_DIR="/etc/xdg/autostart"

# The eight sizes branding/render-app-icons.sh draws. If that list changes, this
# one changes with it — they are compared against the actual files below, so a
# disagreement stops the build rather than shipping half a theme.
SIZES=(16 24 32 48 64 128 256 512)

# Every icon file name that must exist in BOTH themes.
#
# ⚠️ THE THREE GNOME NAMES ARE THE POINT OF THE LIST. GNOME's Files asks for its
# icon as `org.gnome.Nautilus`, GNOME's Settings asks for `org.gnome.Settings`,
# and the Console asks for `org.gnome.Ptyxis` — Ptyxis is Fedora's terminal and
# it is the terminal this image ships. None of the three can be persuaded to ask
# for anything else, so those are the three names that actually replace an icon
# on screen. `aquarius-files`, `aquarius-settings` and `aquarius-console` are the
# SAME PICTURES filed a second time under our own names, so our windows, our docs
# and the Aquarius Shell can name them without knowing GNOME's internal
# identifiers.
ICON_NAMES=(
    aquarius-editor
    aquarius-writer
    org.gnome.Nautilus
    aquarius-files
    org.gnome.Settings
    aquarius-settings
    org.gnome.Ptyxis
    aquarius-console
    aquarius-apps
    aquarius-installer
    aquarius-welcome
    aquarius-install-resolve
    aquarius-remove-resolve
)

# Which launcher entry must carry which icon. Royce's table, 2026-09-06.
#
# ⚠️ aquarius-updater.desktop DELIBERATELY CARRIES THE SETTINGS ICON. There is
# no "Check for Update" app — it is a window the Aquarius logo menu opens — and
# it wears the Settings icon until that flow moves into System Settings where it
# belongs. Not an oversight; do not "fix" it by drawing it one.
DESKTOP_ICONS=(
    "${APPS_DIR}/aquarius-installer.desktop|aquarius-installer"
    "${APPS_DIR}/aquarius-creator-apps.desktop|aquarius-apps"
    "${APPS_DIR}/aquarius-welcome.desktop|aquarius-welcome"
    "${AUTOSTART_DIR}/aquarius-welcome-firstrun.desktop|aquarius-welcome"
    "${APPS_DIR}/aquarius-install-resolve.desktop|aquarius-install-resolve"
    "${APPS_DIR}/aquarius-remove-resolve.desktop|aquarius-remove-resolve"
    "${APPS_DIR}/aquarius-updater.desktop|org.gnome.Settings"
    "${APPS_DIR}/aquarius-writer.desktop|aquarius-writer"
    "/usr/share/aquarius/apps/aquarius-editor.desktop.in|aquarius-editor"
)

# ==============================================================================
# 1. Both themes are really here, and are really themes
# ==============================================================================
# A folder of pictures is not a theme. `index.theme` is what makes it one: it
# names the theme, lists which folders hold which sizes, and says what to fall
# back to. Without it every icon in the folder is invisible to every program.
say "The two Aquarius icon themes"

for theme in "${DEFAULT_THEME}" "${DARK_THEME}"; do
    index="${ICONS_ROOT}/${theme}/index.theme"

    if [ ! -r "${index}" ]; then
        bad "${index} is missing — nothing on this machine would find the ${theme} icons"
        continue
    fi

    aq_file_has "${index}" "^Name=${theme}$" "${theme}/index.theme names itself ${theme}"
    aq_file_has "${index}" "^Comment=" "${theme}/index.theme has a description"

    # The fall-through. We draw nine icons; a desktop needs thousands. Without
    # this line the machine is a screen full of grey squares.
    aq_file_has "${index}" "^Inherits=Adwaita,hicolor$" \
        "${theme} falls back to GNOME's icons for everything we do not draw"

    aq_file_has "${index}" "^Directories=.*scalable/apps" \
        "${theme}/index.theme lists its scalable folder"

    for size in "${SIZES[@]}"; do
        aq_file_has "${index}" "^\[${size}x${size}/apps\]$" \
            "${theme}/index.theme describes its ${size}x${size} folder"
    done
done

# ==============================================================================
# 2. Every icon, at every size, is really there and is really that size
# ==============================================================================
# ⚠️ CONTENTS, NEVER CLOCKS — and for a picture that means more than "the file
# exists". A PNG states its own width and height in the first two dozen bytes,
# so those bytes are what gets read: a 48-pixel folder holding a 512-pixel
# picture is not an error anywhere, it is just a blurry, slow desktop.
say "Every icon, at every size"

if ! aq_have python3; then
    bad "this image has no python3, so the icon sizes could not be read back"
else
    ICON_REPORT="$(mktemp)"
    if python3 - "${ICONS_ROOT}" "${DEFAULT_THEME} ${DARK_THEME}" "${SIZES[*]}" "${ICON_NAMES[*]}" \
        > "${ICON_REPORT}" 2>&1 << 'PY'
import os
import struct
import sys

icons_root = sys.argv[1]
themes = sys.argv[2].split()
sizes = [int(s) for s in sys.argv[3].split()]
names = sys.argv[4].split()

problems = 0


def bad(msg):
    global problems
    problems += 1
    print(f"BAD {msg}")


for theme in themes:
    root = os.path.join(icons_root, theme)
    for name in names:
        svg = os.path.join(root, "scalable", "apps", f"{name}.svg")
        if not os.path.isfile(svg) or os.path.getsize(svg) == 0:
            bad(f"{theme}: scalable/apps/{name}.svg is missing or empty")
        else:
            head = open(svg, encoding="utf-8", errors="replace").read(200)
            if "<svg" not in head or 'viewBox="0 0 64 64"' not in head:
                bad(f"{theme}: scalable/apps/{name}.svg is not an Aquarius icon "
                    "(no <svg> on the 64 grid)")

        for size in sizes:
            png = os.path.join(root, f"{size}x{size}", "apps", f"{name}.png")
            if not os.path.isfile(png):
                bad(f"{theme}: {size}x{size}/apps/{name}.png is missing")
                continue
            with open(png, "rb") as fh:
                header = fh.read(24)
            if header[:8] != b"\x89PNG\r\n\x1a\n":
                bad(f"{theme}: {size}x{size}/apps/{name}.png is not a PNG file")
                continue
            width, height = struct.unpack(">II", header[16:24])
            if (width, height) != (size, size):
                bad(f"{theme}: {size}x{size}/apps/{name}.png is actually "
                    f"{width}x{height}")

    print(f"COUNTED {theme} {len(names)} icons, "
          f"{sum(len(f) for _, _, f in os.walk(root))} files")

sys.exit(1 if problems else 0)
PY
    then
        while read -r line; do
            case "${line}" in
                COUNTED*) ok "${line#COUNTED }" ;;
                *) echo "  ${line}" ;;
            esac
        done < "${ICON_REPORT}"
        ok "all ${#ICON_NAMES[@]} icons, in both themes, at all ${#SIZES[@]} sizes, are the size they claim"
    else
        while read -r line; do
            case "${line}" in
                BAD*) bad "${line#BAD }" ;;
                COUNTED*) ok "${line#COUNTED }" ;;
                *) echo "  ${line}" ;;
            esac
        done < "${ICON_REPORT}"
    fi
    rm -f "${ICON_REPORT}"
fi

# The three GNOME names and our own names must be the SAME PICTURE. If they ever
# drift, Files shows one drawing in the dock and our docs describe another.
say "Our names and GNOME's names are the same drawing"

for theme in "${DEFAULT_THEME}" "${DARK_THEME}"; do
    for pair in "org.gnome.Nautilus|aquarius-files" "org.gnome.Settings|aquarius-settings" \
                "org.gnome.Ptyxis|aquarius-console"; do
        gnome_name="${pair%%|*}"
        our_name="${pair##*|}"
        a="${ICONS_ROOT}/${theme}/scalable/apps/${gnome_name}.svg"
        b="${ICONS_ROOT}/${theme}/scalable/apps/${our_name}.svg"
        if [ ! -r "${a}" ] || [ ! -r "${b}" ]; then
            bad "${theme}: ${gnome_name} or ${our_name} is missing, so they cannot be compared"
        elif cmp -s "${a}" "${b}"; then
            ok "${theme}: ${gnome_name} and ${our_name} are the same drawing"
        else
            bad "${theme}: ${gnome_name} and ${our_name} have drifted apart — regenerate with branding/render-app-icons.sh"
        fi
    done
done

# ==============================================================================
# 3. Nothing left a half-made icon cache behind
# ==============================================================================
# See the long note at the top: we deliberately do not build one. This is the
# check that stops somebody adding one and leaving it stale.
say "No stale icon caches"

for theme in "${DEFAULT_THEME}" "${DARK_THEME}"; do
    cache="${ICONS_ROOT}/${theme}/icon-theme.cache"
    if [ -e "${cache}" ]; then
        bad "${cache} exists — this project does not ship icon caches (see the header of this script)"
    else
        ok "${theme} has no icon cache, which is what we want"
    fi
done

# ==============================================================================
# 4. The default icon theme is Aquarius-Ice — in both places, and it resolves
# ==============================================================================
# AquariusOS is light-first, so Ice is the default. It has to be set in TWO
# places, and a machine where they disagree changes its icons the instant you
# log in:
#
#   the desktop     zz1-aquarius-10-look.gschema.override  (every new account)
#   the login screen /etc/dconf/db/gdm.d/02-aquarius-look   (build_files/50-…)
#
# The check that counts is the last one: ask the finished image what a brand-new
# account's setting IS, exactly as GNOME will on first login.
say "The default icon theme"

aq_file_has "${LOOK_OVERRIDE}" "^icon-theme='${DEFAULT_THEME}'$" \
    "a new account's desktop defaults to ${DEFAULT_THEME}"
aq_file_has "${GDM_LOOK}" "^icon-theme='${DEFAULT_THEME}'$" \
    "the login screen uses ${DEFAULT_THEME} too, so the icons do not change when you log in"

if aq_have gsettings; then
    got="$(GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.interface icon-theme 2> /dev/null || echo '<error>')"
    if [ "${got}" = "'${DEFAULT_THEME}'" ]; then
        ok "the image itself reports icon-theme = ${got}"
    else
        bad "the image reports icon-theme = ${got}, expected '${DEFAULT_THEME}'"
    fi
else
    bad "gsettings is not in this image, so the default could not be read back"
fi

# A setting naming a theme that is not on disk is not an error — GNOME quietly
# falls back to Adwaita and the desktop looks stock. So the thing it points at
# gets checked too.
for dir in "${ICONS_ROOT}/${DEFAULT_THEME}" "${ICONS_ROOT}/${DARK_THEME}"; do
    if [ -d "${dir}" ]; then
        ok "${dir} exists"
    else
        bad "${dir} is missing — the icon-theme setting would fall back to Adwaita in silence"
    fi
done

# ==============================================================================
# 5. Every launcher asks for the icon it is supposed to ask for
# ==============================================================================
# A launcher entry names its icon by name. Name one that does not exist and the
# desktop draws a generic grey square — or, worse, nothing at all — with no
# message anywhere. So each entry's Icon= line is read, compared against Royce's
# table, and then the name it asks for is looked up in the theme.
say "Every launcher's icon"

for entry in "${DESKTOP_ICONS[@]}"; do
    file="${entry%%|*}"
    want="${entry##*|}"

    if [ ! -r "${file}" ]; then
        bad "${file} is missing, so its icon could not be checked"
        continue
    fi

    aq_file_has "${file}" "^Icon=${want}$" "$(basename "${file}") asks for ${want}"

    if [ -r "${ICONS_ROOT}/${DEFAULT_THEME}/scalable/apps/${want}.svg" ]; then
        ok "  …and ${want} is in ${DEFAULT_THEME}"
    else
        bad "  …but ${want} is NOT in ${DEFAULT_THEME} — that launcher would show a blank square"
    fi
done

# ------------------------------------------------------------------------------
# The Console's launcher is not ours — it comes with Ptyxis
# ------------------------------------------------------------------------------
# Every entry in the table above is a file this repo writes, so if one asks for
# the wrong icon that is our mistake to make. The Console is different: Ptyxis is
# Fedora's terminal, its launcher arrives with the RPM, and we replace its icon
# purely by filing a drawing under the name it already asks for. That means the
# whole thing hangs on a name we do not control. If Fedora ever renames the
# launcher or the icon it asks for, our drawing is simply never looked up — no
# error, no blank square, just GNOME's own terminal icon in a dock full of
# Aquarius ones. So the name is read back out of Ptyxis's own launcher here.
PTYXIS_DESKTOP="${APPS_DIR}/org.gnome.Ptyxis.desktop"
if [ -r "${PTYXIS_DESKTOP}" ]; then
    aq_file_has "${PTYXIS_DESKTOP}" "^Icon=org.gnome.Ptyxis$" \
        "Ptyxis's own launcher asks for org.gnome.Ptyxis, which is the name we draw"
else
    bad "${PTYXIS_DESKTOP} is missing — the terminal this image ships has no launcher"
fi

# The logo keeps its own icon and its own job. Everything that is the OS itself
# — the About page, the boot screen, the logo menu — still uses aquarius-logo,
# and none of that changed here.
if [ -s "${ICONS_ROOT}/hicolor/scalable/apps/aquarius-logo.svg" ]; then
    ok "aquarius-logo is still where the OS's own branding looks for it"
else
    bad "aquarius-logo.svg has gone missing from hicolor — the About page and boot screen use it"
fi

aq_finish "STEP 5.6 — the AquariusOS app icons"
