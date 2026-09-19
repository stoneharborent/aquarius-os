#!/usr/bin/bash
# ==============================================================================
# STEP 7g — the handheld layer (Phase G2): the ROG Xbox Ally X
# ==============================================================================
# WHAT THIS STEP IS FOR, IN PLAIN ENGLISH
#
# AquariusOS is built three times from this one recipe:
#
#   aquarius-os            a desktop PC with AMD or Intel graphics
#   aquarius-os-nvidia     the same, plus NVIDIA's driver
#   aquarius-os-handheld   the AMD one again — but for ONE handheld computer,
#                          the ROG Xbox Ally X that sits on Royce's desk
#
# This step is the whole of that third image. Everything else in the build runs
# exactly as it does for the other two; this file adds the handful of things a
# handheld needs and nothing else. On the two desktop images it installs
# nothing at all, and instead PROVES that none of it arrived — which is the
# only way to be sure a change here can never reach a desktop machine.
#
# ------------------------------------------------------------------------------
# WHAT A HANDHELD NEEDS THAT A PC DOES NOT — five things, and that is all
# ------------------------------------------------------------------------------
#
#   1. IT MUST TURN ON INTO GAME MODE. There is no keyboard. A handheld that
#      stops at a password box is a brick, because there is nothing to type
#      with. So this image — and only this image — ships
#      /etc/aquarius/login-mode saying `game`. The machinery is already there
#      from phase G1; this is the flag flipped. `aq game boot off` still puts
#      the login screen back.
#
#   2. THE BUILT-IN CONTROLLER MUST LOOK LIKE ONE CONTROLLER. Linux sees the
#      Ally's built-in pad as three separate devices: two raw USB gadgets (one
#      for the sticks and buttons, one for the paddles and the Armoury and
#      Library buttons) and a motion sensor on a completely different bus. Left
#      alone, Steam shows you a gamepad with no paddles and no gyro.
#      **InputPlumber** is the program that stitches them into one Xbox Elite
#      controller. It is the single most important package in this file.
#
#   3. THE SLIDERS IN STEAM MUST DO SOMETHING. Steam's Quick Access Menu has a
#      power-limit ("TDP") slider and a battery-charge limit. They talk to a
#      service called **steamos-manager**, which on this image is Terra's
#      powerstation build, switched ON — on the desktop images it is installed
#      and left asleep, because a desktop PC has nothing for it to manage.
#
#   4. THE POWER BUTTON MUST BEHAVE LIKE A CONSOLE'S. A short press should put
#      the machine to sleep through Steam; a long press should open the power
#      menu. That is **steamos-powerbuttond**.
#
#   5. TWO SMALL RULES ABOUT SLEEP. One stops a nudged thumbstick waking the
#      machine in your bag; the other lets the controller's own little chip
#      sleep properly so the pad is alive again after a resume.
#
# ------------------------------------------------------------------------------
# ⚠️ WHAT IS DELIBERATELY NOT HERE
# ------------------------------------------------------------------------------
#   * NO KERNEL CHANGE OF ANY KIND. Fedora's own kernel already drives this
#     machine's controller, gyro, speakers, power limits and radios. The things
#     it cannot do yet — rumble strength, stick dead zones, button remapping,
#     and the tidiest controller re-initialisation after a sleep — live in a
#     patch series that is still being reviewed upstream (`hid-asus` v6). If
#     the bench says we need them, that is a separate decision with its own
#     spec. Nothing in this file touches a kernel.
#   * NO SECOND DEVICE. This targets the ROG Xbox Ally X (board `RC73XA`) and
#     only that, because that is the only one on the bench. Widening the list
#     without hardware in front of us is how a "supported device" becomes a
#     bug report.
#   * No OpenGamepadUI, and no fan curves.
#
# ------------------------------------------------------------------------------
# WHY THE HANDHELD-ONLY FILES LIVE IN handheld_files/ AND NOT system_files/
# ------------------------------------------------------------------------------
# Everything under `system_files/` is copied onto EVERY image, wholesale, by
# step 50 (`cp -avf /ctx/system_files/. /`). There is no list and no filter —
# that is what makes it easy to use and it is the right design for files that
# belong everywhere.
#
# The files in this phase do not belong everywhere. A udev rule about an ASUS
# handheld has no business on a desktop PC's image, and `login-mode` saying
# `game` on a desktop image would stop every machine following these images
# from ever showing a login screen again. So they live in their own folder,
# `handheld_files/`, laid out exactly as they sit on the finished machine, and
# this step is the only thing that ever copies them.
#
# ------------------------------------------------------------------------------
# THE RULE THIS STEP LIVES BY
# ------------------------------------------------------------------------------
# Trust content, never timestamps. Every single thing below is read back out of
# the finished image after it is done — the package is asked what version it
# is, the rule file is compared byte for byte against the one in this
# repository, the firmware file is looked for on the disk, the "switched on"
# link is followed to see whether it points at anything.
#
# Plain-language guide: docs/restart/handheld.md
# Spec: ../docs/game-mode-g2-spec.md   Decision: ../docs/decision-2026-09-17-game-mode-and-handheld.md
# ==============================================================================

set -euo pipefail

# shellcheck source=build_files/aq-lib.sh
source /ctx/build_files/aq-lib.sh

FEDORA="$(rpm -E %fedora)"
HANDHELD="${HANDHELD:-0}"

AQ_NOTE_DIR="/usr/share/aquarius/gaming"
AQ_HANDHELD_NOTE="${AQ_NOTE_DIR}/handheld.txt"
AQ_SRC="/ctx/handheld_files"

# The two udev rules, by name, so the copy and the read-back cannot drift.
AQ_UDEV_RULES=(
    usr/lib/udev/rules.d/50-ally-x-controller.rules
    usr/lib/udev/rules.d/70-aquarius-ally-mcu-powersave.rules
)

