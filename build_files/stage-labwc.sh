#!/usr/bin/bash
# ==============================================================================
# BUILD STAGE — labwc, the window manager the Aquarius Desktop runs on
# ==============================================================================
# THIS SCRIPT DOES NOT RUN INSIDE AQUARIUSOS.
#
# It runs in a throwaway Fedora container whose only job is to compile one
# program. The finished program is copied into AquariusOS by a single COPY line
# in the Containerfile; the compiler, the headers and the source code are all
# left behind in the throwaway container and never ship.
#
# ------------------------------------------------------------------------------
# WHY WE COMPILE IT INSTEAD OF INSTALLING IT
# ------------------------------------------------------------------------------
# Fedora 44 packages labwc 0.9.6. We need 0.20.
#
# That is not a small-number-to-bigger-number preference. labwc 0.20 is the
# release that added HDR10 and the colour-management protocol, and those two
# things are the entire reason AquariusOS runs on labwc rather than on niri
# (standing decision 2b, 2026-09-02). A colour-accurate desktop for a video
# editor is the point of the project.
#
# Three ways to get 0.20 onto Fedora 44 were considered, in this order:
#
#   1. A COPR — somebody else's rebuild of the newer package for Fedora 44.
#      Checked 2026-09-03: there isn't one. The only labwc COPR that turns up
#      (gloriouseggroll/labwc) builds for Fedora 42 and carries 0.8-era
#      packages. Rejected: it does not exist, and even if it did, a COPR is
#      somebody else's build machine deciding what lands in our OS.
#
#   2. Rebuilding Fedora Rawhide's labwc source package on Fedora 44. Possible,
#      but it drags in Rawhide's packaging assumptions and needs a source-repo
#      configuration the bare bootable image does not have.
#
#   3. Compiling the upstream release ourselves, pinned to an exact commit.
#      Chosen. It is the shortest path with the fewest moving parts, it depends
#      on nothing outside Fedora 44's own repositories, and the exact source is
#      recorded in this file where anybody can read it.
#
# The dependency that makes option 3 easy: Fedora 44 already ships
# wlroots 0.20.2, and labwc 0.20.2 wants wlroots 0.20.1 or newer. The hard part
# of building a compositor — the library underneath it — is already packaged.
#
# When Fedora 45 ships labwc 0.20 as a package (it is in Rawhide today, at
# 0.20.0), this whole stage can be deleted and replaced with one dnf line.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

# ------------------------------------------------------------------------------
# What we are building, exactly
# ------------------------------------------------------------------------------
# Both values come from aquarius-os.env by way of the Containerfile. The tag is
# what we ask git for; the commit is what we check we actually got. A tag can be
# moved by whoever owns the repository — a commit hash cannot. If somebody ever
# re-points the 0.20.2 tag at different code, this build stops instead of
# quietly shipping it.
AQ_LABWC_VERSION="${LABWC_VERSION:?LABWC_VERSION was not passed to this stage}"
AQ_LABWC_COMMIT="${LABWC_COMMIT:?LABWC_COMMIT was not passed to this stage}"
AQ_LABWC_REPO="https://github.com/labwc/labwc.git"

# Where the finished files are gathered. This directory is laid out exactly like
# the root of a Linux system — /aq-stage/usr/bin/labwc becomes /usr/bin/labwc —
# so the Containerfile can copy it straight across with no rearranging.
AQ_STAGE="/aq-stage"

say "Building labwc ${AQ_LABWC_VERSION} from source"
echo "  repository: ${AQ_LABWC_REPO}"
echo "  tag:        ${AQ_LABWC_VERSION}"
echo "  commit:     ${AQ_LABWC_COMMIT}"

