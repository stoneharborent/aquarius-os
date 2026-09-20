#!/usr/bin/bash
# ==============================================================================
# STEP 7f — Game Mode (Phase G1)
# ==============================================================================
# WHAT THIS STEP IS FOR, IN PLAIN ENGLISH
#
# AquariusOS is a creator's machine that also games. Step 68 made the games run.
# This step gives them the OTHER interface: **Game Mode** — Steam owning the
# whole screen, driven with a controller from the sofa, exactly as a Steam Deck
# does it. Same computer, same games, same drives; a completely different face.
#
# Three things have to exist for that:
#
#   1. A SESSION AT THE LOGIN SCREEN called "Steam Big Picture", which starts
#      gamescope (a tiny compositor) with Steam's console interface inside it.
#      That comes ready-made from Terra as `gamescope-session-steam` plus
#      `gamescope-session`, and we take both of them completely unmodified.
#
#   2. A WAY TO SWITCH, both directions, WITHOUT A PASSWORD. This is the part
#      nobody had written for us and it is most of this file's reason to exist —
#      see "THE SWITCH" below.
#
#   3. A CHOICE ABOUT COLD BOOTS. /etc/aquarius/login-mode. Both desktop images
#      ship `desktop`, which means switching this computer on does exactly what
#      it has always done: the login screen. `game` is what the future handheld
#      image will ship, and anybody can set it by hand with `aq game boot on`.
#
# ⚠️ WHAT CHANGED ON 2026-09-17. Until that day, decision 6 of 2026-09-02 said
# AquariusOS would have no Game Mode at all. Royce reversed it, on the record,
# in docs/decision-2026-09-17-game-mode-and-handheld.md: editing works now, and
# a machine that games from the sofa is worth having. The "what is NOT here"
# section of docs/restart/gaming.md was rewritten the same day.
#
# ------------------------------------------------------------------------------
# THE SWITCH, AND WHY IT IS OURS TO WRITE
# ------------------------------------------------------------------------------
# Every Linux with a Game Mode does the switch as a FULL LOGOUT — your desktop
# really closes. Two compositors cannot sanely share one graphics card, and on
# NVIDIA the attempt freezes the machine (proved on the bench, 2026-09-17).
# Royce accepted that on the same day.
#
# The tricky part is getting back IN without typing a password, because you
# cannot type a password with a game controller. Valve's own answer
# (`steamos-manager`) is hard-wired to a login screen called SDDM, which
# AquariusOS does not use and will not switch to: under SDDM, GNOME has no lock
# screen at all — verified in gnome-shell's own source — and losing the lock
# screen to gain a games menu is the wrong trade for a working machine.
#
# So we do it the way **Nobara** does, which is the one distribution that does
# this switch with GDM, and whose scripts we read line by line:
#
#   * write which session to start next into the account's own file under
#     /var/lib/AccountsService/users/;
#   * switch on GDM's *timed* login (not its automatic login — that fires once
#     per boot and is then spent, which breaks the second half of every switch);
#   * `systemctl reload gdm` — never restart, which fails.
#
# Our three small programs that do it are in system_files/ and each carries its
# own long explanation:
#   /usr/libexec/os-session-select     the hinge; what Steam's own script calls
#   /usr/libexec/aquarius-session-root the root half, behind polkit
#   /usr/libexec/aquarius-game-mode    the "Game Mode" button
#   /usr/libexec/aquarius-login-mode   the once-per-boot cold-boot setting
#
# ------------------------------------------------------------------------------
# WHAT IS DELIBERATELY NOT HERE
# ------------------------------------------------------------------------------
#   * No handheld device support. No Steam Deck, ROG Ally or Legion Go drivers,
#     no gyro, no TDP sliders, no fan curves, no InputPlumber, no PowerStation.
#     That is phase G2, it targets exactly one device Royce owns (his ROG Ally),
#     and it is not this step.
#   * No boot-into-Game-Mode on the desktop images. The setting exists and is
#     shipped set to `desktop`; a cold boot is unchanged.
#   * `steamos-manager` is installed but NOT switched on — see section 4.
#
# Plain-language guide to all of it: docs/restart/game-mode.md
# ==============================================================================

set -euo pipefail

# shellcheck source=build_files/aq-lib.sh
source /ctx/build_files/aq-lib.sh

FEDORA="$(rpm -E %fedora)"
NVIDIA="${NVIDIA:-0}"

AQ_SESSION_FILE="/usr/share/wayland-sessions/gamescope-session-steam.desktop"
AQ_NOTE_DIR="/usr/share/aquarius/gaming"

# ==============================================================================
# 1. Terra — added, used for three packages, and taken back out
# ==============================================================================
# EXACTLY THE SAME DANCE AS STEP 68, AND FOR EXACTLY THE SAME REASONS. Terra is
# where the Game Mode packages live (nobody else builds them for Fedora). It is
# added, switched off so that nothing else in this build can quietly take a
# Terra package instead of Fedora's, switched on for one command at a time, and
# then REMOVED from the image altogether — because a repository file that pairs
# a signed catalogue with a local-path key stops the installer ISO from building
# at all (osbuild/bootc-image-builder#1188). Step 68's own header tells that
# story in full; this step simply must not undo it.
#
# ⚠️ WHY THIS STEP RE-ADDS TERRA INSTEAD OF SHARING STEP 68's. Because step 68
# takes Terra back out before it finishes, on purpose, and that removal is the
# thing the installer ISO depends on. Piggy-backing would mean one step's
# clean-up depending on another step's ordering — the kind of coupling that
# breaks silently a year later when somebody moves a line in the Containerfile.
# Re-adding costs one repository fetch and is impossible to get wrong.
# ⚠️ AND terra-gpg-keys IS ASKED FOR BY NAME. Terra arrives as two packages:
# `terra-release` owns the repository file, and `terra-gpg-keys` owns the
# signing key at /etc/pki/rpm-gpg/RPM-GPG-KEY-terra${FEDORA}. dnf normally
# brings the second one along by itself as a dependency, and on the very first
# install it does. Naming it here anyway costs nothing and removes a whole class
# of "it worked yesterday": if it is ever already installed for any reason, dnf
# would install `terra-release` alone and quietly not lay the key file down —
# which is exactly how build 35301818660 failed on 2026-09-18. The removal
# section further down now takes both packages out for the same reason.
say "Adding Terra again (the repository Game Mode comes from)"

