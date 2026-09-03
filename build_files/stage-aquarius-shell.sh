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
source "$(dirname "$0")/aq-lib.sh"

AQ_SHELL_REPO="${AQUARIUS_SHELL_REPO:?AQUARIUS_SHELL_REPO was not passed to this stage}"
AQ_SHELL_REF="${AQUARIUS_SHELL_REF:?AQUARIUS_SHELL_REF was not passed to this stage}"

AQ_STAGE="/aq-stage"
AQ_DEST="${AQ_STAGE}/usr/share/aquarius/shell"

say "Fetching the Aquarius Shell"
echo "  repository: ${AQ_SHELL_REPO}"
echo "  commit:     ${AQ_SHELL_REF}"

aq_dnf install git

# A shallow clone cannot check out an arbitrary commit, so this is a full clone.
# The repository is a few hundred kilobytes of text; it costs nothing.
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
# In:  the QML, the theme, the services, the logo assets.
# Out: harness/ (the development tool for running the shell in a window),
#      tests/ (checks that run on a developer's machine), docs/, .github/,
#      session/ (the OS image ships its own copies of those, adapted to system
#      paths — see system_files/), and .git.
say "Copying the parts that run"
install -d -m 0755 "${AQ_DEST}"

for aq_part in shell.qml components services theme assets; do
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
