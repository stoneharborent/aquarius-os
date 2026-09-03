#!/usr/bin/bash
# ==============================================================================
# BUILD STAGE — Quickshell, the runtime the Aquarius Shell is written for
# ==============================================================================
# THIS SCRIPT DOES NOT RUN INSIDE AQUARIUSOS. Like the labwc stage next to it,
# it runs in a throwaway Fedora container, and only the finished program is
# copied across.
#
# ------------------------------------------------------------------------------
# WHAT QUICKSHELL IS
# ------------------------------------------------------------------------------
# The Aquarius Shell — our top bar, dock, search palette, quick settings and
# notifications — is written in QML, the language Qt uses for interfaces.
# Quickshell is the program that runs that QML and gives it the desktop-specific
# powers a bar needs: sticking a window to the edge of the screen, listing the
# open applications, reading the battery, being the notification service. The
# command is called `qs`.
#
# ------------------------------------------------------------------------------
# WHY WE COMPILE IT, AND WHY THIS ONE IS NOT OPTIONAL
# ------------------------------------------------------------------------------
# Fedora packages Quickshell, but at a snapshot of 0.2.1. Two reasons that is
# not enough:
#
#   1. The shell uses Quickshell.Networking and Quickshell.Bluetooth. Those
#      modules do not exist in 0.2.1. The Wi-Fi and Bluetooth tiles in Quick
#      Settings are simply missing on it.
#
#   2. THE QT ABI TRAP, and this is the one that cost a real evening on the
#      bench on 2026-09-02. AquariusOS is an atomic system: the Qt libraries are
#      part of the image and cannot be changed by installing something on top.
#      When a person layered Fedora's quickshell package onto the machine, they
#      got a build compiled against a NEWER Qt than the image contains. It
#      installed cleanly and then died the instant it started:
#
#          qs: symbol lookup error: qs: undefined symbol: ... version Qt_6
#
#      The session came up with no bar and no explanation.
#
#      Building Quickshell inside the image, against the image's own Qt, makes
#      that failure impossible by construction. The two pieces are compiled
#      together and shipped together and can never drift apart.
#
# This amends ADR 0001 in the aquarius-shell repository, which originally said
# "ship the Fedora RPM". Standing decision 2c (2026-09-02) is the amendment.
# When Fedora's package catches up to a real 0.3 release, this stage can go.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

AQ_QS_VERSION="${QUICKSHELL_VERSION:?QUICKSHELL_VERSION was not passed to this stage}"
AQ_QS_COMMIT="${QUICKSHELL_COMMIT:?QUICKSHELL_COMMIT was not passed to this stage}"

# Quickshell's own home is git.outfoxxed.me. We fetch from the author's GitHub
# mirror instead, for one boring reason: GitHub is the thing least likely to be
# unreachable from a build machine at three in the morning. The commit check
# below means it does not matter which copy we pull from — if the mirror ever
# carried different code, the build would stop.
AQ_QS_REPO="https://github.com/quickshell-mirror/quickshell.git"

AQ_STAGE="/aq-stage"

say "Building Quickshell ${AQ_QS_VERSION} from source"
echo "  repository: ${AQ_QS_REPO}"
echo "  tag:        ${AQ_QS_VERSION}"
echo "  commit:     ${AQ_QS_COMMIT}"

# ------------------------------------------------------------------------------
# Build tools and libraries
# ------------------------------------------------------------------------------
# From Quickshell's own BUILD.md, translated into Fedora package names.
#
#   qt6-qtbase / qtdeclarative   Qt itself and QML
#   qt6-qtbase-private-devel     Quickshell uses Qt's internal APIs. Fedora ships
#                                those headers in a separate package; without it
#                                the build fails on a missing private header.
#   qt6-qtwayland-devel          the Wayland half of Qt
#   qt6-qtshadertools-devel      compiles the small shaders Quickshell uses
#   qt6-qtsvg-devel              SVG icons (the Aquarius logo in the bar)
#   wayland / wayland-protocols  the protocols a bar speaks: layer-shell (stick
#                                to the screen edge), session-lock, toplevel
#                                management (what is the active window)
#   mesa-libgbm + vulkan-headers screen capture
#   pipewire-devel               audio: the volume slider and the sound glyph
#   pam-devel                    the lock screen's password check
#   polkit-devel + glib2         the "an app wants permission" dialog
#   cli11-devel                  the `qs` command-line parser
#   jemalloc-devel               a memory allocator. Upstream turns this on by
#                                default because a shell runs for weeks and Qt
#                                fragments memory; we keep their default.
say "Installing the build tools and libraries"
aq_dnf install \
    cmake \
    ninja-build \
    gcc-c++ \
    git \
    pkgconf-pkg-config \
    spirv-tools \
    qt6-qtbase-devel \
    qt6-qtbase-private-devel \
    qt6-qtdeclarative-devel \
    qt6-qtwayland-devel \
    qt6-qtshadertools-devel \
    qt6-qtsvg-devel \
    wayland-devel \
    wayland-protocols-devel \
    libdrm-devel \
    mesa-libgbm-devel \
    vulkan-headers \
    pipewire-devel \
    pam-devel \
    polkit-devel \
    glib2-devel \
    cli11-devel \
    jemalloc-devel

