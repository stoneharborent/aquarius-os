#!/usr/bin/bash
# ==============================================================================
# STEP 7g — the handheld layer (phases G2 and G4): the two handhelds
# ==============================================================================
# WHAT THIS STEP IS FOR, IN PLAIN ENGLISH
#
# AquariusOS is built four times from this one recipe:
#
#   aquarius-os                  a desktop PC with AMD or Intel graphics
#   aquarius-os-nvidia           the same, plus NVIDIA's driver
#   aquarius-os-handheld         the AMD one again — but for ONE handheld
#                                computer, the ROG Xbox Ally X (phase G2)
#   aquarius-os-handheld-claw    and again — for the OTHER handheld Royce owns,
#                                the MSI Claw 8 AI+ (phase G4, 2026-09-20)
#
# This step is the whole of those last two images. Everything else in the build
# runs exactly as it does for the two desktop images; this file adds the handful
# of things a handheld needs and nothing else. On the two desktop images it
# installs nothing at all, and instead PROVES that none of it arrived — which is
# the only way to be sure a change here can never reach a desktop machine.
#
# ------------------------------------------------------------------------------
# TWO SWITCHES, NOT ONE
# ------------------------------------------------------------------------------
#   HANDHELD=0 or 1          is this a handheld image at all?
#   HANDHELD_TARGET=ally     WHICH handheld, when it is one.
#                   or claw
#
# HANDHELD_TARGET is only ever read when HANDHELD=1. Anything other than those
# two words stops the build on the spot, with a sentence saying so.
#
# The two machines share most of this file — the same InputPlumber, the same
# Terra dance, the same power-button daemon, the same cold-boot setting. Where
# they differ, the difference is in a clearly marked `case` and nothing else:
#
#   * which InputPlumber version is the right one;
#   * which device description InputPlumber has to carry;
#   * which udev rules go on the image (the ASUS ones must NEVER reach the MSI
#     machine, and the MSI one must never reach the ASUS machine);
#   * which power-limit story is true, which on the Claw today is "there is not
#     one yet";
#   * which firmware and which drivers have to be on the disk.
#
# ------------------------------------------------------------------------------
# WHAT A HANDHELD NEEDS THAT A PC DOES NOT — five things, and that is all
# ------------------------------------------------------------------------------
#
#   1. IT MUST TURN ON INTO GAME MODE. There is no keyboard. A handheld that
#      stops at a password box is a brick, because there is nothing to type
#      with. So these images — and only these images — ship
#      /etc/aquarius/login-mode saying `game`. The machinery is already there
#      from phase G1; this is the flag flipped. `aq game boot off` still puts
#      the login screen back.
#
#   2. THE BUILT-IN CONTROLLER MUST LOOK LIKE ONE CONTROLLER. Linux sees a
#      handheld's built-in pad as several separate devices — on the Ally, two
#      raw USB gadgets (one for the sticks and buttons, one for the paddles and
#      the Armoury and Library buttons) and a motion sensor on a completely
#      different bus; on the Claw, a plain Xbox-style pad plus a set of extra
#      keys that arrive as keyboard presses. Left alone, Steam shows you a
#      gamepad with no paddles and no Guide button.
#      **InputPlumber** is the program that stitches them into one Xbox Elite
#      controller. It is the single most important package in this file.
#
#   3. THE SLIDERS IN STEAM SHOULD DO SOMETHING. Steam's Quick Access Menu has a
#      power-limit ("TDP") slider and a battery-charge limit. They talk to a
#      service called **steamos-manager**, which on these images is Terra's
#      powerstation build, switched ON — on the desktop images it is installed
#      and left asleep, because a desktop PC has nothing for it to manage.
#      ⚠️ On the CLAW, on Fedora's kernel 7.2, there is no power-limit knob for
#      the service to reach at all. That is not a bug in this file; it is the
#      kernel, and this step says so out loud rather than pretending. See
#      section 3b.
#
#   4. THE POWER BUTTON MUST BEHAVE LIKE A CONSOLE'S. A short press should put
#      the machine to sleep through Steam; a long press should open the power
#      menu. That is **steamos-powerbuttond**.
#
#   5. SMALL RULES ABOUT SLEEP. On both machines, one that stops a nudged
#      thumbstick waking the computer in your bag. On the Ally, a second one
#      that lets the controller's own little chip sleep properly so the pad is
#      alive again after a resume.
#
# ------------------------------------------------------------------------------
# ⚠️ WHAT IS DELIBERATELY NOT HERE
# ------------------------------------------------------------------------------
#   * NO KERNEL CHANGE OF ANY KIND. On the ALLY, Fedora's own kernel already
#     drives the controller, gyro, speakers, power limits and radios; the things
#     it cannot do yet — rumble strength, stick dead zones, button remapping,
#     and the tidiest controller re-initialisation after a sleep — live in a
#     patch series still being reviewed upstream (`hid-asus` v6). On the CLAW,
#     rather more waits: the `hid-msi` driver (the M1/M2 paddles, switching the
#     pad between its modes, the lights, rumble strength) is merged for kernel
#     **7.3** and is simply not in 7.2, and power limits and fan curves need a
#     series that is still unmerged. Round one of the Claw image ships what 7.2
#     can do and names what it cannot. If the bench says we need more, that is a
#     separate decision with its own spec. Nothing in this file touches a kernel.
#   * NO THIRD DEVICE. This targets the ROG Xbox Ally X (board `RC73XA`) and the
#     MSI Claw 8 AI+ A2VM (board `MS-1T52`), because those are the two machines
#     on the bench. Widening the list without hardware in front of us is how a
#     "supported device" becomes a bug report. In particular the other Claws —
#     `MS-1T41`, `MS-1T42`, `MS-1T8K`, `MS-1T91` — are different computers with
#     different processors and are NOT targeted.
#   * No OpenGamepadUI, no fan curves, no gyro on the Claw (nothing on Linux
#     exposes one), and no Handheld Daemon.
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
# handheld has no business on a desktop PC's image — or on an MSI one — and
# `login-mode` saying `game` on a desktop image would stop every machine
# following these images from ever showing a login screen again. So they live in
# their own folder, `handheld_files/`, laid out exactly as they sit on the
# finished machine, and this step is the only thing that ever copies them.
#
# ⚠️ AND THAT FOLDER HAS THREE PARTS (changed 2026-09-20, phase G4):
#
#     handheld_files/          files BOTH handhelds get, at the top
#     handheld_files/ally/     files only the ROG Xbox Ally X gets
#     handheld_files/claw/     files only the MSI Claw 8 AI+ gets
#
# The per-machine folders are laid out from the root of the finished machine in
# exactly the same way, so `handheld_files/ally/usr/lib/udev/rules.d/x.rules`
# becomes `/usr/lib/udev/rules.d/x.rules` — on the Ally image and nowhere else.
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
# Plain-language guides: docs/restart/handheld.md (the Ally)
#                        docs/restart/handheld-claw.md (the Claw)
# Specs: ../docs/game-mode-g2-spec.md   ../docs/game-mode-g4-spec.md
# Decision: ../docs/decision-2026-09-17-game-mode-and-handheld.md
# ==============================================================================