aq_dnf install --refresh --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release terra-gpg-keys

aq_installed terra-release terra-gpg-keys

# ------------------------------------------------------------------------------
# The key really has to be ON DISK, not merely owned by an installed package
# ------------------------------------------------------------------------------
# Trust content, never timestamps — and here, never the package database either.
# A package can be installed while the file it owns has been deleted from under
# it, and that is precisely the state a previous step's clean-up can leave.
# So the question asked is "is the key file there", and if it is not, the answer
# is to make dnf lay it down again with `reinstall`, which re-writes every file
# a package owns whether or not it thinks they are missing.
AQ_TERRA_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-terra${FEDORA}"

if [ ! -s "${AQ_TERRA_KEY}" ]; then
    echo "  ${AQ_TERRA_KEY} is not on the disk, although its package is installed."
    echo "  That means something deleted the file and left the package. Putting it back."
    aq_dnf reinstall --nogpgcheck \
        --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
        terra-gpg-keys || true
fi

if [ -s "${AQ_TERRA_KEY}" ]; then
    ok "Terra's signing key is really on the disk (${AQ_TERRA_KEY})"
else
    echo "  what terra-gpg-keys believes it owns:"
    rpm -ql terra-gpg-keys 2> /dev/null | sed 's/^/       /' || true
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

# dnf5 spells it `--enable-repo`; dnf4 spelled it `--enablerepo`. Step 68 works
# out which one this build's dnf understands, and so does this one, for the same
# reason: the answer has changed under us before.
say "Checking Terra can be switched on for one command"
AQ_TERRA_FLAG=""
for flag in --enable-repo=terra --enablerepo=terra; do
    if aq_dnf repoquery "${flag}" --queryformat '%{name}' gamescope-session > /tmp/aq-terra-probe.txt 2>&1; then
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
# 2. The three Game Mode packages
# ==============================================================================
# WHAT EACH ONE IS, because none of these names explain themselves:
#
#   gamescope-session        The plumbing. A script called
#                            `gamescope-session-plus` that works out your
#                            screen, your refresh rate and which options this
#                            build of gamescope understands, and then starts it.
#                            It needs nothing but `gamescope` itself, which
#                            Fedora already gave us in step 68.
#
#   gamescope-session-steam  The Steam-shaped half: the session file the login
#                            screen lists as "Steam Big Picture", and the small
#                            scripts Steam calls when you press things in its
#                            menus — including `steamos-session-select`, which
#                            is what makes "Switch to Desktop" work.
#
#   steamos-manager          Valve's own background service for the sliders on
#                            a handheld — power limit, fan, performance. Not
#                            used on a desktop PC; installed now so the future
#                            ROG Ally image (phase G2) does not need a different
#                            base image. ⚠️ Section 4 checks it is switched OFF.
#
# ⚠️ WE TAKE ALL THREE COMPLETELY UNMODIFIED. Not one line is patched. Every
# AquariusOS-specific behaviour is added ALONGSIDE them, through the hooks they
# already provide: an `os-session-select` they look for and we supply, and an
# environment file the session reads. A fork of a session script is a fork we
# would be maintaining for ever, and the first upstream fix we missed would be a
# bench day nobody could explain.
say "The Game Mode packages, with Terra switched on for this one command"
aq_dnf install "${AQ_TERRA_FLAG}" gamescope-session gamescope-session-steam steamos-manager

say "Where the Game Mode packages came from"
rpm -q --queryformat '       %{NAME}-%{VERSION}-%{RELEASE}  (packaged by: %{VENDOR})\n' \
    gamescope-session gamescope-session-steam steamos-manager 2>&1 || true

aq_installed gamescope-session gamescope-session-steam steamos-manager

# ------------------------------------------------------------------------------
# Terra back out again
# ------------------------------------------------------------------------------
say "Removing Terra now its packages are installed (the installer ISO needs it gone)"

# ⚠️ AND terra-gpg-keys COMES OUT TOO. THIS ONE LINE IS A WHOLE BUILD FAILURE,
# SO HERE IS THE TRAP IN FULL (it stopped build 35301818660 on 2026-09-18).
#
# Terra arrives as TWO packages, not one. `terra-release` owns the repository
# file; a second package, `terra-gpg-keys`, owns the signing key itself —
# /etc/pki/rpm-gpg/RPM-GPG-KEY-terra44 — and dnf pulls it in silently as a
# dependency. Removing only `terra-release` and then deleting the key FILE by
# hand leaves `terra-gpg-keys` still INSTALLED, with the package database
# believing it owns a file that is no longer on the disk.
#
# Nothing looks wrong at that point. The trap springs later:
#
#   * step 71 installs `terra-release` again, to add Terra for the Game Mode
#     packages;
#   * dnf looks at `terra-gpg-keys`, sees it is already installed, and does
#     nothing — a package manager does not re-lay files for a package that is
#     already there;
#   * so the key file never comes back, the signing key is missing, and the
#     step fails with "Terra's signing key for Fedora 44 is not there".
#
# The rule this now follows: remove BOTH packages, so the two steps leave the
# machine in exactly the same state and the second one starts from the same
# place the first one did.

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

