#!/usr/bin/bash
# ==============================================================================
# STEP 74 (builder stage only) — compiling xremap, the key remapper
# ==============================================================================
# WHAT THIS IS FOR
#
# AquariusOS ships Mac-style keyboard shortcuts turned on by default. The
# program that makes that happen is called **xremap**. It sits between the
# keyboard and everything else: it watches the keys you actually press, and
# hands the rest of the computer a different set of keys.
#
# Nobody packages xremap for Fedora — there is no `dnf install xremap` — so we
# build it ourselves, from its published source, at one exact version.
#
# ------------------------------------------------------------------------------
# THIS SCRIPT DOES NOT RUN INSIDE AQUARIUSOS
# ------------------------------------------------------------------------------
# It runs in a throwaway Fedora container (the `xremap-build` stage in the
# Containerfile) whose only job is to compile two small programs and leave them
# in /out. Only those two finished programs are copied into AquariusOS.
#
# That is deliberate. Compiling Rust needs about a gigabyte of compiler,
# and none of it belongs in an operating system that only needs to RUN the
# result. This is the same pattern the NVIDIA driver step uses.
#
# ------------------------------------------------------------------------------
# ⚠️ WHY TWO PROGRAMS AND NOT ONE
# ------------------------------------------------------------------------------
# Some of our shortcut rules only apply in certain apps — copy means something
# different in a terminal than it does in a web browser. So xremap has to be
# able to ask "which window is the person actually typing into right now?"
#
# There is no single Linux-wide way to ask that question. Every desktop answers
# it differently, so xremap is compiled with ONE answer built in, chosen with a
# "feature" flag:
#
#   wlroots   the answer labwc understands — this is the Aquarius Session
#   gnome     the answer GNOME understands (through a small GNOME add-on)
#
# We tried to have one program carry both. It cannot: xremap's own source says
# so out loud. In src/client/mod.rs, the function that picks the answer ends
#
#     panic!("There is no way to run with multiple clients enabled.")
#
# — so a binary built with both features would compile and then crash the
# instant it started. Two binaries it is. Which one runs is decided at login by
# /usr/libexec/aquarius-keys-run, from the name of the desktop you logged into.
#
# ------------------------------------------------------------------------------
# WHAT "PINNED" MEANS HERE, AND WHY IT IS DONE THIS WAY
# ------------------------------------------------------------------------------
# We do not build "the latest xremap". We build one exact release, and the
# build FAILS if it gets anything else. The pin is a git commit id, which is
# the strongest form available: a commit id is a checksum of the entire source
# tree, so it cannot be moved, re-pointed or quietly rewritten the way a tag or
# a downloaded file can.
#
# (A downloaded .tar.gz would be the obvious alternative, and GitHub's
# auto-generated source tarballs are NOT byte-stable over time — the same tag
# has produced different archives after upstream tooling changes. Its checksum
# is recorded below for the record, but the commit id is what is enforced.)
#
# To move to a newer xremap: change XREMAP_VERSION and XREMAP_COMMIT in the
# Containerfile, in one deliberate, tested step.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

# ------------------------------------------------------------------------------
# The pin
# ------------------------------------------------------------------------------
# Passed in from the Containerfile so that the version lives in one place, next
# to every other version this project pins. Defaults repeat them so that
# running this script by hand still works.
#
# Verified 2026-09-03 against https://github.com/xremap/xremap/releases —
# v0.15.12, published 2026-08-27, the newest release at the time of writing.
#
#   tag             v0.15.12
#   commit          7e6649e442ca445b781e4cf0e90c165f86e717db
#   source tarball  https://github.com/xremap/xremap/archive/refs/tags/v0.15.12.tar.gz
#   its sha256      8f18561ae65c71deec07e8faa9eeb5c376c9624c050613e701612edc4670987c
#                   (recorded for the record; the commit id above is what is
#                    actually enforced, for the reason in the header)
#   licence         MIT
XREMAP_VERSION="${XREMAP_VERSION:-0.15.12}"
XREMAP_COMMIT="${XREMAP_COMMIT:-7e6649e442ca445b781e4cf0e90c165f86e717db}"

# ------------------------------------------------------------------------------
# The GNOME add-on
# ------------------------------------------------------------------------------
# On GNOME's Wayland desktop, no program is allowed to ask which window is
# focused — GNOME closed that door for security reasons, and it applies to
# everyone, not just us. xremap's answer is a tiny GNOME add-on, written by
# xremap's own author, that answers the question on xremap's behalf.
#
# It is not packaged by Fedora either (checked 2026-09-03:
# packages.fedoraproject.org returns nothing for "xremap" or
# "gnome-shell-extension-xremap"), so we fetch the exact published build and
# check its checksum. This one IS a stable uploaded file, so a checksum is the
# right pin for it.
#
#   uuid            xremap@k0kubun.com
#   version         15 (supports GNOME 45 through 50)
#   from            https://extensions.gnome.org/extension/5060/xremap/
#   licence         GPL-2.0-or-later — shipped unmodified, as a separate file
XREMAP_EXT_UUID="xremap@k0kubun.com"
XREMAP_EXT_TAG="69781"
XREMAP_EXT_SHA256="9f81d40ecc23810c704f0e6e6d9cc69c25e7c5528c24576a4972056b5b7d6d5a"
XREMAP_EXT_URL="https://extensions.gnome.org/download-extension/${XREMAP_EXT_UUID}.shell-extension.zip?version_tag=${XREMAP_EXT_TAG}"

OUT="/out"

say "Building xremap ${XREMAP_VERSION} (commit ${XREMAP_COMMIT})"

