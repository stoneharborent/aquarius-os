#!/usr/bin/bash
# ==============================================================================
# STEP 5 — Making it look and feel like AquariusOS
# ==============================================================================
# Up to here we have assembled a competent, completely anonymous Fedora GNOME
# machine. This step is where it becomes ours:
#
#   * our files are copied in (wallpaper, logos, fonts, settings)
#   * GNOME's factory defaults are replaced with ours: Ice light theme,
#     Aquarius blue, Inter and JetBrains Mono, our wallpaper, our dock
#   * the Settings > About page shows our logo instead of Fedora's
#   * the login screen shows our logo
#   * the "Make Editor-Ready" right-click menu is installed in Files
#
# ⚠️ THE POSTURE, WHICH IS A DECISION AND NOT LAZINESS
#
# We work WITH GNOME's grain. Accent colour, wallpaper, fonts, a small set of
# extensions, and then we stop. No GNOME Shell theme, no GTK theme, no icon
# theme, no libadwaita patching. Every theme we do not ship is a theme that
# cannot break on the next GNOME release, and chasing GNOME's internals is a
# treadmill that has eaten entire distributions.
#
# The one thing we would like and cannot have is the exact Aquarius Blue
# (#2C8FC4) as the accent. GNOME accepts nine fixed words for that setting and
# a hex colour is not one of them. Patching libadwaita to add a tenth would mean
# owning a fork of the library every GTK app draws itself with, forever, and
# Ubuntu has been paying that bill for years. So: 'blue', which is the nearest
# of the nine and a good match.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

SCHEMA_DIR="/usr/share/glib-2.0/schemas"
BACKGROUNDS_DIR="/usr/share/backgrounds/aquarius"
BACKGROUND_XML="/usr/share/gnome-background-properties/aquarius.xml"
NAUTILUS_EXT="/usr/share/nautilus-python/extensions/aquarius_editor_ready.py"
LOGO_SVG="/usr/share/icons/hicolor/scalable/apps/aquarius-logo.svg"
LOGO_PNG="/usr/share/aquarius/branding/aquarius-logo.png"
ABOUT_LOGO_SRC_LIGHT="/usr/share/aquarius/branding/aquarius-about-logo.png"
ABOUT_LOGO_SRC_DARK="/usr/share/aquarius/branding/aquarius-about-logo-white.png"
ABOUT_LOGO_DEST_LIGHT="/usr/share/pixmaps/fedora_logo_med.png"
ABOUT_LOGO_DEST_DARK="/usr/share/pixmaps/fedora_whitelogo_med.png"
CONTROL_CENTER="/usr/bin/gnome-control-center"

# ==============================================================================
# 1. Copy our own files into the image
# ==============================================================================
# Everything under system_files/ is laid out exactly as it will sit on the
# finished system, so this is a straight copy from the root of that folder to
# the root of the image. Adding a file to the OS means putting it in the right
# place under system_files/ — there is no list to update.
say "Copying the AquariusOS files into the image"
cp -avf /ctx/system_files/. /

# ==============================================================================
# 2. Sora, the headline typeface
# ==============================================================================
# Sora is not packaged by anybody, so it ships as a font file in system_files/
# and was copied in just now. Fonts are not found by being present — they are
# found by being in an index, and the index has to be rebuilt after anything is
# added. Skipping this gives a machine with the font file on disk and no
# application able to see it.
say "Rebuilding the font index"
fc-cache --system-only --force
if aq_output_has "Sora" fc-list; then
    ok "Sora is installed and findable"
else
    bad "Sora is on disk but no application can find it — the font index did not rebuild"
fi
for want in Inter "JetBrains Mono"; do
    if aq_output_has "${want}" fc-list; then
        ok "${want} is installed and findable"
    else
        bad "${want} is not findable — the interface would fall back to a default face"
    fi
done

# ==============================================================================
# 3. The About page logo
# ==============================================================================
# ⚠️ THIS ONE COST US A DAY, SO READ IT BEFORE CHANGING IT.
#
# Every guide on the internet says the logo on GNOME's About page comes from the
# LOGO= line in os-release. On Fedora that is not true. Fedora compiles
# gnome-control-center with two picture paths hardcoded into the program — one
# for light mode, one for dark — and the os-release branch is dead code that
# never runs. So the ONLY way to brand that page is to replace those two files.
#
# That is what Bazzite does too, and it is what we do. The check below greps the
# actual compiled program for the paths, so that if Fedora ever moves the
# pictures the build stops and says so, instead of shipping an image that
# quietly shows Fedora's logo on the About page.
#
# The two pictures are 279x80 and that size is load-bearing: the page lays out
# around the image's own dimensions, so a differently-shaped logo pushes the
# text around.
say "The About page logo"