# And Fedora still owns the graphics driver. Step 68 asks this too; a second
# visit from Terra is a second chance to get it wrong, so it is asked again.
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
# 3. The login screen really can offer Game Mode
# ==============================================================================
# The session file is the whole contract with GDM: a file in
# /usr/share/wayland-sessions/ is a thing the login screen lists and can start.
# If it is missing, everything else in this step is plumbing to nowhere.
say "The login screen has a Game Mode to offer"

if [ -r "${AQ_SESSION_FILE}" ]; then
    ok "$(basename "${AQ_SESSION_FILE}") is installed"
    sed 's/^/       /' "${AQ_SESSION_FILE}"
else
    bad "${AQ_SESSION_FILE} is missing — the login screen would have no Game Mode to offer"
fi

# It has to actually START something, and that something has to be here.
aq_file_has "${AQ_SESSION_FILE}" '^Exec=gamescope-session-plus steam$' \
    "the Game Mode session starts 'gamescope-session-plus steam'"

if [ -x /usr/bin/gamescope-session-plus ]; then
    ok "/usr/bin/gamescope-session-plus is installed and can be run"
else
    bad "/usr/bin/gamescope-session-plus is missing — the Game Mode session would fail the moment it was chosen"
fi

echo "Every session the login screen can now offer:"
ls -1 /usr/share/wayland-sessions/ 2> /dev/null | sed 's/^/       /'

# All three have to be there: two desktops and Game Mode. A missing desktop
# would mean a switch with nowhere to come back to.
for aq_s in gnome plasma gamescope-session-steam; do
    if [ -r "/usr/share/wayland-sessions/${aq_s}.desktop" ]; then
        ok "the login screen can start '${aq_s}'"
    else
        bad "/usr/share/wayland-sessions/${aq_s}.desktop is missing"
    fi
done

# ⚠️ AND GDM IS STILL THE LOGIN SCREEN. This step must never change that. It is
# asked here because installing Valve's session packages is exactly the kind of
# thing that could drag SDDM in as a dependency, and the day it does, GNOME
# silently loses its lock screen (verified in gnome-shell's source: it only
# makes a lock screen if the GDM daemon answers on D-Bus).
say "GDM is still the login screen, and SDDM is nowhere near this image"
if rpm -q sddm > /dev/null 2>&1; then
    bad "sddm is installed — something pulled it in, and GNOME loses its lock screen on a machine that uses it"
else
    ok "sddm is NOT installed"
fi
if systemctl is-enabled gdm.service > /dev/null 2>&1; then
    ok "GDM is still switched on"
else
    bad "GDM is not switched on — nothing would draw a login screen"
fi

# ==============================================================================
# 4. steamos-manager is installed and switched OFF
# ==============================================================================
# ⚠️ THIS IS A DELIBERATE DECISION AND IT IS NOT AN OVERSIGHT.
#
# steamos-manager is Valve's service for the things a *handheld* has: a power
# limit slider, a fan curve, a performance overlay control. On a desktop PC with
# a 5080 in it there is nothing for it to manage. It is installed because the
# ROG Ally image (phase G2) will want it and because keeping one base image is
# worth more than the few megabytes — but it is NOT started.
#
# Two reasons for leaving it off, and the second is the important one:
#
#   1. Nothing on a desktop needs it.
#   2. It also contains Valve's OWN session-switching code, which is hard-wired
#      to SDDM: it refuses to manage sessions unless /usr/lib/sddm/sddm.conf.d/
#      holo.conf exists. AquariusOS switches sessions its own way, with GDM. Two
#      mechanisms for one job is how a machine ends up in a login loop that
#      nobody can read. So Valve's half stays asleep, and the check below proves
#      the file that would wake it is not in this image.
#
# It has not been tested on a machine with no handheld hardware — that was an
# open question in the G1 spec and it stays open until the Ally is on the bench.
# Leaving it switched off is how that question stays harmless.
say "steamos-manager is installed, and its session switching is switched off"

if [ -e /usr/lib/sddm/sddm.conf.d/holo.conf ] || [ -e /etc/sddm.conf.d/holo.conf ]; then
    bad "an SDDM 'holo.conf' is in this image — Valve's session switching would wake up and fight ours"
else
    ok "no SDDM holo.conf, so Valve's own session switching can never start"
fi

for aq_unit in steamos-manager.service steamos-manager-user.service; do
    if [ -e "/usr/lib/systemd/system/graphical.target.wants/${aq_unit}" ] \
        || [ -e "/usr/lib/systemd/system/multi-user.target.wants/${aq_unit}" ] \
        || [ -e "/etc/systemd/system/multi-user.target.wants/${aq_unit}" ]; then
        bad "${aq_unit} has been switched on — G1 installs steamos-manager and leaves it asleep"
    else
        ok "${aq_unit} is not switched on"
    fi
done