# ==============================================================================
# 0. The two desktop images: install nothing, and prove nothing arrived
# ==============================================================================
# ⚠️ THIS HALF IS NOT A FORMALITY. It is the promise that phase G2 cannot change
# the computer Royce edits on. If a future edit ever drops a handheld package or
# a handheld file into the shared part of the build, this is what notices — on
# the very next build, by name, before anybody installs anything.
if [ "${HANDHELD}" != "1" ]; then
    say "This is not the handheld image — checking that none of phase G2 landed here"

    echo "  The handheld image is a third build of this same recipe, for the one"
    echo "  ROG Xbox Ally X on the bench. Everything below belongs only there."
    echo

    for aq_pkg in inputplumber powerstation powerbuttond steamos-manager-powerstation opengamepadui; do
        if rpm -q "${aq_pkg}" > /dev/null 2>&1; then
            bad "${aq_pkg} is installed on a DESKTOP image — that is handheld-only software (phase G2). Something in the shared part of the build started installing it."
        else
            ok "${aq_pkg} is not on this image, as intended"
        fi
    done

    # The G1 promise, asked again from this side: a desktop machine starts at
    # its login screen. Step 71 checks this too; a second voice costs nothing
    # and this is the check whose failure would be the most expensive.
    aq_file_has /etc/aquarius/login-mode '^mode=desktop$' \
        "/etc/aquarius/login-mode still ships as 'desktop' — switching this computer on shows the login screen"

    for aq_f in "${AQ_UDEV_RULES[@]}"; do
        if [ -e "/${aq_f}" ]; then
            bad "/${aq_f} is on a desktop image — it is a rule about an ASUS handheld and has no business here"
        else
            ok "/${aq_f} is not on this image, as intended"
        fi
    done

    for aq_f in /usr/libexec/aquarius-handheld-status "${AQ_HANDHELD_NOTE}"; do
        if [ -e "${aq_f}" ]; then
            bad "${aq_f} is on a desktop image — it is part of the handheld layer"
        else
            ok "${aq_f} is not on this image, as intended"
        fi
    done

    # `aq handheld` itself IS on every image, because `aq` is one program and
    # one program is easier to keep honest than three. It must refuse politely
    # here rather than fail in a way that looks like a broken command.
    say "'aq handheld status' says so politely on a machine that is not one"
    if /usr/bin/aq handheld status > /tmp/aq-hh.txt 2>&1; then
        sed 's/^/       /' /tmp/aq-hh.txt
        bad "'aq handheld status' succeeded on a desktop image — it should say the handheld layer is not in this image"
    else
        sed 's/^/       /' /tmp/aq-hh.txt
        ok "'aq handheld status' explains itself and stops, which is the right answer here"
    fi
    rm -f /tmp/aq-hh.txt

    aq_finish "Handheld layer (phase G2) — correctly absent"
    exit 0
fi

# ==============================================================================
# From here on: THE HANDHELD IMAGE
# ==============================================================================
say "Building the handheld image (ROG Xbox Ally X, board RC73XA)"

# ==============================================================================
# 1. Terra — added, used, and taken back out again
# ==============================================================================
# EXACTLY THE SAME DANCE AS STEPS 68 AND 71, FOR EXACTLY THE SAME REASONS, and
# those two files carry the full explanation. In short:
#
#   * Terra is the only place that builds these packages for Fedora.
#   * It is added, then switched OFF, so nothing else in this build can quietly
#     take a Terra package in place of Fedora's.
#   * It is switched on for one command at a time.
#   * Then it is REMOVED from the image entirely, because a repository file
#     that pairs a signed catalogue with a local-path key stops the installer
#     ISO from building at all (osbuild/bootc-image-builder#1188).
#
# ⚠️ AND terra-gpg-keys IS NAMED. Terra arrives as two packages and a previous
# step has already removed both. Asking for the key package by name is what
# stops "it worked yesterday" — the failure mode is explained in full at the
# top of build_files/71-game-mode.sh.
say "Adding Terra again (the repository the handheld packages come from)"

# shellcheck disable=SC2016
aq_dnf install --refresh --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release terra-gpg-keys

aq_installed terra-release terra-gpg-keys

AQ_TERRA_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-terra${FEDORA}"
if [ ! -s "${AQ_TERRA_KEY}" ]; then
    echo "  ${AQ_TERRA_KEY} is not on the disk although its package is installed."
    echo "  Something deleted the file and left the package. Putting it back."
    # shellcheck disable=SC2016
    aq_dnf reinstall --nogpgcheck \
        --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
        terra-gpg-keys || true
fi
if [ -s "${AQ_TERRA_KEY}" ]; then
    ok "Terra's signing key is really on the disk (${AQ_TERRA_KEY})"
else
    echo "  what is actually in /etc/pki/rpm-gpg:"
    ls -1 /etc/pki/rpm-gpg/ 2> /dev/null | sed 's/^/       /' || true
    bad "Terra's signing key for Fedora ${FEDORA} is not there — installs from Terra would fail their signature check"
fi

say "Switching Terra off again, so nothing in this build uses it by accident"
aq_dnf config-manager setopt terra.enabled=0 terra-source.enabled=0

aq_dnf repolist --enabled | awk 'NR > 1 { print $1 }' > /tmp/aq-enabled.txt
if grep -qFx 'terra' /tmp/aq-enabled.txt; then
    bad "Terra is still enabled — it could replace Fedora packages without anybody asking"
else
    ok "Terra is present but switched off"
fi
rm -f /tmp/aq-enabled.txt

if rpm -q terra-release-mesa > /dev/null 2>&1; then
    bad "terra-release-mesa is installed — this image would take Valve-patched Mesa instead of Fedora's, which is not the trade we chose"
else
    ok "terra-release-mesa is NOT installed — the graphics driver stays Fedora's"
fi

say "Checking Terra can be switched on for one command"
AQ_TERRA_FLAG=""
for flag in --enable-repo=terra --enablerepo=terra; do
    if aq_dnf repoquery "${flag}" --queryformat '%{name}' inputplumber > /tmp/aq-terra-probe.txt 2>&1; then
        AQ_TERRA_FLAG="${flag}"
        break
    fi
done
if [ -n "${AQ_TERRA_FLAG}" ]; then
    ok "Terra answers when it is switched on for one command (${AQ_TERRA_FLAG})"
else
    echo "AQUARIUS ERROR: Terra could not be switched on for a single command." >&2
    sed 's/^/       /' /tmp/aq-terra-probe.txt >&2 || true
    exit 1
fi
rm -f /tmp/aq-terra-probe.txt

