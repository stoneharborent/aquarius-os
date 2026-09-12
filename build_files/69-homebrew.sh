#!/usr/bin/bash
# ==============================================================================
# STEP 69 — Homebrew: the command-line software shop
# ==============================================================================
# WHAT THIS STEP IS FOR, IN PLAIN ENGLISH
#
# Royce asked for `brew` to be on AquariusOS out of the box, on both images.
# This step is what puts it there.
#
# Homebrew (the command is `brew`) is a software shop you use by typing rather
# than by clicking. On a Mac it is the thing you run when a tutorial says
# "install ffmpeg" or "install node" or "install yt-dlp" and there is no app to
# download. It works the same way on Linux, and it is the one piece of a Mac
# workflow that a creator coming across genuinely misses.
#
# ⚠️ IT IS NOT A REPLACEMENT FOR ANYTHING WE ALREADY HAVE, and the docs say so
# out loud. Real applications with windows still come from the creator-apps
# chooser and from Aquarius Installer (docs/restart/creator-apps.md). Homebrew
# is for the other kind of software: command-line tools, small utilities,
# programming languages, the things a person follows a tutorial to install.
#
# ------------------------------------------------------------------------------
# THE PROBLEM THIS STEP HAS TO SOLVE, AND IT IS THE WHOLE REASON IT IS ODD
# ------------------------------------------------------------------------------
# Homebrew on Linux installs itself into a folder called
#
#     /home/linuxbrew/.linuxbrew
#
# and it insists on that location — it is where all of its ready-built packages
# expect to find themselves, and installing anywhere else makes it compile
# everything from source instead.
#
# On this kind of operating system, `/home` is not a real folder. It is a
# signpost pointing at `/var/home`. And `/var` is the half of the machine that
# belongs to the PERSON, not to us: an AquariusOS update replaces `/usr` whole
# and does not touch `/var` at all.
#
# So anything we install into `/var` during the build has exactly one destiny:
# it lands on a machine that installs this image from an ISO, and it NEVER
# arrives on a machine that was already running and simply ran an update.
# Half our users would have `brew` and the other half would not, depending on
# how they got here, and nothing about that would be visible to anybody.
#
# ------------------------------------------------------------------------------
# SO WE DO WHAT UNIVERSAL BLUE DOES: SHIP IT IN A BOX, UNPACK IT AT FIRST BOOT
# ------------------------------------------------------------------------------
# Universal Blue (the Bluefin/Bazzite family) hit this before we did and their
# answer is the sensible one, so we use the same shape with our own names:
#
#   1. HERE, IN THE BUILD: really install Homebrew, then pack the finished
#      folder into a single compressed file and put THAT in /usr — the half of
#      the machine every update replaces. Then delete the folder from /var, so
#      nothing of it ships in the part we are not allowed to rely on.
#
#          /usr/share/aquarius/homebrew/homebrew.tar.zst
#
#   2. ON THE MACHINE, ONCE: a small service at the first boot notices there is
#      no /var/home/linuxbrew, unpacks the box into place, and sets the
#      ownership so that anybody who can administer this computer can run
#      `brew install` without a password. That is
#      /usr/libexec/aquarius-brew-setup, started by
#      aquarius-brew-setup.service.
#
# The happy consequence: because the box lives in /usr, EVERY update carries it.
# A machine that installed AquariusOS before Homebrew existed gets `brew` the
# first time it boots after taking this image. That is the whole point of doing
# it this way rather than the obvious way.
#
# ------------------------------------------------------------------------------
# ⚠️ HOMEBREW'S INSTALLER REFUSES TO RUN AS root, AND THIS BUILD IS root
# ------------------------------------------------------------------------------
# It is not being awkward. `brew` downloads and executes other people's build
# instructions, and doing that as the account that owns the whole computer is
# genuinely a bad idea, so the installer checks and stops.
#
# A container build has nobody in it except root. Homebrew already knows this
# case and allows it: their installer looks for the file `/.dockerenv`, which is
# the marker a container build leaves behind, and permits a root install when it
# finds one. So this step creates that marker, installs, and removes it again.
#
# That is exactly what Universal Blue's own brew image does
# (github.com/ublue-os/brew), and it was the first thing checked before writing
# this — the alternative (invent a temporary account with password-free `sudo`,
# then delete it) is more moving parts and two more ways to ship something we
# did not mean to.
#
# The checks at the bottom fail the build if `/.dockerenv` is still in the
# finished image.
#
# ------------------------------------------------------------------------------
# WHO OWNS IT AFTERWARDS
# ------------------------------------------------------------------------------
# `root:wheel`, with the group allowed to write, and the "new files inherit this
# group" flag set on every folder.
#
# `wheel` is Linux's name for "the people who can administer this computer" —
# the account created when AquariusOS was installed is in it. So on a normal
# one-person machine, `brew install ffmpeg` works with no password, which is
# what anybody coming from a Mac expects. On a machine with a second, ordinary
# account, that person can USE everything brew installed and cannot change it,
# which is the correct answer rather than a limitation.
#
# The honest cost, which docs/restart/homebrew.md states plainly: `brew doctor`
# may mention that the folder is not owned by you personally. It is a note, not
# a fault, and nothing stops working because of it.
#
# Plain-English guide: docs/restart/homebrew.md
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