# ==============================================================================
# 5. Our own half of the switch
# ==============================================================================
# Everything here arrived with system_files/ at step 50. It is RE-INSTALLED from
# the build context and then compared, for one specific reason:
#
# ⚠️ /usr/libexec/os-session-select IS A FILE NAME UPSTREAM ALSO USES. It is the
# hook Steam's own `steamos-session-select` looks for, and some distributions
# (Nobara, for one) ship their own copy of it inside the very package we install
# in section 2. If a future Terra build starts doing the same, its copy would
# have landed on top of ours a moment ago and the switch would quietly become
# somebody else's — pointed at a login screen we do not use. So: put ours back,
# then prove byte-for-byte that ours is what is on the disk. The same discipline
# step 40 uses for aquarius-files, and for the same kind of reason.
say "Our own half of the switch"

for aq_f in \
    usr/libexec/os-session-select \
    usr/libexec/aquarius-session-root \
    usr/libexec/aquarius-game-mode \
    usr/libexec/aquarius-login-mode \
    usr/libexec/aquarius-bluetooth-wake \
    usr/libexec/ogc/os-update; do
    install -Dm755 "/ctx/system_files/${aq_f}" "/${aq_f}"
    if cmp -s "/ctx/system_files/${aq_f}" "/${aq_f}"; then
        ok "/${aq_f} is ours, byte for byte"
    else
        bad "/${aq_f} is not the file this repository ships — something replaced it"
    fi
done

# The three read-only files that go with them.
for aq_f in \
    usr/share/applications/aquarius-game-mode.desktop \
    usr/share/polkit-1/actions/org.aquariusos.gamemode.policy \
    usr/share/polkit-1/rules.d/51-aquarius-game-mode.rules \
    etc/aquarius/login-mode \
    etc/gamescope-session-plus/sessions.d/steam; do
    install -Dm644 "/ctx/system_files/${aq_f}" "/${aq_f}"
    if cmp -s "/ctx/system_files/${aq_f}" "/${aq_f}"; then
        ok "/${aq_f} is ours, byte for byte"
    else
        bad "/${aq_f} is not the file this repository ships"
    fi
done

# ------------------------------------------------------------------------------
# The launcher's icon: Steam's own, with a controller badge
# ------------------------------------------------------------------------------
# The app grid entry is called "Game Mode" and wears Steam's icon with a small
# controller in the bottom-right corner — the same idea as SteamOS's "Return
# to Gaming Mode" icon, which is Steam's with a small arrow. The badge is a
# committed drawing (branding/icons/game-mode-badge.svg, rendered to a PNG in
# system_files/usr/share/aquarius/branding/ — the folder this build can reach);
# Steam's icon is Valve's and only exists on the machine, so the two are put
# together HERE, by build_files/aq-game-mode-icon.py, with the GdkPixbuf
# library GNOME already has. That is the one picture in AquariusOS made during
# a build, and the script's header says why.
#
# The result goes into hicolor, which both Aquarius icon themes inherit, so it
# shows on GNOME and on KDE Plasma without either theme listing it.
say "The Game Mode icon: Steam's, with a controller badge"
if python3 /ctx/build_files/aq-game-mode-icon.py /ctx/system_files/usr/share/aquarius/branding/game-mode-badge.png /usr/share/icons \
    > /tmp/aq-game-mode-icon.txt 2>&1; then
    sed 's/^/       /' /tmp/aq-game-mode-icon.txt
else
    bad "the Game Mode icon could not be made — the launcher would show a generic icon"
    sed 's/^/       /' /tmp/aq-game-mode-icon.txt
fi
rm -f /tmp/aq-game-mode-icon.txt

# Read the finished files back: a PNG states its own size in its first bytes,
# and the folder it sits in must agree (the rule from build_files/56-aquarius-icons.sh).
aq_icon_ok=0
for aq_n in 16 24 32 48 64 128 256 512; do
    aq_p="/usr/share/icons/hicolor/${aq_n}x${aq_n}/apps/aquarius-game-mode.png"
    [ -s "${aq_p}" ] || continue
    aq_wh="$(python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(24); print(*struct.unpack(">II", d[16:24]))' "${aq_p}")"
    if [ "${aq_wh}" = "${aq_n} ${aq_n}" ]; then
        aq_icon_ok=$((aq_icon_ok + 1))
    else
        bad "${aq_p} is ${aq_wh}, not ${aq_n} ${aq_n}"
    fi
done
if [ "${aq_icon_ok}" -ge 5 ]; then
    ok "aquarius-game-mode.png exists at ${aq_icon_ok} sizes, each the size its folder says"
else
    bad "aquarius-game-mode.png exists at only ${aq_icon_ok} sizes — Valve ships at least five"
fi
aq_file_has /usr/share/applications/aquarius-game-mode.desktop '^Icon=aquarius-game-mode$' \
    "and the Game Mode launcher asks for it by that name"

# ------------------------------------------------------------------------------
# The cold-boot setting ships as `desktop`, and that is a promise
# ------------------------------------------------------------------------------
# ⚠️ IF THIS EVER SHIPS AS `game` ON A DESKTOP IMAGE, every machine following
# these images would, at its next update and restart, stop showing a login
# screen and boot into Steam instead. Nothing else in this step could cause a
# change that large, so it is checked on its own.
say "A cold boot on this image is unchanged: the login screen"
aq_file_has /etc/aquarius/login-mode '^mode=desktop$' \
    "/etc/aquarius/login-mode ships as 'desktop' — switching this computer on shows the login screen, exactly as before"

if grep -q '^mode=game' /etc/aquarius/login-mode 2> /dev/null; then
    bad "/etc/aquarius/login-mode says 'game' — this image would boot straight into Steam on every machine that takes it"
fi

