#!/usr/bin/bash
# ==============================================================================
# AquariusOS — the GNOME desktop layer
# ==============================================================================
# WHAT THIS FILE DOES
#   Everything that makes a Bazzite GNOME image into an AquariusOS GNOME image,
#   apart from the dock (that is build_files/gnome-extensions.sh, which runs
#   just before this one).
#
#   1. Installs the two small packages the GNOME versions of our own tools need.
#   2. Trims the handheld-only settings file off the images that are not the
#      handheld.
#   3. Puts the AquariusOS logo on the login screen.
#   4. Compiles the settings defaults — WITHOUT this last step, every single
#      thing in our override files is a file nobody reads.
#
# HOW OUR DEFAULTS REACH THE DESKTOP, IN PLAIN ENGLISH
#   GNOME keeps a compiled index of every setting on the machine at
#   /usr/share/glib-2.0/schemas/gschemas.compiled. Text files ending
#   .gschema.override in that folder change what the factory value of a setting
#   is — but only when that index is rebuilt. Drop the files in and do nothing
#   else and NOTHING happens, with no error anywhere. Rebuilding the index is
#   the last thing this script does.
#
#   ⚠️ THIS IS NOT THE SAME MECHANISM THE KDE LINE USES, and the difference is
#   worth understanding. On KDE we ship a folder of settings files and put it on
#   Plasma's own search path (system_files/etc/xdg/plasma-workspace/env/
#   zz-aquarius.sh), so KDE reads our answers as one more layer underneath the
#   user's. On GNOME there is no such cascade: there is one settings database,
#   and the override mechanism changes what "untouched" means inside it.
#
#   What the two have in common is the part that matters: in both, a person's
#   own choice always wins. Nothing here is a lock, and nothing here will ever
#   overwrite a setting somebody has changed.
#
# Called from build_files/build.sh, GNOME images only.
# Beginner-facing write-up: docs/gnome-variants.md
# ==============================================================================

set -euo pipefail

AQ_IMAGE_NAME="${IMAGE_NAME:-aquarius-os-gnome}"

SCHEMA_DIR="/usr/share/glib-2.0/schemas"
BACKGROUNDS_DIR="/usr/share/backgrounds/aquarius"
BACKGROUND_XML="/usr/share/gnome-background-properties/aquarius.xml"
NAUTILUS_EXT="/usr/share/nautilus-python/extensions/aquarius_editor_ready.py"
HANDHELD_OVERRIDE="${SCHEMA_DIR}/zz1-aquarius-40-handheld.gschema.override"
LOGO_PNG="/usr/share/aquarius/branding/aquarius-logo.png"

say() { echo; echo "=== $* ==="; }

# ==============================================================================
# 1 — The two packages the GNOME versions of our own tools need
# ==============================================================================
# Both are small, both are permanent, and both are here because a piece of
# AquariusOS does not work without them.
#
#   zenity           How a script asks a question with a window on GNOME.
#                    kdialog is the KDE equivalent and is not on a GNOME image,
#                    so without this the first-login "set up your creator apps"
#                    window would simply never appear — and the way that script
#                    is written (correctly), it would not even complain: it
#                    exits quietly rather than failing in front of a new user.
#                    Bazzite's GNOME images do usually carry zenity already, so
#                    this line often costs a second and changes nothing. It is
#                    here as insurance, exactly like the libnotify line in
#                    build.sh.
#
#   nautilus-python  What lets a Python file add an item to the right-click menu
#                    in Files. Our "Make Editor-Ready" menu item is that file.
#                    Nothing else on the machine provides this, and without it
#                    the ingest tool is terminal-only on GNOME.
# ------------------------------------------------------------------------------

say "Installing the GNOME-side packages"
dnf5 install -y zenity nautilus-python

# ==============================================================================
# 2 — Handheld-only settings: kept on the handheld, deleted from the others
# ==============================================================================
# Same shape as the KDE line's /usr/share/aquarius/xdg-handheld trim in
# build.sh, and for the same reason: shipping the file everywhere and removing
# it again is the arrangement that cannot fail quietly. The file is always in
# the repo, always reviewed, always in one place, and the only image-specific
# thing is one `rm -f`.
#
# What is in it, and why only the handheld wants it, is written at the top of
# system_files/usr/share/glib-2.0/schemas/zz1-aquarius-40-handheld.gschema.override.
# ------------------------------------------------------------------------------