# ==============================================================================
# 2. InputPlumber, and the one version question in this whole phase
# ==============================================================================
# WHAT INPUTPLUMBER IS, ONCE MORE, BECAUSE IT MATTERS MOST
#
# The Ally's built-in controller is not one device. It is two raw USB gadgets
# and a motion sensor, and Steam has no idea they belong together. InputPlumber
# reads all three, applies a description of this exact machine
# (`50-rog_xbox_ally.yaml`, which matches on the board name RC73XA) and creates
# ONE virtual Xbox Elite controller with the paddles and the gyro attached.
# That virtual pad is what Steam sees.
#
# ------------------------------------------------------------------------------
# ⚠️ THE VERSION MATTERS, AND HERE IS THE WHOLE STORY
# ------------------------------------------------------------------------------
#   * Before 0.79.0, the paddles and the Armoury and Library buttons on THIS
#     device were mapped wrongly and labelled wrongly in Steam. The fix is
#     InputPlumber PR #688, released in 0.79.0 on 3 September 2026.
#   * 0.79.5 introduced a regression on Ally X hardware: the thumbsticks stop
#     reporting their full range (InputPlumber issue #724).
#
# So the version we would choose, if we could choose, is "at least 0.79.0 and
# below 0.79.5". Terra publishes ONE version of this package at a time, so most
# days there is no choice to make. The code below therefore does the honest
# thing rather than the wishful thing:
#
#   * it asks Terra what versions exist;
#   * if one of them is in the good window, it installs exactly that one;
#   * if not, it installs what there is, SAYS SO in the build log, and writes
#     the version and the known issue into the image itself, at
#     /usr/share/aquarius/gaming/handheld.txt, so the first person to wonder why
#     a stick feels short can read the answer on the machine.
#
# It does NOT fail the build for being outside the window. A handheld image with
# a slightly odd stick range is still a working handheld image; a handheld image
# that does not exist is not.
say "Which versions of InputPlumber Terra has today"
aq_dnf repoquery "${AQ_TERRA_FLAG}" --showduplicates \
    --queryformat '%{version}-%{release}\n' inputplumber \
    > /tmp/aq-ip-versions.txt 2>&1 || true
sed 's/^/       /' /tmp/aq-ip-versions.txt

# The good window: >= 0.79.0 and < 0.79.5. `sort -V` is the shell's own
# version-aware sort, which is exactly the comparison rpm would make for
# version numbers this simple.
AQ_IP_WANTED=""
while IFS= read -r aq_evr; do
    [ -n "${aq_evr}" ] || continue
    aq_ver="${aq_evr%%-*}"
    case "${aq_ver}" in
        0.79.*) : ;;
        *) continue ;;
    esac
    # 0.79.0 .. 0.79.4 only
    aq_patch="${aq_ver##*.}"
    case "${aq_patch}" in
        0 | 1 | 2 | 3 | 4) AQ_IP_WANTED="${aq_evr}" ;;
    esac
done < <(grep -E '^[0-9]' /tmp/aq-ip-versions.txt | sort -V)
rm -f /tmp/aq-ip-versions.txt

if [ -n "${AQ_IP_WANTED}" ]; then
    say "Installing InputPlumber ${AQ_IP_WANTED} — inside the known-good window (>= 0.79.0, < 0.79.5)"
    aq_dnf install "${AQ_TERRA_FLAG}" "inputplumber-${AQ_IP_WANTED}"
else
    say "Terra offers no InputPlumber in the known-good window — taking what it has"
    echo "  The window we would have picked is 0.79.0 up to (not including) 0.79.5."
    echo "  Terra publishes one version at a time, so this is normal, not a fault."
    echo "  Whatever goes in is written into the image's own note so the bench can"
    echo "  read it: ${AQ_HANDHELD_NOTE}"
    aq_dnf install "${AQ_TERRA_FLAG}" inputplumber
fi

aq_installed inputplumber
AQ_IP_VERSION="$(rpm -q --queryformat '%{VERSION}' inputplumber)"
AQ_IP_EVR="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}' inputplumber)"
echo "  InputPlumber in this image: ${AQ_IP_EVR}"

# What it is known to do wrong, in one line, for the note that ships in the OS.
AQ_IP_NOTE="no known issues recorded for this version"
case "${AQ_IP_VERSION}" in
    0.79.0 | 0.79.1 | 0.79.2 | 0.79.3 | 0.79.4)
        AQ_IP_NOTE="inside the known-good window — paddles and button labels are correct (PR #688) and the stick-range regression of 0.79.5 is not in it"
        ;;
    0.7[0-8].*)
        AQ_IP_NOTE="OLDER than 0.79.0: the back paddles and the Armoury/Library buttons may be mapped and labelled wrongly in Steam (fixed upstream by PR #688)"
        ;;
    *)
        AQ_IP_NOTE="NEWER than 0.79.4: watch the thumbsticks. 0.79.5 shipped a regression that shortened the Ally X stick range (InputPlumber issue #724). If a stick feels like it will not reach the corners, that is the first thing to suspect — and it is a userspace package, so it can be changed without rebuilding anything else"
        ;;
esac
echo "  What that means: ${AQ_IP_NOTE}"

# The device description for THIS machine has to be in the package, or
# InputPlumber will happily run and do nothing useful.
AQ_IP_YAML="/usr/share/inputplumber/devices/50-rog_xbox_ally.yaml"
aq_file_has "${AQ_IP_YAML}" 'RC73XA' \
    "InputPlumber's profile matches this exact board (RC73XA — the Xbox Ally X)"
aq_file_has "${AQ_IP_YAML}" 'product_id: 0x1b4c' \
    "and it matches the built-in controller's USB id"
aq_file_has "${AQ_IP_YAML}" 'name: bmi323-imu' \
    "and it picks up the motion sensor, which is what gives Steam a gyro"
aq_file_has "${AQ_IP_YAML}" '^[[:space:]]*-[[:space:]]*xbox-elite$' \
    "and the controller it builds is an Xbox Elite pad, which Steam understands"
aq_file_has "${AQ_IP_YAML}" 'capability_map_id: aly2' \
    "and it uses the Xbox Ally button map"
if [ -r /usr/share/inputplumber/capability_maps/ally_type2.yaml ]; then
    ok "the Xbox Ally button map (ally_type2.yaml) is in the image"
else
    bad "/usr/share/inputplumber/capability_maps/ally_type2.yaml is missing — the paddles and the Armoury button would do nothing"
fi

