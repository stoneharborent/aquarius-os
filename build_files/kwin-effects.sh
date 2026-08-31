#!/bin/bash
# ==============================================================================
# AquariusOS — the KWin effects layer  (Tier 2, Track B)
# ==============================================================================
# WHAT THIS FILE DOES, IN ONE SENTENCE
#   It downloads the source code of two community KWin add-ons, compiles them
#   inside the image build against the exact KWin this image ships, and installs
#   the two resulting plug-in files. If either one fails to compile, the whole
#   OS build goes red and nothing is published.
#
# WHAT THE TWO ADD-ONS ARE FOR
#   Better Blur DX      makes ordinary application windows glassy. Stock KWin
#                       will only blur behind a window if the *application*
#                       asks for it, and almost none do, so plain transparency
#                       reads as cheap plastic instead of glass. Better Blur DX
#                       can blur behind every window whether it asked or not.
#
#   KDE-Rounded-Corners rounds the corners of every window to 16px, matching the
#                       AquariusOS design, and re-shapes the window's shadow to
#                       follow that rounded outline.
#
# WHY COMPILE THEM HERE INSTEAD OF INSTALLING A READY-MADE PACKAGE
#   This is the important part, and it is a deliberate decision, not laziness.
#
#   A KWin effect is a plug-in loaded into the running compositor. It works with
#   EXACTLY the KWin version it was compiled against and no other — KDE makes no
#   promise of compatibility between releases, not even between 6.7.1 and 6.7.2.
#   The failure mode is the nastiest kind: nothing crashes, no error appears,
#   the plug-in simply is not loaded and the desktop quietly stops being glassy.
#   That is not a theory; it is upstream issue #105, where 6.7.1 → 6.7.2 broke
#   the effect on an already-working machine:
#     https://github.com/xarblu/kwin-effects-better-blur-dx/issues/105
#
#   There is a ready-made Fedora package (a COPR), and using it would mean our
#   image's KWin and somebody else's build of the effect are updated by two
#   different people on two different days. Sooner or later a user boots an
#   image where they do not match, and the glass silently disappears.
#
#   Compiling here removes that gap entirely. The effect and the KWin it was
#   built for are welded into the same image; an update ships both or neither,
#   and a rollback rolls back both. And when Bazzite moves to a new Plasma that
#   upstream has not caught up with yet, THIS BUILD FAILS, loudly, in GitHub
#   Actions — while everybody's installed image keeps working, because bootc
#   images only change when a new one is published. The problem becomes a red X
#   in a tab that only we look at, instead of a broken desktop.
#
#   That is the whole doctrine in one line: turn an unavoidable compatibility
#   treadmill into a build-time signal. Do not "fix" a failure here by making it
#   non-fatal. A silent skip would ship an image whose desktop is missing half
#   its design with nothing anywhere to say so.
#
# WHY THERE IS NO `|| true` ANYWHERE BELOW
#   Same reason. `set -e` on the next line plus the explicit checks at the end
#   mean this script has exactly two outcomes: both effects are in the image, or
#   there is no image.
#
# The beginner-facing write-up — what the effects do, how to bump the pinned
# versions, and the two commands to check them on a real machine — is in
# ../docs/kwin-effects-layer.md.
#
# Called from build_files/build.sh. The settings that switch the effects on live
# in system_files/usr/share/aquarius/xdg/kwinrc (and breezerc next to it).
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# WHAT WE BUILD — pinned, to the exact byte
# ------------------------------------------------------------------------------
# Each project is pinned three ways, on purpose:
#
#   the TAG      what a human should look up when reading release notes
#   the COMMIT   the exact revision that tag pointed at when this was written,
#                so a re-tagged or moved tag is obvious to a person comparing
#   the SHA256   the fingerprint of the downloaded file, which is the one the
#                MACHINE checks. Nothing is unpacked or compiled until the
#                download matches this string.
#
# The checksum is the real gate; the other two are provenance for people. This
# is the same discipline the DaVinci Resolve AAC plug-in recipe uses in
# system_files/usr/share/ublue-os/just/96-aquarius-creator.just — a pinned URL
# and a pinned fingerprint, both written down where a human put them.
#
# ⚠️ HOW TO BUMP A VERSION. Change the four lines for that project together —
# tag, commit, URL and checksum — and never one without the others. Get the new
# checksum the honest way, by downloading the file and asking for it:
#
#     curl -fsSL -o /tmp/x.tar.gz <the new URL>
#     sha256sum /tmp/x.tar.gz
#
# Do NOT copy a checksum out of a web page. The point of the number is that it
# was computed from a file somebody actually held.
#
# (These are GitHub's automatically generated source tarballs. They are byte
# stable for a given tag — the tarball checked in here was fetched three times
# on three connections and matched — and the contents were compared file by file
# against a `git clone` of the pinned commit before the value was written down.)
# ------------------------------------------------------------------------------