# Where Homebrew insists on living, said two ways. The first is the path
# Homebrew itself uses; the second is the same place spelled the way this
# operating system really stores it, which is what we must pack and delete.
BREW_PREFIX="/home/linuxbrew/.linuxbrew"
BREW_REAL="/var/home/linuxbrew"

# The box, and the folder it lives in. Under /usr on purpose — see the header.
BOX_DIR="/usr/share/aquarius/homebrew"
BOX="${BOX_DIR}/homebrew.tar.zst"

# The marker that tells Homebrew's installer "you are inside a container build,
# a root install is fine here". See the header.
DOCKERENV="/.dockerenv"

# The installer, from Homebrew themselves. Taken from their `HEAD` the same way
# their own published instructions do it, and downloaded to a file first rather
# than piped straight into a shell — so that a failed or truncated download is
# an error here, with a message, instead of half a script running.
INSTALLER_URL="https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
INSTALLER="/tmp/aq-brew-install.sh"

# The pieces that have to be in the image for the first-boot half to work.
SETUP="/usr/libexec/aquarius-brew-setup"
UPDATE="/usr/libexec/aquarius-brew-update"
SETUP_UNIT="/usr/lib/systemd/system/aquarius-brew-setup.service"
SETUP_LINK="/usr/lib/systemd/system/multi-user.target.wants/aquarius-brew-setup.service"
UPDATE_UNIT="/usr/lib/systemd/user/aquarius-brew-update.service"
UPDATE_TIMER="/usr/lib/systemd/user/aquarius-brew-update.timer"
UPDATE_LINK="/usr/lib/systemd/user/timers.target.wants/aquarius-brew-update.timer"
PROFILE="/etc/profile.d/aquarius-brew.sh"
ENVD="/usr/lib/environment.d/70-aquarius-brew.conf"

# ==============================================================================
# 1. What Homebrew needs before it will install at all
# ==============================================================================
# Homebrew's own documented requirements on Linux. Most of these are already in
# the image from earlier steps; naming them here is not duplication, it is the
# list failing in the step whose heading says why it matters.
#
#   git, curl   how brew fetches everything it fetches
#   file        how it identifies what it downloaded
#   procps-ng   supplies `pgrep`/`ps`, which brew's own scripts call
#   gcc         the compiler. Most things install as ready-built "bottles" and
#               never touch it, but the moment something has no bottle for this
#               machine, brew compiles it — and without a compiler that is a
#               wall of red text rather than a slower install.
#   zstd        the squeezer this step uses to make the box, and the one the
#               first-boot service uses to open it again.
say "What Homebrew needs"
aq_dnf install \
    git \
    curl \
    file \
    procps-ng \
    gcc \
    zstd

aq_installed \
    git \
    file \
    procps-ng \
    gcc \
    zstd

# `tar` and `curl` are checked by asking for the command rather than the package
# name, because the base image provides them under names that vary
# (curl-minimal, and tar from the base).
for cmd in tar curl bash; do
    if aq_have "${cmd}"; then
        ok "${cmd} is available"
    else
        bad "${cmd} is missing — the Homebrew installer cannot run without it"
    fi