say "Handheld-only settings"
case "${AQ_IMAGE_NAME}" in
*deck*)
    echo "OK: '${AQ_IMAGE_NAME}' is the GNOME handheld image — keeping the handheld settings."
    # Prove it is really there. A file that quietly stopped being copied would
    # otherwise ship a handheld with two on-screen keyboards fighting each
    # other, and nothing would go red.
    test -r "${HANDHELD_OVERRIDE}"
    grep -q "block-caribou-36@lxylxy123456.ercli.dev" "${HANDHELD_OVERRIDE}"
    ;;
*)
    echo "NOTE: '${AQ_IMAGE_NAME}' is a desktop image — removing the handheld-only settings."
    rm -f "${HANDHELD_OVERRIDE}"
    ;;
esac

# ==============================================================================
# 3 — The AquariusOS logo on the login screen
# ==============================================================================
# GDM is GNOME's login screen. It reads its settings from its OWN settings
# database rather than from the one every other account uses — which makes
# sense (it runs before anybody has logged in) and means the override files
# above do not reach it. The supported way to change something about it is the
# one used here, and it is GNOME's own documented sysadmin recipe:
#
#   /etc/dconf/profile/gdm      says where GDM's settings come from
#   /etc/dconf/db/gdm.d/…       the settings themselves, as plain text
#   dconf update                turns that folder into the database GDM reads
#
# ⚠️ NOT ON THE HANDHELD, AND THIS IS NOT AN OVERSIGHT. Bazzite's handheld
# images use SDDM as their login screen, not GDM — even the GNOME ones. That is
# not an accident on their side either: SDDM is what Valve's Game Mode session
# is wired into, and /usr/libexec/bazzite-autologin writes SDDM configuration to
# decide whether the machine boots into Game Mode or the desktop. Writing GDM
# settings on that image would be writing a file nothing reads. Branding the
# handheld's login screen is a separate job for a later phase.
# ------------------------------------------------------------------------------

say "The login screen logo"
case "${AQ_IMAGE_NAME}" in
*deck*)
    echo "NOTE: the GNOME handheld uses SDDM, not GDM — skipping the GDM logo."
    ;;
*)
    if [ ! -r "${LOGO_PNG}" ]; then
        echo "AQUARIUS ERROR: ${LOGO_PNG} is missing." >&2
        echo "                GDM's logo setting takes a path to a real picture file," >&2
        echo "                and a path pointing at nothing gives a login screen with" >&2
        echo "                a blank space where the logo should be — silently." >&2
        echo "                Re-render it with: bash branding/render-logo-png.sh" >&2
        exit 1
    fi

    # The profile file. Fedora's gdm package usually ships one already, and if
    # it does we leave it exactly alone — it is not ours and replacing it could
    # take other GDM defaults with it. All we insist on is that it really does
    # read the gdm database, because that is the line our settings arrive
    # through.
    if [ -f /etc/dconf/profile/gdm ]; then
        echo "OK: /etc/dconf/profile/gdm already exists — leaving it alone."
        if ! grep -q '^system-db:gdm$' /etc/dconf/profile/gdm; then
            echo "AQUARIUS ERROR: /etc/dconf/profile/gdm does not read the 'gdm' database," >&2
            echo "                so the logo setting below would never be seen. The file:" >&2
            cat /etc/dconf/profile/gdm >&2
            exit 1
        fi
    else
        echo "NOTE: writing /etc/dconf/profile/gdm (this image did not have one)."
        install -d -m 0755 /etc/dconf/profile
        cat > /etc/dconf/profile/gdm <<'EOF'
# Written at build time by build_files/gnome-desktop.sh.
# This is GNOME's standard login-screen settings profile, read top to bottom.
user-db:user
system-db:gdm
file-db:/usr/share/gdm/greeter-dconf-defaults
EOF
    fi

    install -d -m 0755 /etc/dconf/db/gdm.d
    cat > /etc/dconf/db/gdm.d/01-aquarius-logo <<EOF