for f in "${ABOUT_LOGO_SRC_LIGHT}" "${ABOUT_LOGO_SRC_DARK}"; do
    if [ ! -s "$f" ]; then
        echo "AQUARIUS ERROR: ${f} is missing or empty." >&2
        echo "                It is one of the two About-page logos. Re-draw them with:" >&2
        echo "                    bash branding/render-about-logo.sh" >&2
        exit 1
    fi
done

if [ ! -x "${CONTROL_CENTER}" ]; then
    echo "AQUARIUS ERROR: ${CONTROL_CENTER} is not in this image, so there is no" >&2
    echo "                Settings app and no About page. Step 4 should have" >&2
    echo "                installed gnome-control-center." >&2
    exit 1
fi

echo "Paths under /usr/share/pixmaps named inside ${CONTROL_CENTER}:"
CC_PIXMAP_PATHS="$(grep -a -o -E '/usr/share/pixmaps/[A-Za-z0-9._+-]+' "${CONTROL_CENTER}" | sort -u || true)"
if [ -z "${CC_PIXMAP_PATHS}" ]; then
    echo "  (none)"
else
    echo "${CC_PIXMAP_PATHS}" | sed 's/^/  /'
fi

for want in "${ABOUT_LOGO_DEST_LIGHT}" "${ABOUT_LOGO_DEST_DARK}"; do
    if printf '%s\n' "${CC_PIXMAP_PATHS}" > /tmp/aq-cc-paths.txt && grep -qx "${want}" /tmp/aq-cc-paths.txt; then
        ok "the Settings app really does read ${want}"
    else
        echo "AQUARIUS ERROR: this image's Settings app does not mention ${want}." >&2
        echo "                That is the file we replace to brand the About page, so" >&2
        echo "                replacing it would now do nothing and the page would keep" >&2
        echo "                showing Fedora's logo. Fedora has probably moved the" >&2
        echo "                picture — the paths this build DOES name are listed above." >&2
        echo "                Pick the light and dark ones and update the two DEST paths" >&2
        echo "                at the top of this script." >&2
        exit 1
    fi
done

install -D -m 0644 "${ABOUT_LOGO_SRC_LIGHT}" "${ABOUT_LOGO_DEST_LIGHT}"
install -D -m 0644 "${ABOUT_LOGO_SRC_DARK}" "${ABOUT_LOGO_DEST_DARK}"

if cmp -s "${ABOUT_LOGO_SRC_LIGHT}" "${ABOUT_LOGO_DEST_LIGHT}" \
    && cmp -s "${ABOUT_LOGO_SRC_DARK}" "${ABOUT_LOGO_DEST_DARK}"; then
    ok "the About page now shows the AquariusOS logo, light and dark"
else
    bad "the About-page logos did not copy correctly"
    ls -l "${ABOUT_LOGO_DEST_LIGHT}" "${ABOUT_LOGO_DEST_DARK}" || true
fi

# ==============================================================================
# 4. The login screen logo
# ==============================================================================
# GDM reads its settings from its own dconf database, which is separate from
# every user's. Two files are needed and neither does anything on its own:
#
#   /etc/dconf/profile/gdm   tells GDM which databases to read
#   /etc/dconf/db/gdm.d/…    the setting itself
#
# and then `dconf update` has to bake the folder into a binary database. Drop
# the file in and run nothing, and nothing happens, with no error anywhere.
#
# The setting takes a path to a real picture. A path pointing at nothing gives a
# login screen with a blank space where the logo should be — silently. So the
# file is checked first.
say "The login screen logo"

if [ ! -r "${LOGO_PNG}" ]; then
    echo "AQUARIUS ERROR: ${LOGO_PNG} is missing." >&2
    echo "                Re-render it with: bash branding/render-logo-png.sh" >&2
    exit 1
fi

install -d -m 0755 /etc/dconf/profile
if [ -f /etc/dconf/profile/gdm ]; then
    ok "/etc/dconf/profile/gdm already exists — leaving it alone"
    aq_file_has /etc/dconf/profile/gdm '^system-db:gdm$' "GDM reads its own settings database"