set -euo pipefail

# shellcheck source=build_files/aq-lib.sh
source /ctx/build_files/aq-lib.sh

FEDORA="$(rpm -E %fedora)"
HANDHELD="${HANDHELD:-0}"

# WHICH handheld. Only meaningful when HANDHELD=1; on a desktop image it is
# never read and never checked. `ally` is the default because the Ally image
# came first and nothing that builds it passes this in.
HANDHELD_TARGET="${HANDHELD_TARGET:-ally}"

AQ_NOTE_DIR="/usr/share/aquarius/gaming"
AQ_HANDHELD_NOTE="${AQ_NOTE_DIR}/handheld.txt"
AQ_SRC="/ctx/handheld_files"

# ------------------------------------------------------------------------------
# The udev rules, by name, so the copy and the read-back cannot drift
# ------------------------------------------------------------------------------
# These names are written down ONCE and used three times: to copy the file in,
# to read it back out of the finished image, and — on the images that must NOT
# have it — to prove it is absent. A rule that were named in only two of those
# three places is exactly how one would quietly go missing.
#
# The paths are written from the root of the finished machine. In this
# repository each one lives under its machine's own folder, so
#   handheld_files/ally/usr/lib/udev/rules.d/50-ally-x-controller.rules
# becomes
#   /usr/lib/udev/rules.d/50-ally-x-controller.rules
# on the Ally image, and is on no other image at all.
AQ_ALLY_RULES=(
    usr/lib/udev/rules.d/50-ally-x-controller.rules
    usr/lib/udev/rules.d/70-aquarius-ally-mcu-powersave.rules
)
AQ_CLAW_RULES=(
    usr/lib/udev/rules.d/50-aquarius-claw-controller.rules
)
# Every rule this whole step can ever install, whichever machine it is building
# for. This is the list the DESKTOP images check the absence of — and it is also
# what each handheld image uses to prove the OTHER handheld's rules did not come
# along. An ASUS rule on an MSI machine would be harmless but wrong; a rule
# arriving on an image nobody asked for it on is the kind of drift this whole
# file exists to catch.
AQ_ALL_RULES=("${AQ_ALLY_RULES[@]}" "${AQ_CLAW_RULES[@]}")

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

    # ⚠️ EVERY rule this step can install, from BOTH handhelds — the two ASUS
    # ones and the MSI one. Extended on 2026-09-20 when phase G4 added the Claw:
    # a list that only named one machine's rules would let the other machine's
    # leak onto a desktop image without a word.
    for aq_f in "${AQ_ALL_RULES[@]}"; do
        if [ -e "/${aq_f}" ]; then
            bad "/${aq_f} is on a desktop image — it is a rule about a handheld's built-in controller and has no business here"
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
# From here on: A HANDHELD IMAGE — but WHICH ONE?
# ==============================================================================
# Everything below this line runs on a handheld image only. The first thing it
# does is settle which of the two machines this build is for, because almost
# every check further down needs the answer.
#
# ⚠️ AN UNKNOWN NAME STOPS THE BUILD HERE, ON PURPOSE. The alternative — quietly
# falling back to the Ally — would build an ASUS image, publish it under an MSI
# name, and put two ASUS udev rules on a machine that has never seen one. A typo
# in a workflow file should cost fifteen minutes of a build machine, not a
# wrongly-built operating system.
case "${HANDHELD_TARGET}" in
    ally | claw) : ;;
    *)
        echo "AQUARIUS ERROR: HANDHELD_TARGET is '${HANDHELD_TARGET}', which is not a handheld this recipe knows." >&2
        echo "                It must be 'ally' (the ROG Xbox Ally X, board RC73XA) or 'claw'" >&2
        echo "                (the MSI Claw 8 AI+ A2VM, board MS-1T52). Check the --build-arg in" >&2
        echo "                the Justfile and the matrix in .github/workflows/build.yml." >&2
        exit 1
        ;;
esac