# ==============================================================================
# 3. The sliders and the power button
# ==============================================================================
# steamos-manager-powerstation IS steamos-manager. It is Terra's build of the
# same program with extra support for `powerstation` (a small service that
# knows how to read and set graphics-card power on AMD hardware), and its RPM
# says `Obsoletes: steamos-manager` — so installing it REPLACES the plain one
# that step 71 put on every image. That is the intended swap and it is why this
# step must run after step 71, never before.
#
# ⚠️ IT DRAGS TWO THINGS IN WITH IT, AND BOTH ARE FINE:
#
#   powerstation                  a required dependency. The G2 spec said to
#                                 skip it in round one; it is not optional, so
#                                 it comes. It is small, it is switched on by
#                                 its own author's preset, and it is what the
#                                 TDP slider ends up talking to on AMD.
#   gamescope-session-ogui-steam  two files: one extra entry at the login
#                                 screen called "gamescope (OpenGamepadUI)".
#                                 We do not use it and nothing points at it.
#                                 It is listed here so that nobody on the bench
#                                 is surprised by a session they did not ask
#                                 for. Our Game Mode is still
#                                 gamescope-session-steam.
#
# powerbuttond is the package that PROVIDES steamos-powerbuttond. Terra renamed
# it; the old name is still a `Provides:`, which is checked below so that a
# future rename is noticed here rather than on the bench.
say "The handheld services, with Terra switched on for this one command"
# `install` alone refuses this: the plain steamos-manager that step 71 put in
# "conflicts with" the powerstation build, and dnf will not remove a package
# to satisfy a plain install (build 35431665659 died exactly here). `swap`
# is dnf's word for "take this one out and put that one in, in one go".
aq_dnf swap "${AQ_TERRA_FLAG}" steamos-manager steamos-manager-powerstation
aq_dnf install "${AQ_TERRA_FLAG}" powerbuttond

say "Where the handheld packages came from"
rpm -q --queryformat '       %{NAME}-%{VERSION}-%{RELEASE}  (packaged by: %{VENDOR})\n' \
    inputplumber steamos-manager-powerstation powerbuttond powerstation 2>&1 || true

aq_installed inputplumber steamos-manager-powerstation powerbuttond powerstation

# The swap really happened, and the program it provides is on the disk.
if rpm -q steamos-manager > /dev/null 2>&1; then
    bad "both steamos-manager and steamos-manager-powerstation are installed — they own the same files and one of them is not being used"
else
    ok "Terra's powerstation build replaced the plain steamos-manager, as its RPM asks"
fi
if rpm -q --whatprovides steamos-manager > /dev/null 2>&1; then
    ok "something still provides 'steamos-manager': $(rpm -q --whatprovides steamos-manager)"
else
    bad "nothing provides 'steamos-manager' any more — Steam's sliders would have no service to talk to"
fi
for aq_bin in /usr/lib/steamos-manager /usr/bin/steamosctl /usr/lib/hwsupport/steamos-powerbuttond /usr/bin/inputplumber /usr/bin/powerstation; do
    if [ -x "${aq_bin}" ]; then
        ok "${aq_bin} is installed and can be run"
    else
        bad "${aq_bin} is missing"
    fi
done
if rpm -q --provides powerbuttond | grep -q '^steamos-powerbuttond'; then
    ok "powerbuttond still provides the old name 'steamos-powerbuttond'"
else
    bad "the powerbuttond package no longer provides 'steamos-powerbuttond' — Terra has renamed something and this step needs revisiting"
fi

# ------------------------------------------------------------------------------
# The power-limit table for THIS board, read out of the installed package
# ------------------------------------------------------------------------------
# ⚠️ THIS IS EASY TO GET WRONG AND EXPENSIVE TO MISS. steamos-manager decides how
# to move the power limit by looking up the machine's board name in its own
# table of devices. There are two files that mention an Xbox Ally, and they do
# NOT say the same thing:
#
#   rog-xbox-ally.toml    RC73YA only (the Z2 A), and it drives the limit
#                         through amdgpu's own sensor interface, 4-20 W.
#   rog-ally-series.toml  RC71L, RC72LA and **RC73XA** — our machine — and it
#                         drives the limit through `asus-armoury`, which is the
#                         kernel driver that owns the real ASUS power knobs.
#
# If a future Terra build ever moved RC73XA into the other file, Steam's slider
# would appear to work and would be limited to 20 W on a machine that can take
# 35. So the board name is looked for, by hand, in the file that must contain it.
say "Steam's power-limit table knows this exact board"
AQ_SMDEV="/usr/share/steamos-manager/devices"
aq_file_has "${AQ_SMDEV}/rog-ally-series.toml" 'RC73XA' \
    "the ROG Xbox Ally X (RC73XA) is in steamos-manager's device table"
aq_file_has "${AQ_SMDEV}/rog-ally-series.toml" 'attribute = "asus-armoury"' \
    "and its power limit is driven through asus-armoury, the kernel's own ASUS knobs"
echo "  the whole entry, for the record:"
sed -n '/RC73XA/,/^$/p' "${AQ_SMDEV}/rog-ally-series.toml" | sed 's/^/       /'

# The extra login-screen entry that came along with the dependency, named out
# loud so it is never a surprise.
say "What came along as a dependency"
if [ -r /usr/share/wayland-sessions/gamescope-session-ogui-steam.desktop ]; then
    echo "  gamescope-session-ogui-steam is installed (steamos-manager-powerstation"
    echo "  requires it). It adds ONE extra entry to the login screen that we do not"
    echo "  use. AquariusOS's Game Mode is still gamescope-session-steam, and the"
    echo "  cold-boot setting names that one by hand."
    ok "the extra session is present and accounted for"
fi
echo "  every session this image can offer:"
ls -1 /usr/share/wayland-sessions/ 2> /dev/null | sed 's/^/       /'
for aq_s in gnome plasma gamescope-session-steam; do
    if [ -r "/usr/share/wayland-sessions/${aq_s}.desktop" ]; then
        ok "the login screen can still start '${aq_s}'"
    else
        bad "/usr/share/wayland-sessions/${aq_s}.desktop is missing"
    fi
done

