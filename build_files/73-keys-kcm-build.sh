#!/usr/bin/bash
# ==============================================================================
# STEP 73 (builder stage only) — compiling the KDE settings page for Mac/Windows
# ==============================================================================
# WHAT THIS IS FOR
#
# AquariusOS has one Mac-or-Windows switch: Mac-style keyboard shortcuts, where
# copy is Command-C, or the normal Windows ones, where copy is Ctrl+C. (Until
# 2026-09-17 it moved the window buttons as well; Royce dropped that because
# applications that draw their own title bar never followed it, so the buttons
# are stock and on the right for everybody now.)
# Until 2026-09-16 the only ways to change it were the Welcome window
# — which you see once, on your first login — and typing `aq keys mac` in a
# terminal. Royce asked for a switch you can find.
#
# On GNOME that switch is a small add-on of ours in the menu at the top-right of
# the screen; it is plain text files and needs no compiler, so it simply ships
# in system_files/. On KDE Plasma it is a PAGE IN SYSTEM SETTINGS, and a page in
# System Settings has to be a compiled program. This script compiles it.
#
# The source lives in kcm/aquarius-keys/ in this repo. Its CMakeLists.txt
# explains, with the evidence, why a page made only of QML text files is not
# possible on Plasma 6.
#
# ------------------------------------------------------------------------------
# THIS SCRIPT DOES NOT RUN INSIDE AQUARIUSOS
# ------------------------------------------------------------------------------
# It runs in a throwaway Fedora container — the `kcm-build` stage in the
# Containerfile — whose only job is to compile one small plugin and leave it in
# /out. Only the finished plugin is copied into AquariusOS.
#
# That is the same pattern 74-xremap-build.sh uses, and for the same reason: a
# C++ compiler and a pile of -devel packages come to several hundred megabytes,
# and none of it belongs in an operating system that only needs to RUN the
# result. The finished plugin is about a hundred kilobytes.
#
# ------------------------------------------------------------------------------
# ⚠️ THE ONE RISK THIS PATTERN CARRIES, AND HOW IT IS CAUGHT
# ------------------------------------------------------------------------------
# The plugin is built against the KDE libraries in THIS container and then runs
# against the KDE libraries in the FINISHED IMAGE. Both come from the same
# Fedora 44, in the same build, so in practice they are the same versions — but
# "in practice" is not a check. So build_files/75-aquarius-keys.sh asks `ldd`,
# inside the finished image, whether every library this plugin needs is really
# there. A mismatch fails the build instead of producing a settings page that
# silently does not appear.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

# Where our source is (the whole repo is mounted at /ctx by the Containerfile)
# and where the finished plugin is left for the image stage to collect.
SRC="/ctx/kcm/aquarius-keys"
BUILD="/tmp/kcm-build"
STAGE="/tmp/kcm-stage"
OUT="/out"

say "Building the KDE 'Mac or Windows' settings page"

if [ ! -r "${SRC}/CMakeLists.txt" ]; then
    bad "${SRC}/CMakeLists.txt is missing — the source did not come through"
    aq_finish "The KDE settings page"
fi

# ------------------------------------------------------------------------------
# The compiler and the KDE development libraries
# ------------------------------------------------------------------------------
# Each of these is here for one reason:
#
#   cmake, gcc-c++            the compiler and the thing that drives it
#   extra-cmake-modules       KDE's own build rules (the "ECM" of KDECMakeSettings)
#   kf6-kcmutils-devel        what a settings page IS — KQuickConfigModule
#   kf6-kcoreaddons-devel     how KDE loads a plugin at all (KPluginFactory)
#   kf6-ki18n-devel           the wrapper KDE pages put their text through
#   kf6-kirigami-devel        the look: Kirigami is what every Plasma 6 settings
#                             page is drawn with, and the page imports it
#   qt6-qtbase-devel          Qt itself
#   qt6-qtdeclarative-devel   QML — the language the page's interface is written
#                             in — and the tools that bake it into the plugin
say "Installing the compiler and the KDE development libraries"
aq_dnf install \
    cmake \
    gcc-c++ \
    extra-cmake-modules \
    kf6-kcmutils-devel \
    kf6-kcoreaddons-devel \
    kf6-ki18n-devel \
    kf6-kirigami-devel \
    qt6-qtbase-devel \
    qt6-qtdeclarative-devel