# Better Blur DX — https://github.com/xarblu/kwin-effects-better-blur-dx
# v2.5.1, released 2026-06-23. Upstream's README lists Plasma 6.5, 6.6 and 6.7
# as supported; its CMakeLists.txt refuses outright to build against anything
# older than KWin 6.4.
BBDX_TAG="v2.5.1"
BBDX_COMMIT="e8475d0a7045e1ef035d54cff9cf2c0b02f0aff0"
BBDX_URL="https://github.com/xarblu/kwin-effects-better-blur-dx/archive/refs/tags/v2.5.1.tar.gz"
BBDX_SHA256="42152f040434f0adfef55eab510000a5fc00b0afe1935e0dc6f01c766b4c9dbb"
BBDX_SRCDIR="kwin-effects-better-blur-dx-2.5.1"

# KDE-Rounded-Corners — https://github.com/matinlotfali/KDE-Rounded-Corners
# v0.10.0, released 2026-08-23. This is the release that added the Plasma 6.7
# fixes by name: "Load the core-profile shader on KWin 6.7+" and "Fix shader
# loading on KWin X11 6.7". The previous release, v0.9.0, predates them.
KRC_TAG="v0.10.0"
KRC_COMMIT="08dee25ac0410d977a45dd1e74a7de1823c1f098"
KRC_URL="https://github.com/matinlotfali/KDE-Rounded-Corners/archive/refs/tags/v0.10.0.tar.gz"
KRC_SHA256="f3f03d96e17ae4b7dcee6347a01c75de6f90ed19e070e98ae8bf2dd71ae276db"
KRC_SRCDIR="KDE-Rounded-Corners-0.10.0"

# ------------------------------------------------------------------------------
# WHERE THE FINISHED PLUG-INS LAND
# ------------------------------------------------------------------------------
# KWin looks for compiled effects in one folder and one folder only:
#   <Qt plug-in folder>/kwin/effects/plugins/
# On 64-bit Fedora the Qt plug-in folder is /usr/lib64/qt6/plugins, so:
KWIN_PLUGIN_DIR="/usr/lib64/qt6/plugins/kwin/effects/plugins"
KWIN_CONFIG_DIR="/usr/lib64/qt6/plugins/kwin/effects/configs"

# The exact file names, read out of each project's build files rather than
# guessed:
#   better_blur_dx.so
#     src/CMakeLists.txt: `add_library(better_blur_dx MODULE …)` +
#     `install(TARGETS better_blur_dx DESTINATION
#      ${KDE_INSTALL_PLUGINDIR}/kwin/effects/plugins)`.
#     There is no "lib" on the front because KDE's shared CMake rules strip it:
#     extra-cmake-modules, kde-modules/KDECMakeSettings.cmake — "By default,
#     don't put a prefix on MODULE targets… in KDE plugins don't have a prefix",
#     `set(CMAKE_SHARED_MODULE_PREFIX "")`.
#     Confirmed independently by upstream issue #105, where a maintainer's build
#     log names the file as
#     /usr/lib64/qt6/plugins/kwin-x11/effects/plugins/better_blur_dx.so
#     (that is the X11 folder; ours is the kwin/ one — we do not build X11).
#
#   kwin4_effect_shapecorners.so
#     src/CMakeLists.txt: `kcoreaddons_add_plugin(kwin4_effect_shapecorners …
#     INSTALL_NAMESPACE "${KWIN_NAMESPACE_PREFIX}/effects/plugins/")`, with
#     KWIN_NAMESPACE_PREFIX set to "kwin" for the Wayland build.
#     Also listed literally in the project's own Fedora spec file,
#     .copr/kwin-effect-roundcorners.spec.
BBDX_SO="${KWIN_PLUGIN_DIR}/better_blur_dx.so"
BBDX_KCM_SO="${KWIN_CONFIG_DIR}/kwin_better_blur_dx_config.so"
KRC_SO="${KWIN_PLUGIN_DIR}/kwin4_effect_shapecorners.so"
KRC_KCM_SO="${KWIN_CONFIG_DIR}/kwin_shapecorners_config.so"

