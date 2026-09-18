#!/usr/bin/bash
# ==============================================================================
# BUILDER STAGE — our own gamescope, for the NVIDIA image only
# ==============================================================================
# ⚠️ THIS SCRIPT DOES NOT RUN INSIDE AQUARIUSOS. It runs in a throwaway Fedora
# container whose only job is to compile one program and leave it in /out. The
# real image then copies that one program in. Nothing else from this container
# reaches the finished operating system — not the compiler, not the hundreds of
# development packages, not the source code. That is why it is a separate
# "stage" in the Containerfile, and it is the same pattern the retired Aquarius
# Session used to compile labwc and Quickshell.
#
# ------------------------------------------------------------------------------
# WHY WE ARE COMPILING A PROGRAM AT ALL, WHEN FEDORA SHIPS IT
# ------------------------------------------------------------------------------
# gamescope is the little compositor that Game Mode runs inside — Steam and your
# games draw into it, and it puts the picture on the screen. Fedora packages it,
# and on an AMD or Intel machine Fedora's copy is exactly right, which is why the
# AMD/Intel image keeps it and this script never runs for that image.
#
# On an NVIDIA card, Fedora's copy draws a corrupted picture. This is not a
# theory; it was photographed on Royce's RTX 5080 on 2026-09-17, four separate
# runs, and it looks like this: Steam's interface draws correctly, and then a
# staircase-shaped band across the middle of the screen shows *somebody else's
# memory* — a browser window's text, with the colours wrong.
#
# THE CAUSE, in plain English and confirmed by NVIDIA (their bug 5240452):
# a picture that is about to be put on screen has to live in one unbroken run of
# graphics memory, because the display hardware reads it straight through from
# the start. gamescope asks for that memory through Vulkan, and NVIDIA's driver
# can answer with memory that is *scattered* in pieces. The driver does not
# check, and hands it to the display hardware anyway. The display hardware reads
# straight on past the end of the first piece — into whatever happens to be
# next, which is why you see part of another program's window. AMD and Intel are
# unaffected. GNOME and KDE are unaffected, because they ask for that memory a
# different way (through GBM), which the driver always makes contiguous.
#
# THE FIX is to make gamescope ask the same way GNOME does. Somebody has already
# written it — NightHammer1000's branch `poc/gamescope-gbm-route` — and it is
# confirmed working on NVIDIA cards including Blackwell. It is NOT in upstream
# gamescope and NOT in Fedora's package, so until it is, the NVIDIA image builds
# its own.
#
# ⚠️ WHEN THIS FILE RETIRES. The moment the fix reaches upstream gamescope and
# Fedora ships a version containing it. Then delete this script, delete the
# builder stage from the Containerfile, delete the "our own gamescope" section
# of build_files/71-game-mode.sh, and the NVIDIA image goes back to Fedora's
# package like the AMD one. Nothing else has to change; the environment file
# that switches the fix on is harmless on a gamescope that has never heard of
# it. The whole story in plain language is in docs/restart/game-mode.md.
#
# ------------------------------------------------------------------------------
# THE COMMIT IS PINNED, AND THAT IS NOT OPTIONAL
# ------------------------------------------------------------------------------
# This is somebody's experimental branch, not a release. "Whatever is on that
# branch today" would mean an operating system that is a different operating
# system every time it is built. So one exact commit is named here, it was read
# and checked on 2026-09-17, and moving it is a deliberate act with a bench test
# behind it.
# ==============================================================================

set -euo pipefail

# shellcheck source=build_files/aq-lib.sh
source /ctx/build_files/aq-lib.sh

# ------------------------------------------------------------------------------
# THE PIN
# ------------------------------------------------------------------------------
# NightHammer1000/gamescope, branch poc/gamescope-gbm-route, head on 2026-09-17.
# The commit message is "drm, rendervulkan: apply final review findings".
AQ_GS_REPO="https://github.com/NightHammer1000/gamescope.git"
AQ_GS_COMMIT="2bfc18c736520b7d4f9756977213ea439daa1c63"
AQ_GS_BRANCH="poc/gamescope-gbm-route"

# Where the finished program is left for the real image to pick up.
AQ_OUT="/out"