# The facts about this machine, gathered in one place so the rest of the file
# reads the same for both: what it is called, which board name identifies it,
# and which of the two folders under handheld_files/ its own files come from.
case "${HANDHELD_TARGET}" in
    ally)
        AQ_HH_NAME="ROG Xbox Ally X"
        AQ_HH_BOARD="RC73XA"
        AQ_UDEV_RULES=("${AQ_ALLY_RULES[@]}")
        AQ_OTHER_RULES=("${AQ_CLAW_RULES[@]}")
        ;;
    claw)
        AQ_HH_NAME="MSI Claw 8 AI+ (A2VM)"
        AQ_HH_BOARD="MS-1T52"
        AQ_UDEV_RULES=("${AQ_CLAW_RULES[@]}")
        AQ_OTHER_RULES=("${AQ_ALLY_RULES[@]}")
        ;;
esac

say "Building the handheld image (${AQ_HH_NAME}, board ${AQ_HH_BOARD})"
echo "  HANDHELD_TARGET=${HANDHELD_TARGET}"
echo "  its own files come from handheld_files/${HANDHELD_TARGET}/"

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
# A handheld's built-in controller is not one device.
#
#   On the ALLY it is two raw USB gadgets and a motion sensor, and Steam has no
#   idea they belong together. InputPlumber reads all three, applies a
#   description of that exact machine (`50-rog_xbox_ally.yaml`, which matches on
#   the board name RC73XA) and creates ONE virtual Xbox Elite controller with
#   the paddles and the gyro attached.
#
#   On the CLAW it is a plain Xbox-style pad (which Linux drives all by itself
#   with the `xpad` driver) PLUS a scattering of extra buttons that arrive as
#   ordinary keyboard presses — the Guide button is an F15 keypress from a
#   device called "MSI WMI hotkeys", the Quick Access button is F16, and so on.
#   Steam would see a gamepad with no Guide button and a keyboard that
#   mysteriously types F-keys. InputPlumber applies
#   `50-msi_claw8_a2vm.yaml` (which matches on the board name MS-1T52), gathers
#   the pad and the key presses together and again presents ONE virtual Xbox
#   Elite controller. There is no gyro on this machine — nothing on Linux
#   exposes one — so that part is simply absent.
#
# That virtual pad is what Steam sees, on both machines.
#
# ------------------------------------------------------------------------------
# ⚠️ THE VERSION MATTERS, AND THE TWO MACHINES WANT DIFFERENT VERSIONS
# ------------------------------------------------------------------------------
# THE ALLY wants "at least 0.79.0 and below 0.79.5":
#   * Before 0.79.0, the paddles and the Armoury and Library buttons on that
#     device were mapped wrongly and labelled wrongly in Steam. The fix is
#     InputPlumber PR #688, released in 0.79.0 on 3 September 2026.
#   * 0.79.5 introduced a regression on Ally X hardware: the thumbsticks stop
#     reporting their full range (InputPlumber issue #724).
#
# THE CLAW wants "at least 0.80.0", and has no ceiling:
#   * Before 0.80.0 the Guide button on the Claw did nothing at all — the F15
#     keypress was not turned into a Guide press, so there was no way to open
#     Steam's menu from the pad. The fix is InputPlumber PR #714, merged
#     14 September 2026 and released the same day in 0.80.0 and 0.81.0.
#   * The 0.79.5 stick regression is an ALLY problem, on ASUS hardware, and
#     does not apply here. Do not copy the Ally's ceiling onto this machine —
#     it would rule out every version that has the Guide fix.
#
# Terra publishes ONE version of this package at a time, so most days there is
# no choice to make. The code below therefore does the honest thing rather than
# the wishful thing:
#
#   * it asks Terra what versions exist;
#   * if one of them is in the window THIS machine wants, it installs exactly
#     that one;
#   * if not, it installs what there is, SAYS SO in the build log, and writes
#     the version and the known issue into the image itself, at
#     /usr/share/aquarius/gaming/handheld.txt, so the first person to wonder why
#     a stick feels short — or why the Guide button does nothing — can read the
#     answer on the machine.
#
# It does NOT fail the build for being outside the window. A handheld image with
# a slightly odd stick range is still a working handheld image; a handheld image
# that does not exist is not.

# aq_ver_ge <version> <minimum> — is the first version at least the second?
#
# `sort -V` is the shell's own version-aware sort, which for version numbers
# this simple makes the same comparison rpm would. The output is captured into a
# variable and the first line taken with plain text-trimming rather than piping
# into `head`: a pipe into `head` can kill `sort` with a broken-pipe signal, and
# `set -o pipefail` (on in every script here) then reports the whole thing as
# failed. That trap is written out at length in build_files/aq-lib.sh.
aq_ver_ge() {
    local both lowest
    both="$(printf '%s\n%s\n' "$1" "$2" | sort -V)"
    lowest="${both%%$'\n'*}"
    [ "${lowest}" = "$2" ]
}

case "${HANDHELD_TARGET}" in
    ally) AQ_IP_WINDOW="at least 0.79.0 and below 0.79.5" ;;
    claw) AQ_IP_WINDOW="0.80.0 or newer (no upper limit)" ;;
esac

say "Which versions of InputPlumber Terra has today"
echo "  the window this machine (${AQ_HH_NAME}) wants: ${AQ_IP_WINDOW}"
aq_dnf repoquery "${AQ_TERRA_FLAG}" --showduplicates \
    --queryformat '%{version}-%{release}\n' inputplumber \
    > /tmp/aq-ip-versions.txt 2>&1 || true
sed 's/^/       /' /tmp/aq-ip-versions.txt