aq_installed cmake gcc-c++ extra-cmake-modules kf6-kcmutils-devel qt6-qtdeclarative-devel

# ------------------------------------------------------------------------------
# Build it
# ------------------------------------------------------------------------------
# CMAKE_INSTALL_PREFIX=/usr matters: it is what puts the finished plugin under
# the exact folder System Settings looks in, which is
# /usr/lib64/qt6/plugins/plasma/kcms/systemsettings/ on Fedora. KDE's own
# KDEInstallDirs works that out from the prefix; we never spell the path.
say "Compiling"
rm -rf "${BUILD}" "${STAGE}"
cmake -S "${SRC}" -B "${BUILD}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DBUILD_TESTING=OFF
cmake --build "${BUILD}" --parallel "$(nproc)"
DESTDIR="${STAGE}" cmake --install "${BUILD}"

# ------------------------------------------------------------------------------
# Did it actually produce the plugin, and in the right place?
# ------------------------------------------------------------------------------
# "Trust content, never timestamps": this looks for the finished file by name,
# under the folder System Settings reads, and fails if the build put it
# anywhere else.
say "Checking what the build produced"
PLUGIN="$(find "${STAGE}" -type f -name 'kcm_aquariuskeys.so' -print -quit)"
if [ -z "${PLUGIN}" ]; then
    bad "no kcm_aquariuskeys.so was produced — the page would simply not exist"
    echo "  what the build DID install:"
    find "${STAGE}" -type f | sed 's/^/    /'
    aq_finish "The KDE settings page"
fi

# The path inside the staging folder, with the DESTDIR prefix taken off, is
# where this file will live in the finished image.
PLUGIN_PATH="${PLUGIN#"${STAGE}"}"
echo "  it will be installed at: ${PLUGIN_PATH}"
case "${PLUGIN_PATH}" in
    */plasma/kcms/systemsettings/kcm_aquariuskeys.so)
        ok "it lands in the folder System Settings reads"
        ;;
    *)
        bad "it lands at ${PLUGIN_PATH}, which System Settings does not read — the page would never appear"
        ;;
esac

# ------------------------------------------------------------------------------
# ⚠️ NO MENU ENTRY. This is checked, not assumed.
# ------------------------------------------------------------------------------
# AquariusOS ships GNOME as well as KDE, and both desktops read
# /usr/share/applications/. A KDE-only settings page with a menu entry there
# would appear as a dead app in GNOME's app grid. The build is told not to
# generate one (DISABLE_DESKTOP_FILE_GENERATION in the CMakeLists), and this is
# the check that keeps that true if anybody edits it.
if find "${STAGE}/usr/share/applications" -type f 2> /dev/null | grep -q .; then
    bad "the build installed a menu entry into /usr/share/applications — it would show up in GNOME's app grid"
    find "${STAGE}/usr/share/applications" -type f | sed 's/^/    /'
else
    ok "no menu entry was installed (correct — it would appear in GNOME)"
fi

# ------------------------------------------------------------------------------
# The page's own interface has to be INSIDE the plugin
# ------------------------------------------------------------------------------
# KDE's build macro bakes everything in the ui/ folder into the plugin file, so
# the page cannot arrive without its own interface. That is invisible from the
# outside — so read the plugin and look for a line of our own QML text in it.
# If the baking silently did not happen, the page loads and is blank.
if grep -aq "AquariusOS can type like a Mac" "${PLUGIN}"; then
    ok "the page's interface is baked into the plugin"
else
    bad "the plugin does not contain the page's QML — the page would open empty"
fi

# ------------------------------------------------------------------------------
# Hand everything to the image stage
# ------------------------------------------------------------------------------
say "Leaving the result in ${OUT} for the image to collect"
install -d -m 0755 "${OUT}/kcm"
install -D -m 0755 "${PLUGIN}" "${OUT}/kcm/kcm_aquariuskeys.so"

# The path is written down beside the file so the image stage installs it in
# exactly the place this build chose, rather than guessing lib or lib64.
printf '%s\n' "${PLUGIN_PATH}" > "${OUT}/kcm/install-path"
ok "kcm_aquariuskeys.so ($(stat -c '%s' "${OUT}/kcm/kcm_aquariuskeys.so") bytes)"
ok "its home in the image: $(cat "${OUT}/kcm/install-path")"

aq_finish "The KDE settings page"