# ------------------------------------------------------------------------------
# Steam's own update button answers honestly
# ------------------------------------------------------------------------------
# Steam calls `steamos-update check` and expects exit code 7 to mean "nothing to
# update". Our answer is at /usr/libexec/ogc/os-update, which is where the
# package's script looks. Asked here, of the real file, in the finished image —
# a shim that returns the wrong number would make Steam sit at a progress bar
# for ever.
say "Steam is told, honestly, that it does not update this computer"
if [ -x /usr/bin/steamos-update ]; then
    ok "/usr/bin/steamos-update is installed (it comes from gamescope-session-steam)"
else
    bad "/usr/bin/steamos-update is missing — Steam's update button would do nothing at all"
fi

set +e
/usr/libexec/ogc/os-update check > /tmp/aq-osupdate.txt 2>&1
AQ_OSUPDATE_CODE=$?
set -e
sed 's/^/       /' /tmp/aq-osupdate.txt
rm -f /tmp/aq-osupdate.txt
if [ "${AQ_OSUPDATE_CODE}" -eq 7 ]; then
    ok "our os-update answers 7, which is Steam's word for 'there is no update'"
else
    bad "our os-update answered ${AQ_OSUPDATE_CODE}, not 7 — Steam would try to update this operating system"
fi

# ------------------------------------------------------------------------------
# The services, switched on from /usr
# ------------------------------------------------------------------------------
# All three shipped as links in system_files/ at step 50; this proves the links
# really are there and really point at something. The long explanation of why
# AquariusOS never uses `systemctl enable` is in build_files/aq-lib.sh.
# ------------------------------------------------------------------------------
# The 2026-09-19 fixes, read back out of the image
# ------------------------------------------------------------------------------
# Four things went wrong on the first real use of the switch (docs/restart/
# game-mode.md, "What went wrong on 2026-09-19"). Each fix is checked here by
# reading the finished file, not by trusting the copy step.
say "The way back from Game Mode ends the session (the 2026-09-19 hang)"
# Steam's own script `exec`s ours, so ours has to be the one that ends Game
# Mode. If that line ever goes, "Switch to Desktop" hangs on its card for ever.
aq_file_has /usr/bin/steamos-session-select 'os-session-select' \
    "Steam's steamos-session-select hands over to an os-session-select hook"
aq_file_has /usr/bin/steamos-session-select '/usr/libexec/os-session-select' \
    "and it looks in /usr/libexec, which is where ours is"
aq_file_has /usr/libexec/os-session-select '^aq_end_game_session\(\)' \
    "our os-session-select knows how to end Game Mode itself"
aq_file_has /usr/libexec/os-session-select 'steam -shutdown' \
    "and asks Steam to close, the way Steam's own script would have"

say "Game Mode starts at the screen's own resolution"
aq_file_has /etc/gamescope-session-plus/sessions.d/steam '^[[:space:]]*SCREEN_WIDTH=' \
    "the session file works out SCREEN_WIDTH from the connected screen"
aq_file_has /usr/share/gamescope-session-plus/gamescope-session-plus 'CLIENT_CONFIG_DIR_ETC=/etc/gamescope-session-plus/sessions.d' \
    "and Terra's session script really reads /etc/gamescope-session-plus/sessions.d"
aq_file_has /usr/share/gamescope-session-plus/gamescope-session-plus 'SCREEN_WIDTH' \
    "and really turns SCREEN_WIDTH into a gamescope size"
if bash -n /etc/gamescope-session-plus/sessions.d/steam; then
    ok "the session file is valid shell (it is sourced, so a typo there would break Game Mode)"
else
    bad "the session file does not parse — Game Mode would fail to start"
fi

# ------------------------------------------------------------------------------
# Bench 2, 2026-09-19 — bug 1: the switch writes BOTH logins
# ------------------------------------------------------------------------------
# GDM 50's daemon refuses the login screen's timed login unless the automatic-
# login keys are set for the same person (daemon/gdm-session.c,
# gdm_session_handle_client_begin_auto_login). Writing only the TimedLogin
# lines — what this image did until 2026-09-19 — is what put a password box in
# the middle of a switch, and made it flicker while Royce typed. These checks
# fail the build if any part of that fix ever goes missing.
say "A switch writes the timed login AND the automatic one (the GDM 50 rule)"
aq_file_has /usr/libexec/aquarius-session-root '^aq_switch_login\(\)' \
    "the root helper has one job for the whole password-free switch login"
aq_file_has /usr/libexec/aquarius-session-root '"AutomaticLogin=\$\{account\}"' \
    "and that job writes the automatic-login lines as well as the timed ones"
aq_file_has /usr/libexec/aquarius-session-root 'Autologin not permitted for user' \
    "and the journal line it was diagnosed from is written down beside it"
aq_file_has /usr/libexec/aquarius-session-root '^aq_gdm_add\(\)' \
    "the two login jobs share one way of writing custom.conf, not two copies"
aq_file_has /usr/libexec/aquarius-session-root '^aq_gdm_must_say\(\)' \
    "and one way of reading it back out afterwards"
aq_file_has /usr/libexec/os-session-select 'switch-login on "\$\{USER\}"' \
    "a switch asks for switch-login, not the old timed-login"
aq_file_has /usr/libexec/os-session-select 'switch-login off' \
    "and a desktop arrival clears it again"
aq_file_has /usr/libexec/aquarius-login-mode 'switch-login off' \
    "the boot-time program clears all five lines in both of its branches"

say "Starting IN Game Mode uses the login GDM honours at boot"
aq_file_has /usr/libexec/aquarius-session-root '^aq_auto_login\(\)' \
    "the root helper can still write AutomaticLogin on its own, for a cold boot"
