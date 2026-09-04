#!/usr/bin/bash
# ==============================================================================
# 62 — DaVinci Resolve: everything except Resolve
# ==============================================================================
# PLAIN ENGLISH
#
# DaVinci Resolve is the professional video editor AquariusOS is built around,
# and it is the flagship reason this operating system exists rather than being
# "Fedora with a nice theme". This step puts in place everything needed to run
# it — and deliberately does NOT put in Resolve itself.
#
# WHY RESOLVE IS NOT IN THE IMAGE
# Blackmagic's licence does not allow anybody else to distribute their
# installer. Not us, not Fedora, not anyone. So the user downloads it from
# Blackmagic and AquariusOS installs it into a container on their own machine.
# Nothing licensed is ever published by us, and that is not negotiable.
#
# WHY RESOLVE RUNS IN A CONTAINER AND NOT ON THE DESKTOP
# Resolve carries its own copy of a library called GLib from 2021. On a modern
# Linux, the system's text-drawing library is built against a much newer GLib,
# asks Resolve's old copy for something that does not exist in it, and Resolve
# dies before its window appears. It is the most common "Resolve does not work
# on Linux" story and it recurs every time a distribution moves GLib forward.
#
# Enterprise Linux 9 — Rocky — is still on the same GLib series Resolve bundles.
# In there the clash is not worked around; it cannot happen. That container is
# built by resolve-runtime/Containerfile in this repository and downloaded onto
# a machine the first time somebody sets Resolve up.
#
# WHAT THIS STEP ACTUALLY DOES
#   1. Checks the container machinery (podman, distrobox) is here — step 30 put
#      it there; this is the step that would notice if it ever stopped.
#   2. On the NVIDIA image, checks the graphics-card-into-container plumbing.
#   3. Switches on the safety-net service that describes the graphics card to
#      containers, for the driver builds that do not ship NVIDIA's own.
#   4. Checks every file this feature is made of arrived, and that each script
#      is valid shell.
#
# The files themselves came in at step 50 with the rest of system_files/. This
# step owns none of them; it owns the QUESTION "did they all get here, and are
# they right?".
#
# The beginner-facing guide is docs/restart/resolve.md.
# ==============================================================================

set -euo pipefail
# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

NVIDIA="${NVIDIA:-0}"

say "DaVinci Resolve — the container machinery"

# ------------------------------------------------------------------------------
# 1. The container machinery
# ------------------------------------------------------------------------------
# distrobox is what runs the Rocky Linux; podman is the engine underneath it.
# Both were installed by step 30 — this is a read-back, not an install, so that
# a change to step 30 that dropped one of them fails HERE, in a step whose name
# says why they matter.
aq_installed podman distrobox

for cmd in podman distrobox distrobox-create distrobox-enter; do
    if aq_have "${cmd}"; then
        ok "${cmd} is on the path"
    else
        bad "${cmd} is missing — the Resolve container could not be built on a real machine"
    fi
done