say "Building our own gamescope (NVIDIA image only)"
echo "  from:   ${AQ_GS_REPO}"
echo "  branch: ${AQ_GS_BRANCH}"
echo "  commit: ${AQ_GS_COMMIT}"

# ==============================================================================
# 1. The tools to build it with
# ==============================================================================
# ⚠️ THE LIST OF DEVELOPMENT PACKAGES IS ASKED FOR, NOT WRITTEN OUT BY HAND —
# AND THERE IS A HAND-WRITTEN ONE BEHIND IT ANYWAY. Here is why both exist.
#
# gamescope needs something like forty development packages and the list
# changes between versions. Fedora already packages gamescope, so Fedora already
# knows that list: `dnf builddep gamescope` asks for it. That is the right
# first answer, because it can never go stale.
#
# ⚠️ BUT IT NEEDS THE *SOURCE* REPOSITORY, WHICH FEDORA'S CONTAINER IMAGES SHIP
# SWITCHED OFF. `builddep <name>` works by finding the SOURCE package and
# reading its recipe, and `fedora-source` and `updates-source` are disabled in
# the container base. Without them the command fails with "no package matched",
# forty minutes into a build, for a reason that has nothing to do with our code.
# So they are switched on for exactly that one command — the same "on for one
# command" discipline this repository uses for Terra.
#
# AND IF IT STILL FAILS, WE DO NOT STOP. A builder stage that dies on a
# repository configuration detail is a bad builder stage. The fallback is the
# list of build requirements read out of Fedora's own gamescope recipe
# (https://src.fedoraproject.org/rpms/gamescope, rawhide, read 2026-09-17),
# written out below. Most of it is in `pkgconfig(...)` form, which is not a
# typo: that is a thing dnf can be asked for directly, so nobody here has to
# guess which package provides which library — Fedora's own recipe already said,
# and we are repeating it word for word rather than translating it.
#
# The hand-written list can go stale, which is why it is second and not first.
# If it is ever the one doing the work, the build log says so loudly.
say "The tools and libraries needed to compile it"
# pkgconf-pkg-config is named on purpose: `pkg-config` is how meson asks
# whether a library is here, and the checks further down ask the same way. It is
# normally dragged in by the first -devel package, but a check that depends on a
# tool arriving by accident is not a check.
aq_dnf install dnf5-plugins git meson ninja-build gcc gcc-c++ cmake glslang spirv-tools pkgconf-pkg-config

# The source repositories, on for one command. dnf5 spells it --enable-repo and
# dnf4 spelled it --enablerepo; the same uncertainty step 68 works around for
# Terra, worked around the same way.
AQ_SRC_FLAGS=""
for flag in --enable-repo --enablerepo; do
    if aq_dnf repolist "${flag}=fedora-source" > /tmp/aq-src-probe.txt 2>&1; then
        AQ_SRC_FLAGS="${flag}=fedora-source ${flag}=updates-source"
        ok "the source repositories can be switched on for one command (${flag})"
        break
    fi
done
if [ -z "${AQ_SRC_FLAGS}" ]; then
    echo "  neither --enable-repo nor --enablerepo was understood:"
    sed 's/^/       /' /tmp/aq-src-probe.txt
    echo "  Carrying on; 'builddep' will probably fail and the written-out list will be used."
fi
rm -f /tmp/aq-src-probe.txt

# ------------------------------------------------------------------------------
# ⚠️ TWO RECIPES ARE ASKED FOR, NOT ONE, AND THAT IS THE 2026-09-18 LESSON
# ------------------------------------------------------------------------------
# Build 35301818660 got all the way through `builddep gamescope` and then died
# configuring, on this line:
#
#     wlroots| Run-time dependency xwayland found: NO
#     ERROR: Subproject xserver is buildable: NO
#
# WHY, IN PLAIN ENGLISH. gamescope is built on top of wlroots, a library for
# building compositors. Fedora's gamescope package links against the wlroots
# that Fedora packages separately, so Fedora's gamescope recipe does not list
# wlroots' own build requirements — it does not need them.
#
# OURS DOES. This commit of gamescope wants wlroots 0.19 and Fedora ships 0.20,
# so the version does not match and meson quietly builds the copy of wlroots
# that comes inside gamescope. That copy has to be BUILT, which means every
# development package WLROOTS needs has to be here too — and the one that bit
# us is the Xwayland development files, which nothing else on this list wants.
#
# So both recipes are asked for. `builddep wlroots` covers wlroots' whole list
# (libseat, libinput, the xcb pieces, hwdata, lcms2, libdisplay-info, Xwayland
# and the rest) and keeps covering it if wlroots adds to it, which is the whole
# reason for asking Fedora rather than writing a list here.
say "Asking Fedora what gamescope needs to be built"
AQ_BUILDDEP_WORKED=0
# shellcheck disable=SC2086
if aq_dnf builddep ${AQ_SRC_FLAGS} gamescope; then
    AQ_BUILDDEP_WORKED=1
    ok "Fedora's own build requirements for gamescope are installed"