# Written at build time by build_files/gnome-desktop.sh — do not edit by hand.
# The picture GDM shows under the clock on the login screen.
[org/gnome/login-screen]
logo='${LOGO_PNG}'
EOF

    # Turn the text file above into the database GDM actually reads. Without
    # this, the file sits there and the login screen never changes.
    if ! command -v dconf > /dev/null 2>&1; then
        echo "AQUARIUS ERROR: the 'dconf' command is not in this image, so the login" >&2
        echo "                screen settings cannot be compiled." >&2
        exit 1
    fi
    dconf update

    # And prove the compiled database really came out, rather than assuming.
    if [ -s /etc/dconf/db/gdm ]; then
        echo "OK: the login screen database was rebuilt."
    else
        echo "AQUARIUS ERROR: /etc/dconf/db/gdm was not written. The login screen" >&2
        echo "                would keep Bazzite's logo." >&2
        exit 1
    fi
    ;;
esac

# ==============================================================================
# 4 — Compile the settings defaults  (THE STEP EVERYTHING ELSE DEPENDS ON)
# ==============================================================================
# This is the line that makes every override file real. It has to be last,
# because anything installed after it that adds a settings description would not
# be in the index.
#
# It is done in two passes, and the first one is the important one:
#
#   PASS 1, in a throwaway copy, with --strict, and with ONLY OUR OVERRIDES.
#     --strict turns warnings into errors. In particular it turns "this override
#     mentions a setting that does not exist" — a typo in one of our files, or a
#     setting GNOME renamed in a new release — from a warning nobody reads into
#     a failed build.
#
#     ⚠️ The copy contains every schema in the image but ONLY the zz1-aquarius-*
#     override files, and that scoping is the whole point. Bazzite and several
#     Fedora packages ship overrides of their own; one of THOSE emitting a
#     warning is not our business and must not be able to stop AquariusOS
#     shipping. Copying only ours means a failure here is unambiguously ours,
#     and points at a file we can fix. Do not "simplify" this to copy them all.
#
#   PASS 2, for real, on the real folder, without --strict.
#     Writes the index the machine actually uses, from everybody's overrides.
#
# The `rm` first is not superstition. glib-compile-schemas will refuse to
# overwrite an index it thinks is newer than its inputs, and in a container
# where every file has a build timestamp that is a real possibility. Deleting it
# means the second line cannot be a silent no-op. This is the same order Bluefin
# uses in its own extension build script.
# ------------------------------------------------------------------------------

say "Compiling the GNOME settings defaults"

# Show what we are actually applying, in the build log, so a person reading a
# failed build can see the files without downloading the image.
echo "AquariusOS override files in ${SCHEMA_DIR}:"
ls -l "${SCHEMA_DIR}"/zz1-aquarius-*.gschema.override

if ! command -v glib-compile-schemas > /dev/null 2>&1; then
    echo "AQUARIUS ERROR: glib-compile-schemas is not in this image, so the GNOME" >&2
    echo "                defaults cannot be applied." >&2
    exit 1
fi