else
    echo "NOTE: writing /etc/dconf/profile/gdm (this image did not have one)."
    cat > /etc/dconf/profile/gdm << 'EOF'
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF
fi

install -d -m 0755 /etc/dconf/db/gdm.d
cat > /etc/dconf/db/gdm.d/01-aquarius-logo << EOF
[org/gnome/login-screen]
logo='${LOGO_PNG}'
EOF

if ! aq_have dconf; then
    echo "AQUARIUS ERROR: the 'dconf' command is not in this image." >&2
    exit 1
fi
dconf update

if [ -s /etc/dconf/db/gdm ]; then
    ok "the login screen settings database was built"
else
    bad "/etc/dconf/db/gdm was not written — the login screen would keep Fedora's logo"
fi
if grep -a -q "${LOGO_PNG}" /etc/dconf/db/gdm 2> /dev/null; then
    ok "the built database really names our logo"
else
    bad "/etc/dconf/db/gdm does not mention ${LOGO_PNG} — it was built without our file"
fi

# ==============================================================================
# 5. The GNOME defaults
# ==============================================================================
# The three .gschema.override files copied in at the top of this script are what
# make a brand-new account come up as Ice-light AquariusOS instead of stock
# Fedora. Read the long header inside zz1-aquarius-10-look.gschema.override for
# what an override file is and why it is only a default that a user always beats.
#
# Two things have to happen and the second is the one people forget:
#
#   1. check the files name real settings with valid values
#   2. rebuild the settings index, or every one of them is ignored
say "The AquariusOS GNOME defaults"

echo "Override files in ${SCHEMA_DIR}:"
ls -l "${SCHEMA_DIR}"/zz1-aquarius-*.gschema.override

if ! aq_have glib-compile-schemas; then
    echo "AQUARIUS ERROR: glib-compile-schemas is not in this image (it belongs to" >&2
    echo "                the glib2 package), so the defaults cannot be applied." >&2
    exit 1
fi