# ------------------------------------------------------------------------------
# 1. The tools needed to compile it
# ------------------------------------------------------------------------------
# rust + cargo  the Rust compiler and its build tool; xremap is written in Rust
# gcc           a C compiler. One of xremap's building blocks (wayland-backend)
#               compiles a small piece of C as part of its own build.
# wayland-devel the description of how to talk to a Wayland desktop. Needed
#               only by the `wlroots` build, and needed at COMPILE time; the
#               finished program then loads the matching library at runtime,
#               which AquariusOS already has because it is a Wayland desktop.
# pkgconf       how the Rust build finds the line above
# git, unzip    fetching the source, unpacking the GNOME add-on
say "Installing the compiler and the pieces the build needs"
aq_dnf install \
    cargo \
    rust \
    gcc \
    git-core \
    pkgconf-pkg-config \
    unzip \
    wayland-devel

aq_installed cargo rust gcc git-core wayland-devel

# ------------------------------------------------------------------------------
# 2. Fetch the source, at exactly the commit we pinned
# ------------------------------------------------------------------------------
SRC="/tmp/xremap"
say "Fetching the xremap source"
git clone --quiet --depth 1 --branch "v${XREMAP_VERSION}" \
    https://github.com/xremap/xremap.git "${SRC}"

GOT_COMMIT="$(git -C "${SRC}" rev-parse HEAD)"
echo "  asked for : ${XREMAP_COMMIT}"
echo "  got       : ${GOT_COMMIT}"
if [ "${GOT_COMMIT}" != "${XREMAP_COMMIT}" ]; then
    echo "::error::The xremap tag v${XREMAP_VERSION} no longer points at the commit this repository pinned." >&2
    echo "         Expected ${XREMAP_COMMIT}" >&2
    echo "         Got      ${GOT_COMMIT}" >&2
    echo "         A tag that moves means the source changed under us. Read the" >&2
    echo "         upstream changes, then update XREMAP_COMMIT in the Containerfile" >&2
    echo "         on purpose. Do not just paste the new number in to make this pass." >&2
    exit 1
fi
ok "the source is exactly the commit we pinned"

# The licence travels with the program. MIT requires the copyright notice to be
# shipped alongside, and it is good manners regardless.
install -D -m 0644 "${SRC}/LICENSE" "${OUT}/licenses/xremap/LICENSE"

# ------------------------------------------------------------------------------
# 3. Compile it twice — once per desktop
# ------------------------------------------------------------------------------
# Both builds share one target folder on purpose: everything that is not
# desktop-specific is compiled once and reused by the second build, which is
# most of it.
install -d -m 0755 "${OUT}/bin"

for feature in wlroots gnome; do
    say "Compiling xremap with the '${feature}' feature"
    (
        cd "${SRC}"
        # --locked means "use exactly the dependency versions the project
        # recorded in Cargo.lock". Without it, cargo is free to pick newer
        # versions of xremap's building blocks than upstream ever tested, and
        # the build becomes a different program every time it runs.
        cargo build --release --locked --no-default-features --features "${feature}"
    )
    install -D -m 0755 "${SRC}/target/release/xremap" "${OUT}/bin/xremap-${feature}"
    ok "built xremap-${feature}"
done

# ------------------------------------------------------------------------------
# 4. Do the finished programs actually run?
# ------------------------------------------------------------------------------
# A compile that succeeds and a program that starts are two different claims.
say "Checking the two programs run"
for feature in wlroots gnome; do
    version_line="$("${OUT}/bin/xremap-${feature}" --version)"
    echo "  xremap-${feature}: ${version_line}"
    if [ -z "${version_line}" ]; then
        bad "xremap-${feature} printed nothing when asked its version"
    else
        ok "xremap-${feature} runs"
    fi
done

# What system libraries do they need? Recorded in the build log so that a
# missing-library failure in the finished image can be diagnosed by reading,
# not guessing. The real check happens in CI, inside the finished image.
say "What the finished programs link against"
for feature in wlroots gnome; do
    echo "--- xremap-${feature} ---"
    ldd "${OUT}/bin/xremap-${feature}" || true
done

# ------------------------------------------------------------------------------
# 5. The GNOME add-on
# ------------------------------------------------------------------------------
say "Fetching the xremap GNOME add-on"
ZIP="/tmp/xremap-extension.zip"
curl --fail --location --silent --show-error --output "${ZIP}" "${XREMAP_EXT_URL}"
echo "${XREMAP_EXT_SHA256}  ${ZIP}" | sha256sum --check --status \
    || {
        echo "::error::The xremap GNOME add-on did not match its recorded checksum." >&2
        echo "         Expected ${XREMAP_EXT_SHA256}" >&2
        echo "         Got      $(sha256sum "${ZIP}" | cut -d' ' -f1)" >&2
        echo "         Either the published file changed, or the download was" >&2
        echo "         tampered with. Do not update the number without looking." >&2
        exit 1
    }
ok "the add-on matches its recorded checksum"

EXT_OUT="${OUT}/gnome-shell/extensions/${XREMAP_EXT_UUID}"
install -d -m 0755 "${EXT_OUT}"
unzip -q -o "${ZIP}" -d "${EXT_OUT}"
chmod -R a+rX,go-w "${EXT_OUT}"

# metadata.json is the add-on's identity card. If it is missing or does not
# name the uuid we expect, GNOME would silently ignore the whole thing.
aq_file_has "${EXT_OUT}/metadata.json" "\"uuid\": \"${XREMAP_EXT_UUID}\"" \
    "the add-on declares the uuid we expect"
echo "--- metadata.json ---"
cat "${EXT_OUT}/metadata.json"

aq_finish "Building xremap"