# ------------------------------------------------------------------------------
# The build tools and the libraries labwc is written against
# ------------------------------------------------------------------------------
# This list is not guesswork. It is every `dependency()` line in labwc 0.20.2's
# own meson.build, translated into Fedora package names:
#
#   wlroots            the compositor library that does the actual hard work
#   wayland            the display protocol itself, and its scanner tool
#   wayland-protocols  the protocol descriptions, including the newer ones
#                      labwc 0.20 needs for colour management
#   libxkbcommon       keyboard layouts
#   libxml2            labwc's configuration file (rc.xml) is XML
#   glib2              its event loop helpers
#   cairo + pango      drawing window title bars and their text
#   pixman             pixel pushing
#   libpng             images in themes
#   librsvg2           scalable icons — without it labwc builds, but window
#                      menus and title-bar buttons lose their icons
#   libsfdo            the freedesktop icon/desktop-entry lookups (0.1.3 is the
#                      minimum labwc asks for; Fedora 44 has exactly 0.1.3)
#   libdrm, libinput   graphics cards and input devices
#   libxcb + xcb-util-wm   XWayland support. Leave these out and labwc builds
#                      without the ability to run X11 software — which on a
#                      creator machine means no DaVinci Resolve.
#   systemd-devel      the systemd session integration
#   gettext            compiles the translations
say "Installing the build tools and libraries"
aq_dnf install \
    meson \
    ninja-build \
    gcc \
    git \
    pkgconf-pkg-config \
    gettext \
    wlroots-devel \
    wayland-devel \
    wayland-protocols-devel \
    libxkbcommon-devel \
    libxml2-devel \
    glib2-devel \
    cairo-devel \
    pango-devel \
    pixman-devel \
    libpng-devel \
    librsvg2-devel \
    libsfdo-devel \
    libdrm-devel \
    libinput-devel \
    libxcb-devel \
    xcb-util-wm-devel \
    systemd-devel

# Write down what we built against. When something breaks in six months, this
# line in the build log is the difference between an afternoon and a week.
say "The versions this was built against"
rpm -q wlroots-devel wayland-devel wayland-protocols-devel libsfdo-devel

# ------------------------------------------------------------------------------
# Getting the source, and proving it is the right source
# ------------------------------------------------------------------------------
say "Fetching the source"
git clone --depth 1 --branch "${AQ_LABWC_VERSION}" "${AQ_LABWC_REPO}" /src
cd /src || exit 1

AQ_GOT="$(git rev-parse HEAD)"
if [ "${AQ_GOT}" != "${AQ_LABWC_COMMIT}" ]; then
    echo "::error::labwc tag ${AQ_LABWC_VERSION} points at ${AQ_GOT}, but this build expects ${AQ_LABWC_COMMIT}." >&2
    echo "                Either the tag was moved upstream, or LABWC_COMMIT in aquarius-os.env is stale." >&2
    echo "                Nothing is built until a person decides which." >&2
    exit 1
fi
ok "the source is commit ${AQ_GOT}, exactly as pinned"

# ------------------------------------------------------------------------------
# Compiling
# ------------------------------------------------------------------------------
# No feature switches are passed on purpose. Every optional feature in labwc's
# meson.build defaults to "auto", which means "switch it on if the library is
# installed" — and the step above installed every one of them. Naming them again
# here would be a second list to keep in step with the first, and the two would
# eventually disagree.
#
# What we do instead is CHECK, further down, that the features we care about
# really were compiled in. A list of switches is a statement of intent; reading
# the finished binary is a fact.
#
# A note on the Vulkan renderer, because HDR needs it and somebody will look for
# it here: it is NOT a labwc build option. The renderer belongs to wlroots, and
# which one is used is chosen when the compositor starts, by the environment
# variable WLR_RENDERER. Fedora's wlroots is built with the Vulkan renderer
# available, so the choice exists on every AquariusOS machine — but AquariusOS
# does not force it yet, because the Vulkan renderer on the NVIDIA driver has
# not been tested on the bench. See docs/restart/aquarius-session.md.
say "Configuring"
meson setup build \
    --prefix=/usr \
    --buildtype=release

echo
echo "--- how meson configured this build ---"
meson configure build || true
echo "--- end ---"

say "Compiling"
ninja -C build