AQ_IP_WANTED=""
while IFS= read -r aq_evr; do
    [ -n "${aq_evr}" ] || continue
    aq_ver="${aq_evr%%-*}"
    case "${HANDHELD_TARGET}" in
        ally)
            # 0.79.0 .. 0.79.4 only.
            case "${aq_ver}" in
                0.79.*) : ;;
                *) continue ;;
            esac
            aq_patch="${aq_ver##*.}"
            case "${aq_patch}" in
                0 | 1 | 2 | 3 | 4) AQ_IP_WANTED="${aq_evr}" ;;
            esac
            ;;
        claw)
            # Anything from 0.80.0 upwards. The list is walked in version order,
            # so the last one that matches is the newest one Terra has.
            if aq_ver_ge "${aq_ver}" 0.80.0; then
                AQ_IP_WANTED="${aq_evr}"
            fi
            ;;
    esac
done < <(grep -E '^[0-9]' /tmp/aq-ip-versions.txt | sort -V)
rm -f /tmp/aq-ip-versions.txt

if [ -n "${AQ_IP_WANTED}" ]; then
    say "Installing InputPlumber ${AQ_IP_WANTED} — inside the window this machine wants (${AQ_IP_WINDOW})"
    aq_dnf install "${AQ_TERRA_FLAG}" "inputplumber-${AQ_IP_WANTED}"
else
    say "Terra offers no InputPlumber in the window this machine wants — taking what it has"
    echo "  The window we would have picked is ${AQ_IP_WINDOW}."
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
case "${HANDHELD_TARGET}" in
    ally)
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
        ;;
    claw)
        if aq_ver_ge "${AQ_IP_VERSION}" 0.80.0; then
            AQ_IP_NOTE="0.80.0 or newer, which is what this machine needs — it carries the Guide-button fix (PR #714, 14 September 2026), so the Xbox button in the middle of the pad really opens Steam's menu"
        else
            AQ_IP_NOTE="OLDER than 0.80.0: the Guide button (the Xbox button in the middle of the pad) will do NOTHING, because the fix that turns this machine's F15 keypress into a Guide press is PR #714, first released in 0.80.0. Everything else still works. It is a userspace package, so it can be changed without rebuilding anything else"
        fi
        ;;
esac
echo "  What that means: ${AQ_IP_NOTE}"

# ------------------------------------------------------------------------------
# The device description for THIS machine has to be in the package
# ------------------------------------------------------------------------------
# InputPlumber will happily run with no description of the computer it is on,
# and do nothing useful. The description is a plain text file inside the
# package, one per supported machine, and it is matched to the computer by the
# board name the motherboard reports. So the check is: is the right file there,
# and does it name this board?
case "${HANDHELD_TARGET}" in
    ally)
        say "InputPlumber knows this machine (the ROG Xbox Ally X)"
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
        ;;
    claw)
        say "InputPlumber knows this machine (the MSI Claw 8 AI+)"
        # ⚠️ THE BOARD NAME IS THE WHOLE IDENTIFICATION, and MSI sell
        # several machines called "Claw" that are different computers inside:
        #   MS-1T52  the Claw 8 AI+ A2VM — Intel Lunar Lake — THIS ONE
        #   MS-1T41  the A1M (Meteor Lake)       MS-1T42  the Claw 7 AI+
        #   MS-1T8K  the Claw A8 (AMD)           MS-1T91  the Claw 8 EX AI+
        # Only MS-1T52 is on the bench and only MS-1T52 is targeted.
        AQ_IP_YAML="/usr/share/inputplumber/devices/50-msi_claw8_a2vm.yaml"
        aq_file_has "${AQ_IP_YAML}" 'MS-1T52' \
            "InputPlumber's profile matches this exact board (MS-1T52 — the Claw 8 AI+ A2VM)"
        aq_file_has "${AQ_IP_YAML}" '^[[:space:]]*-[[:space:]]*xbox-elite$' \
            "and the controller it builds is an Xbox Elite pad, which Steam understands"
        aq_file_has "${AQ_IP_YAML}" 'capability_map_id: claw1' \
            "and it uses the MSI Claw button map, which is what turns the Guide and Quick Access keypresses into real controller buttons"
        if [ -r /usr/share/inputplumber/capability_maps/msiclaw_type1.yaml ]; then
            ok "the MSI Claw button map (msiclaw_type1.yaml) is in the image"
        else
            bad "/usr/share/inputplumber/capability_maps/msiclaw_type1.yaml is missing — the Guide button and the Quick Access button would do nothing"
        fi
        # There is no gyro line to look for: this machine has no motion sensor
        # Linux can reach, and the profile's IMU section is empty upstream.
        echo "  (There is deliberately no gyro check here. Nothing on Linux exposes a"
        echo "   motion sensor on this machine, so Steam's gyro settings will be empty."
        echo "   That is expected, not a fault — see docs/restart/handheld-claw.md.)"
        ;;
esac

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
AQ_SMDEV="/usr/share/steamos-manager/devices"

# AQ_TDP_NOTE is one sentence about whether Steam's power slider can work on
# this machine at all. It ends up in the note that ships inside the image, so
# that somebody holding the handheld can read the answer without a computer.
AQ_TDP_NOTE=""