# KDE-Rounded-Corners does not put everything in its .so. It also installs two
# GLSL shader files that the effect reads at run time, and it will not draw
# anything without them.
#   src/shaders/CMakeLists.txt: install(FILES shapecorners.frag
#   shapecorners_core.frag DESTINATION "${KDE_INSTALL_DATADIR}/kwin/shaders")
KRC_SHADERS=(
    "/usr/share/kwin/shaders/shapecorners.frag"
    "/usr/share/kwin/shaders/shapecorners_core.frag"
)

# ------------------------------------------------------------------------------
# THE DEVELOPMENT PACKAGES — installed, used, then removed again
# ------------------------------------------------------------------------------
# Compiling C++ needs a compiler, CMake, and the header files of every library
# the code touches. None of that belongs in a finished operating system: it is
# hundreds of megabytes that no user will ever open.
#
# HOW THEY ARE REMOVED, AND WHY IT REALLY IS FREE
#   The Containerfile runs build_files/build.sh inside ONE `RUN` instruction.
#   A container image layer is the *difference* between the filesystem before
#   and after that instruction — not a recording of everything that happened
#   in between. So a package installed and removed within the same RUN leaves
#   no trace in the published image at all. That is why this does not need the
#   multi-stage build gymnastics you may have read about; the image's existing
#   shape already gives us the same result for free.
#
#   The removal below is deliberately not "remove this list". It is "remove
#   exactly the packages that were not installed before we started", worked out
#   by comparing the package list either side of the install. That catches the
#   extra libraries dnf pulled in as dependencies, and — much more importantly —
#   it can never remove something Bazzite had already put there.
#
# WHERE THIS LIST CAME FROM
#   Not from guesswork and not from a forum. Both projects publish their own
#   Fedora build instructions, and both are tested on Fedora by their own CI:
#     * Better Blur DX — README.md, the "Fedora 41, 42" box, Wayland column.
#     * KDE-Rounded-Corners — .github/workflows/fedora.yml, which runs on
#       fedora:44 (the same Fedora our Bazzite base is built from), plus its
#       .copr/kwin-effect-roundcorners.spec.
#
#   The list below is those two lists merged, with the entries that are plainly
#   runtime-only dropped (they are already on any Plasma desktop) and the two
#   X11-only ones dropped (we build the Wayland version only — see below).
#   Everything else is kept even where it looks redundant, and that is a
#   deliberate choice: this is the exact set the people who maintain these
#   projects use to build them on Fedora, and second-guessing it to save
#   packages would buy nothing. It all goes away again at the end of this
#   script, so an over-generous list costs a little build time and not one byte
#   of the finished image. Trimming it is not an optimisation worth the risk of
#   a red build.
#
#   Where a package is only needed by one of the two projects, it is still
#   installed for both. One dnf transaction is simpler than two.
#
#   kwin-devel is NOT in this list. It is handled separately below, because it
#   is the one package whose version has to match something already installed.
AQ_BUILD_PACKAGES=(
    # --- the compiler and the build system ---
    cmake
    gcc-c++
    extra-cmake-modules         # find_package(ECM) — both projects
    gettext                     # msgfmt, for KDE-Rounded-Corners' translations
                                # (ki18n_install(po) in its top CMakeLists.txt)

    # --- Qt 6 ---
    qt6-qtbase-devel            # Core, DBus, Gui, Network, OpenGL, Widgets
    qt6-qtbase-private-devel    # KWin's headers use Qt's private API, and
                                # KDE-Rounded-Corners links Qt6::CorePrivate
                                # directly on Qt 6.10 and newer
    qt6-qtdeclarative-devel     # Qt6::Qml and Qt6::Quick — Better Blur DX

    # --- KDE Frameworks 6 ---
    # The first block is one package per find_package(KF6 … COMPONENTS …) entry
    # in the two CMakeLists.txt files.
    kf6-kconfig-devel           # Config
    kf6-kconfigwidgets-devel    # ConfigWidgets
    kf6-kcoreaddons-devel       # CoreAddons
    kf6-kcolorscheme-devel      # ColorScheme
    kf6-kcmutils-devel          # KCMUtils — the System Settings pages
    kf6-ki18n-devel             # I18n
    kf6-kwidgetsaddons-devel    # WidgetsAddons
    kf6-kwindowsystem-devel     # WindowSystem
    # The second block is not referenced by either project's own CMakeLists —
    # they come in through KWin's, which is pulled in by find_package(KWin).
    # Upstream lists every one of them in its Fedora instructions, so they stay.
    kf6-kcrash-devel
    kf6-kdeclarative-devel
    kf6-kglobalaccel-devel
    kf6-kguiaddons-devel
    kf6-kio-devel
    kf6-knotifications-devel
    libplasma-devel
    plasma-workspace-devel

    # --- the window-decoration API ---
    kdecoration-devel           # find_package(KDecoration3) — Better Blur DX

    # --- graphics and display plumbing that KWin's own headers reach for ---
    libepoxy-devel              # find_package(epoxy) — both projects
    libX11-devel                # find_package(X11) — Better Blur DX
    libxcb-devel                # find_package(XCB) — both projects
    libdrm-devel
    wayland-devel
    vulkan-headers              # KWin 6.7's headers want these. Upstream hit
                                # exactly this and added the same dependency for
                                # Arch in KDE-Rounded-Corners v0.10.0 (PR #510).
)