# ------------------------------------------------------------------------------
# OpenGamepadUI's developer manual does not ship
# ------------------------------------------------------------------------------
# opengamepadui comes along as a dependency and brings its class-reference
# manual under /usr/share/doc, which includes a page named after another
# distribution (PlatformBazzite.md). CI's naming rule (build.yml, "RULE 1")
# rightly refuses any file on the image named after Bazzite, and this was the
# one path that tripped it on the very first handheld build. Nobody reads a
# developer manual on a handheld with no keyboard, so the whole folder goes.
say "OpenGamepadUI's developer manual is not on this image"
rm -rf /usr/share/doc/opengamepadui
if find / -xdev -iname '*bazzite*' 2> /dev/null | grep -q .; then
    bad "something on this image is still named after Bazzite:"
    find / -xdev -iname '*bazzite*' 2> /dev/null | sed 's/^/       /'
else
    ok "no file or folder on this image is named after Bazzite"
fi

# ------------------------------------------------------------------------------
# Valve's own session switching is still asleep, on this image too
# ------------------------------------------------------------------------------
# steamos-manager contains Valve's way of switching between Game Mode and a
# desktop, and it is hard-wired to a login screen called SDDM: it does nothing
# at all unless SDDM's `holo.conf` exists. AquariusOS uses GDM and does the
# switch its own way (step 71). Two mechanisms for one job is how a machine ends
# up in a login loop nobody can read, so the check is that the file which would
# wake Valve's half up is not in this image — exactly as on the desktop images.
say "Valve's own session switching is still asleep (ours owns the switch)"
if [ -e /usr/lib/sddm/sddm.conf.d/holo.conf ] || [ -e /etc/sddm.conf.d/holo.conf ]; then
    bad "an SDDM 'holo.conf' is in this image — Valve's session switching would wake up and fight ours"
else
    ok "no SDDM holo.conf, so Valve's own session switching can never start"
fi
if rpm -q sddm > /dev/null 2>&1; then
    bad "sddm is installed — GDM is the login screen on every AquariusOS image"
else
    ok "sddm is NOT installed"
fi
# The powerstation build also ships a settings file FOR sddm and a tidy-up job
# that removes SDDM's temporary login files. With no SDDM on this machine both
# are simply inert: the drop-in belongs to a service that does not exist, and
# the tidy-up deletes files that were never written. Named here so that reading
# the image later does not raise a false alarm.
echo "  (steamos-manager-powerstation ships an SDDM settings file and a tidy-up"
echo "   job for SDDM's temporary logins. There is no SDDM on this image, so both"
echo "   do nothing. Our switch writes GDM's files, which they never touch.)"

# ------------------------------------------------------------------------------
# Terra back out again
# ------------------------------------------------------------------------------
say "Removing Terra now its packages are installed (the installer ISO needs it gone)"
for aq_pkg in terra-release terra-gpg-keys; do
    if rpm -q "${aq_pkg}" > /dev/null 2>&1; then
        if rpm -e "${aq_pkg}" 2> /tmp/aq-terra-rm.txt; then
            ok "removed the ${aq_pkg} package"
        else
            echo "  rpm could not remove ${aq_pkg} cleanly:"
            sed 's/^/       /' /tmp/aq-terra-rm.txt
            echo "  Falling back to deleting its files directly."
        fi
        rm -f /tmp/aq-terra-rm.txt
    else
        echo "  ${aq_pkg} is not installed as a package (already gone, or added by file)."
    fi
done

rm -f /etc/yum.repos.d/terra*.repo /etc/pki/rpm-gpg/RPM-GPG-KEY-terra* 2> /dev/null || true

say "Proving Terra is gone, so the installer ISO can still be built"
find /etc/yum.repos.d -maxdepth 1 -name 'terra*.repo' > /tmp/aq-terra-left.txt 2> /dev/null || true
if [ -s /tmp/aq-terra-left.txt ]; then
    sed 's/^/       /' /tmp/aq-terra-left.txt
    bad "a Terra repository file is still in the image — the installer ISO would fail to build (osbuild#1188)"
else
    ok "no Terra repository file remains in /etc/yum.repos.d"
fi
rm -f /tmp/aq-terra-left.txt

find /etc/pki/rpm-gpg -maxdepth 1 -name 'RPM-GPG-KEY-terra*' > /tmp/aq-terra-key.txt 2> /dev/null || true
if [ -s /tmp/aq-terra-key.txt ]; then
    sed 's/^/       /' /tmp/aq-terra-key.txt
    bad "a Terra signing key file is still in the image"
else
    ok "no Terra signing key file remains"
fi
rm -f /tmp/aq-terra-key.txt

say "The graphics driver is still Fedora's"
for pkg in mesa-dri-drivers mesa-vulkan-drivers mesa-libGL; do
    AQ_VENDOR="$(rpm -q --queryformat '%{VENDOR}' "${pkg}" 2> /dev/null || echo '(missing)')"
    echo "  ${pkg}: ${AQ_VENDOR}"
    case "${AQ_VENDOR}" in
        *Fedora*) ok "${pkg} is Fedora's" ;;
        *) bad "${pkg} says its vendor is '${AQ_VENDOR}' — something replaced Fedora's Mesa" ;;
    esac
done

# ==============================================================================
# 4. Our own files, copied in and then compared byte for byte
# ==============================================================================
# The same discipline step 71 uses for `os-session-select`, and for the same
# reason: a file we ship can be quietly replaced by a file a package ships, and
# nothing looks wrong afterwards. So each one is installed from this repository
# and then compared against the copy in the build context. `cmp -s` reads both
# files. It cannot be fooled by a date.
say "Our own handheld files"

for aq_f in "${AQ_UDEV_RULES[@]}"; do
    install -Dm644 "${AQ_SRC}/${aq_f}" "/${aq_f}"
    if cmp -s "${AQ_SRC}/${aq_f}" "/${aq_f}"; then
        ok "/${aq_f} is ours, byte for byte"
    else
        bad "/${aq_f} is not the file this repository ships — something replaced it"
    fi
done

install -Dm644 "${AQ_SRC}/usr/lib/systemd/system/inputplumber.service.d/10-aquarius-before-login.conf" \
    /usr/lib/systemd/system/inputplumber.service.d/10-aquarius-before-login.conf
install -Dm755 "${AQ_SRC}/usr/libexec/aquarius-handheld-status" \
    /usr/libexec/aquarius-handheld-status
install -Dm644 "${AQ_SRC}/etc/aquarius/login-mode" /etc/aquarius/login-mode