case "${HANDHELD_TARGET}" in
    ally)
        say "Steam's power-limit table knows this exact board"
        aq_file_has "${AQ_SMDEV}/rog-ally-series.toml" 'RC73XA' \
            "the ROG Xbox Ally X (RC73XA) is in steamos-manager's device table"
        aq_file_has "${AQ_SMDEV}/rog-ally-series.toml" 'attribute = "asus-armoury"' \
            "and its power limit is driven through asus-armoury, the kernel's own ASUS knobs"
        echo "  the whole entry, for the record:"
        sed -n '/RC73XA/,/^$/p' "${AQ_SMDEV}/rog-ally-series.toml" | sed 's/^/       /'
        AQ_TDP_NOTE="driven through asus-armoury (steamos-manager device table: rog-ally-series.toml). Steam's TDP slider moves real hardware."
        ;;
    claw)
        # ------------------------------------------------------------------
        # ⚠️ ON THIS MACHINE, TODAY, THERE IS PROBABLY NO POWER SLIDER
        # ------------------------------------------------------------------
        # This is the one place where the Claw image is honestly different from
        # the Ally image, and it must not be papered over.
        #
        # steamos-manager moves a power limit by writing to a knob the KERNEL
        # provides. On the Ally that knob is `asus-armoury`, which is in
        # Fedora's kernel and works. On the Claw the equivalent knob lives in a
        # patch series for the `msi-wmi-platform` driver that has been waiting
        # to be accepted upstream since May 2025 and that its own author
        # described as stuck in February 2026. It is not in Fedora's kernel
        # 7.2, and we do not carry kernel patches (standing decision 1).
        #
        # So: Steam's TDP slider on the Claw is expected to do NOTHING. The
        # machine still runs at its normal power, decided by its own firmware,
        # which is a perfectly good handheld — it just is not adjustable from
        # Steam yet.
        #
        # This check therefore does not demand a table entry. It LOOKS for one,
        # says what it found, and passes either way. If a future Terra build of
        # steamos-manager starts shipping a table for this board, this is where
        # we will see it, on the next build, by name.
        say "Is there a power-limit table for this board? (expected: no, and that is fine)"
        echo "  Looking through every device file steamos-manager ships for the"
        echo "  board name MS-1T52 or the word Claw."

        # The whole list first, so the log shows what there was to look at.
        AQ_SM_TOMLS="$(find "${AQ_SMDEV}" -maxdepth 1 -name '*.toml' 2> /dev/null | sort || true)"
        if [ -n "${AQ_SM_TOMLS}" ]; then
            echo "  device files in ${AQ_SMDEV}:"
            printf '%s\n' "${AQ_SM_TOMLS}" | sed 's|.*/|       |'
        else
            echo "  ${AQ_SMDEV} has no .toml files in it at all."
        fi

        # grep -l over the found files, with no pipe into anything that could
        # stop early — a pipe into `head` can kill the writer with a broken-pipe
        # signal and `set -o pipefail` then reports a found match as a failure.
        # The long version of that trap is in build_files/aq-lib.sh.
        AQ_SM_HIT=""
        if [ -n "${AQ_SM_TOMLS}" ]; then
            while IFS= read -r aq_toml; do
                [ -n "${aq_toml}" ] || continue
                if grep -qE 'MS-1T52|Claw|claw' "${aq_toml}" 2> /dev/null; then
                    AQ_SM_HIT="${AQ_SM_HIT}${aq_toml}
"
                fi
            done <<< "${AQ_SM_TOMLS}"
        fi

        if [ -n "${AQ_SM_HIT}" ]; then
            ok "steamos-manager DOES ship a device file mentioning this machine:"
            printf '%s' "${AQ_SM_HIT}" | sed 's/^/       /'
            echo "  what those files say about it, and which method they name:"
            AQ_TDP_METHOD=""
            while IFS= read -r aq_toml; do
                [ -n "${aq_toml}" ] || continue
                grep -nE 'MS-1T52|Claw|claw|attribute|tdp|TdpLimit|method' "${aq_toml}" 2> /dev/null \
                    | sed "s|^|       $(basename "${aq_toml}"): |" || true
                AQ_TDP_METHOD="${AQ_TDP_METHOD}$(basename "${aq_toml}") "
            done <<< "${AQ_SM_HIT}"
            echo
            echo "  WHAT TO DO WITH THAT: this is NEW since the image was designed."
            echo "  Read the method named above. If it is a firmware attribute, it still"
            echo "  needs the kernel series that is not merged, so the slider will still"
            echo "  do nothing. If it names a helper daemon, that is worth a round two."
            AQ_TDP_NOTE="steamos-manager ships a device file naming this machine (${AQ_TDP_METHOD}). Whether the slider actually moves anything is a bench question — on kernel 7.2 the firmware-attribute method has nothing to write to."
        else
            ok "no TDP backend for this device on kernel 7.2 — Steam's power slider will not work; expected."
            echo "  This is not a fault and not a missing package. The knob Steam would"
            echo "  write through does not exist in Fedora's kernel for this machine, and"
            echo "  AquariusOS does not carry kernel patches. The machine runs at the"
            echo "  power its own firmware chooses, which is fine — it just cannot be"
            echo "  changed from Steam yet. It becomes possible when the msi-wmi-platform"
            echo "  firmware-attributes series is merged upstream."
            echo "  The raw Intel power readings ARE visible, and 'aq handheld status'"
            echo "  prints them, so the bench can at least see what the machine is doing."
            AQ_TDP_NOTE="NONE on kernel 7.2. Steam's TDP slider will not move anything: the kernel knob it writes through (msi-wmi-platform firmware attributes) is an unmerged patch series. Raw readings only, via /sys/class/powercap/intel-rapl."
        fi
        ;;
esac

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

# WARNING: THE UDEV RULES COME FROM THIS MACHINE'S OWN FOLDER, NOT THE SHARED
# ONE. handheld_files/ally/... for the Ally, handheld_files/claw/... for the
# Claw. That separation is the whole reason the folder was split on 2026-09-20:
# the ASUS rules name an ASUS controller and an ASUS platform driver, and they
# have no business on an MSI machine (and the other way round).
for aq_f in "${AQ_UDEV_RULES[@]}"; do
    install -Dm644 "${AQ_SRC}/${HANDHELD_TARGET}/${aq_f}" "/${aq_f}"
    if cmp -s "${AQ_SRC}/${HANDHELD_TARGET}/${aq_f}" "/${aq_f}"; then
        ok "/${aq_f} is ours, byte for byte"
    else
        bad "/${aq_f} is not the file this repository ships — something replaced it"
    fi