else
    echo
    echo "  ⚠️  'dnf builddep gamescope' did not work. That is not fatal."
    echo "      Falling back to the list written into this script, which was read"
    echo "      out of Fedora's gamescope recipe on 2026-09-17."
    echo
fi

# The second recipe: what wlroots itself needs, because we build it.
say "And asking Fedora what wlroots needs to be built, because we build that too"
# shellcheck disable=SC2086
if aq_dnf builddep ${AQ_SRC_FLAGS} wlroots; then
    ok "Fedora's own build requirements for wlroots are installed"
else
    echo "  ⚠️  'dnf builddep wlroots' did not work. Not fatal — the written-out"
    echo "      list below names the pieces the wlroots inside gamescope actually"
    echo "      asks for, which were read out of its own meson.build files."
    AQ_BUILDDEP_WORKED=0
fi

# ------------------------------------------------------------------------------
# THE WLROOTS SUB-PROJECT'S OWN LIST, ALWAYS INSTALLED
# ------------------------------------------------------------------------------
# ⚠️ THIS IS NOT A FALLBACK. It runs whether or not `builddep` worked, because
# `builddep wlroots` describes FEDORA'S wlroots (0.20) and we are building a
# different one (0.19, the copy inside gamescope at the pinned commit). Every
# name below was read out of that exact copy's meson.build files on 2026-09-18,
# at submodule commit 88a869855742281c98c22cab9641b317b8d065ef, and each one was
# checked against Fedora 44 to be sure a real package provides it.
#
# gamescope builds that wlroots with these options (src/meson.build at the
# pinned commit):
#     xwayland=enabled  backends=libinput  session=enabled
#     renderers=[]  allocators=[]  examples=false  default_library=static
#
# which is why this list has the Xwayland and xcb pieces and does NOT have the
# OpenGL, EGL or GBM ones — with no renderers and no allocators, wlroots never
# asks for those.
#
#   pkgconfig(xwayland)      xwayland/meson.build:23 — THE ONE THAT FAILED.
#                            Without it wlroots tries to build a whole X server
#                            from a sub-project that is not there, and the error
#                            message ("Subproject xserver is buildable: NO")
#                            says nothing about Xwayland at all.
#   the xcb pieces           xwayland/meson.build:2-13, the required list.
#                            xcb-errors is the optional one and is included so
#                            that X11 errors are readable in the journal.
#   pkgconfig(libseat)       backend/session/meson.build:3  (session=enabled)
#   pkgconfig(libinput)      backend/libinput/meson.build:6 (backends=libinput)
#   pkgconfig(hwdata)        backend/drm/meson.build:1
#   pkgconfig(libdisplay-info) backend/drm/meson.build:8
#   pkgconfig(lcms2)         render/meson.build:61 (colour management — the
#                            thing a video editor's desktop is actually for)
#   pkgconfig(libudev)       backend/session/meson.build:2
#   pkgconfig(pixman-1),
#   pkgconfig(xkbcommon),
#   pkgconfig(libdrm),
#   the wayland pieces       meson.build:96-120 and protocol/meson.build
say "The pieces the wlroots inside gamescope needs, which Fedora's gamescope does not"
aq_dnf install \
    "pkgconfig(xwayland)" \
    "pkgconfig(xcb)" \
    "pkgconfig(xcb-composite)" \
    "pkgconfig(xcb-ewmh)" \
    "pkgconfig(xcb-icccm)" \
    "pkgconfig(xcb-render)" \
    "pkgconfig(xcb-res)" \
    "pkgconfig(xcb-xfixes)" \
    "pkgconfig(xcb-errors)" \
    "pkgconfig(libseat)" \
    "pkgconfig(libinput)" \
    "pkgconfig(libudev)" \
    "pkgconfig(hwdata)" \
    "pkgconfig(libdisplay-info)" \
    "pkgconfig(lcms2)" \
    "pkgconfig(pixman-1)" \
    "pkgconfig(xkbcommon)" \
    "pkgconfig(libdrm)" \
    "pkgconfig(wayland-server)" \
    "pkgconfig(wayland-client)" \
    "pkgconfig(wayland-protocols)" \
    "pkgconfig(wayland-scanner)"