aq_file_has /usr/libexec/aquarius-login-mode 'auto-login on' \
    "and the boot-time program uses it for mode=game"

# ------------------------------------------------------------------------------
# Bench 3, 2026-09-20 — 'plasma' from Steam means "the desktop", never Plasma
# ------------------------------------------------------------------------------
# Steam's power menu has one button out of Game Mode, and the SteamOS script
# behind it always passes the hard-coded word `plasma` (or `desktop`, or one of
# the two `*-persistent` spellings). On AquariusOS both desktops ship, so an
# os-session-select that honoured the name whenever the session file existed
# sent EVERY "Switch to Desktop" into Plasma — including Royce's, from GNOME,
# on 2026-09-20. The fix is that there is no literal-name branch anywhere
# in that file: the remembered desktop decides, full stop. This check is here
# because the deleted line is exactly the sort of thing a future reader would
# put back thinking it was an improvement.
say "Switch to Desktop obeys the remembered desktop, not Steam's word"
if [ ! -r /usr/libexec/os-session-select ]; then
    bad "os-session-select has no literal-desktop override left — the file does not exist"
elif grep -Eq 'wayland-sessions/\$\{aq_target\}\.desktop' /usr/libexec/os-session-select; then
    bad "os-session-select still turns Steam's literal '\${aq_target}' into a session — Switch to Desktop would always land in Plasma"
else
    ok "os-session-select has no literal-desktop override left"
fi
aq_file_has /usr/libexec/os-session-select 'aq_session="\$\(aq_remembered_desktop\)"' \
    "and every word Steam can pass resolves to the desktop you came from"
aq_file_has /usr/libexec/os-session-select "asked for 'plasma' from 'Game Mode'" \
    "with the 2026-09-20 journal line written down beside it, so the next reader recognises it"

say "'aq game status' no longer calls the timed login 'a switch' on its own"
aq_file_has /usr/bin/aq 'a switch sets both; a boot into Game Mode sets the automatic ones' \
    "aq game status explains that a switch sets both sets of lines"

# ------------------------------------------------------------------------------
# Bench 2, 2026-09-19 — bug 2: the login screen must not run the tidy service
# ------------------------------------------------------------------------------
# GDM 50 runs the login screen as a systemd DYNAMIC user, `gdm-greeter`, whose
# user number comes from the 61184-65519 range — above the ordinary range, so
# `ConditionUser=!@system` does not catch it. The greeter was starting the
# tidy service twelve seconds after every logout and only failing because
# pkexec refused it. Two belts now: the unit's conditions, and a test inside
# --tidy itself.
say "The login screen's own account does not run the tidy service"
aq_file_has /usr/lib/systemd/user/aquarius-game-tidy.service '^ConditionUser=!@system$' \
    "aquarius-game-tidy.service is for people's accounts only (GDM 49 and before)"
aq_file_has /usr/lib/systemd/user/aquarius-game-tidy.service '^ConditionUser=!gdm-greeter$' \
    "and not for GDM 50's dynamic greeter account either"
aq_file_has /usr/libexec/os-session-select '^aq_not_a_person\(\)' \
    "and --tidy refuses to run for a caller who is not a person, whatever started it"
aq_file_has /usr/libexec/os-session-select '/run/gdm/\*' \
    "it knows the greeter's throwaway home folder"
aq_file_has /usr/libexec/os-session-select 'Gg\]\[Rr\]\[Ee\]\[Ee\]\[Tt\]\[Ee\]\[Rr\]' \
    "and a desktop that calls itself a Greeter"
# systemd's own opinion of the file, reported honestly: a container where the
# manager cannot start is said out loud rather than counted as a green tick
# nobody earned. The content checks above are what really guard this unit.
# (Same shape as step 79's check — see the note there.)
if aq_have systemd-analyze; then
    aq_tidy_verdict="$(systemd-analyze verify --user /usr/lib/systemd/user/aquarius-game-tidy.service 2>&1 || true)"
    printf '%s\n' "${aq_tidy_verdict}" | sed 's/^/  /'
    if printf '%s' "${aq_tidy_verdict}" | grep -Eqi "failed to initialize manager|failed to lookup runtimedirectory"; then
        echo "  note   systemd-analyze could not start inside this container, so it"
        echo "         did not read the file. The checks above are what guard it."
    elif printf '%s' "${aq_tidy_verdict}" | grep -Eqi "unknown (key|lvalue)|failed to parse"; then
        bad "systemd cannot understand part of aquarius-game-tidy.service (see above)"
    else
        ok "systemd read the tidy service and understood every line, both ConditionUser= lines included"
    fi
fi

say "The Game Mode services are switched on, in the way an update cannot lose"
aq_unit_is_on_from_usr aquarius-login-mode.service \
    "makes the login screen match /etc/aquarius/login-mode at every boot"

for aq_u in aquarius-game-tidy.service aquarius-bluetooth-wake.service; do
    aq_link="/usr/lib/systemd/user/graphical-session.target.wants/${aq_u}"
    if [ -L "${aq_link}" ] && [ -e "${aq_link}" ]; then
        ok "${aq_u} is switched on from /usr for every desktop session"
    else
        bad "${aq_link} is missing or points at nothing"
    fi
done

# ------------------------------------------------------------------------------
# And `aq game` exists
# ------------------------------------------------------------------------------
say "The 'aq game' command is in this image"
if /usr/bin/aq game --help > /tmp/aq-game-help.txt 2>&1; then
    ok "'aq game --help' runs"
    head -3 /tmp/aq-game-help.txt | sed 's/^/       /'