# ------------------------------------------------------------------------------
# Installing into the staging tree
# ------------------------------------------------------------------------------
# DESTDIR is the standard way to say "install as though the root of the system
# were this folder". Nothing is installed into the throwaway container's own
# /usr, so there is no chance of the check below accidentally reading a file
# that will not be copied across.
say "Gathering the finished files"
DESTDIR="${AQ_STAGE}" meson install -C build --no-rebuild

# --- things we deliberately do NOT ship ---------------------------------------
# labwc installs its own login-screen entry. Left in place, the AquariusOS login
# screen would offer three sessions: GNOME, Aquarius Desktop, and a bare "Labwc"
# — the third being a window manager with no bar, no dock and no way to launch
# anything, which is exactly the kind of trap a beginner falls into once and
# never trusts the machine again afterwards. Ours is the only labwc session.
rm -fv "${AQ_STAGE}/usr/share/wayland-sessions/labwc.desktop"

# Manual pages are worth keeping (labwc-config(5) is genuinely useful when
# editing rc.xml) but the developer documentation and any leftover build
# metadata are not.
rm -rf "${AQ_STAGE}/usr/share/doc"

say "What is being copied into AquariusOS"
find "${AQ_STAGE}" -type f -o -type l | sort | sed 's/^/  /'

# ------------------------------------------------------------------------------
# Checking the binary, by reading it
# ------------------------------------------------------------------------------
# Everything below reads the compiled program rather than trusting the build log.
say "Checking what was actually built"

AQ_LABWC_BIN="${AQ_STAGE}/usr/bin/labwc"

if [ -x "${AQ_LABWC_BIN}" ]; then
    ok "labwc was built and is executable"
else
    bad "there is no executable at ${AQ_LABWC_BIN} — the build produced nothing"
    aq_finish "labwc build stage"
fi

# The version, from the program itself. `labwc --version` prints its own version
# and exits without needing a screen, which is why this works in a container.
AQ_REPORTED="$("${AQ_LABWC_BIN}" --version 2>&1 || true)"
echo "  labwc --version says: ${AQ_REPORTED}"
if printf '%s' "${AQ_REPORTED}" | grep -q "${AQ_LABWC_VERSION}"; then
    ok "the binary reports version ${AQ_LABWC_VERSION}"
else
    bad "the binary reports '${AQ_REPORTED}', not ${AQ_LABWC_VERSION}"
fi

# Which libraries it was linked against. This is how we check that the optional
# features really were compiled in: a program that does not use SVG icons has no
# reason to be linked against the SVG library, and a program built without
# XWayland support has no reason to be linked against the X11 protocol library.
say "Which features were compiled in (read from the binary's libraries)"
ldd "${AQ_LABWC_BIN}" > /tmp/labwc-libs.txt
sed 's/^/  /' /tmp/labwc-libs.txt

aq_ldd_has() { # aq_ldd_has <library name fragment> "<what it proves>"
    if grep -q "$1" /tmp/labwc-libs.txt; then
        ok "$2"
    else
        bad "$2 — nothing links to $1, so that feature was NOT compiled in"
    fi
}

aq_ldd_has "libwlroots"  "built against wlroots (the compositor itself)"
aq_ldd_has "librsvg"     "scalable icons in menus and title bars"
aq_ldd_has "libxcb"      "XWayland, so X11-only software such as DaVinci Resolve can run"
aq_ldd_has "libsfdo"     "desktop-entry and icon lookups"
aq_ldd_has "libpangocairo" "text rendering in window title bars"

# Anything the linker cannot find here is a library Fedora 44 has in its -devel
# package but not as a plain runtime package. Better to discover that now, in a
# ten-second stage, than in the finished image.
if grep -q "not found" /tmp/labwc-libs.txt; then
    bad "some libraries could not be found even on the build machine:"
    grep "not found" /tmp/labwc-libs.txt | sed 's/^/       /'
else
    ok "every library labwc needs was found on the build machine"
fi

aq_finish "labwc build stage"