done

# ==============================================================================
# 2. Install Homebrew, for real
# ==============================================================================
# Every part of this line is here for a reason:
#
#   touch /.dockerenv      the container marker that lets the installer run as
#                          root. Removed again a few lines below, and the checks
#                          at the bottom fail the build if it survives.
#
#   env --ignore-environment
#                          throw away everything the build has set and hand the
#                          installer a clean, known environment. Without this it
#                          inherits whatever the previous eleven build steps left
#                          lying around, and "it worked until we added an
#                          unrelated step" is not a thing anybody should have to
#                          debug.
#
#   HOME=/home/linuxbrew   where Homebrew insists on living. On this operating
#                          system /home is a signpost to /var/home, so this
#                          really writes /var/home/linuxbrew — which is why
#                          sections 3 and 4 exist at all.
#
#   NONINTERACTIVE=1       Homebrew's own switch for "nobody is sitting here to
#                          press Return". ⚠️ Without it the installer waits at a
#                          "press RETURN to continue" prompt, sees no keyboard,
#                          and the build hangs until GitHub's six-hour ceiling
#                          kills it with no useful message at all.
#
# /var/home has to exist first: on a bare Fedora bootc image it is an empty
# machine with no accounts, so nothing has created it yet.
say "Installing Homebrew (this is the real thing, not a stub)"
mkdir -p /var/home

curl --retry 3 -fsSL -o "${INSTALLER}" "${INSTALLER_URL}"
if [ -s "${INSTALLER}" ]; then
    ok "downloaded Homebrew's installer ($(wc -l < "${INSTALLER}" | tr -d ' ') lines)"
else
    bad "Homebrew's installer did not download from ${INSTALLER_URL}"
fi

touch "${DOCKERENV}"
env --ignore-environment \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    HOME=/home/linuxbrew \
    NONINTERACTIVE=1 \
    /bin/bash "${INSTALLER}" 2>&1 | sed 's/^/       /'
rm -f "${INSTALLER}"

# ⚠️ READ THE RESULT BACK, DO NOT TRUST THE EXIT CODE ABOVE. That command is a
# pipeline into sed, so its exit status belongs to sed, which always succeeds.
# The question that matters is whether the program is there, so ask that.
if [ -x "${BREW_PREFIX}/bin/brew" ]; then
    ok "${BREW_PREFIX}/bin/brew exists"
else
    bad "Homebrew did not install — ${BREW_PREFIX}/bin/brew is not there"
fi

# ==============================================================================
# 3. And it can actually answer a question
# ==============================================================================
# A `brew` that is present and broken looks identical to a working one until
# somebody types a command, which on a real machine is weeks later.
#
# ⚠️ THE CONTAINER MARKER IS STILL IN PLACE FOR THIS, AND ONLY FOR THIS. `brew`
# refuses to run as root just as its installer did, and this build is root, so
# the marker has to survive until the last thing we ask brew to do. It is
# removed on the line after, and section 6 fails the build if it is still in the
# finished image.
say "Asking the freshly installed brew what version it is"
if env HOME=/home/linuxbrew "${BREW_PREFIX}/bin/brew" --version > /tmp/aq-brew-version.txt 2>&1; then
    sed 's/^/       /' /tmp/aq-brew-version.txt
    if grep -qi '^Homebrew' /tmp/aq-brew-version.txt; then
        ok "brew runs and names itself"
    else
        bad "brew ran but did not say 'Homebrew' — read the lines above"
    fi
else
    bad "brew --version failed:"
    sed 's/^/       /' /tmp/aq-brew-version.txt
fi
rm -f /tmp/aq-brew-version.txt

# The marker's whole job is now done. Everything below this line is packing and
# checking, and none of it runs brew.
rm -f "${DOCKERENV}"

# Homebrew keeps a cache under the home folder it was installed with, which on
# this build is /var/home/linuxbrew/.cache. It is downloaded files, it is not
# part of Homebrew, and it would otherwise be packed into the box and shipped to
# every machine. (It is inside /var/home/linuxbrew either way, so section 5
# deletes it — but it must not be in the BOX, which is the thing that ships.)
rm -rf /var/home/linuxbrew/.cache

