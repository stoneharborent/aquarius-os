#!/usr/bin/bash
# ==============================================================================
# AquariusOS — the one GNOME Shell extension we bake in ourselves
# ==============================================================================
# WHAT THIS FILE DOES, IN ONE SENTENCE
#   It downloads one community GNOME extension — Dash to Dock — at a pinned
#   version with a pinned fingerprint, installs it into the image system-wide,
#   and fails the whole build if anything about that does not come out right.
#
# WHY WE HAVE TO DO THIS AT ALL
#   Bazzite's GNOME images ship a good set of extensions (app indicators, phone
#   pairing, caffeine, the hot edge) and we keep most of them. Dash to Dock is
#   the one thing on our list they do not ship: GNOME's own dash only exists
#   inside the Activities overview, and AquariusOS wants a dock on the desktop
#   the way macOS has one, and the way our KDE line already does.
#
#   There is no Fedora package for it. So we fetch it the same way
#   build_files/kwin-effects.sh fetches the KDE rounded-corners effect — from
#   the project's own release, pinned and checksummed — and the same discipline
#   applies.
#
# WHY IT IS INSTALLED "SYSTEM-WIDE", WHICH IS NOT THE OBVIOUS CHOICE
#   ⚠️ THIS IS THE ONE THING IN THIS FILE THAT WOULD BE EASY TO "TIDY UP" AND
#   BREAK, so it is spelled out.
#
#   A GNOME extension normally carries its own compiled settings file inside its
#   own folder (…/dash-to-dock@micxgx.gmail.com/schemas/gschemas.compiled).
#   When it does, GNOME reads the extension's settings from THERE, and it looks
#   there FIRST — before the system-wide settings database.
#
#   That would quietly defeat our entire dock configuration. All of the dock's
#   defaults — bottom, always visible, centred, icon size — live in
#   system_files/usr/share/glib-2.0/schemas/zz1-aquarius-30-dash-to-dock.gschema.override,
#   which is part of the SYSTEM-WIDE database. If the extension kept a private
#   copy of its settings, every one of those lines would be read past and
#   ignored, the dock would come up with stock behaviour, and nothing anywhere
#   would say why.
#
#   Upstream's own `make install` handles this correctly when it is doing a
#   system install: it puts the settings description in
#   /usr/share/glib-2.0/schemas/ and deliberately does NOT leave a compiled copy
#   inside the extension folder. That is exactly the arrangement every
#   distribution-packaged GNOME extension uses. So we use upstream's installer
#   rather than copying files around by hand, and this script checks afterwards
#   that the private copy really is absent.
#
# Called from build_files/build.sh, GNOME images only. The KDE line never runs
# this file, and there is no KWin/Plasma equivalent of it — our KDE dock is a
# fork of KDE's own task manager and ships as plain files in system_files/.
#
# Beginner-facing write-up: docs/gnome-variants.md
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# WHAT WE INSTALL — pinned, to the exact byte
# ------------------------------------------------------------------------------
# Pinned three ways, exactly like build_files/kwin-effects.sh:
#
#   the TAG      what a human should look up when reading release notes
#   the COMMIT   the exact revision that tag pointed at when this was written,
#                so a re-tagged or moved tag is obvious to a person comparing
#   the SHA256   the fingerprint of the downloaded file, which is the one the
#                MACHINE checks. Nothing is unpacked or installed until the
#                download matches this string.
#
# ⚠️ HOW TO BUMP THE VERSION. Change the five lines together — tag, commit, URL,
# checksum and source folder — and never one without the others. Get the new
# checksum the honest way, by downloading the file and asking for it:
#
#     curl -fsSL -o /tmp/x.tar.gz <the new URL>
#     sha256sum /tmp/x.tar.gz
#
# Do NOT copy a checksum out of a web page.
#
# Dash to Dock — https://github.com/micheleg/dash-to-dock
# v106 is the current release. Its metadata.json declares support for GNOME
# Shell 45 through 51, which covers the 50 that Fedora 44 ships — that was
# checked by reading the file inside the tarball, not by trusting a listing.
# (v105 stops at 50, so it would work today and break on the next Fedora. v106
# is the one that does not need revisiting in six months.)
#
# The tarball is GitHub's automatically generated source archive. It was
# downloaded three times on this connection and gave the same fingerprint each
# time before the value below was written down.
D2D_TAG="extensions.gnome.org-v106"
D2D_COMMIT="a7b19816b7277e41c18ea5c3ff165e493a14e0d4"
D2D_URL="https://github.com/micheleg/dash-to-dock/archive/refs/tags/extensions.gnome.org-v106.tar.gz"
D2D_SHA256="09ab0589b314bbfd8040f9137a85db6e6ea2ff9a82773ac9289efce857058349"
D2D_SRCDIR="dash-to-dock-extensions.gnome.org-v106"