for aq_f in \
    usr/lib/systemd/system/inputplumber.service.d/10-aquarius-before-login.conf \
    usr/libexec/aquarius-handheld-status \
    etc/aquarius/login-mode; do
    if cmp -s "${AQ_SRC}/${aq_f}" "/${aq_f}"; then
        ok "/${aq_f} is ours, byte for byte"
    else
        bad "/${aq_f} is not the file this repository ships"
    fi
done

# ------------------------------------------------------------------------------
# The wake-source rule is Bazzite's, unchanged, on purpose
# ------------------------------------------------------------------------------
# ⚠️ DO NOT "TIDY" 50-ally-x-controller.rules. It is copied byte-identically
# from ublue-os/bazzite (PR #5735, 6 September 2026) because it is the exact
# rule that has been tested on this hardware by the distribution with the most
# Ally mileage. Keeping it identical means a future upstream change can be
# compared with one `diff` instead of being reasoned about.
#
# What it does: it tells Linux that the built-in controller may NOT wake the
# machine. Without it, a thumbstick nudged in a bag wakes the handheld up — and
# worse, it can wake it in the middle of going to sleep, which leaves the
# machine in a half-suspended state that eats the battery.
say "The wake-source rule really says what Bazzite's says"
aq_file_has /usr/lib/udev/rules.d/50-ally-x-controller.rules \
    'ATTR\{idVendor\}=="0b05", ATTR\{idProduct\}=="1b4c"' \
    "it is aimed at the built-in controller and nothing else"
aq_file_has /usr/lib/udev/rules.d/50-ally-x-controller.rules \
    'ATTR\{power/wakeup\}="disabled"' \
    "and it stops that controller waking the machine"

say "The controller-chip power-saving rule"
aq_file_has /usr/lib/udev/rules.d/70-aquarius-ally-mcu-powersave.rules \
    'KERNEL=="asus-nb-wmi"' \
    "it only ever fires on an ASUS machine"
aq_file_has /usr/lib/udev/rules.d/70-aquarius-ally-mcu-powersave.rules \
    'ATTR\{mcu_powersave\}=="\?\*"' \
    "and only when the setting actually exists, so every other computer ignores it"
aq_file_has /usr/lib/udev/rules.d/70-aquarius-ally-mcu-powersave.rules \
    'ATTR\{mcu_powersave\}="1"' \
    "and it switches the controller chip's power saving on"

# udev refuses to load a rule file it cannot parse, at runtime, with nothing on
# screen to say so. `udevadm verify` is systemd's own checker for exactly that
# — the same gate step 82 puts in front of its own rule.
if aq_have udevadm && udevadm verify --help > /dev/null 2>&1; then
    for aq_f in "${AQ_UDEV_RULES[@]}"; do
        if udevadm verify "/${aq_f}" > /tmp/aq-udev.txt 2>&1; then
            ok "udev can read /${aq_f}"
        else
            sed 's/^/       /' /tmp/aq-udev.txt
            bad "udev refuses to load /${aq_f} — it would be silently ignored on the machine"
        fi
        rm -f /tmp/aq-udev.txt
    done
else
    echo "  note   udevadm verify is not available in this build; the content checks above are the answer"
fi

# ==============================================================================
# 5. Switching the services on — from /usr, never with `systemctl enable`
# ==============================================================================
# ⚠️ WHY THE LINKS ARE MADE BY HAND. `systemctl enable` writes its link into
# /etc. On this operating system /etc is the part that belongs to the person and
# is merged, not replaced, at every update — and systemd remembers a deletion
# there for ever. So one `systemctl disable`, on one machine, would switch a
# service off permanently and no update could ever put it back. Writing the link
# into /usr instead means the image always carries the truth. The full
# explanation is in build_files/aq-lib.sh.
#
# WHAT EACH LINK IS FOR:
#
#   inputplumber.service              the built-in controller. Started at boot,
#                                     and (see the drop-in) before the login
#                                     screen, so Steam never decides there is no
#                                     controller on a machine that is one.
#   inputplumber-suspend.service      tells InputPlumber the machine is going to
#                                     sleep and has woken up, so it can put the
#                                     virtual controller back together. This is
#                                     the userspace half of "the pad still works
#                                     after a resume".
#   steamos-manager.service (system)  the half of the sliders that needs root:
#                                     power limit, battery charge limit.
#   powerstation.service              what the power limit is actually written
#                                     through on AMD.
#   steamos-manager.service (user)    the half that lives in your session and
#                                     that Steam talks to. Its own package only
#                                     starts it for OpenGamepadUI's session, so
#                                     we ask for it in OURS as well.
#   steamos-powerbuttond.service      short press sleeps, long press opens the
#                                     power menu. A user service with no
#                                     [Install] section of its own, so a link is
#                                     the only way to ask for it.
say "Switching the handheld services on, in the way an update cannot lose"

aq_link_on() { # aq_link_on <wants-directory> <unit-file-directory> <unit>
    local wants="$1" unitdir="$2" unit="$3"
    if [ ! -e "${unitdir}/${unit}" ]; then
        bad "${unitdir}/${unit} does not exist — there is nothing to switch on"
        return
    fi
    install -d -m 0755 "${wants}"
    ln -sf "${unitdir}/${unit}" "${wants}/${unit}"
    if [ -L "${wants}/${unit}" ] && [ -e "${wants}/${unit}" ]; then
        echo "  ${wants}/${unit} -> $(readlink "${wants}/${unit}")"
        ok "${unit} is switched on from /usr"
    else
        bad "${wants}/${unit} is missing or points at nothing"
    fi
}

AQ_SYS=/usr/lib/systemd/system
AQ_USR=/usr/lib/systemd/user
AQ_GAME_WANTS="${AQ_USR}/gamescope-session-plus@steam.service.wants"

aq_link_on "${AQ_SYS}/multi-user.target.wants" "${AQ_SYS}" inputplumber.service
aq_link_on "${AQ_SYS}/sleep.target.wants" "${AQ_SYS}" inputplumber-suspend.service
aq_link_on "${AQ_SYS}/multi-user.target.wants" "${AQ_SYS}" steamos-manager.service
aq_link_on "${AQ_SYS}/multi-user.target.wants" "${AQ_SYS}" powerstation.service
aq_link_on "${AQ_GAME_WANTS}" "${AQ_USR}" steamos-manager.service
aq_link_on "${AQ_GAME_WANTS}" "${AQ_USR}" steamos-powerbuttond.service

