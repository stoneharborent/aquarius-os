#!/usr/bin/bash
# ==============================================================================
# BUILD STAGE — the Aquarius Shell itself (the bar, dock, search and settings)
# ==============================================================================
# THIS SCRIPT DOES NOT RUN INSIDE AQUARIUSOS. It runs in a throwaway container
# whose whole job is to fetch one folder of QML files at one exact commit.
#
# ------------------------------------------------------------------------------
# WHY A BUILD STAGE FOR SOMETHING THAT IS NOT COMPILED
# ------------------------------------------------------------------------------
# The shell is QML — text files. Nothing is compiled. So why not just clone it
# in the main build?
#
# Because a clone leaves a .git folder, a test suite, a development harness and
# a GitHub workflow behind, and every one of those would end up inside the
# operating system that ships to people. Doing it in a separate stage means we
# copy exactly the nine things the shell needs to run and nothing else.
#
# It also gives us one place to pin the version. AQUARIUS_SHELL_REF in
# aquarius-os.env is a commit hash; changing that one line is how AquariusOS
# takes a new version of its own desktop, and it is a deliberate act with a
# build behind it.
#
# ------------------------------------------------------------------------------
# WHERE IT LANDS, AND WHY THAT EXACT PATH
# ------------------------------------------------------------------------------
#   /usr/share/aquarius/shell/shell.qml
#
# The launcher (/usr/bin/aquarius-session) points the QS_CONFIG_PATH environment
# variable at that folder before it starts the window manager. Everything after
# that — the window manager's autostart file starting the shell with a bare
# `qs`, and the Super+Space key binding reaching the running shell with a bare
# `qs ipc call search toggle` — works because they all inherit that one variable.
#
# That is the shell repository's own mechanism, and it was corrected on the
# bench on 2026-09-01: `qs ipc` does NOT take a configuration name, it talks to
# whichever instance is running the configuration QS_CONFIG_PATH names. An
# earlier version of the key binding passed "aquarius-shell" as an argument and
# would have silently done nothing.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
# NOTE (2026-09-03): the shell repo, github.com/stoneharborent/aquarius-shell, was
# private when this line was first built, so the fetch below failed loudly and the
# image shipped the placeholder. Royce made it public the same day; no token is
# ever used here (a build secret would end up in the published image's history).
source "$(dirname "$0")/aq-lib.sh"

AQ_SHELL_REPO="${AQUARIUS_SHELL_REPO:?AQUARIUS_SHELL_REPO was not passed to this stage}"
AQ_SHELL_REF="${AQUARIUS_SHELL_REF:?AQUARIUS_SHELL_REF was not passed to this stage}"

AQ_STAGE="/aq-stage"
AQ_DEST="${AQ_STAGE}/usr/share/aquarius/shell"

say "Fetching the Aquarius Shell"
echo "  repository: ${AQ_SHELL_REPO}"
echo "  commit:     ${AQ_SHELL_REF}"

aq_dnf install git

# A missing or unreachable shell is a failed build, never a publishable image.
export GIT_TERMINAL_PROMPT=0
git clone "${AQ_SHELL_REPO}" /src

cd /src || exit 1
git checkout --detach "${AQ_SHELL_REF}"

AQ_GOT="$(git rev-parse HEAD)"
if [ "${AQ_GOT}" != "${AQ_SHELL_REF}" ]; then
    echo "::error::Asked for aquarius-shell ${AQ_SHELL_REF} and got ${AQ_GOT}." >&2
    exit 1
fi
ok "the shell is commit ${AQ_GOT}, exactly as pinned"

echo
echo "  what that commit says it is:"
git log -1 --format='    %h  %ad  %s' --date=short

# ------------------------------------------------------------------------------
# Copying only what runs
# ------------------------------------------------------------------------------
# In:  the QML, the theme, the services, the logo assets, the login screen.
# Out: harness/ (the development tool for running the shell in a window),
#      tests/ (checks that run on a developer's machine), docs/, .github/,
#      session/ (the OS image ships its own copies of those, adapted to system
#      paths — see system_files/), and .git.
say "Copying the parts that run"
install -d -m 0755 "${AQ_DEST}"

# greeter.qml (at the repo root, beside shell.qml) is the login screen's ENTRY
# point, and greeter/ holds its pieces. The entry sits at the root on purpose:
# Quickshell treats the folder of the file it is given as the config folder and
# discards imports that escape it, so an entry inside greeter/ could not reach
# ../theme or the Aquarius mark and the login screen failed to draw (fixed
# 2026-09-07). Both must travel: the root greeter.qml AND the greeter/ folder.
# It shares theme/ and the mark with the desktop because it IS the shell wearing
# a different hat, and the two must never disagree about a colour.
#
# lock/ is the LOCK screen, and it is a different case from greeter/ again: it
# is not a separate entry point at all. shell.qml holds it, so it is already
# loaded and waiting the moment you log in, which is the whole reason Super+L is
# instant. It has to come across or Super+L would do nothing at all.
for aq_part in shell.qml greeter.qml components services theme assets greeter lock; do
    if [ ! -e "/src/${aq_part}" ]; then
        bad "the shell repository has no '${aq_part}' — its layout changed and this script has not caught up"
        continue
    fi
    cp -a "/src/${aq_part}" "${AQ_DEST}/"
    ok "copied ${aq_part}"