# ------------------------------------------------------------------------------
# Small helpers — same shape as the ones in creator-apps.sh
# ------------------------------------------------------------------------------

die() {
    echo ""
    echo "=============================================================="
    echo "AquariusOS KWin effects build step FAILED"
    echo "--------------------------------------------------------------"
    printf '%s\n' "$@"
    echo "=============================================================="
    echo ""
    exit 1
}

say() { echo ">> $*"; }

# ==============================================================================
# STEP 1 — find out which KWin this image actually has
# ==============================================================================
# Everything below hangs off this number. It is printed into the build log on
# purpose: when somebody investigates "the glass stopped working", the first
# question is always "which KWin was this built against", and the answer should
# be in the log of the build that produced the image.

AQ_KWIN_PKG="$(rpm -qf --queryformat '%{NAME}\n' /usr/bin/kwin_wayland 2>/dev/null | head -n1 || true)"
if [ -z "${AQ_KWIN_PKG}" ]; then
    die "Could not find out which package owns /usr/bin/kwin_wayland." \
        "" \
        "That file is KWin itself, so either this base image is not a KDE" \
        "image any more, or KWin has moved. Nothing has been installed." \
        "" \
        "This is exactly the kind of change that should stop a build: the two" \
        "effects below are compiled against KWin and are meaningless without it."
fi

AQ_KWIN_VR="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}\n' "${AQ_KWIN_PKG}" | head -n1)"

say "KWin in this image: ${AQ_KWIN_PKG} ${AQ_KWIN_VR}"

# ==============================================================================
# STEP 2 — install the build tools
# ==============================================================================

# Snapshot the package list BEFORE, so we can put it back exactly afterwards.
AQ_PKGS_BEFORE="/tmp/aq-packages-before.txt"
rpm -qa --queryformat '%{NAME}\n' | sort -u > "${AQ_PKGS_BEFORE}"