# --strict rejects a setting name that does not exist, or a value of the wrong
# shape. It is run in a copy of the folder first, because --strict on the real
# folder would leave the index half-written if it failed.
#
# ⚠️ The *.enums.xml files have to be copied too. Some GNOME settings are
# "one of these words" and the list of words lives in a separate enums file; a
# strict compile without them fails on settings that are perfectly correct.
AQ_SCHEMA_TEST="$(mktemp -d)"
cp "${SCHEMA_DIR}"/*.gschema.xml "${AQ_SCHEMA_TEST}/"
cp "${SCHEMA_DIR}"/*.enums.xml "${AQ_SCHEMA_TEST}/" 2> /dev/null || true
cp "${SCHEMA_DIR}"/zz1-aquarius-*.gschema.override "${AQ_SCHEMA_TEST}/"
if ! glib-compile-schemas --strict "${AQ_SCHEMA_TEST}"; then
    echo "AQUARIUS ERROR: one of the AquariusOS override files is wrong." >&2
    echo "                Read the message above — it names the file, the setting" >&2
    echo "                and the problem. The usual cause is a misspelled setting" >&2
    echo "                name, or one this version of GNOME has renamed." >&2
    rm -rf "${AQ_SCHEMA_TEST}"
    exit 1
fi
rm -rf "${AQ_SCHEMA_TEST}"
ok "every override file names real settings with valid values"

rm -f "${SCHEMA_DIR}/gschemas.compiled"
glib-compile-schemas "${SCHEMA_DIR}"
if [ -s "${SCHEMA_DIR}/gschemas.compiled" ]; then
    ok "the settings index was rebuilt"
else
    bad "${SCHEMA_DIR}/gschemas.compiled was not written — every AquariusOS default would be ignored"
fi

# The real proof: ask GNOME what the settings ARE now, in this image. This is
# the "trust content, never timestamps" rule in its most literal form — the
# check does not look at our file at all, it asks the system the same question
# a freshly created user account will ask on first login.
#
# GSETTINGS_BACKEND=memory means "do not look for a running dconf daemon, just
# read the compiled defaults", which is the only thing that can work inside a
# build with no desktop session running.
say "Asking GNOME what the defaults are now"
if aq_have gsettings; then
    want() { # want <group> <setting> <expected>
        got="$(GSETTINGS_BACKEND=memory gsettings get "$1" "$2" 2> /dev/null || echo '<error>')"
        if [ "${got}" = "$3" ]; then
            ok "$1 $2 = ${got}"
        else
            bad "$1 $2 is ${got}, expected $3"
        fi
    }
    want org.gnome.desktop.interface color-scheme "'default'"
    want org.gnome.desktop.interface accent-color "'blue'"
    want org.gnome.desktop.interface font-name "'Inter 11'"
    want org.gnome.desktop.interface document-font-name "'Inter 11'"
    want org.gnome.desktop.interface monospace-font-name "'JetBrains Mono 10'"
    want org.gnome.desktop.background picture-options "'zoom'"
    want org.gnome.shell.extensions.dash-to-dock dock-position "'BOTTOM'"
    want org.gnome.shell.extensions.dash-to-dock dock-fixed "true"
    want org.gnome.shell.extensions.dash-to-dock intellihide "false"
    want org.gnome.shell.extensions.dash-to-dock extend-height "false"

    echo "  ---- for the log ----"
    GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.background picture-uri || true
    GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.background picture-uri-dark || true
    GSETTINGS_BACKEND=memory gsettings get org.gnome.shell favorite-apps || true
    GSETTINGS_BACKEND=memory gsettings get org.gnome.shell enabled-extensions || true

    # ----------------------------------------------------------------------
    # Every app pinned to the dock must actually be installed
    # ----------------------------------------------------------------------
    # A name in favorite-apps that does not match a real .desktop file is
    # silent: the icon simply does not appear. So the list is read back out of
    # GNOME and every entry is checked against the applications folder. This is
    # what keeps the dock honest as apps come and go between phases.
    say "Checking every app pinned to the dock is really installed"
    GSETTINGS_BACKEND=memory gsettings get org.gnome.shell favorite-apps \
        | tr -d "[]' " | tr ',' '\n' | grep -v '^$' > /tmp/aq-favorites.txt || true
    while read -r fav; do
        if [ -r "/usr/share/applications/${fav}" ]; then
            ok "dock: ${fav}"
        else
            bad "dock: ${fav} is pinned but /usr/share/applications/${fav} does not exist — the icon would just be missing"
        fi
    done < /tmp/aq-favorites.txt
    rm -f /tmp/aq-favorites.txt

    # ----------------------------------------------------------------------
    # Every extension switched on must actually be installed
    # ----------------------------------------------------------------------
    # Same trap, same silence: GNOME simply does not load an extension it
    # cannot find, and says nothing.
    say "Checking every extension switched on is really installed"
    GSETTINGS_BACKEND=memory gsettings get org.gnome.shell enabled-extensions \
        | tr -d "[]' " | tr ',' '\n' | grep -v '^$' > /tmp/aq-extensions.txt || true
    while read -r ext; do
        if [ -r "/usr/share/gnome-shell/extensions/${ext}/metadata.json" ]; then
            ok "extension: ${ext}"
        else
            bad "extension: ${ext} is switched on but is not installed — GNOME would ignore it silently"
        fi
    done < /tmp/aq-extensions.txt
    rm -f /tmp/aq-extensions.txt
else
    bad "gsettings is not in this image, so the defaults could not be read back"
fi

# ==============================================================================
# 6. The wallpaper
# ==============================================================================
# "The Pour" ships in two colourways — Ice for the light appearance, Midnight
# for dark — and GNOME swaps between them by itself.
#
# Two separate things have to be true and it is easy to do one and forget the
# other:
#   * it is the wallpaper on a new machine   → the override file, checked above
#   * it is IN THE LIST in Settings          → the XML file, checked here
#
# The paths are written in both places, so they are compared rather than
# remembered: a rename that only updates one gives a desktop that comes up a
# flat colour, with no error.
say "The wallpaper"

for f in "${BACKGROUNDS_DIR}/the-pour-ice-3840x2160.png" \
    "${BACKGROUNDS_DIR}/the-pour-midnight-3840x2160.png"; do
    if [ -s "$f" ]; then
        ok "$(basename "$f") is installed ($(stat -c '%s' "$f") bytes)"
    else
        bad "$f is missing — the desktop would come up a flat colour"
    fi
done

for want in the-pour-ice-3840x2160.png the-pour-midnight-3840x2160.png; do
    aq_file_has "${SCHEMA_DIR}/zz1-aquarius-10-look.gschema.override" "${want}" \
        "the defaults point at ${want}"
    aq_file_has "${BACKGROUND_XML}" "${want}" \
        "Settings > Appearance lists ${want}"
done

# ==============================================================================
# 7. The "Make Editor-Ready" right-click menu
# ==============================================================================
# The ingest helper is the flagship creator feature of this operating system and
# it is worth saying why, because it looks like a small utility.
#
# Free DaVinci Resolve on Linux cannot open a file from a camera or a phone. Not
# "opens it badly" — cannot open it. H.264 and H.265 decoding is Studio-only and
# NVIDIA-only, and AAC audio is not supported at all, in any version. Every
# person who tries Resolve on Linux hits this on their first import and most of
# them conclude Linux is not for editing.
#
# `aq-ingest` fixes it at the operating-system level: it rewraps the audio to
# PCM and makes an edit-friendly video copy, so the file opens. Nobody else
# ships this. In R1 it is the command and the right-click menu; R3 makes it a
# proper service with the Resolve container behind it.
say "The ingest helper and its right-click menu"

if ! aq_have python3; then
    echo "AQUARIUS ERROR: this image has no python3, so aq-ingest cannot be installed." >&2
    exit 1
fi

AQ_PYTHON_VERSION="$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
AQ_INGEST_SITE="/usr/lib/python${AQ_PYTHON_VERSION}/site-packages"
if ! python3 -c "import sys; sys.exit(0 if '${AQ_INGEST_SITE}' in sys.path else 1)"; then
    echo "AQUARIUS ERROR: ${AQ_INGEST_SITE} is not on this image's Python search path," >&2
    echo "                so installing there would produce a broken command. Python" >&2
    echo "                looks in:" >&2
    python3 -c "import sys; print('\n'.join('                  ' + p for p in sys.path if p))" >&2
    exit 1
fi

install -d -m 0755 "${AQ_INGEST_SITE}"
rm -rf "${AQ_INGEST_SITE:?}/aq_ingest"
cp -a /ctx/ingest/aq_ingest "${AQ_INGEST_SITE}/aq_ingest"
find "${AQ_INGEST_SITE}/aq_ingest" -name '__pycache__' -type d -prune -exec rm -rf {} +
python3 -m compileall -q "${AQ_INGEST_SITE}/aq_ingest"
install -D -m 0755 /ctx/ingest/aq-ingest /usr/bin/aq-ingest

# Actually run it. A Python package can install perfectly and fail to start
# because of one missing import, and this is the cheapest possible way to find
# that out here rather than on Royce's machine.
/usr/bin/aq-ingest --version
/usr/bin/aq-ingest --help > /dev/null
ok "aq-ingest runs"

# The Files right-click menu. nautilus-python loads any .py file in this folder
# and ignores, silently, any that does not compile — so it is compiled here.
if [ -r "${NAUTILUS_EXT}" ]; then
    ok "the 'Make Editor-Ready' menu item is installed"
    if python3 -m py_compile "${NAUTILUS_EXT}" 2> /dev/null; then
        ok "its code compiles — Files will load it"
    else
        bad "${NAUTILUS_EXT} does not compile — Files would ignore it silently"
    fi
    rm -rf "$(dirname "${NAUTILUS_EXT}")/__pycache__"
else
    bad "${NAUTILUS_EXT} is missing — there would be no right-click ingest"
fi

# aq-ingest is ffmpeg wearing a menu. Without these two it refuses to run.
for tool in ffmpeg ffprobe; do
    if aq_have "${tool}"; then
        ok "${tool} is present (aq-ingest needs it)"
    else
        bad "${tool} is missing — aq-ingest would refuse to run"
    fi
done

# ==============================================================================
# 8. Odds and ends
# ==============================================================================
say "The AquariusOS icon"
if [ -s "${LOGO_SVG}" ]; then
    ok "$(basename "${LOGO_SVG}") is installed"
else
    bad "${LOGO_SVG} is missing — os-release names it and the About page would be blank"
fi

# Nothing in system_files/ should be writable by everybody: /usr is meant to be
# read-only and a world-writable file there is a security hole that `bootc
# container lint` will not catch.
say "Permissions on the files we shipped"
find /usr/share/aquarius /usr/share/backgrounds/aquarius \
    ! -type l -perm -o+w > /tmp/aq-world-writable.txt 2> /dev/null || true
if [ ! -s /tmp/aq-world-writable.txt ]; then
    ok "nothing we shipped is world-writable"
else
    bad "world-writable files under /usr:"
    sed 's/^/       /' /tmp/aq-world-writable.txt
fi
rm -f /tmp/aq-world-writable.txt

aq_finish "The AquariusOS desktop layer"