# ==============================================================================
# 4. Pack it into the box that lives in /usr
# ==============================================================================
# The flags, because every one of them is load-bearing:
#
#   -C /var/home        pack from there, so the paths inside the box are
#                       ".linuxbrew/..." and unpacking into /var/home puts it
#                       back exactly where it came from.
#   --zstd              squeeze it. Homebrew is a few hundred megabytes of
#                       mostly text and scripts, which compresses very well.
#   --owner=0 --group=0 --numeric-owner
#                       flatten every file's owner to root INSIDE the box. The
#                       temporary account's user number is meaningless on a real
#                       machine, and the first-boot service sets the real
#                       ownership anyway. This makes the box the same bytes on
#                       every build rather than carrying a number that depends
#                       on what order accounts were created in.
#   --sort=name         same idea: a predictable order, so two builds of the
#                       same Homebrew produce the same box.
say "Packing Homebrew into the box that ships in /usr"
install -d -m 0755 "${BOX_DIR}"
tar \
    -C /var/home \
    --zstd \
    --sort=name \
    --owner=0 --group=0 --numeric-owner \
    -cf "${BOX}" \
    linuxbrew

# ==============================================================================
# 5. Take it back out of /var
# ==============================================================================
# This is the step that makes the whole design work. Anything left in /var here
# would reach machines installed from an ISO and no machine that updated, which
# is the worst of both worlds.
say "Removing Homebrew from /var, where an update would never carry it"
rm -rf "${BREW_REAL}"

# ==============================================================================
# 6. Read the finished image back — content, never timestamps
# ==============================================================================
say "The box"
if [ -r "${BOX}" ]; then
    ok "${BOX} is in the image"
else
    bad "${BOX} is missing — there would be no Homebrew to unpack at first boot"
fi

# A box that exists and is tiny is the failure that looks like success: a `tar`
# that packed an empty folder produces a perfectly valid file of a few hundred
# bytes. Twenty megabytes is far below a real Homebrew (expect roughly ten times
# that) and far above anything an empty or half-finished pack could produce.
AQ_BOX_BYTES="$(stat -c '%s' "${BOX}" 2> /dev/null || echo 0)"
echo "  the box is ${AQ_BOX_BYTES} bytes ($(du -h "${BOX}" 2> /dev/null | cut -f1)) — this is what Homebrew adds to the image"
if [ "${AQ_BOX_BYTES}" -gt 20000000 ]; then
    ok "the box is a real Homebrew, not an empty folder that packed cleanly"
else
    bad "the box is only ${AQ_BOX_BYTES} bytes — that is not a Homebrew install"
fi

# ⚠️ AND THE CHECK THAT ACTUALLY PROVES IT: open the box and look for the
# program. A valid archive full of the wrong thing passes every check above.
say "Looking inside the box for the brew program itself"
if tar --zstd -tf "${BOX}" > /tmp/aq-brew-list.txt 2>&1; then
    echo "  the box holds $(wc -l < /tmp/aq-brew-list.txt | tr -d ' ') files"
    if grep -qx 'linuxbrew/\.linuxbrew/bin/brew' /tmp/aq-brew-list.txt; then
        ok "linuxbrew/.linuxbrew/bin/brew is inside the box"
    else
        bad "the box does not contain .linuxbrew/bin/brew — unpacking it would produce no brew command"
        head -20 /tmp/aq-brew-list.txt | sed 's/^/       /'
    fi
    # The library of Ruby that IS Homebrew. bin/brew on its own is a short
    # launcher script; without this folder it is a command that immediately
    # fails with a message about a missing file.
    if grep -q 'linuxbrew/\.linuxbrew/Homebrew/bin/brew' /tmp/aq-brew-list.txt \
        || grep -q 'linuxbrew/\.linuxbrew/Homebrew/library' /tmp/aq-brew-list.txt \
        || grep -q 'linuxbrew/\.linuxbrew/Homebrew/Library/' /tmp/aq-brew-list.txt; then
        ok "Homebrew's own program library is inside the box too"
    else
        bad "the box has bin/brew but not the Homebrew/ library it needs — brew would fail on its first command"
    fi