# kwin-devel first, and PINNED to the version of KWin that is already here.
#
# ⚠️ The pin is the whole point. Without it, dnf is free to solve the request by
# UPGRADING KWin to whatever the repository has today — and then the image would
# ship a KWin that is not the one Bazzite tested, changed silently by us, as a
# side effect of asking for some header files. With the pin, either we get the
# matching headers or the build stops.
say "Installing kwin-devel-${AQ_KWIN_VR} (pinned to the KWin already installed)"
if ! dnf5 install -y "kwin-devel-${AQ_KWIN_VR}"; then
    die "Could not install kwin-devel-${AQ_KWIN_VR}." \
        "" \
        "This image has KWin ${AQ_KWIN_VR}, and the effects below MUST be" \
        "compiled against the headers of that exact version — a different one" \
        "produces plug-ins that load into nothing and silently do not work." \
        "" \
        "The usual cause is timing: Fedora has already replaced that build in" \
        "its repository, but the Bazzite image we start from was made before" \
        "the replacement. It normally fixes itself within a day, when a fresh" \
        "Bazzite image picks up the newer KWin. Re-running the build later is" \
        "the correct response. Do NOT remove the version pin to get past this."
fi

say "Installing the rest of the build tools"
dnf5 install -y "${AQ_BUILD_PACKAGES[@]}"

# Belt and braces: prove the headers we just installed really do belong to the
# KWin that is installed. If these two ever differ, everything compiles cleanly
# and nothing works at run time — the exact silent failure this whole file
# exists to prevent.
AQ_KWIN_DEVEL_VR="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}\n' kwin-devel | head -n1)"
if [ "${AQ_KWIN_DEVEL_VR}" != "${AQ_KWIN_VR}" ]; then
    die "KWin and its headers do not match." \
        "" \
        "  KWin (${AQ_KWIN_PKG}): ${AQ_KWIN_VR}" \
        "  kwin-devel:            ${AQ_KWIN_DEVEL_VR}" \
        "" \
        "Effects compiled against mismatched headers load into nothing and" \
        "fail silently on the user's machine. Stopping here instead."
fi

# The compositor's plug-in interface has its own version number, separate from
# the Plasma release number, and it is the number that actually decides whether
# a plug-in is accepted. Printing it makes "which ABI was this image built for"
# answerable from the build log alone.
if [ -r /usr/include/kwin/effect/effect.h ]; then
    say "KWin effect plug-in interface version:"
    grep -E '#define KWIN_EFFECT_API_VERSION' /usr/include/kwin/effect/effect.h || true
fi

# ==============================================================================
# STEP 3 — download, check, unpack, compile, install
# ==============================================================================
# Everything happens under /tmp. The Containerfile mounts a tmpfs there
# (`--mount=type=tmpfs,dst=/tmp`), which means it is memory, not part of the
# image, and it disappears on its own when the build step finishes.

AQ_WORK="/tmp/aquarius-kwin-effects"
rm -rf "${AQ_WORK}"
mkdir -p "${AQ_WORK}"

# fetch_and_verify <name> <url> <expected sha256> <output file>
fetch_and_verify() {
    local name="$1" url="$2" want="$3" out="$4" got

    say "Downloading ${name}"
    say "  from: ${url}"
    if ! curl --retry 3 --retry-delay 5 -fsSL -o "${out}" "${url}"; then
        die "Could not download the source code for ${name}." \
            "" \
            "  Tried: ${url}" \
            "" \
            "Either GitHub is unreachable from the build machine, or the tag" \
            "pinned at the top of build_files/kwin-effects.sh no longer exists."
    fi

    got="$(sha256sum "${out}" | awk '{print $1}')"
    say "  expected: ${want}"
    say "  actual:   ${got}"
    if [ "${got}" != "${want}" ]; then
        die "CHECKSUM MISMATCH for ${name}." \
            "" \
            "  expected ${want}" \
            "  actual   ${got}" \
            "" \
            "The file that arrived is not the file this build expects. Nothing" \
            "has been unpacked and nothing has been compiled." \
            "" \
            "Do not 'fix' this by pasting the new number in. Find out why it" \
            "changed first: a tag that was moved or re-cut upstream is a real" \
            "event worth understanding, and so is a download that was tampered" \
            "with in transit."
    fi
    say "  checksum OK"
}