# And nothing of ours may be switched on through /etc.
# The powerstation package switches itself on when it is installed (its
# installer runs 'systemctl enable', which writes a link under /etc). We want
# it on — but from /usr, where an update can never lose it, and that link was
# made above. So the /etc copy comes out again; build 35433856783 failed on
# exactly this line. Same for any other handheld package that does the same.
for aq_unit in powerstation.service inputplumber.service steamos-manager.service; do
    aq_etc_link="/etc/systemd/system/multi-user.target.wants/${aq_unit}"
    if [ -L "${aq_etc_link}" ]; then
        rm -f "${aq_etc_link}"
        echo "  removed ${aq_etc_link} (the package's own 'enable'; the /usr link above is the one that counts)"
    fi
done

say "Nothing is switched on through /etc"
AQ_ETC_ON="$(find /etc/systemd \
    \( -name 'inputplumber*.service' -o -name 'steamos-*.service' -o -name 'powerstation.service' \) \
    2> /dev/null || true)"
if [ -z "${AQ_ETC_ON}" ]; then
    ok "no handheld service is switched on through /etc (an update could lose that)"
else
    printf '%s\n' "${AQ_ETC_ON}" | sed 's/^/       /'
    bad "a handheld service is switched on through /etc — a build step ran 'systemctl enable'. See the note in aq-lib.sh."
fi

# The ordering drop-in, read back out of the finished image.
say "InputPlumber is ready before the login screen (Steam's 'connect a controller' dead end)"
aq_file_has /usr/lib/systemd/system/inputplumber.service.d/10-aquarius-before-login.conf \
    '^Before=display-manager\.service$' \
    "the login screen waits for InputPlumber, so Steam's first run sees the built-in controller"
if aq_have systemd-analyze; then
    if systemd-analyze verify /usr/lib/systemd/system/inputplumber.service > /tmp/aq-sd.txt 2>&1; then
        ok "systemd is happy with inputplumber.service and our drop-in"
    else
        # Not a build failure: `systemd-analyze verify` in a container complains
        # about units it cannot see (the login screen is not running here). The
        # output is printed so a real syntax error is readable in the log.
        echo "  systemd-analyze had something to say (often only about units that are"
        echo "  not present in a build container — read it, do not panic):"
        sed 's/^/       /' /tmp/aq-sd.txt
    fi
    rm -f /tmp/aq-sd.txt
fi

# ==============================================================================
# 6. A cold boot on THIS image goes straight into Game Mode
# ==============================================================================
# ⚠️ THE ONE LINE THAT MAKES THIS A HANDHELD. The desktop images ship
# /etc/aquarius/login-mode saying `desktop` and step 71 fails the build if they
# ever ship `game`. This image ships the opposite, because a handheld with no
# keyboard cannot get past a password box.
#
# The machinery is entirely phase G1's and is unchanged: a once-per-boot service
# (aquarius-login-mode.service) reads this file just before the login screen
# starts and sets GDM's automatic login accordingly. Nothing new runs here.
say "A cold boot on the handheld image goes straight into Game Mode"
aq_file_has /etc/aquarius/login-mode '^mode=game$' \
    "/etc/aquarius/login-mode says 'game' — switching this handheld on takes it straight to Steam"
aq_file_has /etc/aquarius/login-mode 'aq game boot off' \
    "and the file itself says how to put the login screen back"

# The service that reads it has to be switched on, or the setting is a wish.
aq_unit_is_on_from_usr aquarius-login-mode.service \
    "reads /etc/aquarius/login-mode at every boot and makes the login screen match"

# The session it will ask for has to exist.
if [ -r /usr/share/wayland-sessions/gamescope-session-steam.desktop ]; then
    ok "the Game Mode session this setting points at is installed"
else
    bad "gamescope-session-steam.desktop is missing — this image would boot into nothing at all"
fi

# And the way out has to be there too, because it is the escape hatch.
say "The way out is in the image"
if /usr/bin/aq game --help > /tmp/aq-game-help.txt 2>&1; then
    ok "'aq game' is here, so 'aq game boot off' can put the login screen back"
else
    sed 's/^/       /' /tmp/aq-game-help.txt
    bad "'aq game' does not run — there would be no way off Game Mode without reinstalling"
fi
rm -f /tmp/aq-game-help.txt
aq_file_has /usr/bin/aq 'aq game boot off' \
    "and the command's own help says how to put the login screen back"

# ==============================================================================
# 7. The firmware this machine cannot work without, proven on the disk
# ==============================================================================
# ⚠️ WHY THIS IS A BUILD FAILURE AND NOT A WARNING. Every one of these failures
# looks like broken hardware and none of them says anything useful on screen:
#
#   TAS2XXX13840.bin   the speakers' own program. Without it the Ally is silent
#                      — not quiet, silent — and nothing in the volume settings
#                      hints at why.
#   MT7922 files       the Wi-Fi and Bluetooth chip's program. Without them the
#                      desktop says "No Wi-Fi Adapter Found", as if the radio
#                      were not fitted.
#   amdgpu gc_11_5 /   the graphics and video engine of this exact chip family
#   psp_14_0 / vcn_4_0 (AMD "Strix"). Without them the machine does not draw.
#
# Fedora ships firmware compressed, and which compression it uses has changed
# before (xz today, zstd on some spins), so each file is looked for under every
# name it could have. Trust content, never a file name you remember.
say "The firmware this handheld cannot work without"

aq_firmware_file() { # aq_firmware_file <path-without-extension> "<what it is for>"
    local base="$1" what="$2" found=""
    local d
    for d in "" ".xz" ".zst" ".zstd"; do
        if [ -e "${base}${d}" ]; then
            found="${base}${d}"
            break
        fi
    done
    if [ -n "${found}" ]; then
        ok "${what} — ${found}"
    else
        echo "  what IS in $(dirname "${base}"):"
        ls -1 "$(dirname "${base}")" 2> /dev/null | head -20 | sed 's/^/       /' || true
        bad "${what} — no ${base} in any form (.bin, .bin.xz, .bin.zst). See docs/restart/hardware.md."
    fi
}

aq_firmware_file /usr/lib/firmware/TAS2XXX13840.bin \
    "the speakers' firmware (TI TAS2781); without it the handheld is completely silent"
aq_firmware_file /usr/lib/firmware/mediatek/WIFI_MT7922_patch_mcu_1_1_hdr.bin \
    "Wi-Fi firmware patch (MediaTek MT7922)"