# ------------------------------------------------------------------------------
# gamescope's own extras that its Fedora recipe gets a different way
# ------------------------------------------------------------------------------
# Read out of gamescope's meson.build and src/meson.build at the pinned commit.
# Most of these `builddep gamescope` already brought; naming them is cheap and
# means a change in Fedora's packaging cannot quietly take one away.
#   gbm             src/meson.build:15 — the memory allocator this whole NVIDIA
#                   fix is ABOUT, so it had better be here.
#   libdecor-0      src/meson.build:43
#   libcap          src/meson.build:22 (the real-time scheduling capability)
#   luajit          src/meson.build:129
#   libeis-1.0      src/meson.build:16
#   libavif         src/meson.build:25
#   pipewire, vulkan, x11, hwdata   meson.build:45-51
say "gamescope's own libraries"
aq_dnf install \
    "pkgconfig(gbm)" \
    "pkgconfig(libdecor-0)" \
    "pkgconfig(libcap)" \
    "pkgconfig(luajit)" \
    "pkgconfig(libeis-1.0)" \
    "pkgconfig(libavif)" \
    "pkgconfig(libpipewire-0.3)" \
    "pkgconfig(vulkan)" \
    "pkgconfig(x11)" \
    "pkgconfig(sdl2)" \
    libXcursor-devel libXmu-devel libXi-devel \
    "pkgconfig(xcomposite)" \
    "pkgconfig(xdamage)" \
    "pkgconfig(xext)" \
    "pkgconfig(xfixes)" \
    "pkgconfig(xrender)" \
    "pkgconfig(xres)" \
    "pkgconfig(xtst)" \
    "pkgconfig(xxf86vm)" \
    glm-devel spirv-headers-devel

if [ "${AQ_BUILDDEP_WORKED}" -eq 0 ]; then
    say "Installing the written-out list of build requirements instead"
    # Straight from Fedora's gamescope.spec, minus the three things this build
    # deliberately switches off further down (OpenVR, the unit tests and the
    # benchmark tools), because asking for a package we are not going to use is
    # one more thing that can fail for nothing.
    aq_dnf install \
        glm-devel \
        libXcursor-devel \
        libXmu-devel \
        libXi-devel \
        spirv-headers-devel \
        stb_image-devel stb_image-static \
        stb_image_resize-devel stb_image_resize-static \
        stb_image_write-devel stb_image_write-static \
        "pkgconfig(hwdata)" \
        "pkgconfig(libavif)" \
        "pkgconfig(libcap)" \
        "pkgconfig(libdecor-0)" \
        "pkgconfig(libdisplay-info)" \
        "pkgconfig(libdrm)" \
        "pkgconfig(libeis-1.0)" \
        "pkgconfig(libinput)" \
        "pkgconfig(libpipewire-0.3)" \
        "pkgconfig(libudev)" \
        "pkgconfig(luajit)" \
        "pkgconfig(pixman-1)" \
        "pkgconfig(sdl2)" \
        "pkgconfig(vulkan)" \
        "pkgconfig(wayland-client)" \
        "pkgconfig(wayland-protocols)" \
        "pkgconfig(wayland-scanner)" \
        "pkgconfig(wayland-server)" \
        "pkgconfig(x11)" \
        "pkgconfig(xcomposite)" \
        "pkgconfig(xdamage)" \
        "pkgconfig(xext)" \
        "pkgconfig(xfixes)" \
        "pkgconfig(xkbcommon)" \
        "pkgconfig(xrender)" \
        "pkgconfig(xres)" \
        "pkgconfig(xtst)" \
        "pkgconfig(xxf86vm)"
    ok "the written-out build requirements are installed"