# ------------------------------------------------------------------------------
# 2. Getting the graphics card into the container (NVIDIA image only)
# ------------------------------------------------------------------------------
# THE DECISION, WRITTEN DOWN HERE BECAUSE THIS IS WHERE SOMEBODY WILL LOOK:
#
# There are two ways to let a container use the graphics card, and AquariusOS
# prefers the first:
#
#   (a) CDI, the Container Device Interface. NVIDIA's own supported mechanism. A
#       file on the machine describes the card and its driver libraries and
#       podman reads it. `nvidia-container-toolkit` provides the tool that
#       writes it, and — in current driver builds — a service called
#       `nvidia-cdi-refresh` that writes it at every boot and after every driver
#       change. Step 60 installs the toolkit and switches that service on.
#
#   (b) `distrobox create --nvidia`, which copies the host's driver files into
#       the container itself. No toolkit needed. It is distrobox's own best
#       guess rather than NVIDIA's description of the hardware, and distrobox's
#       documentation is explicit that it needs a recent glibc distribution in
#       the container to work.
#
# WHY (a) IS THE RIGHT ANSWER ON THIS OPERATING SYSTEM SPECIFICALLY:
# AquariusOS updates by replacing the whole system, driver included. The
# description names driver library files by their exact version, so anything
# generated when the IMAGE was built would name a driver that no longer existed
# after the first update — the machine would work, then silently stop seeing the
# graphics card. Generated at boot by the driver that is actually installed, it
# cannot go stale. (And there is no graphics card in the machine that builds the
# image, so there would be nothing true to generate anyway.)
#
# The installer on the machine picks (a) when the file exists and falls back to
# (b) when it does not, so a driver build without the refresh service still
# works. Neither is a guess made at build time.
if [ "${NVIDIA}" = "1" ]; then
    say "DaVinci Resolve — the NVIDIA graphics-card passthrough"

    aq_installed nvidia-container-toolkit

    if aq_have nvidia-ctk; then
        ok "nvidia-ctk is on the path (the tool that describes the card to containers)"
    else
        bad "nvidia-ctk is missing — nothing could describe the graphics card to a container"
    fi

    # Whether NVIDIA's own refresh service is in this driver build. Both answers
    # are fine; what matters is that exactly one thing writes the file, which is
    # what the safety-net unit's Condition lines guarantee.
    if [ -f /usr/lib/systemd/system/nvidia-cdi-refresh.service ]; then
        ok "NVIDIA's own nvidia-cdi-refresh service is in this driver build (step 60 enables it)"
        echo "       The AquariusOS safety-net unit will therefore stay dormant, by design."
    else
        echo "  NOTE this driver build has no nvidia-cdi-refresh service."
        echo "       The AquariusOS safety-net unit below is what will write the file."
    fi

    say "The safety-net service"
    AQ_CDI_UNIT=/usr/lib/systemd/system/aquarius-resolve-cdi.service
    if [ ! -f "${AQ_CDI_UNIT}" ]; then
        bad "${AQ_CDI_UNIT} is missing — it should have arrived with system_files at step 50"
    else
        # The two Conditions are the whole safety of this unit: without the
        # second one it would fight NVIDIA's own service for the same file.
        aq_file_has "${AQ_CDI_UNIT}" \
            '^ConditionPathExists=!/usr/lib/systemd/system/nvidia-cdi-refresh\.service$' \
            "it stands down when NVIDIA's own service is present"
        aq_file_has "${AQ_CDI_UNIT}" \
            '^ConditionPathExists=/proc/driver/nvidia/version$' \
            "it only runs on a machine with the NVIDIA driver loaded"
        aq_file_has "${AQ_CDI_UNIT}" \
            'nvidia-ctk cdi generate' \
            "it runs NVIDIA's own tool"

        if systemctl enable aquarius-resolve-cdi.service; then
            ok "the safety-net service is switched on"
        else
            bad "could not switch on aquarius-resolve-cdi.service"
        fi
    fi
else
    say "DaVinci Resolve — graphics card"
    echo "  NOTE this is the AMD/Intel image, so there is no NVIDIA passthrough to set up."
    echo "       Resolve on AMD needs ROCm's OpenCL, which is not in the runtime"
    echo "       container yet — the installer says so plainly rather than letting"
    echo "       somebody find out from Resolve. See docs/restart/resolve.md."

    # The safety-net unit ships in both images because system_files is one tree,
    # but it must never run on a machine with no NVIDIA driver. Its own
    # Condition covers that; leaving it switched off here is the second lock.
    if systemctl is-enabled aquarius-resolve-cdi.service > /dev/null 2>&1; then
        bad "the NVIDIA safety-net service is switched on in the AMD/Intel image"
    else
        ok "the NVIDIA safety-net service is correctly left switched off"
    fi
fi

# ------------------------------------------------------------------------------
# 3. Every file the feature is made of
# ------------------------------------------------------------------------------
say "DaVinci Resolve — the files"

for f in /usr/libexec/aquarius-resolve-install \
    /usr/libexec/aquarius-resolve-install-gui \
    /usr/libexec/aquarius-resolve-launch; do
    if [ ! -f "${f}" ]; then
        bad "${f} is missing"
        continue
    fi
    # An executable bit that did not survive the copy is a silent failure: the
    # icon is there, the click does nothing.
    chmod 0755 "${f}"
    if [ -x "${f}" ]; then
        ok "$(basename "${f}") is present and runnable"
    else
        bad "${f} is not runnable"
    fi
    # Valid shell. `bash -n` reads the file and checks it parses without running
    # a single line of it — the cheapest possible way to catch a typo that would
    # otherwise be discovered by a person clicking an icon.
    if bash -n "${f}"; then
        ok "$(basename "${f}") is valid shell"
    else
        bad "${f} has a syntax error"
    fi
done

# The one place the runtime container image is named.
AQ_RUNTIME_ENV=/usr/share/aquarius/resolve/runtime.env
if [ ! -r "${AQ_RUNTIME_ENV}" ]; then
    bad "${AQ_RUNTIME_ENV} is missing — nothing would know which container to download"
else
    aq_file_has "${AQ_RUNTIME_ENV}" \
        '^AQ_RESOLVE_RUNTIME_IMAGE=ghcr\.io/[a-z0-9-]+/aquarius-resolve-runtime$' \
        "the runtime container image is named"
    aq_file_has "${AQ_RUNTIME_ENV}" \
        '^AQ_RESOLVE_RUNTIME_TAG=[0-9]+$' \
        "it is pinned to an Enterprise Linux release, not a moving 'latest' tag"
    aq_file_has "${AQ_RUNTIME_ENV}" \
        '^AQ_RESOLVE_CONTAINER=[a-z0-9-]+$' \
        "the container has a fixed name"
    echo "  The runtime this image will pull:"
    grep -E '^AQ_RESOLVE' "${AQ_RUNTIME_ENV}" | sed 's/^/       /'