else
    bad "'aq game --help' does not run — the command is missing or broken"
    sed 's/^/       /' /tmp/aq-game-help.txt
fi
rm -f /tmp/aq-game-help.txt

# ==============================================================================
# 6. NVIDIA only: our own gamescope
# ==============================================================================
# ⚠️ READ build_files/72-gamescope-build.sh BEFORE CHANGING ANYTHING HERE. It
# carries the whole explanation: NVIDIA's driver can hand gamescope scattered
# graphics memory for the picture it is about to put on screen, the display
# hardware reads straight past the end of it, and what you see is a staircase-
# shaped band of somebody else's window across the middle of Steam. NVIDIA bug
# 5240452, photographed on Royce's RTX 5080 four times on 2026-09-17, no fix
# date. AMD and Intel are unaffected, which is why this whole section is skipped
# on that image and it keeps Fedora's gamescope.
#
# ------------------------------------------------------------------------------
# HOW OURS IS INSTALLED, AND WHY NOT ON TOP OF FEDORA'S
# ------------------------------------------------------------------------------
# The obvious thing is to overwrite /usr/bin/gamescope. We deliberately do not:
# that leaves the package database claiming to own a file that is not the one it
# installed, and it would change the program every OTHER use of gamescope on
# this machine gets — per-game launch options, for instance, where gamescope
# runs INSIDE the desktop and where this bug cannot happen, because the desktop
# is the one talking to the screen.
#
# So ours goes in beside it, as /usr/bin/aquarius-gamescope, and the Game Mode
# session is pointed at it through GAMESCOPE_BIN — a variable the session script
# already reads, so nothing is forked. The same drop-in also switches on the fix
# itself (`gamescope_drm_gbm_scanout=1`), which gamescope reads from the
# environment like any of its settings.
#
# ⚠️ AND IT NEEDS ONE CAPABILITY. gamescope asks the system for real-time
# scheduling so the picture does not stutter, and Linux only allows that with
# CAP_SYS_NICE. Fedora's own package grants exactly that to its copy; ours needs
# the same grant or it runs with worse timing and says so in its log. This is
# the one place in this whole repository where a build step grants a capability,
# it is granted to a file we compiled ourselves, and it matches what the
# distribution does with the same program.
case "${NVIDIA}" in

    1)
        say "Our own gamescope, for the NVIDIA scan-out bug"

        if [ ! -x /ctx-gamescope/out/usr/bin/gamescope ]; then
            bad "the builder stage produced no gamescope at /ctx-gamescope/out/usr/bin/gamescope — check the 'gamescope-build' stage in the Containerfile"
        else
            install -Dm755 /ctx-gamescope/out/usr/bin/gamescope /usr/bin/aquarius-gamescope

            if cmp -s /ctx-gamescope/out/usr/bin/gamescope /usr/bin/aquarius-gamescope; then
                ok "/usr/bin/aquarius-gamescope is the program the builder stage produced"
            else
                bad "/usr/bin/aquarius-gamescope is not the file the builder stage produced"
            fi

            # The real-time capability, and then the proof that it took.
            if setcap 'cap_sys_nice=eip' /usr/bin/aquarius-gamescope 2> /dev/null; then
                AQ_CAP="$(getcap /usr/bin/aquarius-gamescope 2> /dev/null || true)"
                echo "       ${AQ_CAP:-(nothing)}"
                case "${AQ_CAP}" in
                    *cap_sys_nice*) ok "our gamescope has cap_sys_nice, the same grant Fedora gives its own copy" ;;
                    *) bad "cap_sys_nice was set on our gamescope and getcap cannot see it" ;;
                esac
            else
                bad "could not grant cap_sys_nice to /usr/bin/aquarius-gamescope (is libcap installed in this build?)"
            fi

            # The version record, copied from the builder stage, so the finished
            # machine can say exactly which commit it is carrying.
            mkdir -p "${AQ_NOTE_DIR}"
            install -Dm644 /ctx-gamescope/out/aquarius/gamescope-build.txt \
                "${AQ_NOTE_DIR}/gamescope-build.txt"
            echo "  ${AQ_NOTE_DIR}/gamescope-build.txt:"
            sed 's/^/       /' "${AQ_NOTE_DIR}/gamescope-build.txt"
            aq_file_has "${AQ_NOTE_DIR}/gamescope-build.txt" '^commit=[0-9a-f]{40}$' \
                "the exact commit our gamescope was built from is written down in the image"

            # ------------------------------------------------------------------
            # Point the session at it, and switch the fix on
            # ------------------------------------------------------------------
            # A systemd drop-in on the session's own unit. `@.service` with no
            # instance name means "every instance", so it applies to
            # gamescope-session-plus@steam.service without naming steam here.
            mkdir -p /usr/lib/systemd/user/gamescope-session-plus@.service.d
            cat > /usr/lib/systemd/user/gamescope-session-plus@.service.d/10-aquarius-nvidia.conf << 'EOF'