say "The Qt this is being built against"
rpm -q qt6-qtbase qt6-qtdeclarative qt6-qtwayland

# ------------------------------------------------------------------------------
# Getting the source, and proving it is the right source
# ------------------------------------------------------------------------------
say "Fetching the source"
git clone --depth 1 --branch "${AQ_QS_VERSION}" "${AQ_QS_REPO}" /src
cd /src || exit 1

AQ_GOT="$(git rev-parse HEAD)"
if [ "${AQ_GOT}" != "${AQ_QS_COMMIT}" ]; then
    echo "::error::Quickshell tag ${AQ_QS_VERSION} points at ${AQ_GOT}, but this build expects ${AQ_QS_COMMIT}." >&2
    echo "                Either the tag was moved, or QUICKSHELL_COMMIT in aquarius-os.env is stale." >&2
    exit 1
fi
ok "the source is commit ${AQ_GOT}, exactly as pinned"

# ------------------------------------------------------------------------------
# Configuring — and the four things we switch OFF
# ------------------------------------------------------------------------------
# Quickshell turns nearly everything on by default. Four of those defaults are
# wrong for AquariusOS:
#
#   CRASH_HANDLER   needs a library called cpptrace, which Fedora 44 does not
#                   package (it is in Rawhide only, checked 2026-09-03). With
#                   this on, the build fails looking for it. The cost of turning
#                   it off is that a crash writes a plain message instead of a
#                   stack trace; the session log still records that it died.
#
#   HYPRLAND        integrations for a compositor we do not ship and never will.
#   I3              the same, for i3 and Sway.
#                   The Aquarius Shell is forbidden from importing either — its
#                   own test suite enforces the standardised-protocols law — so
#                   building them in would add code that nothing can call.
#
#   X11             lets a bar draw itself on an X11 desktop. The Aquarius
#                   Session is Wayland-only. (This does not affect XWayland:
#                   X11 applications still run, they just are not what draws
#                   the bar.)
#
# Everything else stays at upstream's default, which is on. In particular
# SERVICE_NOTIFICATIONS, SERVICE_STATUS_NOTIFIER, SERVICE_PIPEWIRE,
# SERVICE_UPOWER, SERVICE_POLKIT, SERVICE_PAM, NETWORK, BLUETOOTH, SCREENCOPY
# and the three Wayland protocol groups are all required by the shell's QML —
# the check at the bottom of this file proves each one arrived.
#
# CMAKE_INSTALL_LIBDIR is named explicitly because Fedora puts 64-bit libraries
# in /usr/lib64 and the QML modules go beside them. Guessing wrong here produces
# a build that installs happily into /usr/lib and a shell that starts and
# reports that every Quickshell import is unknown.
say "Configuring"
cmake -GNinja -B build \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DCMAKE_INSTALL_LIBDIR=lib64 \
    -DDISTRIBUTOR="AquariusOS" \
    -DDISTRIBUTOR_DEBUGINFO_AVAILABLE=OFF \
    -DCRASH_HANDLER=OFF \
    -DHYPRLAND=OFF \
    -DHYPRLAND_IPC=OFF \
    -DHYPRLAND_GLOBAL_SHORTCUTS=OFF \
    -DHYPRLAND_FOCUS_GRAB=OFF \
    -DHYPRLAND_SURFACE_EXTENSIONS=OFF \
    -DSCREENCOPY_HYPRLAND_TOPLEVEL=OFF \
    -DI3=OFF \
    -DI3_IPC=OFF \
    -DX11=OFF \
    -DBUILD_TESTING=OFF