fi

# ⚠️ NOT ASKED FOR ON PURPOSE: pkgconfig(wlroots-0.20) and
# pkgconfig(libliftoff). Fedora builds gamescope against the system copies of
# those. THIS gamescope wants wlroots 0.19 (see src/meson.build at the pinned
# commit) and insists on building libliftoff and vkroots itself — its own
# meson.build refuses to configure if you take them out of that list. So both
# come from the sub-projects fetched in section 2, and a system wlroots of the
# wrong version is simply ignored. If `builddep` installed one anyway, no harm
# is done.

say "Proving every library is really here, the same way meson will ask"

# And prove the one that failed is really here now, by name, before we spend
# twenty minutes finding out the hard way again.
#
# ⚠️ ASKED THE WAY MESON ASKS IT. meson does not look in the package database;
# it runs pkg-config. So this runs pkg-config too — the same question, of the
# same program, so the answer here cannot disagree with the answer twenty
# minutes into the build.
if pkg-config --exists xwayland 2> /dev/null; then
    ok "pkg-config can see Xwayland ($(pkg-config --modversion xwayland 2> /dev/null))"
else
    echo "  the pkg-config files that ARE here, in case the name has changed:"
    ls -1 /usr/share/pkgconfig /usr/lib64/pkgconfig 2> /dev/null | grep -i 'wayland\|xorg' | sed 's/^/       /' || true
    bad "pkg-config cannot see 'xwayland' — the wlroots inside gamescope will try to build a whole X server and stop with 'Subproject xserver is buildable: NO', which is what failed build 35301818660"
fi

# The rest of the wlroots list, asked the same way, so that a missing one is a
# named sentence here rather than a meson error later.
for aq_pc in xcb xcb-composite xcb-ewmh xcb-icccm xcb-render xcb-res xcb-xfixes \
    libseat libinput libudev hwdata libdisplay-info lcms2 pixman-1 xkbcommon libdrm \
    wayland-server wayland-client wayland-protocols; do
    if pkg-config --exists "${aq_pc}" 2> /dev/null; then
        ok "pkg-config can see ${aq_pc}"
    else
        bad "pkg-config cannot see '${aq_pc}', which the wlroots inside gamescope asks for"
    fi
done

if [ "${AQ_FAILS}" -ne 0 ]; then
    echo
    echo "AQUARIUS ERROR: the libraries gamescope's own copy of wlroots needs are" >&2
    echo "                not all here, so meson would stop a long way into the" >&2
    echo "                build with a message about a sub-project rather than" >&2
    echo "                about a missing package. Stopping now instead." >&2
    aq_finish "our own gamescope"
fi

# ==============================================================================
# 2. Fetch exactly that commit, and its sub-projects
# ==============================================================================
# gamescope carries several other projects inside it (wlroots, libliftoff,
# vkroots and more) as git "submodules". A plain download of the source gets the
# folders but not their contents, and the build then fails a long way in with a
# message about a missing subproject. --recurse-submodules is what avoids that.
say "Fetching the source"
git clone --recurse-submodules --shallow-submodules \
    --branch "${AQ_GS_BRANCH}" "${AQ_GS_REPO}" /src

cd /src
git checkout --recurse-submodules "${AQ_GS_COMMIT}"

# Trust content, never timestamps: ask git what it actually has, and compare.
AQ_GOT="$(git rev-parse HEAD)"
echo "  checked out: ${AQ_GOT}"
if [ "${AQ_GOT}" != "${AQ_GS_COMMIT}" ]; then
    bad "git is on ${AQ_GOT}, not the pinned ${AQ_GS_COMMIT}"
    aq_finish "our own gamescope"
fi
ok "the source is the exact commit this image pins"

# ------------------------------------------------------------------------------
# AND THE FIX IS REALLY IN IT
# ------------------------------------------------------------------------------
# ⚠️ THIS IS THE CHECK THAT MATTERS MOST IN THIS FILE, AND IT EXISTS BECAUSE OF
# A REAL NEAR-MISS: the pull request that put this fix on the branch was closed,
# and a LATER version of the same author's work REMOVED the setting and made the
# behaviour unconditional. Pin the wrong commit and you get a gamescope that
# builds perfectly, installs perfectly, passes every other check — and quietly
# ignores the setting the session switches on, so the screen is still corrupted.
#
# So the source is read for the setting's own name before a single line is
# compiled.
if grep -rq 'drm_gbm_scanout' src/Backends/DRMBackend.cpp; then
    ok "the source really contains the 'drm_gbm_scanout' setting (the NVIDIA fix)"