else
    bad "the box cannot be opened — it is not a readable zstd tar archive:"
    sed 's/^/       /' /tmp/aq-brew-list.txt
fi
rm -f /tmp/aq-brew-list.txt

say "Nothing of Homebrew is left in /var"
# This is the check that catches the one mistake that would silently split our
# users in half. See the header.
if [ -e "${BREW_REAL}" ]; then
    bad "${BREW_REAL} is still in the image — an update would never carry it, so only ISO installs would have it"
    ls -la "${BREW_REAL}" | head -5 | sed 's/^/       /'
else
    ok "${BREW_REAL} is gone (correct)"
fi

# /var/home itself is expected to be here and empty: it is where real accounts
# go, and the base image or an earlier step may have created it. What must not
# be here is anything inside it.
AQ_VAR_HOME_LEFT="$(find /var/home -mindepth 1 -maxdepth 1 2> /dev/null | wc -l | tr -d ' ')"
if [ "${AQ_VAR_HOME_LEFT}" -eq 0 ]; then
    ok "/var/home is empty, as it should be in an image with no accounts yet"
else
    bad "${AQ_VAR_HOME_LEFT} thing(s) are in /var/home — this step left something behind:"
    ls -la /var/home | sed 's/^/       /'
fi

# The container marker must not ship. It is one empty file, and leaving it means
# every program on the finished machine that asks "am I in a container?" — and
# several do — gets the wrong answer forever.
if [ -e "${DOCKERENV}" ]; then
    bad "${DOCKERENV} shipped in the image — every program that asks 'am I in a container' would be told yes"
else
    ok "the container marker is gone (correct)"
fi

# ==============================================================================
# 7. The first-boot half — the service that unpacks the box
# ==============================================================================
# These files arrived with system_files at step 5. This step reads them, because
# a box nobody ever opens is the same as no Homebrew at all.
say "The service that unpacks it on a real machine"
if [ -x "${SETUP}" ]; then
    ok "${SETUP} is present and runnable"
else
    bad "${SETUP} is missing — the box would never be unpacked"
fi
if bash -n "${SETUP}" 2> /tmp/aq-brew-setup-syntax.txt; then
    ok "the setup script is valid shell"
else
    bad "the setup script has a syntax error:"
    sed 's/^/       /' /tmp/aq-brew-setup-syntax.txt
fi
rm -f /tmp/aq-brew-setup-syntax.txt

if [ -r "${SETUP_UNIT}" ]; then
    ok "$(basename "${SETUP_UNIT}") is installed"
else
    bad "${SETUP_UNIT} is missing — nothing would start the setup"
fi
aq_file_has "${SETUP_UNIT}" "^ExecStart=${SETUP}\$" \
    "the service runs the setup script"
aq_file_has "${SETUP_UNIT}" '^Type=oneshot$' \
    "it runs once and finishes, rather than sitting in memory"
aq_file_has "${SETUP_UNIT}" "^ConditionPathExists=!${BREW_REAL}/\.linuxbrew/bin/brew\$" \
    "systemd itself skips it on a machine that already has brew"

# ⚠️ SWITCHED ON FROM /usr, NOT /etc — the rule in aq-lib.sh next to
# aq_unit_is_on_from_usr. That helper only knows about graphical.target, and
# this one hangs off multi-user.target (it has nothing to do with a screen and
# should run on a machine nobody has logged into yet), so the same two checks
# are written out here.
say "The setup service is switched on in a way an update cannot lose"
if [ -L "${SETUP_LINK}" ]; then
    echo "  ${SETUP_LINK} -> $(readlink "${SETUP_LINK}")"
    if [ -e "${SETUP_LINK}" ]; then
        ok "aquarius-brew-setup.service is switched on from /usr"
    else
        bad "the 'switched on' link for aquarius-brew-setup is dangling — it points at nothing"
    fi
else
    bad "${SETUP_LINK} is missing — the service would be installed but never start"