# build_effect <name> <source folder under $AQ_WORK> <extra cmake args…>
#
# The three cmake settings that are always passed:
#   CMAKE_BUILD_TYPE=Release   optimised, no debug symbols to strip afterwards
#   CMAKE_INSTALL_PREFIX=/usr  install into the OS proper. NOT /usr/local —
#                              that is redirected to writable storage that does
#                              not exist yet at build time on this kind of OS,
#                              the same trap documented at length in build.sh
#                              for the Python helper.
#   CMAKE_INSTALL_LIBDIR=lib64 spelled out rather than left to be detected, so
#                              the plug-in provably lands in the one folder KWin
#                              looks in on 64-bit Fedora.
build_effect() {
    local name="$1" srcdir="$2"
    shift 2

    say "Configuring ${name}"
    cmake \
        -S "${AQ_WORK}/${srcdir}" \
        -B "${AQ_WORK}/${srcdir}-build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DCMAKE_INSTALL_LIBDIR=lib64 \
        "$@"

    say "Compiling ${name}"
    cmake --build "${AQ_WORK}/${srcdir}-build" -j "$(nproc)"

    say "Installing ${name}"
    cmake --install "${AQ_WORK}/${srcdir}-build"
}

# --- Better Blur DX -----------------------------------------------------------
# Wayland only. Upstream ships an X11 build behind -DBETTERBLUR_X11=ON and says
# in its own README that X11 is "more or less deprecated and not tested much".
# AquariusOS logs in on Wayland, so building the X11 version would double the
# build time to produce a file nothing loads — and, per upstream issue #105, a
# half-updated X11 build is itself a way to break the Wayland one. Not built.
say ""
say "=== Better Blur DX ${BBDX_TAG} (commit ${BBDX_COMMIT}) ==="
fetch_and_verify "Better Blur DX ${BBDX_TAG}" "${BBDX_URL}" "${BBDX_SHA256}" "${AQ_WORK}/bbdx.tar.gz"
tar -xzf "${AQ_WORK}/bbdx.tar.gz" -C "${AQ_WORK}"
[ -d "${AQ_WORK}/${BBDX_SRCDIR}" ] || die "Better Blur DX unpacked into an unexpected folder." \
    "Expected ${AQ_WORK}/${BBDX_SRCDIR}; the archive contained:" \
    "$(ls -1 "${AQ_WORK}")"
build_effect "Better Blur DX" "${BBDX_SRCDIR}"

# --- KDE-Rounded-Corners ------------------------------------------------------
# Same reasoning: -DKWIN_X11=ON is available and deliberately not used.
say ""
say "=== KDE-Rounded-Corners ${KRC_TAG} (commit ${KRC_COMMIT}) ==="
fetch_and_verify "KDE-Rounded-Corners ${KRC_TAG}" "${KRC_URL}" "${KRC_SHA256}" "${AQ_WORK}/krc.tar.gz"
tar -xzf "${AQ_WORK}/krc.tar.gz" -C "${AQ_WORK}"
[ -d "${AQ_WORK}/${KRC_SRCDIR}" ] || die "KDE-Rounded-Corners unpacked into an unexpected folder." \
    "Expected ${AQ_WORK}/${KRC_SRCDIR}; the archive contained:" \
    "$(ls -1 "${AQ_WORK}")"
build_effect "KDE-Rounded-Corners" "${KRC_SRCDIR}"

# ==============================================================================
# STEP 4 — prove the files are really there, before the tools go away
# ==============================================================================
# A compile can succeed and still install nothing where we expect it — a changed
# install path upstream, a wrong libdir, a renamed target. Check now, while the
# error message can still say something useful.

say ""
say "=== Checking the installed plug-ins ==="