done

# The LICENSE travels with the code. The shell is Apache-2.0 and shipping the
# licence text alongside it is both correct and courteous.
install -d -m 0755 "${AQ_STAGE}/usr/share/licenses/aquarius-shell"
cp -a /src/LICENSE "${AQ_STAGE}/usr/share/licenses/aquarius-shell/LICENSE"

# A record of exactly what was baked in, readable on the finished machine. When
# Royce asks "which version of the bar is this", this is the answer.
{
    echo "# Written by build_files/stage-aquarius-shell.sh. Do not edit by hand."
    echo "status=installed"
    echo "repository=${AQ_SHELL_REPO}"
    echo "commit=${AQ_GOT}"
    echo "subject=$(git log -1 --format='%s')"
    echo "date=$(git log -1 --format='%ad' --date=short)"
} > "${AQ_STAGE}/usr/share/aquarius/shell-build.txt"

# Permissions: text files readable by everyone, directories traversable, and
# nothing executable or writable. /usr is read-only on this operating system and
# a stray writable file there is a security hole.
find "${AQ_DEST}" -type d -exec chmod 0755 {} +
find "${AQ_DEST}" -type f -exec chmod 0644 {} +

say "What is being copied into AquariusOS"
find "${AQ_STAGE}" -type f | sort | sed "s|${AQ_STAGE}||; s/^/  /"
echo "  total size: $(du -sh "${AQ_STAGE}" | cut -f1)"

# ------------------------------------------------------------------------------
# Checking it looks like a shell
# ------------------------------------------------------------------------------
say "Checking the shell tree"

# Quickshell's entry point. Without this exact filename in this exact folder,
# `qs` starts, finds nothing, and exits.
if [ -s "${AQ_DEST}/shell.qml" ]; then
    ok "shell.qml is present (this is the file Quickshell looks for)"
else
    bad "there is no shell.qml — Quickshell would find nothing to run"
fi

# The theme singletons. These are the only place colour is allowed to live in
# the whole project, and every component reads them.
for aq_f in theme/qmldir theme/Theme.qml theme/Ice.qml theme/Midnight.qml; do
    if [ -s "${AQ_DEST}/${aq_f}" ]; then
        ok "${aq_f}"
    else
        bad "${aq_f} is missing — the shell would start with no colours defined"
    fi
done

# The login screen's own front door and the one piece of it that thinks. The
# helper beside them is copied out to /usr/libexec by 55-aquarius-session.sh,
# because that is where greetd's greeter will look for it.
for aq_f in greeter.qml greeter/qmldir greeter/GreeterState.qml \
    greeter/aquarius-greeter-info; do
    if [ -s "${AQ_DEST}/${aq_f}" ]; then
        ok "${aq_f}"
    else
        bad "${aq_f} is missing — the login screen would not start"
    fi
done

# The lock screen. Its state file is the one that talks to PAM, and the pam.d
# file this image installs at /etc/pam.d/aquarius-lock is only useful if it is
# here to ask for it. build_files/57-lock-screen.sh checks the two agree on the
# name; this checks the files arrived at all.
for aq_f in lock/qmldir lock/LockState.qml lock/LockLayer.qml \
    lock/LockSurface.qml lock/LockCard.qml lock/LockField.qml \
    lock/LockVeil.qml lock/LockBlur.qml lock/LockIdle.qml; do
    if [ -s "${AQ_DEST}/${aq_f}" ]; then
        ok "${aq_f}"
    else
        bad "${aq_f} is missing — Super+L would do nothing and the machine would never lock itself"
    fi
done

# The four things a person actually sees.
for aq_f in components/bar/TopBar.qml components/dock/Dock.qml \
    components/search/FlowSearch.qml components/notifications/NotificationLayer.qml; do
    if [ -s "${AQ_DEST}/${aq_f}" ]; then
        ok "$(basename "${aq_f}")"
    else
        bad "${aq_f} is missing"
    fi
done

# Nothing that should have been left behind came along.
for aq_unwanted in harness tests .github .git docs; do
    if [ -e "${AQ_DEST}/${aq_unwanted}" ]; then
        bad "${aq_unwanted}/ was copied into the image and should not have been"
    else
        ok "${aq_unwanted}/ was correctly left out"
    fi
done

aq_finish "Aquarius Shell source stage"