fi
if [ -e /etc/systemd/system/multi-user.target.wants/aquarius-brew-setup.service ]; then
    bad "aquarius-brew-setup is ALSO switched on through /etc — a build step ran 'systemctl enable'. See aq-lib.sh."
else
    ok "nothing switches aquarius-brew-setup on through /etc (an update could lose that)"
fi
if aq_have systemctl; then
    echo "  (for information) systemctl is-enabled aquarius-brew-setup.service: $(systemctl is-enabled aquarius-brew-setup.service 2> /dev/null || echo "no answer")"
fi

# ------------------------------------------------------------------------------
# The setup script must be idempotent, and this is where that is proved
# ------------------------------------------------------------------------------
# "Idempotent" means running it twice does the same thing as running it once. It
# matters because this service runs at EVERY boot — it is the script's own guard
# that makes it do nothing on the second one. Get that wrong and every boot
# spends a minute unpacking a few hundred megabytes over the top of somebody's
# Homebrew, wiping whatever they had installed.
#
# tests/test-brew-setup.sh runs it for real against a fake root folder with a
# fake box, twice, and checks the second run changed nothing.
say "Running it twice changes nothing the second time (the real test)"
if [ -r /ctx/tests/test-brew-setup.sh ]; then
    if bash /ctx/tests/test-brew-setup.sh "${SETUP}"; then
        ok "tests/test-brew-setup.sh passed against the copy in this image"
    else
        bad "tests/test-brew-setup.sh FAILED — the first-boot setup would not behave"
    fi
else
    bad "/ctx/tests/test-brew-setup.sh is missing — nothing would prove the setup is safe to run at every boot"
fi

# ==============================================================================
# 8. brew on PATH, for every shell and every app launcher
# ==============================================================================
# A `brew` that is installed and not on PATH is a `brew` that does not exist, as
# far as anybody typing at a terminal is concerned. Two files cover the two
# different ways a program finds out what its PATH is:
#
#   /etc/profile.d/aquarius-brew.sh    every bash/sh login shell — a terminal
#                                      window, an SSH session, a `su -`.
#   /usr/lib/environment.d/70-aquarius-brew.conf
#                                      everything started from the DESKTOP —
#                                      the Aquarius Session and GNOME both run
#                                      their apps under systemd's user manager,
#                                      which reads this folder at login.
#
# ⚠️ THE PROFILE FILE IS IN /etc AND THAT IS CORRECT, unlike our systemd links.
# There is no /usr/lib/profile.d — the shell only reads /etc/profile.d. It is
# also the right half of the machine for this: it is a preference, and somebody
# who wants a different one should be able to change it and keep the change.
#
# NO FISH SNIPPET, and that is not an oversight: this image ships no fish shell
# (nothing in build_files/ installs it). Anybody who installs fish themselves —
# with brew, most likely — adds two lines to their own config, and
# docs/restart/homebrew.md says exactly which two.
say "brew on PATH in a terminal"
if [ -r "${PROFILE}" ]; then
    ok "${PROFILE} is installed"
else
    bad "${PROFILE} is missing — brew would be installed and invisible in every terminal"
fi
aq_file_has "${PROFILE}" "${BREW_PREFIX}/bin/brew" \
    "the profile snippet names the brew program"
aq_file_has "${PROFILE}" 'shellenv' \
    "it asks brew itself where its folders are, rather than hard-coding them"
# The guard matters more than the rest of the file. Without it, every terminal
# on a machine where the setup has not run yet (or where somebody removed brew)
# prints an error before its first prompt.
aq_file_has "${PROFILE}" '^if \[ -x ' \
    "it does nothing at all when brew is not installed"

say "brew on PATH for apps started from the desktop"
if [ -r "${ENVD}" ]; then
    ok "${ENVD} is installed"
else
    bad "${ENVD} is missing — a program started from the dock would not find brew's tools"
fi
aq_file_has "${ENVD}" "${BREW_PREFIX}/bin" \
    "the session PATH includes brew's bin folder"