else
    bad "this commit has no 'drm_gbm_scanout' setting in src/Backends/DRMBackend.cpp — it is the wrong commit, or the fix has been rewritten. Read docs/restart/game-mode.md before changing the pin."
    aq_finish "our own gamescope"
fi

# ==============================================================================
# 3. Build it
# ==============================================================================
# The options switched OFF are things this machine has no use for and which each
# drag in more to compile:
#   enable_openvr_support  VR headsets. Not a thing AquariusOS supports.
#   enable_tests           gamescope's own unit tests — useful to its authors,
#                          not something to ship.
#   benchmark              its benchmarking tools, same reasoning.
#
# Everything else is left exactly as upstream has it, including the two
# sub-projects upstream insists on building itself (libliftoff and vkroots) —
# their meson.build refuses to configure if you take them out of that list, and
# it is right to.
# ⚠️ AND THE THREE OPTIONS REALLY EXIST AT THIS COMMIT. meson stops on an
# option it has never heard of, which is the right behaviour — but the message
# is buried in a configure log and the obvious reading of it ("our build is
# broken") is wrong. The honest cause would be a pin bump to a version that
# renamed or dropped one. So they are read out of the source's own option list
# first, by name, and named in the failure.
say "The build options we pass still exist at this commit"
for aq_opt in enable_openvr_support enable_tests benchmark; do
    if grep -q "option('${aq_opt}'" meson_options.txt; then
        ok "meson_options.txt has '${aq_opt}'"
    else
        bad "this commit of gamescope has no build option called '${aq_opt}' — it has been renamed or removed since the pin was set. Read meson_options.txt and update the 'meson setup' line below."
    fi
done
if [ "${AQ_FAILS}" -ne 0 ]; then
    aq_finish "our own gamescope"
fi

say "Compiling"
meson setup build \
    --prefix=/usr \
    --buildtype=release \
    -Denable_openvr_support=false \
    -Denable_tests=false \
    -Dbenchmark=disabled

ninja -C build

# ==============================================================================
# 4. Leave it where the real image can pick it up
# ==============================================================================
say "Staging the finished program"
mkdir -p "${AQ_OUT}"
DESTDIR="${AQ_OUT}" ninja -C build install

# What did we actually produce? Print it, because a build that installs nothing
# is a build that looks successful.
echo "  everything staged in ${AQ_OUT}:"
# (Written to a file first, then shown: under `set -o pipefail`, a `| head`
# that stops reading early makes `find` die of SIGPIPE and the whole step
# fail with exit code 141 — which is exactly how build 35303696765 ended,
# AFTER the compile had succeeded.)
find "${AQ_OUT}" -type f | sed "s|^${AQ_OUT}|       |" > /tmp/aq-gamescope-files.txt
head -40 /tmp/aq-gamescope-files.txt
echo "       ($(wc -l < /tmp/aq-gamescope-files.txt) files in all)"

if [ -x "${AQ_OUT}/usr/bin/gamescope" ]; then
    ok "${AQ_OUT}/usr/bin/gamescope exists and can be run"
else
    bad "no gamescope program was produced — the build said it succeeded and there is nothing there"
fi

# The version string, written down beside the program, so that the finished
# image can say exactly what it is carrying without anybody guessing.
mkdir -p "${AQ_OUT}/aquarius"
{
    echo "source=${AQ_GS_REPO}"
    echo "branch=${AQ_GS_BRANCH}"
    echo "commit=${AQ_GS_COMMIT}"
    echo "built-for=NVIDIA scan-out corruption (NVIDIA bug 5240452)"
    echo "switch=gamescope_drm_gbm_scanout=1"
    echo "retire-when=the fix reaches upstream gamescope and Fedora ships it"
} > "${AQ_OUT}/aquarius/gamescope-build.txt"
cat "${AQ_OUT}/aquarius/gamescope-build.txt" | sed 's/^/       /'

aq_finish "our own gamescope (builder stage)"