fi

# The app-grid entry — the zero-terminal way in.
AQ_DESKTOP=/usr/share/applications/aquarius-install-resolve.desktop
if [ ! -r "${AQ_DESKTOP}" ]; then
    bad "${AQ_DESKTOP} is missing — there would be no way to start this without a terminal"
else
    aq_file_has "${AQ_DESKTOP}" '^Exec=/usr/libexec/aquarius-resolve-install-gui$' \
        "the app-grid entry points at the graphical setup"
    aq_file_has "${AQ_DESKTOP}" '^Terminal=false$' \
        "it opens its own window rather than expecting a terminal"
    # desktop-file-validate is the freedesktop project's own checker. A .desktop
    # file with a bad line is silently ignored by the app grid — the entry
    # simply never appears — so this is worth a package.
    if ! aq_have desktop-file-validate; then
        aq_dnf install desktop-file-utils
    fi
    if desktop-file-validate "${AQ_DESKTOP}"; then
        ok "the app-grid entry passes freedesktop's own validator"
    else
        bad "${AQ_DESKTOP} is not a valid desktop entry — it would never appear in the app grid"
    fi
fi

# The USB rules for licence dongles and control panels. These have to be on the
# host: Resolve's own installer writes them inside the container, where they
# apply to nothing, and AquariusOS's system folder is read-only so nothing can
# add them afterwards. Shipping them in the image is the only way.
AQ_UDEV=/usr/lib/udev/rules.d/75-aquarius-resolve.rules
if [ ! -r "${AQ_UDEV}" ]; then
    bad "${AQ_UDEV} is missing — a Resolve Studio licence dongle would not be seen"
else
    aq_file_has "${AQ_UDEV}" 'idVendor}=="1edb"' \
        "Blackmagic Design hardware (control panels) has a rule"
    aq_file_has "${AQ_UDEV}" 'idVendor}=="096e"' \
        "the Resolve Studio USB licence dongle has a rule"
    echo "  The rules, in full:"
    grep -v '^#' "${AQ_UDEV}" | grep -v '^$' | sed 's/^/       /'
fi

# ------------------------------------------------------------------------------
# 4. The `aq resolve` command
# ------------------------------------------------------------------------------
say "DaVinci Resolve — the aq resolve command"

if [ ! -x /usr/bin/aq ]; then
    bad "/usr/bin/aq is missing"
else
    aq_file_has /usr/bin/aq '^    resolve\)' "aq knows the 'resolve' subcommand"
    # Run it for real. A help screen that crashes is a help screen nobody can
    # read at the moment they most need it.
    if /usr/bin/aq resolve --help > /tmp/aq-resolve-help.txt 2>&1; then
        ok "'aq resolve --help' runs"
        # ⚠️ `head` FIRST, THEN `sed`. The other way round — `sed file | head` —
        # is the broken-pipe trap written up at the top of aq-lib.sh: `head`
        # stops after 20 lines, whatever is upstream is killed writing to a pipe
        # nobody is reading, and `set -o pipefail` reports the whole pipeline as
        # failed.
        #
        # Being precise, because a half-understood rule is worse than none: with
        # 46 lines of help text this particular pipeline would probably NOT have
        # failed, because all of it fits in the pipe's buffer and `sed` finishes
        # before `head` closes anything. It is a latent bug, not a certain one —
        # it would start failing the day somebody added enough help text to
        # exceed 64 KB, and would then look like a change to a different file
        # breaking this one. Writing it the safe way round costs nothing.
        head -20 /tmp/aq-resolve-help.txt | sed 's/^/       /'
    else
        bad "'aq resolve --help' does not run"
        cat /tmp/aq-resolve-help.txt
    fi
fi

# ------------------------------------------------------------------------------
# 5. What this step deliberately does NOT do
# ------------------------------------------------------------------------------
# It does not download the Rocky Linux runtime. That would add about a gigabyte
# to an operating system image that everyone downloads, for a feature not
# everyone uses. It arrives on first use instead, which is the whole reason it
# is a separate image with its own build.
say "Not downloaded on purpose"
echo "  The Rocky Linux runtime is NOT baked into this image."
echo "  It is about a gigabyte and it is fetched the first time somebody sets"
echo "  Resolve up. Baking it in would make every AquariusOS download bigger"
echo "  for a feature not everybody uses."

aq_finish "DaVinci Resolve"