AQ_SCHEMA_TEST="$(mktemp -d)"
# Every schema description, so the overrides have something to attach to.
# TWO globs, not one: some of GNOME's schemas keep their enum definitions in a
# separate `.enums.xml` file (GWeather is one). Copy only the `.gschema.xml`
# half and --strict fails on GNOME's OWN files with "enum not (yet) defined" —
# which is exactly how the first six-variant CI run died (run 33422024053).
cp "${SCHEMA_DIR}"/*.gschema.xml "${AQ_SCHEMA_TEST}/"
cp "${SCHEMA_DIR}"/*.enums.xml "${AQ_SCHEMA_TEST}/" 2> /dev/null || true
# ...but only OUR overrides. See the note above.
cp "${SCHEMA_DIR}"/zz1-aquarius-*.gschema.override "${AQ_SCHEMA_TEST}/"
if ! glib-compile-schemas --strict "${AQ_SCHEMA_TEST}"; then
    echo "AQUARIUS ERROR: one of the AquariusOS settings override files is wrong." >&2
    echo "                Read the message above: it names the file, the setting and" >&2
    echo "                the problem. The usual cause is a misspelled setting name," >&2
    echo "                or a setting that this version of GNOME has renamed." >&2
    rm -rf "${AQ_SCHEMA_TEST}"
    exit 1
fi
rm -rf "${AQ_SCHEMA_TEST}"
echo "OK: every override file names real settings with valid values."

rm -f "${SCHEMA_DIR}/gschemas.compiled"
glib-compile-schemas "${SCHEMA_DIR}"

if [ ! -s "${SCHEMA_DIR}/gschemas.compiled" ]; then
    echo "AQUARIUS ERROR: ${SCHEMA_DIR}/gschemas.compiled was not written." >&2
    echo "                Every AquariusOS default would be ignored." >&2
    exit 1
fi
echo "OK: the settings index was rebuilt."

# ==============================================================================
# 5 — Prove the rest of the GNOME layer really shipped
# ==============================================================================
# Cheap checks on things whose absence is silent. Each one is a file that, if it
# went missing, would produce a desktop that looks slightly wrong and says
# nothing about why.
# ------------------------------------------------------------------------------

say "Checking the GNOME layer"

AQ_GNOME_FAILS=0
bad() { echo "  FAIL $*"; AQ_GNOME_FAILS=1; }
ok() { echo "  OK   $*"; }

for f in "${SCHEMA_DIR}/zz1-aquarius-10-look.gschema.override" \
    "${SCHEMA_DIR}/zz1-aquarius-20-shell.gschema.override" \
    "${SCHEMA_DIR}/zz1-aquarius-30-dash-to-dock.gschema.override"; do
    if [ -r "$f" ]; then ok "$(basename "$f") is installed"
    else bad "$f is missing"; fi
done

# The wallpapers the -10- file names. A picture-uri pointing at nothing gives a
# flat coloured desktop and no error.
for f in "${BACKGROUNDS_DIR}/the-pour-ice-3840x2160.png" \
    "${BACKGROUNDS_DIR}/the-pour-midnight-3840x2160.png"; do
    if [ -s "$f" ]; then ok "$(basename "$f") is installed"
    else bad "$f is missing — the desktop would come up a flat colour"; fi
done

# And the two paths written into the settings file really are these two files.
# Comparing the text to the filesystem is the only way to catch a rename that
# updated one and not the other.
for want in the-pour-ice-3840x2160.png the-pour-midnight-3840x2160.png; do
    if grep -q "${want}" "${SCHEMA_DIR}/zz1-aquarius-10-look.gschema.override"; then
        ok "the settings file points at ${want}"
    else
        bad "the settings file does not mention ${want} — the paths have drifted apart"
    fi
done

# The wallpaper picker's listing.
if [ -r "${BACKGROUND_XML}" ]; then ok "the wallpaper appears in Settings > Appearance"
else bad "${BACKGROUND_XML} is missing — our wallpaper would not be listed in Settings"; fi

# The right-click menu item in Files.
if [ -r "${NAUTILUS_EXT}" ]; then ok "the 'Make Editor-Ready' menu item is installed"
else bad "${NAUTILUS_EXT} is missing — there would be no right-click ingest on GNOME"; fi
if python3 -m py_compile "${NAUTILUS_EXT}" 2> /dev/null; then
    ok "the menu item's code has no typos in it"
else
    bad "${NAUTILUS_EXT} does not compile — Files would ignore it silently"
fi
# py_compile leaves a __pycache__ folder next to the file. Nothing imports from
# that folder, so those files would never be read again.
rm -rf "$(dirname "${NAUTILUS_EXT}")/__pycache__"

# zenity, which is how every AquariusOS script asks a question on GNOME.
if command -v zenity > /dev/null 2>&1; then ok "zenity is installed"
else bad "zenity is missing — the first-login creator-apps window would never appear"; fi

if [ "${AQ_GNOME_FAILS}" -ne 0 ]; then
    echo "::error::The GNOME desktop layer is not complete in this image. See above."
    exit 1
fi

say "The AquariusOS GNOME layer is in place."