done

# And the OTHER handheld's rules are not here. This is the same promise the
# desktop images make, asked from inside a handheld image: a rule that belongs
# to one machine must never arrive on the other.
for aq_f in "${AQ_OTHER_RULES[@]}"; do
    if [ -e "/${aq_f}" ]; then
        bad "/${aq_f} is on the ${AQ_HH_NAME} image — that rule belongs to the other handheld and must not be here"
    else
        ok "/${aq_f} is not on this image, as intended (it belongs to the other handheld)"
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
# What each machine's rules must actually say
# ------------------------------------------------------------------------------
case "${HANDHELD_TARGET}" in
    ally)
        # ----------------------------------------------------------------------
        # The wake-source rule is Bazzite's, unchanged, on purpose
        # ----------------------------------------------------------------------
        # ⚠️ DO NOT "TIDY" 50-ally-x-controller.rules. It is copied
        # byte-identically from ublue-os/bazzite (PR #5735, 6 September 2026)
        # because it is the exact rule that has been tested on this hardware by
        # the distribution with the most Ally mileage. Keeping it identical
        # means a future upstream change can be compared with one `diff`
        # instead of being reasoned about.
        #
        # What it does: it tells Linux that the built-in controller may NOT wake
        # the machine. Without it, a thumbstick nudged in a bag wakes the
        # handheld up — and worse, it can wake it in the middle of going to
        # sleep, which leaves the machine in a half-suspended state that eats
        # the battery.
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
        ;;
    claw)
        # ----------------------------------------------------------------------
        # The Claw's wake-source rule is OURS, and it is untested until the bench
        # ----------------------------------------------------------------------
        # No distribution ships a wake-source rule for this machine — not
        # Bazzite, not SteamOS, nobody. This one is AquariusOS's own, written on
        # the same idea and in the same shape as the Ally's: the built-in
        # controller may not wake the computer, so a thumbstick nudged inside a
        # bag cannot switch the handheld on and flatten it.
        #
        # It names three USB product numbers because the Claw's pad changes its
        # identity with its mode: 1901 XInput, 1902 DInput, 1903 Desktop. On
        # kernel 7.2 nothing on Linux can switch between them, so the rule
        # covers whichever one the machine happens to be in.
        #
        # It is a reasonable guess, not a tested fact. The bench list in
        # docs/restart/handheld-claw.md has the line that turns it into one.
        say "The Claw's wake-source rule (ours, and untested until the bench)"
        AQ_CLAW_RULE=/usr/lib/udev/rules.d/50-aquarius-claw-controller.rules
        aq_file_has "${AQ_CLAW_RULE}" 'ATTR\{idVendor\}=="0db0"' \
            "it is aimed at MSI's built-in controller and nothing else"
        for aq_pid in 1901 1902 1903; do
            aq_file_has "${AQ_CLAW_RULE}" "ATTR\{idProduct\}==\"${aq_pid}\"" \
                "and it covers the pad in its ${aq_pid} mode, because kernel 7.2 cannot switch modes"
        done
        aq_file_has "${AQ_CLAW_RULE}" 'ATTR\{power/wakeup\}="disabled"' \
            "and it stops that controller waking the machine"
        aq_file_has "${AQ_CLAW_RULE}" 'untested until the bench' \
            "and the file says out loud that it is ours and has never run on a Claw"
        ;;
esac

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
# 7. The firmware and drivers this machine cannot work without
# ==============================================================================
# ⚠️ WHY THIS IS A BUILD FAILURE AND NOT A WARNING. Every one of these
# failures looks like broken hardware and none of them says anything useful on
# screen: a silent speaker, a "No Wi-Fi Adapter Found", a machine that will not
# draw. Firmware is a small program the kernel hands to a piece of hardware when
# it starts it; with the file missing the hardware simply reports itself absent.
#
# Fedora ships firmware compressed, and which compression it uses has changed
# before (xz today, zstd on some spins), so each file is looked for under every
# name it could have. Trust content, never a file name you remember.

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

# Some firmware comes as a family rather than one file, and the exact suffixes
# change between chips. Counting is the honest check there: we would be chasing
# individual names for ever.
aq_fw_family() { # aq_fw_family <directory> <pattern> <at least> "<what it is>"
    local n
    n="$(find "$1" -maxdepth 1 -name "$2*" \( -type f -o -type l \) 2> /dev/null | wc -l | tr -d ' ')"
    if [ "${n}" -ge "$3" ]; then
        ok "$4 — ${n} files matching ${2}*"
    else
        bad "$4 — only ${n} files matching ${2}* in $1, expected at least $3"
    fi
}

# The kernel drivers, too. Firmware with no driver and a driver with no firmware
# fail in exactly the same way from the desktop.
#
# ⚠️ HYPHEN OR UNDERSCORE? Both, always. A kernel module is written one way
# in its file name and the other way when a program asks for it, and which is
# which is not consistent (hid-asus.ko but bmi323_i2c.ko). Looking for both
# spellings is one line here and saves a build failure that means nothing.
aq_module_path() { # aq_module_path <module>  — prints where it is, or nothing
    local m="$1" alt="" hits=""
    alt="$(printf '%s' "${m}" | tr '_-' '-_')"
    hits="$(find /usr/lib/modules \( -name "${m}.ko*" -o -name "${alt}.ko*" \) 2> /dev/null || true)"
    printf '%s' "${hits%%$'\n'*}"
}