# The extension's id. This exact string is three things at once: the folder it
# installs into, the name GNOME knows it by, and the word that has to appear in
# the enabled-extensions list in
# system_files/usr/share/glib-2.0/schemas/zz1-aquarius-20-shell.gschema.override.
# If those three ever disagree, the dock silently does not appear.
D2D_UUID="dash-to-dock@micxgx.gmail.com"
D2D_DIR="/usr/share/gnome-shell/extensions/${D2D_UUID}"

# Where its settings description has to end up for our defaults to be read.
# See the long note at the top of this file.
D2D_SCHEMA="/usr/share/glib-2.0/schemas/org.gnome.shell.extensions.dash-to-dock.gschema.xml"

say() { echo; echo "=== $* ==="; }

# ------------------------------------------------------------------------------
# The build tools, borrowed and given back
# ------------------------------------------------------------------------------
# Four tools are needed to install this, and none of them belongs on a finished
# AquariusOS machine:
#
#   make               runs the project's own installer.
#   sassc              turns the extension's stylesheet source into real CSS.
#                      Without it the dock loads but is completely unstyled.
#   gettext (msgfmt)   compiles the translations, so the dock's settings window
#                      is not English-only.
#   glib2-devel        would provide glib-compile-schemas on an image that did
#                      not already have it. On Fedora it is in the main glib2
#                      package, so in practice this one is always already here
#                      and nothing gets installed or removed for it. It is named
#                      anyway so that an image that ever lacks it still builds.
#
# We record which ones we actually had to install, and remove exactly those
# again at the end — so a base image that already carries one keeps it, and we
# never remove something that was not ours. Shipping build tools would put tens
# of megabytes of developer software on every user's machine for no reason.
AQ_BORROWED_PACKAGES=()

borrow() {   # borrow <command> <package that provides it>
    if command -v "$1" > /dev/null 2>&1; then
        echo "OK: ${1} is already in this image."
    else
        echo "Installing ${2} for ${1} (it will be removed again at the end)."
        dnf5 install -y "$2"
        AQ_BORROWED_PACKAGES+=("$2")
    fi
}

give_back() {
    if [ "${#AQ_BORROWED_PACKAGES[@]}" -eq 0 ]; then
        echo "Nothing to remove — every tool used was already in the image."
        return
    fi

    say "Removing the build tools again: ${AQ_BORROWED_PACKAGES[*]}"
    dnf5 remove -y "${AQ_BORROWED_PACKAGES[@]}"

    # ⚠️ AND THEN CHECK WE DID NOT TAKE THE DESKTOP WITH THEM.
    # `dnf5 remove` removes anything that DEPENDS on what you named, not just
    # what you named. If some future base image turns out to have a real package
    # depending on one of these, this line would quietly delete it and the image
    # would still build. Naming the pieces the OS cannot live without turns that
    # into a red build instead of a desktop that does not start.
    for aq_essential in gnome-shell gsettings glib-compile-schemas; do
        if ! command -v "${aq_essential}" > /dev/null 2>&1; then
            echo "AQUARIUS ERROR: '${aq_essential}' disappeared when the build tools were removed." >&2
            echo "                Something in this image depended on one of:" >&2
            echo "                ${AQ_BORROWED_PACKAGES[*]}" >&2
            echo "                Do not ship this. Work out which, and stop borrowing it." >&2
            exit 1
        fi
    done
    echo "OK: the desktop survived the cleanup."
}

say "Dash to Dock ${D2D_TAG} (commit ${D2D_COMMIT})"

borrow make make
borrow sassc sassc
borrow msgfmt gettext
borrow glib-compile-schemas glib2-devel

# ------------------------------------------------------------------------------
# Download, and refuse to go on unless it is byte-for-byte what we expect
# ------------------------------------------------------------------------------
AQ_WORK="$(mktemp -d)"
trap 'rm -rf "${AQ_WORK}"' EXIT

if ! curl --retry 3 --retry-delay 5 -fsSL -o "${AQ_WORK}/d2d.tar.gz" "${D2D_URL}"; then
    echo "AQUARIUS ERROR: could not download Dash to Dock from:" >&2
    echo "                ${D2D_URL}" >&2
    exit 1
fi

D2D_GOT="$(sha256sum "${AQ_WORK}/d2d.tar.gz" | awk '{print $1}')"
if [ "${D2D_GOT}" != "${D2D_SHA256}" ]; then
    echo "AQUARIUS ERROR: the Dash to Dock download is not the file we pinned." >&2
    echo "                expected ${D2D_SHA256}" >&2
    echo "                     got ${D2D_GOT}" >&2
    echo "                Nothing has been installed. Either the release was" >&2
    echo "                re-published under the same tag, or the download was" >&2
    echo "                tampered with. Check before changing the number." >&2
    exit 1
fi
echo "OK: the download matches the pinned fingerprint."

tar -xzf "${AQ_WORK}/d2d.tar.gz" -C "${AQ_WORK}"
test -d "${AQ_WORK}/${D2D_SRCDIR}"

