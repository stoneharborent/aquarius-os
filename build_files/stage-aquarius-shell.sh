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

# ------------------------------------------------------------------------------
# ⚠️ THE ONE THING THAT CAN STOP THE SHELL BEING BAKED IN
# ------------------------------------------------------------------------------
# A container build has no GitHub account. It can read a PUBLIC repository and
# nothing else. There is deliberately no token here and there should never be
# one: a secret passed into a container build is recorded in the finished
# image's history, where anybody who downloads AquariusOS can read it.
#
# So if aquarius-shell is private, this stage cannot fetch it, and the honest
# thing to do is say so at the top of the build log and carry on WITHOUT the
# shell — producing an operating system whose Aquarius Desktop starts, shows the
# wallpaper, and puts a dialog on screen explaining in plain English that the
# shell is not installed yet and how to get back to GNOME.
#
# That is not a silent failure. It is written in the build log, it is written
# into the image at /usr/share/aquarius/shell-build.txt, the checks in
# 55-aquarius-session.sh repeat it, and CI prints it as a warning on the run.
#
# THE FIX IS ONE CLICK, AND IT IS ROYCE'S TO MAKE:
#   github.com/stoneharborent/aquarius-shell -> Settings -> General ->
#   Danger Zone -> Change visibility -> Public
# The next build then bakes the shell in with no change to any file here.
#
# (The alternative — a personal access token in an Actions secret — would work
# for the CI job but not for the container build, for the reason above.)
# ------------------------------------------------------------------------------
GIT_TERMINAL_PROMPT=0
export GIT_TERMINAL_PROMPT

AQ_SHELL_AVAILABLE=1
if ! git clone "${AQ_SHELL_REPO}" /src 2>&1 | sed 's/^/  /'; then
    AQ_SHELL_AVAILABLE=0
fi
# The pipe above hides git's exit code, so ask the filesystem instead.
if [ ! -d /src/.git ]; then
    AQ_SHELL_AVAILABLE=0
fi

if [ "${AQ_SHELL_AVAILABLE}" -eq 0 ]; then
    install -d -m 0755 "${AQ_STAGE}/usr/share/aquarius"
    {
        echo "# Written by build_files/stage-aquarius-shell.sh. Do not edit by hand."
        echo "status=unavailable"
        echo "repository=${AQ_SHELL_REPO}"
        echo "wanted_commit=${AQ_SHELL_REF}"
        echo "reason=the repository could not be read without an account, so it is private"
        echo "fix=make the repository public, then rebuild; nothing in the OS recipe needs changing"
    } > "${AQ_STAGE}/usr/share/aquarius/shell-build.txt"

    echo
    echo "::warning::The Aquarius Shell was NOT baked into this image: ${AQ_SHELL_REPO} could not be read without an account. The Aquarius Desktop will start and show a dialog explaining it. Make the repository public and rebuild."
    echo "  ============================================================"
    echo "  THE AQUARIUS SHELL IS NOT IN THIS IMAGE"
    echo "  ============================================================"
    echo "  ${AQ_SHELL_REPO} could not be read."
    echo ""
    echo "  A container build has no GitHub account, so it can only read"
    echo "  public repositories. This one is private."
    echo ""
    echo "  The image is still good: labwc, Quickshell, the login-screen"
    echo "  entry and the portals are all here. Picking \"Aquarius Desktop\""
    echo "  gives a wallpaper and a dialog saying the shell is not"
    echo "  installed yet, and how to get back to GNOME."
    echo ""
    echo "  To fix it, on github.com:"
    echo "    stoneharborent/aquarius-shell -> Settings -> General ->"
    echo "    Danger Zone -> Change visibility -> Public"
    echo "  Then rebuild. No file in this repository needs to change."
    echo "  ============================================================"
    echo

    say "What is being copied into AquariusOS"
    find "${AQ_STAGE}" -type f | sort | sed "s|${AQ_STAGE}||; s/^/  /"
    aq_finish "Aquarius Shell source stage (shell NOT included)"
    exit 0
fi

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

# greeter/ is the login screen — this repository's SECOND entry point. It shares
# theme/ and the Aquarius mark with the desktop and is otherwise its own thing.
# It travels with the shell rather than living here because it IS the shell,
# wearing a different hat, and the two must never disagree about a colour.
for aq_part in shell.qml components services theme assets greeter; do
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
for aq_f in greeter/greeter.qml greeter/qmldir greeter/GreeterState.qml \
    greeter/aquarius-greeter-info; do
    if [ -s "${AQ_DEST}/${aq_f}" ]; then
        ok "${aq_f}"
    else
        bad "${aq_f} is missing — the login screen would not start"
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