aq_have_module() { # aq_have_module <module> "<what it is>"
    local m="$1" what="$2"
    if [ -n "$(find /usr/lib/modules \( -name "${m}.ko*" -o -name "$(printf '%s' "${m}" | tr '_-' '-_').ko*" \) 2> /dev/null | head -1)" ]; then
        ok "${what} — driver ${m}"
    else
        bad "${what} — driver ${m} is MISSING; that part reports itself absent even with firmware present"
    fi
}

# AQ_HIDMSI_NOTE is filled in on the Claw and ends up in the note that ships in
# the image. On the Ally it stays empty and nothing prints it.
AQ_HIDMSI_NOTE=""

case "${HANDHELD_TARGET}" in
    ally)
        # ----------------------------------------------------------------------
        #   TAS2XXX13840.bin   the speakers' own program. Without it the Ally is
        #                      silent — not quiet, silent — and nothing in the
        #                      volume settings hints at why.
        #   MT7922 files       the Wi-Fi and Bluetooth chip's program. Without
        #                      them the desktop says "No Wi-Fi Adapter Found",
        #                      as if the radio were not fitted.
        #   amdgpu gc_11_5 /   the graphics and video engine of this exact chip
        #   psp_14_0 / vcn_4_0 family (AMD "Strix"). Without them the machine
        #                      does not draw.
        # ----------------------------------------------------------------------
        say "The firmware this handheld cannot work without"

        aq_firmware_file /usr/lib/firmware/TAS2XXX13840.bin \
            "the speakers' firmware (TI TAS2781); without it the handheld is completely silent"
        aq_firmware_file /usr/lib/firmware/mediatek/WIFI_MT7922_patch_mcu_1_1_hdr.bin \
            "Wi-Fi firmware patch (MediaTek MT7922)"
        aq_firmware_file /usr/lib/firmware/mediatek/WIFI_RAM_CODE_MT7922_1.bin \
            "Wi-Fi firmware (MediaTek MT7922)"
        aq_firmware_file /usr/lib/firmware/mediatek/BT_RAM_CODE_MT7922_1_1_hdr.bin \
            "Bluetooth firmware (MediaTek MT7922)"

        say "The graphics firmware for this chip family (AMD 'Strix')"
        if [ -d /usr/lib/firmware/amdgpu ]; then
            ok "/usr/lib/firmware/amdgpu exists"
            aq_fw_family /usr/lib/firmware/amdgpu gc_11_5 7 "the graphics engine"
            aq_fw_family /usr/lib/firmware/amdgpu psp_14_0 2 "the security processor (nothing draws without it)"
            aq_fw_family /usr/lib/firmware/amdgpu vcn_4_0 1 "the video decoder and encoder"
        else
            bad "/usr/lib/firmware/amdgpu does not exist — this machine would not draw at all"
        fi

        say "The drivers that go with them"
        aq_have_module hid-asus "the built-in controller and the ASUS buttons"
        aq_have_module bmi323_i2c "the motion sensor (Steam's gyro)"
        aq_have_module mt7921e "Wi-Fi and Bluetooth (MediaTek MT7922)"
        aq_have_module snd-soc-tas2781-i2c "the speakers"
        aq_have_module asus-armoury "the power-limit knobs Steam's TDP slider moves"
        aq_have_module amdgpu "graphics"
        ;;
    claw)
        # ----------------------------------------------------------------------
        # A COMPLETELY DIFFERENT SET OF PARTS. The Claw is an Intel machine:
        # Intel graphics, Intel sound, Intel Wi-Fi. Not one of the Ally's files
        # above is relevant, and looking for them would fail a perfectly good
        # image.
        #
        #   xe/lnl_*           the graphics chip's own programs (Intel Arc 140V
        #                      inside "Lunar Lake"). Without them the machine
        #                      does not draw.
        #   sof-lnl.ri         the sound chip's program. Intel machines run
        #                      their audio on a small separate processor and
        #                      this is what it runs. Without it: silence.
        #   iwlwifi-bz-*       the Wi-Fi chip's program (Intel BE201). Without
        #                      it the desktop says there is no Wi-Fi adapter.
        # ----------------------------------------------------------------------
        say "The firmware this handheld cannot work without (Intel Lunar Lake)"

        aq_firmware_file /usr/lib/firmware/xe/lnl_guc_70.bin \
            "the graphics scheduler (Intel Arc 140V); without it the machine does not draw"
        aq_firmware_file /usr/lib/firmware/xe/lnl_huc.bin \
            "the graphics video-encode helper"
        aq_firmware_file /usr/lib/firmware/xe/lnl_gsc_1.bin \
            "the graphics security controller"
        aq_firmware_file /usr/lib/firmware/intel/sof-ipc4/lnl/sof-lnl.ri \
            "the sound processor's program (Intel SOF); without it the handheld is silent"

        # The Wi-Fi firmware is a family: Intel publishes one file per supported
        # API version and the kernel picks the newest it understands. One is
        # enough; which one this board actually loads is a bench question.
        say "The Wi-Fi firmware (Intel BE201)"
        aq_fw_family /usr/lib/firmware iwlwifi-bz-b0-fm-c0 1 \
            "the Wi-Fi chip's program; without it the desktop says there is no Wi-Fi adapter"

        say "The drivers that go with them"
        aq_have_module xe "graphics (Intel Arc 140V)"
        aq_have_module xpad "the built-in controller in XInput mode — this is what makes the sticks and buttons work at all"
        aq_have_module iwlwifi "Wi-Fi (Intel BE201)"
        aq_have_module snd-sof-pci-intel-lnl "the sound processor"
        aq_have_module msi-wmi-platform "MSI's own platform chip — on kernel 7.2 this reads fan speed and nothing else"

        # ----------------------------------------------------------------------
        # hid-msi: PRINTED, NOT REQUIRED — and the day it appears matters
        # ----------------------------------------------------------------------
        # hid-msi is the kernel driver that would give this machine its M1 and
        # M2 paddles, switching the pad between its modes, its lights and its
        # rumble strength. It was merged for Linux 7.3 and is NOT in Fedora's
        # 7.2. Its absence is expected and is not a build failure.
        #
        # This check exists so that the DAY Fedora's kernel gains it, the build
        # log says so in plain words — because that is the day round two of the
        # Claw image starts, and nobody would otherwise notice.
        say "hid-msi — the driver that arrives with kernel 7.3 (expected: not here yet)"
        AQ_HIDMSI="$(aq_module_path hid-msi)"
        if [ -n "${AQ_HIDMSI}" ]; then
            echo "  FOUND: ${AQ_HIDMSI}"
            echo
            echo "  ⚠️ THIS IS NEWS. hid-msi is in this image's kernel, which means"
            echo "  the kernel has moved to 7.3 or Fedora has backported the driver."
            echo "  That unlocks, on the Claw: the M1 and M2 paddles, switching the"
            echo "  controller between XInput / DInput / Desktop from Linux, the"
            echo "  lights, and rumble strength. It also means InputPlumber's own"
            echo "  mode-switching udev rules start firing."
            echo "  WHAT TO DO: open round two of the Claw image. Nothing in this"
            echo "  build needs changing today — this is a notice, not a fault."
            AQ_HIDMSI_NOTE="PRESENT (${AQ_HIDMSI}) — the kernel has gained it. M1/M2, mode switching, RGB and rumble become possible; round two of this image is due."
        else
            ok "hid-msi is not in this kernel, which is exactly what kernel 7.2 means"
            echo "  Consequence, said plainly: the M1 and M2 paddles do nothing, the"
            echo "  controller cannot be switched between its modes from Linux, and"
            echo "  there is no control over the lights or the rumble strength."
            echo "  All of that arrives with kernel 7.3. Nothing is broken."
            AQ_HIDMSI_NOTE="not in this kernel (expected on 7.2). M1/M2, mode switching, RGB and rumble all wait for kernel 7.3."
        fi
        ;;