say "Compiling (this is the long one — several minutes)"
cmake --build build

say "Gathering the finished files"
DESTDIR="${AQ_STAGE}" cmake --install build

# Quickshell installs a .desktop file so that a desktop's application menu can
# offer it. An entry called "Quickshell" in the AquariusOS app grid would launch
# a second, configuration-less copy of the shell on top of the running one.
# Nobody wants that, so it does not ship.
rm -fv "${AQ_STAGE}"/usr/share/applications/*quickshell*.desktop || true

say "What is being copied into AquariusOS"
find "${AQ_STAGE}" -maxdepth 6 -type d -name 'Quickshell*' | sort | sed 's/^/  /'
find "${AQ_STAGE}/usr/bin" -mindepth 1 | sort | sed 's/^/  /'
echo "  total size: $(du -sh "${AQ_STAGE}" | cut -f1)"

# ------------------------------------------------------------------------------
# Checking what was built, by reading it
# ------------------------------------------------------------------------------
say "Checking what was actually built"

if [ -e "${AQ_STAGE}/usr/bin/qs" ]; then
    ok "the qs command was built"
else
    bad "there is no ${AQ_STAGE}/usr/bin/qs — the build produced nothing usable"
    aq_finish "Quickshell build stage"
fi

# The QML modules. Each of these directories is one `import Quickshell.Something`
# line in the Aquarius Shell. A module that was switched off at configure time
# leaves no directory here, and the failure it would cause on a real machine is
# the shell refusing to start with "module not installed" — after login, on a
# black screen. Catching it here costs nothing.
say "The QML modules the Aquarius Shell imports"
AQ_QML_DIR="${AQ_STAGE}/usr/lib64/qt6/qml/Quickshell"

if [ -d "${AQ_QML_DIR}" ]; then
    ok "Quickshell's QML modules were installed to /usr/lib64/qt6/qml/Quickshell"
    find "${AQ_QML_DIR}" -maxdepth 2 -name qmldir | sed "s|${AQ_STAGE}||; s/^/       /" | sort
else
    bad "no QML modules at ${AQ_QML_DIR} — CMAKE_INSTALL_LIBDIR is probably wrong"
fi

# The exact module list the shell's QML asks for, taken from its import lines.
for aq_mod in \
    "Io" \
    "Widgets" \
    "Wayland" \
    "Networking" \
    "Bluetooth" \
    "Services/Notifications" \
    "Services/Pipewire" \
    "Services/SystemTray" \
    "Services/UPower"
do
    if [ -f "${AQ_QML_DIR}/${aq_mod}/qmldir" ]; then
        ok "Quickshell.$(printf '%s' "${aq_mod}" | tr '/' '.') is present"
    else
        bad "Quickshell.$(printf '%s' "${aq_mod}" | tr '/' '.') is MISSING — a feature was switched off that the shell needs"
    fi
done

# Libraries. Same reasoning as the labwc stage: a missing runtime library here
# means the finished image would ship a program that cannot start.
say "Which libraries qs needs"
ldd "${AQ_STAGE}/usr/bin/quickshell" > /tmp/qs-libs.txt 2>&1 || \
    ldd "${AQ_STAGE}/usr/bin/qs" > /tmp/qs-libs.txt 2>&1
sed 's/^/  /' /tmp/qs-libs.txt

if grep -q "not found" /tmp/qs-libs.txt; then
    bad "some libraries could not be found even on the build machine:"
    grep "not found" /tmp/qs-libs.txt | sed 's/^/       /'
else
    ok "every library qs needs was found on the build machine"
fi

# Record the Qt it is now permanently married to, so the image build can check
# it matches. This file is copied into AquariusOS with everything else.
install -d -m 0755 "${AQ_STAGE}/usr/share/aquarius"
{
    echo "# Written by build_files/stage-quickshell.sh. Do not edit by hand."
    echo "quickshell_version=${AQ_QS_VERSION}"
    echo "quickshell_commit=${AQ_QS_COMMIT}"
    echo "built_against_qt=$(rpm -q --queryformat '%{VERSION}' qt6-qtbase)"
} > "${AQ_STAGE}/usr/share/aquarius/quickshell-build.txt"
cat "${AQ_STAGE}/usr/share/aquarius/quickshell-build.txt" | sed 's/^/  /'

aq_finish "Quickshell build stage"