# ------------------------------------------------------------------------------
# Does this release actually support the GNOME on this image?
# ------------------------------------------------------------------------------
# An extension declares which GNOME Shell versions it works with, and GNOME
# refuses to load one that does not list the version it is. That refusal is
# quiet: no crash, no error on screen, just no dock.
#
# So we ask both questions here — what GNOME is in this image, and what this
# release says it supports — and stop the build if they do not agree. That turns
# "the dock vanished after a Fedora bump" into a red build on the day of the
# bump, which is the only time it is cheap to deal with.
D2D_SHELL_VERSION="$(gnome-shell --version | awk '{print $3}' | cut -d. -f1)"
echo "This image has GNOME Shell ${D2D_SHELL_VERSION}."

if ! python3 - "${AQ_WORK}/${D2D_SRCDIR}/metadata.json" "${D2D_SHELL_VERSION}" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
supported = [str(v) for v in meta["shell-version"]]
wanted = sys.argv[2]
print(f"Dash to Dock {meta['version']} supports GNOME Shell: {', '.join(supported)}")
if wanted not in supported:
    sys.exit(
        f"FAIL: this image has GNOME Shell {wanted}, which that list does not "
        f"include. GNOME would refuse to load the extension and the dock would "
        f"simply not appear, with no error. Bump the pinned version in "
        f"build_files/gnome-extensions.sh."
    )
PY
then
    exit 1
fi

# ------------------------------------------------------------------------------
# Install it, using upstream's own installer
# ------------------------------------------------------------------------------
# DESTDIR is what tells the project's Makefile "this is a system-wide install,
# not an install into one person's home folder" — see the long note at the top
# of this file for why that distinction is the whole ball game here. Setting it
# to "/" means "install into this image".
make -C "${AQ_WORK}/${D2D_SRCDIR}" DESTDIR=/ install

# ------------------------------------------------------------------------------
# Prove it landed properly, rather than hoping
# ------------------------------------------------------------------------------
AQ_D2D_FAILS=0
bad() { echo "  FAIL $*"; AQ_D2D_FAILS=1; }
ok() { echo "  OK   $*"; }

say "Checking the installed Dash to Dock"

# 1. The extension itself: the folder, the code GNOME runs, and its description.
for f in "${D2D_DIR}/extension.js" "${D2D_DIR}/metadata.json" "${D2D_DIR}/stylesheet.css"; do
    if [ -r "$f" ]; then ok "$(basename "$f") is present and readable"
    else bad "$f is missing — the dock would not load"; fi
done

# 2. metadata.json must be readable JSON, must call itself by the id we expect,
#    and must still list this image's GNOME. The version check above was run on
#    the downloaded copy; this one is run on the INSTALLED copy, because those
#    are two different claims.
if [ -r "${D2D_DIR}/metadata.json" ]; then
    if python3 - "${D2D_DIR}/metadata.json" "${D2D_UUID}" "${D2D_SHELL_VERSION}" <<'PY'
import json, sys
meta = json.load(open(sys.argv[1]))
assert meta["uuid"] == sys.argv[2], f"uuid is {meta['uuid']}, expected {sys.argv[2]}"
assert sys.argv[3] in [str(v) for v in meta["shell-version"]], "does not list this GNOME Shell"
PY
    then ok "metadata.json is valid, is the extension we meant, and supports this GNOME"
    else bad "metadata.json is broken, is a different extension, or does not support this GNOME"; fi
fi

# 3. Its settings description is in the SYSTEM-WIDE folder. Without this, our
#    dock defaults have no schema to attach to and glib-compile-schemas will
#    reject them.
if [ -r "${D2D_SCHEMA}" ]; then ok "the dock's settings description is installed system-wide"
else bad "${D2D_SCHEMA} is missing — our dock defaults would have nothing to apply to"; fi

# 4. And there is NO private compiled copy inside the extension folder. This is
#    the check that protects the whole arrangement described at the top of this
#    file: if this file ever appears, every AquariusOS dock default is silently
#    ignored and the dock comes up looking like stock Dash to Dock.
if [ -e "${D2D_DIR}/schemas/gschemas.compiled" ]; then
    bad "${D2D_DIR}/schemas/gschemas.compiled exists — it would override every AquariusOS dock default"
    echo "       Remove it. See 'WHY IT IS INSTALLED SYSTEM-WIDE' at the top of this script."
else
    ok "no private settings copy inside the extension (correct — ours win)"
fi

# 5. The name in our enabled-extensions list has to match the folder it just
#    installed into. This is the pairing that fails silently: an extension
#    nobody enables looks exactly like an extension that failed to install.
AQ_SHELL_OVERRIDE="/usr/share/glib-2.0/schemas/zz1-aquarius-20-shell.gschema.override"
if grep -q "'${D2D_UUID}'" "${AQ_SHELL_OVERRIDE}" 2>/dev/null; then
    ok "${D2D_UUID} is in our enabled-extensions list"
else
    bad "${D2D_UUID} is not switched on in ${AQ_SHELL_OVERRIDE} — it would ship unused"
fi

give_back

if [ "${AQ_D2D_FAILS}" -ne 0 ]; then
    echo "::error::Dash to Dock is not correctly installed in this image — there would be no dock."
    exit 1
fi

say "Dash to Dock ${D2D_TAG} installed."