esac

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

case "${HANDHELD_TARGET}" in
    ally)
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
        ;;
    claw)
        cat > "${AQ_HANDHELD_NOTE}" << EOF
AquariusOS — the Claw handheld image (aquarius-os-handheld-claw)

This image is the AMD/Intel AquariusOS, built for ONE computer: the
MSI Claw 8 AI+ (A2VM), board ${AQ_HH_BOARD}, an Intel "Lunar Lake" machine.
It starts straight into Game Mode.

This is ROUND ONE. It ships what Fedora's kernel 7.2 can do today, and
it says plainly what it cannot. Nothing here is a fault to report;
everything marked "kernel 7.3" is code that exists and is simply not in
this kernel yet.

InputPlumber (the program that gathers the built-in pad and its extra
buttons into one controller Steam understands):

    version: ${AQ_IP_EVR}
    note:    ${AQ_IP_NOTE}

    The version worth having on this machine is 0.80.0 or newer. That is
    what carries the fix (PR #714, 14 September 2026) which makes the
    Guide button — the Xbox button in the middle of the pad — open
    Steam's menu. There is no upper limit: the 0.79.5 thumbstick
    problem is an ASUS Ally problem and does not apply here.

Steam's power slider (TDP):

    ${AQ_TDP_NOTE}

The kernel driver for this pad (hid-msi):

    ${AQ_HIDMSI_NOTE}

Our own udev rule, 50-aquarius-claw-controller.rules, stops the built-in
controller waking the machine — so a thumbstick nudged in a bag cannot
switch the handheld on. It is OURS and it is untested until the bench;
no other distribution ships one for this machine.

M1/M2, mode switch, RGB, rumble: kernel 7.3

Also not here, and not coming: there is no gyro. Nothing on Linux
exposes a motion sensor on this machine, so Steam's gyro settings will
be empty. That is expected.

Before anything else, the pad must be in XInput mode. That is set from
Windows, in MSI Center M, and kernel 7.2 cannot change it. Check with:

    aq handheld status

which also prints every other answer a bench session needs. Run it first
and paste all of it.

If the screen is black or scrambled, press Ctrl+Alt+F3 for a text login,
then:

    aq game boot off
    sudo systemctl reboot

and the machine comes back to the ordinary login screen.

The full guide is in the repository at docs/restart/handheld-claw.md.
EOF
        ;;
esac

sed 's/^/       /' "${AQ_HANDHELD_NOTE}"
aq_file_has "${AQ_HANDHELD_NOTE}" "version: ${AQ_IP_EVR}" \
    "the exact InputPlumber version is written into the image"
aq_file_has "${AQ_HANDHELD_NOTE}" 'Ctrl\+Alt\+F3' \
    "the note tells a person how to get out of a black screen"
if [ "${HANDHELD_TARGET}" = "claw" ]; then
    aq_file_has "${AQ_HANDHELD_NOTE}" 'M1/M2, mode switch, RGB, rumble: kernel 7\.3' \
        "the note says out loud what waits for kernel 7.3"
    aq_file_has "${AQ_HANDHELD_NOTE}" "${AQ_HH_BOARD}" \
        "and it names the one board this image is for"
fi

aq_finish "Handheld layer (${AQ_HH_NAME}, board ${AQ_HH_BOARD})"
