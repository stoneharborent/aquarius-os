#!/bin/bash
# ==============================================================================
# AquariusOS — the KWin effects layer  (Tier 2, Track B)
# ==============================================================================
# WHAT THIS FILE DOES, IN ONE SENTENCE
#   It downloads the source code of ONE community KWin add-on, compiles it
#   inside the image build against the exact KWin this image ships, and
#   installs the resulting plug-in. If it fails to compile, the whole OS build
#   goes red and nothing is published.
#
# WHY THE FILE IS STILL CALLED "kwin-effects" WHEN IT BUILDS ONE EFFECT
#   It used to build two. The second one — Better Blur DX, which made whole
#   application windows frosted glass — was removed on 2026-08-30 when Royce
#   decided AquariusOS ships without glass. The name stays because this is
#   still the place any compiled KWin effect belongs, and because the file is
#   referenced by name from build.sh, the CI workflow and two docs. If a
#   second effect is ever added, it goes here.
#
# WHY BETTER BLUR DX IS GONE — the short version
#   It worked, in the sense that it compiled, installed and loaded. What it
#   never did was produce a visible blur, because KWin on this Plasma does not
#   draw the frost at all — a fault that was chased through every layer we
#   control and found to sit upstream. The full investigation is
#   ../docs/blur-known-issue.md.
#
#   With no blur to show, translucent surfaces were just see-through, so the
#   design dropped the transparency and went fully opaque. And an effect whose
#   entire job is to blur behind windows that are no longer see-through is a
#   compile-from-source dependency, a version treadmill, and a per-frame
#   shader cost, all bought for nothing. So it comes out of the image.
#
#   Restoring it, if a future Plasma fixes the blur: the old recipe is in this
#   file's git history, and what it was for is written up in
#   ../docs/kwin-effects-layer.md. Both the effect AND the theme's
#   translucency would have to come back — one without the other does nothing.
#
# WHAT THE REMAINING ADD-ON IS FOR
#   KDE-Rounded-Corners rounds the corners of every window to 16px, matching
#   the AquariusOS design, and re-shapes the window's shadow to follow that
#   rounded outline. This one is unaffected by the blur problem: its corners
#   and its window outline were both confirmed working on the bench on
#   2026-08-30, and they are visibly part of the shipping look.
#
# WHY COMPILE IT HERE INSTEAD OF INSTALLING A READY-MADE PACKAGE
#   This is the important part, and it is a deliberate decision, not laziness.
#
#   A KWin effect is a plug-in loaded into the running compositor. It works
#   with EXACTLY the KWin version it was compiled against and no other — KDE
#   makes no promise of compatibility between releases, not even between 6.7.1
#   and 6.7.2. The failure mode is the nastiest kind: nothing crashes, no error
#   appears, the plug-in simply is not loaded and the corners quietly go
#   square. That is not a theory; it is a documented upstream case where
#   6.7.1 -> 6.7.2 broke an effect on an already-working machine.
#
#   There are ready-made Fedora packages (COPRs), and using one would mean our
#   image's KWin and somebody else's build of the effect are updated by two
#   different people on two different days. Sooner or later a user boots an
#   image where they do not match, and the effect silently disappears.
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
#   treadmill into a build-time signal. Do not "fix" a failure here by making
#   it non-fatal. A silent skip would ship an image whose windows are square
#   with nothing anywhere to say so.
#
# WHY THERE IS NO `|| true` ANYWHERE BELOW
#   Same reason. `set -e` on the next line plus the explicit checks at the end
#   mean this script has exactly two outcomes: the effect is in the image, or
#   there is no image.
#
# The beginner-facing write-up — what the effect does, how to bump the pinned
# version, and the command to check it on a real machine — is in
# ../docs/kwin-effects-layer.md.
#
# Called from build_files/build.sh. The settings that switch the effect on live
# in system_files/usr/share/aquarius/xdg/kwinrc (and breezerc next to it).
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# WHAT WE BUILD — pinned, to the exact byte
# ------------------------------------------------------------------------------
# The one project below is pinned three ways, on purpose:
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
# ⚠️ HOW TO BUMP THE VERSION. Change the four lines together — tag, commit, URL
# and checksum — and never one without the others. Get the new checksum the
# honest way, by downloading the file and asking for it:
#
#     curl -fsSL -o /tmp/x.tar.gz <the new URL>
#     sha256sum /tmp/x.tar.gz
#
# Do NOT copy a checksum out of a web page. The point of the number is that it
# was computed from a file somebody actually held.
#
# (This is GitHub's automatically generated source tarball. They are byte
# stable for a given tag — the tarball checked in here was fetched three times
# on three connections and matched — and the contents were compared file by file
# against a `git clone` of the pinned commit before the value was written down.)
# ------------------------------------------------------------------------------

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
# WHERE THE FINISHED PLUG-IN LANDS
# ------------------------------------------------------------------------------
# KWin looks for compiled effects in one folder and one folder only:
#   <Qt plug-in folder>/kwin/effects/plugins/
# On 64-bit Fedora the Qt plug-in folder is /usr/lib64/qt6/plugins, so:
KWIN_PLUGIN_DIR="/usr/lib64/qt6/plugins/kwin/effects/plugins"
KWIN_CONFIG_DIR="/usr/lib64/qt6/plugins/kwin/effects/configs"