# ==============================================================================
# 9. The weekly update
# ==============================================================================
# `brew update` refreshes brew's own list of what is available. It does NOT
# upgrade anything that is installed, and this timer deliberately does not do
# that either — see the long note in the timer file. Upgrading somebody's
# command-line tools behind their back is how a working project stops building
# on a Tuesday for no reason anybody can see.
#
# ⚠️ IT IS A USER TIMER, NOT A SYSTEM ONE, and that is a real decision.
# Homebrew refuses to run as root, exactly as it refused during this build. A
# system timer would therefore have to drop to some particular person's account
# to do its work, and there is no correct answer to "which person" on a machine
# with two accounts. Running it as whoever is logged in is both simpler and
# right — it is their brew that is being refreshed. This mirrors the Resolve
# update check (build_files/62-resolve-runtime.sh), which is a user timer for
# the same family of reasons.
say "The weekly refresh of brew's catalogue"
if [ -x "${UPDATE}" ]; then
    ok "${UPDATE} is present and runnable"
else
    bad "${UPDATE} is missing — the weekly refresh would fail every week"
fi
if bash -n "${UPDATE}" 2> /tmp/aq-brew-update-syntax.txt; then
    ok "the update script is valid shell"
else
    bad "the update script has a syntax error:"
    sed 's/^/       /' /tmp/aq-brew-update-syntax.txt
fi
rm -f /tmp/aq-brew-update-syntax.txt

for unit in "${UPDATE_UNIT}" "${UPDATE_TIMER}"; do
    if [ -r "${unit}" ]; then
        ok "$(basename "${unit}") is installed"
    else
        bad "${unit} is missing — the weekly refresh would never run"
    fi
done
aq_file_has "${UPDATE_UNIT}" "^ExecStart=${UPDATE}\$" \
    "the service runs the refresh script"
aq_file_has "${UPDATE_UNIT}" "^ConditionPathExists=${BREW_REAL}/\.linuxbrew/bin/brew\$" \
    "it does not even start on a machine with no brew on it"
aq_file_has "${UPDATE_TIMER}" '^OnUnitActiveSec=1w$' \
    "it asks once a week, not more"
aq_file_has "${UPDATE_TIMER}" '^RandomizedDelaySec=' \
    "every machine picks a different moment, rather than all knocking at once"
aq_file_has "${UPDATE_TIMER}" '^Persistent=true$' \
    "a machine that was switched off catches up rather than skipping a week"

say "The weekly refresh is switched on in a way an update cannot lose"
if [ -L "${UPDATE_LINK}" ]; then
    echo "  ${UPDATE_LINK} -> $(readlink "${UPDATE_LINK}")"
    if [ -e "${UPDATE_LINK}" ]; then
        ok "aquarius-brew-update.timer is switched on from /usr"
    else
        bad "the 'switched on' link for the weekly refresh is dangling — it points at nothing"
    fi
else
    bad "${UPDATE_LINK} is missing — the timer would be installed but never start"
fi
if [ -e /etc/systemd/user/timers.target.wants/aquarius-brew-update.timer ]; then
    bad "the weekly refresh is ALSO switched on through /etc — a build step ran an enable. See aq-lib.sh."
else
    ok "nothing switches the weekly refresh on through /etc (an update could lose that)"
fi

# systemd's own reader. Advisory only: it complains about things that are true
# only on a running machine, so a build never fails on its opinion — the same
# treatment the Resolve timer gets in step 62.
if aq_have systemd-analyze; then
    systemd-analyze verify --user "${UPDATE_TIMER}" > /tmp/aq-brew-verify.txt 2>&1 || true
    if [ -s /tmp/aq-brew-verify.txt ]; then
        echo "  NOTE: systemd-analyze had something to say about the timer:"
        sed 's/^/         /' /tmp/aq-brew-verify.txt
    else
        ok "systemd-analyze reads the timer without complaint"
    fi
    rm -f /tmp/aq-brew-verify.txt
fi

# ==============================================================================
# 10. And the compiler really is here
# ==============================================================================
# Repeated on purpose at the end, because this is the one that turns into a wall
# of red text on somebody's machine weeks later rather than a failed build.
say "A compiler, for the packages that have no ready-built version"
if aq_have gcc; then
    ok "gcc is available ($(gcc --version 2> /dev/null | head -1))"
else
    bad "gcc is missing — any brew package without a ready-built version would fail to install"
fi

aq_finish "Homebrew"
