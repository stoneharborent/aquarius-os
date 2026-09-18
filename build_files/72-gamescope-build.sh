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
# ⚠️ THE LIST OF DEVELOPMENT PACKAGES IS NOT WRITTEN OUT BY HAND, ON PURPOSE.
# gamescope needs something like forty of them and the list changes between
# versions. Fedora already packages gamescope, which means Fedora already knows
# that list — `dnf builddep` asks it. Writing our own list would mean a build
# that breaks every time upstream adds a dependency, with an error message forty
# lines into a compiler log.
#
# The handful named explicitly afterwards are the ones OUR way of building needs
# and Fedora's does not: git (to fetch the branch and its sub-projects) and the
# shader compiler, which some Fedora releases leave out of the build-dependency
# list.
say "The tools and libraries needed to compile it"
aq_dnf install dnf5-plugins git meson ninja-build gcc-c++ glslang spirv-tools

if ! aq_dnf builddep gamescope; then
    echo "AQUARIUS ERROR: could not work out what gamescope needs to be built." >&2
    echo "                'dnf builddep gamescope' failed. Either Fedora ${FEDORA_VERSION:-}" >&2
    echo "                has stopped packaging gamescope — in which case this whole" >&2
    echo "                builder stage needs rethinking — or the source repository" >&2
    echo "                is not enabled in this container." >&2
    exit 1
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
find "${AQ_OUT}" -type f | sed "s|^${AQ_OUT}|       |" | head -40

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