# =============================================================================
# AquariusOS — the NVIDIA picture fix, on the NVIDIA image only
# =============================================================================
# WHAT THIS DOES, IN PLAIN ENGLISH
#
# Game Mode on an NVIDIA card draws a corrupted picture with the gamescope that
# Fedora ships: Steam's interface is right, and a staircase-shaped band across
# the middle of the screen shows part of some other program's window. That is
# NVIDIA's bug 5240452 and there is no fixed driver yet.
#
# So the NVIDIA image carries its own gamescope, built with the fix, at
# /usr/bin/aquarius-gamescope. These two lines are what make Game Mode use it:
#
#   GAMESCOPE_BIN                   which program the session should start. The
#                                   session script already reads this; we are
#                                   not changing the session, only answering a
#                                   question it asks.
#   gamescope_drm_gbm_scanout=1     switches the fix on. gamescope lets any of
#                                   its settings be set from the environment by
#                                   putting `gamescope_` in front of the name.
#
# ⚠️ THIS FILE IS ONLY ON THE NVIDIA IMAGE. The AMD/Intel image uses Fedora's
# gamescope, which is correct there and has no such setting.
#
# ⚠️ WHEN IT RETIRES: when the fix reaches upstream gamescope and Fedora ships
# it. Then this file, /usr/bin/aquarius-gamescope and the whole builder stage go,
# and the NVIDIA image uses Fedora's gamescope like the other one.
#
# The whole story in plain language: docs/restart/game-mode.md
# =============================================================================
[Service]
Environment=GAMESCOPE_BIN=/usr/bin/aquarius-gamescope
Environment=gamescope_drm_gbm_scanout=1
EOF

            AQ_DROPIN=/usr/lib/systemd/user/gamescope-session-plus@.service.d/10-aquarius-nvidia.conf
            aq_file_has "${AQ_DROPIN}" '^Environment=GAMESCOPE_BIN=/usr/bin/aquarius-gamescope$' \
                "the Game Mode session is pointed at our gamescope"
            aq_file_has "${AQ_DROPIN}" '^Environment=gamescope_drm_gbm_scanout=1$' \
                "the NVIDIA picture fix is switched on for the Game Mode session"

            # And the fix is really IN the program we just installed, not merely
            # switched on in a file. gamescope lists its settings in --help on
            # some builds and not others, so the honest test is to look for the
            # setting's name inside the compiled program itself.
            # `grep -a` reads a program file as if it were text, which is the
            # honest way to ask "is this name inside it" without needing the
            # `strings` tool — which the bootc base image does not carry.
            if grep -aq 'drm_gbm_scanout' /usr/bin/aquarius-gamescope 2> /dev/null; then
                ok "our gamescope really contains the 'drm_gbm_scanout' setting"
            else
                bad "our gamescope does NOT contain 'drm_gbm_scanout' — the wrong commit was built, and Game Mode would still draw a corrupted picture"
            fi
        fi

        # Fedora's gamescope must still be exactly as Fedora shipped it. If a
        # future edit ever does overwrite it, this is the only thing that would
        # notice.
        if rpm -V gamescope 2> /dev/null | grep -q '/usr/bin/gamescope'; then
            bad "Fedora's /usr/bin/gamescope has been modified — this step is meant to install beside it, never over it"
        else
            ok "Fedora's own gamescope is untouched"
        fi
        ;;

    0)
        say "The AMD / Intel image keeps Fedora's gamescope"
        echo "  The NVIDIA scan-out bug (NVIDIA 5240452) does not exist on AMD or Intel"
        echo "  graphics: their drivers do not hand out scattered memory for a picture"
        echo "  that is about to go on screen. So there is nothing to fix and nothing"
        echo "  to compile, and this image uses the gamescope Fedora packages — which"
        echo "  is always the preference when it is the right answer."
        if [ -e /usr/bin/aquarius-gamescope ]; then
            bad "/usr/bin/aquarius-gamescope is on the AMD/Intel image — it should only ever be built for NVIDIA"
        else
            ok "no hand-built gamescope on this image, as intended"
        fi
        if [ -e /usr/lib/systemd/user/gamescope-session-plus@.service.d/10-aquarius-nvidia.conf ]; then
            bad "the NVIDIA-only Game Mode settings file is on the AMD/Intel image"
        else
            ok "the NVIDIA-only settings file is not on this image, as intended"
        fi
        ;;
esac

# ==============================================================================
# 7. The note that ships in the image
# ==============================================================================
# The same idea as the gaming note step 68 leaves: somebody on the machine, with
# no internet and no repository checkout, can read what this thing is and how to
# get out of it.
say "The note that ships in the image"
mkdir -p "${AQ_NOTE_DIR}"
cat > "${AQ_NOTE_DIR}/game-mode.md" << 'EOF'
# Game Mode on AquariusOS

Game Mode is Steam owning the whole screen, driven with a controller from the
sofa — the same thing a Steam Deck shows.

## Going there

* The app grid: **Game Mode**.
* Or a terminal: `aq game`.

It warns you first, because **it closes your desktop**: every window shuts and
anything unsaved is lost. That is how Game Mode works on every Linux that has
it — two of these cannot share one graphics card — and it is not something
AquariusOS can work around.

You are not asked for a password. You cannot type one on a controller.

## Coming back

Steam's power button, bottom-left, then **Switch to Desktop**. It puts you back
in the desktop you came from, GNOME or Plasma.

## Starting the computer in Game Mode

    aq game boot on      start in Game Mode from now on
    aq game boot off     start at the login screen (what this image ships)
    aq game status       where am I, and what will a restart do

## If the screen is black or scrambled

Press **Ctrl+Alt+F3**. That gives you a text login on this machine. Log in, then:

    aq game boot off
    sudo systemctl reboot

and the login screen is back.

The full guide, including why the NVIDIA image carries its own gamescope, is in
the repository at `docs/restart/game-mode.md`.
EOF
aq_file_has "${AQ_NOTE_DIR}/game-mode.md" 'Ctrl\+Alt\+F3' \
    "the note in the image tells a person how to get out of a black screen"

aq_finish "Game Mode (phase G1)"