check_file() {
    local what="$1" path="$2"
    if [ ! -f "${path}" ]; then
        die "${what} is not at ${path} after a successful build." \
            "" \
            "That means the project changed where it installs itself. Here is" \
            "everything that looks like a KWin effect on this image:" \
            "$(find /usr/lib64 /usr/lib /usr/share -name '*shapecorners*' -o -name '*better_blur*' 2>/dev/null | sort)" \
            "" \
            "Fix the expected paths at the top of build_files/kwin-effects.sh," \
            "and update the matching check in .github/workflows/build.yml."
    fi
    say "  OK  ${path}  ($(stat -c '%s' "${path}") bytes)"
}

check_file "The Better Blur DX effect"            "${BBDX_SO}"
check_file "The Better Blur DX settings page"     "${BBDX_KCM_SO}"
check_file "The KDE-Rounded-Corners effect"       "${KRC_SO}"
check_file "The KDE-Rounded-Corners settings page" "${KRC_KCM_SO}"
for aq_shader in "${KRC_SHADERS[@]}"; do
    check_file "A KDE-Rounded-Corners shader" "${aq_shader}"
done

# Every library each plug-in needs must be present in the image. `ldd -r` walks
# the whole dependency list and prints "not found" for anything missing. This is
# the closest thing to "will KWin be able to load this" that can be asked inside
# a container with no graphics and no compositor running.
say ""
say "=== Checking every library the plug-ins need is in the image ==="
for aq_so in "${BBDX_SO}" "${KRC_SO}" "${BBDX_KCM_SO}" "${KRC_KCM_SO}"; do
    if ldd -r "${aq_so}" 2>&1 | grep -q 'not found'; then
        die "$(basename "${aq_so}") needs libraries this image does not have:" \
            "" \
            "$(ldd -r "${aq_so}" 2>&1 | grep 'not found')" \
            "" \
            "A plug-in with a missing library is silently ignored by KWin. It" \
            "would look exactly like the effect 'not working' with no error."
    fi
    say "  OK  $(basename "${aq_so}") — all libraries present"
done

# The description KDE reads to list an effect in System Settings is compiled
# INTO the .so as a block of JSON. It is easy to lose (a metadata.json the build
# could not find produces a plug-in that loads but never appears anywhere), and
# easy to check: the text is stored verbatim inside the file.
say ""
say "=== Checking the plug-in descriptions were compiled in ==="
if ! grep -aq 'Better Blur DX' "${BBDX_SO}"; then
    die "The Better Blur DX plug-in has no description compiled into it." \
        "(Expected to find the text 'Better Blur DX' inside ${BBDX_SO}.)" \
        "" \
        "Without it the effect cannot be listed in System Settings and KWin" \
        "cannot work out whether it should be on."
fi
say "  OK  better_blur_dx.so carries its description"
if ! grep -aq 'ShapeCorners\|Rounded Corners' "${KRC_SO}"; then
    die "The KDE-Rounded-Corners plug-in has no description compiled into it." \
        "(Expected 'Rounded Corners' or 'ShapeCorners' inside ${KRC_SO}.)"
fi
say "  OK  kwin4_effect_shapecorners.so carries its description"

# ==============================================================================
# STEP 5 — the settings that switch them on are really in the image
# ==============================================================================
# The plug-ins are useless if nothing turns them on. Those defaults are plain
# text files copied in at the top of build.sh; a rename or a typo there would
# ship an image with two effects nobody ever sees.
#
# The exact spelling of each switch, and where it was read from, is written out
# in the kwinrc file itself. This only checks the lines are present.

say ""
say "=== Checking the settings that switch the effects on ==="

AQ_KWINRC="/usr/share/aquarius/xdg/kwinrc"
AQ_BREEZERC="/usr/share/aquarius/xdg/breezerc"

check_setting() {
    local file="$1" pattern="$2" what="$3"
    if ! grep -Eq "${pattern}" "${file}"; then
        die "${what} is missing from ${file}." \
            "Looked for a line matching: ${pattern}"
    fi
    say "  OK  ${what}"
}

[ -f "${AQ_KWINRC}" ] || die "${AQ_KWINRC} is not in the image."
[ -f "${AQ_BREEZERC}" ] || die "${AQ_BREEZERC} is not in the image."