aq_firmware_file /usr/lib/firmware/mediatek/WIFI_RAM_CODE_MT7922_1.bin \
    "Wi-Fi firmware (MediaTek MT7922)"
aq_firmware_file /usr/lib/firmware/mediatek/BT_RAM_CODE_MT7922_1_1_hdr.bin \
    "Bluetooth firmware (MediaTek MT7922)"

# The graphics blobs are a family, not single files, so these are counted rather
# than named one by one — the exact suffixes change between AMD chips and we
# would be chasing them for ever.
say "The graphics firmware for this chip family (AMD 'Strix')"
aq_fw_family() { # aq_fw_family <pattern> <at least> "<what it is>"
    local n
    n="$(find /usr/lib/firmware/amdgpu -maxdepth 1 -name "$1*" \( -type f -o -type l \) 2> /dev/null | wc -l | tr -d ' ')"
    if [ "${n}" -ge "$2" ]; then
        ok "$3 — ${n} files matching ${1}*"
    else
        bad "$3 — only ${n} files matching ${1}* in /usr/lib/firmware/amdgpu, expected at least $2"
    fi
}
if [ -d /usr/lib/firmware/amdgpu ]; then
    ok "/usr/lib/firmware/amdgpu exists"
    aq_fw_family gc_11_5 7 "the graphics engine"
    aq_fw_family psp_14_0 2 "the security processor (nothing draws without it)"
    aq_fw_family vcn_4_0 1 "the video decoder and encoder"
else
    bad "/usr/lib/firmware/amdgpu does not exist — this machine would not draw at all"
fi

# The kernel drivers, too. Firmware with no driver and a driver with no firmware
# fail in exactly the same way from the desktop.
say "The drivers that go with them"
# ⚠️ HYPHEN OR UNDERSCORE? Both, always. A kernel module is written one way in
# its file name and the other way when a program asks for it, and which is which
# is not consistent (hid-asus.ko but bmi323_i2c.ko). Looking for both spellings
# is one line here and saves a build failure that means nothing.
aq_have_module() { # aq_have_module <module> "<what it is>"
    local m="$1" what="$2" alt=""
    alt="$(printf '%s' "${m}" | tr '_-' '-_')"
    if [ -n "$(find /usr/lib/modules \( -name "${m}.ko*" -o -name "${alt}.ko*" \) 2> /dev/null | head -1)" ]; then
        ok "${what} — driver ${m}"
    else
        bad "${what} — driver ${m} is MISSING; that part reports itself absent even with firmware present"
    fi
}
aq_have_module hid-asus "the built-in controller and the ASUS buttons"
aq_have_module bmi323_i2c "the motion sensor (Steam's gyro)"
aq_have_module mt7921e "Wi-Fi and Bluetooth (MediaTek MT7922)"
aq_have_module snd-soc-tas2781-i2c "the speakers"
aq_have_module asus-armoury "the power-limit knobs Steam's TDP slider moves"
aq_have_module amdgpu "graphics"

# ==============================================================================
# 8. `aq handheld status` — one command for the whole bench report
# ==============================================================================
say "The 'aq handheld' command"
if /usr/bin/aq handheld --help > /tmp/aq-hh-help.txt 2>&1; then
    ok "'aq handheld --help' runs"
    head -4 /tmp/aq-hh-help.txt | sed 's/^/       /'
else
    sed 's/^/       /' /tmp/aq-hh-help.txt
    bad "'aq handheld --help' does not run — the command is missing or broken"
fi
rm -f /tmp/aq-hh-help.txt

# And the report itself really runs, here, in a container with none of the
# hardware present. That is the harshest test it will ever get: every single
# question has to miss, and it still has to finish and exit 0.
say "The report runs even where none of the hardware exists"
if /usr/libexec/aquarius-handheld-status > /tmp/aq-hh.txt 2>&1; then
    ok "aquarius-handheld-status finished cleanly with no handheld present"
    echo "  the first lines of what it said:"
    head -12 /tmp/aq-hh.txt | sed 's/^/       /'
else
    sed 's/^/       /' /tmp/aq-hh.txt
    bad "aquarius-handheld-status stopped with an error — a status command must never do that"
fi
rm -f /tmp/aq-hh.txt

# ==============================================================================
# 9. The note that ships in the image
# ==============================================================================
# Somebody on the handheld itself, with no internet and no copy of this
# repository, can read what this image is, which InputPlumber it carries and
# what that version is known to do wrong. This is also where the version
# decision of section 2 is written down permanently.
say "The note that ships in the image"
install -d -m 0755 "${AQ_NOTE_DIR}"
cat > "${AQ_HANDHELD_NOTE}" << EOF
AquariusOS — the handheld image (aquarius-os-handheld)

This image is the AMD/Intel AquariusOS, built for ONE computer: the
ROG Xbox Ally X (board RC73XA). It starts straight into Game Mode.

InputPlumber (the program that makes the built-in controller work as one
controller, with its paddles and its gyro):

    version: ${AQ_IP_EVR}
    note:    ${AQ_IP_NOTE}

    The version worth having is 0.79.0 or newer and below 0.79.5.
      * 0.79.0 fixed the back paddles and the Armoury / Library button
        labels on this exact device.
      * 0.79.5 shortened the thumbstick range on Ally hardware.
    Terra publishes one version at a time, so this is what there was on
    the day this image was built.

What is NOT here yet, and needs a kernel that does not exist in Fedora:
    rumble strength, stick dead zones, response curves, button remapping,
    and the tidiest controller re-initialisation after waking from sleep.

If something is wrong, run this first and paste all of it:

    aq handheld status

If the screen is black or scrambled, press Ctrl+Alt+F3 for a text login,
then:

    aq game boot off
    sudo systemctl reboot

and the machine comes back to the ordinary login screen.

The full guide is in the repository at docs/restart/handheld.md.
EOF
cat "${AQ_HANDHELD_NOTE}" | sed 's/^/       /'
aq_file_has "${AQ_HANDHELD_NOTE}" "version: ${AQ_IP_EVR}" \
    "the exact InputPlumber version is written into the image"
aq_file_has "${AQ_HANDHELD_NOTE}" 'Ctrl\+Alt\+F3' \
    "the note tells a person how to get out of a black screen"

aq_finish "Handheld layer (phase G2 — ROG Xbox Ally X)"