# The exact file name, read out of the project's build files rather than
# guessed:
#
#   kwin4_effect_shapecorners.so
#     src/CMakeLists.txt: `kcoreaddons_add_plugin(kwin4_effect_shapecorners …
#     INSTALL_NAMESPACE "${KWIN_NAMESPACE_PREFIX}/effects/plugins/")`, with
#     KWIN_NAMESPACE_PREFIX set to "kwin" for the Wayland build.
#     Also listed literally in the project's own Fedora spec file,
#     .copr/kwin-effect-roundcorners.spec.
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
#   Not from guesswork and not from a forum. KDE-Rounded-Corners publishes its
#   own Fedora build instructions and is tested on Fedora by its own CI:
#   .github/workflows/fedora.yml runs on fedora:44 (the same Fedora our Bazzite
#   base is built from), and .copr/kwin-effect-roundcorners.spec lists the same
#   set again.
#
#   ⚠️ THE LIST IS DELIBERATELY NOT TRIMMED, even now that only one project is
#   built from it. It was originally the union of two upstreams' Fedora lists,
#   and a handful of entries below are marked as having come in for Better Blur
#   DX, which was removed on 2026-08-30. They are kept because:
#     * KWin's own headers reach for several of them indirectly, and working
#       out exactly which by deletion means a round of red builds;
#     * every one of them is removed again at the end of this script, inside
#       the same Containerfile RUN, so an over-generous list costs a little
#       build time and not one byte of the finished image.
#   Trimming it would be an optimisation that buys nothing and risks a red
#   build. If somebody does trim it one day, do it one package at a time.
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
    qt6-qtdeclarative-devel     # came in for Better Blur DX (removed 2026-08-30);
                                # kept — see the ⚠️ note above

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
    kdecoration-devel           # came in for Better Blur DX (removed 2026-08-30);
                                # kept — see the ⚠️ note above

    # --- graphics and display plumbing that KWin's own headers reach for ---
    libepoxy-devel              # find_package(epoxy) — both projects
    libX11-devel                # came in for Better Blur DX (removed 2026-08-30);
                                # kept — see the ⚠️ note above
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

# --- KDE-Rounded-Corners ------------------------------------------------------
# Wayland only. -DKWIN_X11=ON is available upstream and deliberately not used:
# AquariusOS logs in on Wayland, so building the X11 version would add build
# time to produce a file nothing loads.
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
say "=== Checking the installed plug-in ==="

check_file() {
    local what="$1" path="$2"
    if [ ! -f "${path}" ]; then
        die "${what} is not at ${path} after a successful build." \
            "" \
            "That means the project changed where it installs itself. Here is" \
            "everything that looks like a KWin effect on this image:" \
            "$(find /usr/lib64 /usr/lib /usr/share -name '*shapecorners*' 2>/dev/null | sort)" \
            "" \
            "Fix the expected paths at the top of build_files/kwin-effects.sh," \
            "and update the matching check in .github/workflows/build.yml."
    fi
    say "  OK  ${path}  ($(stat -c '%s' "${path}") bytes)"
}

check_file "The KDE-Rounded-Corners effect"       "${KRC_SO}"
check_file "The KDE-Rounded-Corners settings page" "${KRC_KCM_SO}"
for aq_shader in "${KRC_SHADERS[@]}"; do
    check_file "A KDE-Rounded-Corners shader" "${aq_shader}"
done

# Every library the plug-in needs must be present in the image. `ldd -r` walks
# the whole dependency list and prints "not found" for anything missing. This is
# the closest thing to "will KWin be able to load this" that can be asked inside
# a container with no graphics and no compositor running.
say ""
say "=== Checking every library the plug-in needs is in the image ==="
for aq_so in "${KRC_SO}" "${KRC_KCM_SO}"; do
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
say "=== Checking the plug-in description was compiled in ==="
if ! grep -aq 'ShapeCorners\|Rounded Corners' "${KRC_SO}"; then
    die "The KDE-Rounded-Corners plug-in has no description compiled into it." \
        "(Expected 'Rounded Corners' or 'ShapeCorners' inside ${KRC_SO}.)"
fi
say "  OK  kwin4_effect_shapecorners.so carries its description"

# ==============================================================================
# STEP 5 — the settings that switch them on are really in the image
# ==============================================================================
# The plug-in is useless if nothing turns it on. Those defaults are plain text
# files copied in at the top of build.sh; a rename or a typo there would ship
# an image with an effect nobody ever sees.
#
# The exact spelling of the switch, and where it was read from, is written out
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

check_setting "${AQ_KWINRC}" '^kwin4_effect_shapecornersEnabled=true$' "Rounded corners are switched on"
check_setting "${AQ_KWINRC}" '^\[Round-Corners\]$'                  "The rounded-corners settings section"
check_setting "${AQ_BREEZERC}" '^\[Common\]$'                       "The window-shadow settings section"
check_setting "${AQ_BREEZERC}" '^ShadowSize=ShadowVeryLarge$'       "The big window shadow"

# On handhelds a second, higher-priority copy of kwinrc adds the settings only
# a handheld needs. That folder only exists on the handheld image (build.sh
# deletes it from the other two, further up), so this is not a variant check —
# it is the same "is the folder there?" question that
# /etc/xdg/plasma-workspace/env/zz-aquarius.sh asks.
#
# Until 2026-08-30 this checked for the handheld's gentler BLUR setting. That
# setting is gone with Better Blur DX, and the file's remaining job — driving
# the desktop with a game controller, on a device that has no mouse — is the
# more important of the two anyway. So that is what is checked now.
if [ -d /usr/share/aquarius/xdg-handheld ]; then
    check_setting /usr/share/aquarius/xdg-handheld/kwinrc \
        '^gamecontrollerEnabled=true$' "The handheld's controller-as-mouse setting"
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
say "  KDE-Rounded-Corners ${KRC_TAG}  against KWin ${AQ_KWIN_VR}"