check_setting "${AQ_KWINRC}" '^better_blur_dxEnabled=true$'         "Better Blur DX is switched on"
check_setting "${AQ_KWINRC}" '^kwin4_effect_shapecornersEnabled=true$' "Rounded corners are switched on"
check_setting "${AQ_KWINRC}" '^blurEnabled=false$'                  "KDE's own blur is switched off"
check_setting "${AQ_KWINRC}" '^\[Effect-better-blur-dx\]$'          "The Better Blur DX settings section"
check_setting "${AQ_KWINRC}" '^\[Round-Corners\]$'                  "The rounded-corners settings section"
check_setting "${AQ_BREEZERC}" '^\[Common\]$'                       "The window-shadow settings section"
check_setting "${AQ_BREEZERC}" '^ShadowSize=ShadowVeryLarge$'       "The big window shadow"

# On handhelds a second, higher-priority copy of kwinrc turns the blur down for
# a laptop-class chip. That folder only exists on the handheld image (build.sh
# deletes it from the other two, further up), so this is not a variant check —
# it is the same "is the folder there?" question that
# /etc/xdg/plasma-workspace/env/zz-aquarius.sh asks.
if [ -d /usr/share/aquarius/xdg-handheld ]; then
    check_setting /usr/share/aquarius/xdg-handheld/kwinrc \
        '^\[Effect-better-blur-dx\]$' "The handheld's gentler blur setting"
fi

# ==============================================================================
# STEP 6 — take the build tools back out
# ==============================================================================
# See the long note at the top of the package list. In short: remove exactly the
# packages that were not here before, so nothing Bazzite installed can be caught
# in the sweep, and — because this all happens inside a single Containerfile RUN
# — none of it costs the finished image a single byte.

say ""
say "=== Removing the build tools again ==="

rpm -qa --queryformat '%{NAME}\n' | sort -u > /tmp/aq-packages-after.txt
comm -13 "${AQ_PKGS_BEFORE}" /tmp/aq-packages-after.txt > /tmp/aq-packages-added.txt

AQ_ADDED_COUNT="$(wc -l < /tmp/aq-packages-added.txt | tr -d ' ')"
say "${AQ_ADDED_COUNT} packages were added for the build; removing them."

if [ "${AQ_ADDED_COUNT}" -gt 0 ]; then
    # xargs rather than a shell expansion: the list is long enough that spelling
    # it out on one line is asking for trouble.
    xargs -a /tmp/aq-packages-added.txt dnf5 remove -y
fi

# Prove the removal did not take the desktop with it. `dnf remove` also removes
# anything that depended on what you asked for, so this is worth checking rather
# than assuming — a build that quietly uninstalled KWin would still be "green"
# right up until somebody tried to log in.
say ""
say "=== Checking the desktop survived ==="
for aq_must_exist in \
    /usr/bin/kwin_wayland \
    "${BBDX_SO}" \
    "${KRC_SO}" \
    "${KRC_SHADERS[0]}" \
    "${KRC_SHADERS[1]}"
do
    [ -e "${aq_must_exist}" ] || die "${aq_must_exist} disappeared when the build tools were removed." \
        "" \
        "Removing the development packages has taken something with it that" \
        "the finished OS needs. Nothing usable can be built from here."
    say "  OK  ${aq_must_exist} is still here"
done

# And the headers really are gone — this is the check that catches "we shipped
# half a compiler" long before anybody notices the image is 400 MB fatter.
if rpm -q kwin-devel > /dev/null 2>&1; then
    die "kwin-devel is still installed after the clean-up step." \
        "The finished image must not carry development packages."
fi
say "  OK  the development packages are gone"

rm -rf "${AQ_WORK}" "${AQ_PKGS_BEFORE}" /tmp/aq-packages-after.txt /tmp/aq-packages-added.txt

say ""
say "KWin effects layer built and installed:"
say "  Better Blur DX      ${BBDX_TAG}   against KWin ${AQ_KWIN_VR}"
say "  KDE-Rounded-Corners ${KRC_TAG}  against KWin ${AQ_KWIN_VR}"
