#!/usr/bin/bash
# =============================================================================
# test-decky.sh — `aq decky` tells the truth before it changes anything
# =============================================================================
# WHAT THIS PROVES, AND WHY IT IS WORTH A TEST OF ITS OWN
#
# `aq decky install` downloads 26 MB from GitHub and switches on a background
# service that runs as the administrator. None of that can be rehearsed in a
# build container and none of it should be. But every DECISION the command
# makes before it touches anything can be — and those decisions are where the
# damage would be:
#
#   * "Decky is already installed" has to be believed, or a second install
#     overwrites a working one and asks for a password to do it;
#   * "half installed" has to be SEEN, because a downloaded loader with no
#     service file, or the other way round, is the state somebody spends an
#     evening on wondering why the plug icon never appears;
#   * `status` must never claim a version it has not read off the disk;
#   * running any of it under sudo has to be refused, because Decky installs
#     into ONE person's home folder and under sudo that is the administrator's;
#   * and `remove` on a computer with no Decky must do nothing and say so,
#     rather than asking for a password to delete files that are not there.
#
# HOW IT DOES THAT WITHOUT A COMPUTER: it points HOME at a throwaway folder and
# builds each of those situations out of empty files. Every command it runs is
# one that reads and reports. Nothing here downloads, nothing asks for a
# password, and nothing writes outside the throwaway folder — which is why it
# can run in CI before the image is even built.
#
# ⚠️ ONE THING IS DELIBERATELY NOT TESTED: the real install. It needs the
# internet, a real Steam, a real systemd and a real password. That is a bench
# job, and the bench list is at the bottom of docs/restart/decky.md.
#
# HOW TO RUN IT
#   ./tests/test-decky.sh
#   ./tests/test-decky.sh /usr/bin/aq
# =============================================================================

set -uo pipefail

AQ="${1:-}"
if [ -z "${AQ}" ]; then
    AQ="$(cd "$(dirname "$0")/.." && pwd)/system_files/usr/bin/aq"
fi

if [ ! -r "${AQ}" ]; then
    echo "FAIL ${AQ} is not there — nothing to test." >&2
    exit 1
fi

fails=0
ok() { echo "  OK   $*"; }
bad() {
    echo "  FAIL $*" >&2
    fails=$((fails + 1))
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

# -----------------------------------------------------------------------------
# say_of <what we are pretending> <arguments to aq...>
# -----------------------------------------------------------------------------
# Runs `aq` with HOME pointed at the throwaway folder and keeps everything it
# printed. Output goes into a file rather than through a pipe, for the reason
# spelled out at length in build_files/aq-lib.sh: `grep -q` in a pipeline ends
# the command early and `pipefail` then reports the whole thing as a failure —
# finding what you looked for makes the check say it is missing.
OUT="${WORK}/out.txt"
run_aq() {
    HOME="${WORK}/home" bash "${AQ}" "$@" > "${OUT}" 2>&1
    return $?
}

says() { # says <pattern> "<what it means>"
    if grep -qi -- "$1" "${OUT}"; then
        ok "$2"
    else
        echo "       what it actually said:" >&2
        sed 's/^/         /' "${OUT}" >&2
        bad "$2 — expected to see /$1/"
    fi
}

says_not() { # says_not <pattern> "<what it means>"
    if grep -qi -- "$1" "${OUT}"; then
        echo "       what it actually said:" >&2
        sed 's/^/         /' "${OUT}" >&2
        bad "$2 — did NOT expect to see /$1/"
    else
        ok "$2"
    fi
}

fresh_home() {
    rm -rf "${WORK}/home"
    mkdir -p "${WORK}/home"
}

# -----------------------------------------------------------------------------
# ⚠️ ONE THING THIS TEST CANNOT PRETEND: /etc
# -----------------------------------------------------------------------------
# Half of "is Decky installed?" is a file at /etc/systemd/system/plugin_loader.
# service, which belongs to the whole computer and not to a home folder. HOME
# can be pointed anywhere; /etc cannot. So on a machine that really does have
# Decky installed — Royce's own desktop, for one — the "nothing installed"
# situations below cannot be built at all, and running them anyway would test
# the machine rather than the command (and, worse, would reach a real `sudo`
# password prompt and hang).
#
# CI runs this inside a fresh container, where the file is never there, so every
# check below really does run where it matters. On a developer's own machine the
# affected ones say plainly that they were skipped, rather than passing quietly.
HOST_DECKY=0
[ -e /etc/systemd/system/plugin_loader.service ] && HOST_DECKY=1
if [ "${HOST_DECKY}" -eq 1 ]; then
    echo "   NOTE: this machine really has Decky installed"
    echo "         (/etc/systemd/system/plugin_loader.service exists), so the checks"
    echo "         that need a computer WITHOUT Decky are skipped below."
fi

echo "== aq decky tells the truth before it changes anything =="
echo "   command under test: ${AQ}"

# -----------------------------------------------------------------------------
# 0. The file still parses, and decky is discoverable
# -----------------------------------------------------------------------------
echo ""
echo "-- the aq command itself --"
if bash -n "${AQ}" 2> "${WORK}/syntax.txt"; then
    ok "aq is valid shell with the decky part in it"
else
    sed 's/^/       /' "${WORK}/syntax.txt" >&2
    bad "aq does not parse — every aq command is broken, not just decky"
fi

fresh_home
run_aq --help
says 'aq decky' "'aq --help' lists 'aq decky', so a person can find it"

run_aq decky --help
says 'aq decky install' "'aq decky --help' offers install"
says 'aq decky update' "and update"
says 'aq decky status' "and status"
says 'aq decky remove' "and remove"
says 'ONLY EXISTS IN GAME MODE' "and warns, before anything is installed, that Decky is Game Mode only"
says 'administrator' "and that it runs as an administrator"

# -----------------------------------------------------------------------------
# 1. A computer with no Decky on it
# -----------------------------------------------------------------------------
echo ""
echo "-- nothing installed --"
if [ "${HOST_DECKY}" -eq 1 ]; then
    echo "  (skipped: this machine really has Decky's service file — see the note above)"
else
fresh_home
run_aq decky status
says 'NOT installed' "status says Decky is not installed"
says_not 'version' "and does not invent a version number"
says 'Game Mode' "and still says where Decky would appear"

# ⚠️ REMOVE ON A CLEAN MACHINE MUST NOT ASK FOR A PASSWORD. It is the wrong
# answer to a question nobody asked, and `sudo` in a test would hang forever.
fresh_home
run_aq decky remove
rc=$?
if [ "${rc}" -eq 0 ]; then
    ok "'aq decky remove' on a clean computer succeeds quietly"
else
    bad "'aq decky remove' on a clean computer exited ${rc}"
fi
says 'not installed' "and says there is nothing to remove"
fi

# -----------------------------------------------------------------------------
# 2. Half installed — the state that wastes an evening
# -----------------------------------------------------------------------------
# The downloaded loader is there and the service file is not. On a real machine
# this is what an install looks like when the administrator's half was
# cancelled at the password box.
echo ""
echo "-- the loader is downloaded, the service was never written --"
fresh_home
mkdir -p "${WORK}/home/homebrew/services"
: > "${WORK}/home/homebrew/services/PluginLoader"
chmod +x "${WORK}/home/homebrew/services/PluginLoader"
echo "v3.2.9" > "${WORK}/home/homebrew/services/.loader.version"

if [ "${HOST_DECKY}" -eq 1 ]; then
    echo "  (skipped: this machine really has Decky's service file — see the note above)"
else
    run_aq decky status
    says 'HALF installed' "status sees a half-finished install and says so"
    says 'aq decky remove' "and names the way out of it"
fi

# -----------------------------------------------------------------------------
# 3. The version comes off the disk, never out of the air
# -----------------------------------------------------------------------------
echo ""
echo "-- the version number --"
fresh_home
mkdir -p "${WORK}/home/homebrew/services"
: > "${WORK}/home/homebrew/services/PluginLoader"
chmod +x "${WORK}/home/homebrew/services/PluginLoader"
printf 'v9.9.9-aquarius-test\n' > "${WORK}/home/homebrew/services/.loader.version"
run_aq decky status
says 'v9.9.9-aquarius-test' "status reports the version written in .loader.version, and no other"

# -----------------------------------------------------------------------------
# 3b. A folder we cannot write into: refuse EARLY, and never claim success
# -----------------------------------------------------------------------------
# ⚠️ THE BUG THIS EXISTS FOR, found on Royce's own desktop in September 2026.
#
# Decky's own installer — the one people ran before AquariusOS had this command
# — hands parts of ~/homebrew/services to the administrator. On that machine
# `aq decky update` downloaded 26 MB, could not write .loader.version because
# the file was root's, said "Permission denied", carried on regardless, and
# finished with "Decky Loader is now v3.2.9" while the file still said v3.2.6.
# Two separate holes: an unchecked write, and a success message printed without
# checking anything at all.
#
# So: when our half cannot write where it needs to, the command must stop
# BEFORE the download and BEFORE the password box, say what did not happen, and
# never print "is now v...".
#
# This is checked through `install` rather than `update` because `update` first
# insists the service file in /etc is there, and /etc cannot be pretended at
# (see the note near the top). `install` runs the same writability check first,
# and on a fake HOME it reaches it on every machine, CI included.
echo ""
echo "-- the services folder belongs to somebody else --"
if [ "$(id -u)" -eq 0 ]; then
    echo "  (skipped: running as root, which can write into any folder —"
    echo "   CI runs an unprivileged copy of this test, which does exercise it)"
else
    fresh_home
    mkdir -p "${WORK}/home/homebrew/services"
    chmod 0555 "${WORK}/home/homebrew/services"

    run_aq decky install
    rc=$?
    chmod 0755 "${WORK}/home/homebrew/services"

    if [ "${rc}" -ne 0 ]; then
        ok "'aq decky install' stops when it cannot write into ~/homebrew/services"
    else
        bad "'aq decky install' carried on with a folder it cannot write into"
    fi
    says 'not a folder you are allowed to write into' "and says plainly what is wrong"
    says 'nothing on this computer changed' "and says what state the machine is in"
    says 'chown' "and gives the one command that fixes it"
    says_not 'Downloading Decky' "and refuses BEFORE downloading 26 MB"
    says_not 'password' "and BEFORE asking for a password"
    says_not 'is installed and running' "and never claims success"
    says_not 'is now v' "and never prints the false 'Decky Loader is now vX' line"

    # The same thing one level down: the folder is ours, the loader inside it
    # is not. This is the shape Decky's own installer actually leaves behind.
    fresh_home
    mkdir -p "${WORK}/home/homebrew/services"
    : > "${WORK}/home/homebrew/services/PluginLoader"
    chmod 0444 "${WORK}/home/homebrew/services/PluginLoader"
    printf 'v3.2.6\n' > "${WORK}/home/homebrew/services/.loader.version"
    chmod 0444 "${WORK}/home/homebrew/services/.loader.version"

    run_aq decky install
    rc=$?
    chmod 0644 "${WORK}/home/homebrew/services/PluginLoader" \
        "${WORK}/home/homebrew/services/.loader.version"

    if [ "${rc}" -ne 0 ]; then
        ok "'aq decky install' stops when PluginLoader cannot be replaced"
    else
        bad "'aq decky install' carried on with a PluginLoader it cannot replace"
    fi
    says 'not allowed to replace it' "and says which file is in the way"
    says_not 'Downloading Decky' "and again refuses before the download"
    says_not 'is now v' "and again never prints the false success line"
fi

# -----------------------------------------------------------------------------
# 3c. A version file we are not allowed to read
# -----------------------------------------------------------------------------
# `status` must never let an unreadable version file look like a clean machine
# with no version noted down. Those are different answers and only one of them
# means "something here needs fixing".
echo ""
echo "-- a version file that cannot be read --"
if [ "$(id -u)" -eq 0 ]; then
    echo "  (skipped: running as root, which can read any file)"
else
    fresh_home
    mkdir -p "${WORK}/home/homebrew/services"
    : > "${WORK}/home/homebrew/services/PluginLoader"
    chmod +x "${WORK}/home/homebrew/services/PluginLoader"
    printf 'v3.2.6\n' > "${WORK}/home/homebrew/services/.loader.version"
    chmod 0000 "${WORK}/home/homebrew/services/.loader.version"

    run_aq decky status
    chmod 0644 "${WORK}/home/homebrew/services/.loader.version"

    says 'version cannot be read' "status says the version is unknown, not absent"
    says_not 'v3\.2\.6' "and does not report a version it could not read"
fi

# -----------------------------------------------------------------------------
# 4. Under sudo it refuses, and refuses BEFORE it does anything
# -----------------------------------------------------------------------------
# Run as root, `aq decky install` would put Decky in the administrator's home
# folder, where the person who asked for it would never find it. The refusal
# has to come first, before the download — which is what "no network was
# touched" below is really checking.
echo ""
echo "-- run as an administrator --"
if [ "$(id -u)" -eq 0 ]; then
    for verb in install update remove; do
        fresh_home
        run_aq decky "${verb}"
        rc=$?
        if [ "${rc}" -ne 0 ]; then
            ok "'aq decky ${verb}' refuses to run as root"
        else
            bad "'aq decky ${verb}' ran as root — it would install into the wrong home folder"
        fi
        says 'do not run' "and says why, in a sentence"
    done
    # status is a read, so it stays allowed.
    fresh_home
    run_aq decky status
    if [ "$?" -eq 0 ]; then
        ok "'aq decky status' still works as root — it only reads"
    else
        bad "'aq decky status' refused as root, and it should not"
    fi
else
    echo "  (skipped: this test is not running as root, so the refusal cannot fire)"
    echo "   CI runs the container copy of this test as root, which does exercise it."
fi

# -----------------------------------------------------------------------------
# 5. The app-grid entry
# -----------------------------------------------------------------------------
echo ""
echo "-- the 'Decky Loader' entry in the app grid --"
ENTRY="$(cd "$(dirname "$0")/.." && pwd)/system_files/usr/share/applications/aquarius-decky.desktop"
if [ ! -r "${ENTRY}" ] && [ -r /usr/share/applications/aquarius-decky.desktop ]; then
    ENTRY=/usr/share/applications/aquarius-decky.desktop
fi

if [ -r "${ENTRY}" ]; then
    ok "${ENTRY} is there"
    key_is() { # key_is <key> <wanted> "<what it is for>"
        local got
        got="$(awk -v k="$1=" 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }' \
            "${ENTRY}" 2> /dev/null || true)"
        if [ "${got}" = "$2" ]; then
            ok "$1=$2${3:+ — $3}"
        else
            bad "$1 is '${got}', should be '$2'${3:+ — $3}"
        fi
    }
    key_is Type Application "it is an application entry"
    key_is Name "Decky Loader" "the name a person searches for"
    key_is Exec "/usr/bin/aq decky install" "clicking it installs Decky"
    key_is Terminal true "it opens a terminal — the install prints things and asks for a password"
    key_is Categories "Game;" "it has a shelf in the menu"
    if awk 'index($0, "Comment=") == 1 { found = 1 } END { exit !found }' "${ENTRY}"; then
        ok "it has a one-sentence description under the name"
    else
        bad "the entry has no Comment= line"
    fi
    if awk 'index($0, "Icon=") == 1 { found = 1 } END { exit !found }' "${ENTRY}"; then
        ok "it has an icon"
    else
        bad "the entry has no Icon= line"
    fi
    if command -v desktop-file-validate > /dev/null 2>&1; then
        if desktop-file-validate "${ENTRY}" > "${WORK}/dfv.txt" 2>&1; then
            ok "the desktop's own validator is happy with it"
        else
            sed 's/^/       /' "${WORK}/dfv.txt" >&2
            bad "desktop-file-validate rejected the entry"
        fi
    else
        echo "  (desktop-file-validate is not on this machine — the key checks stand alone)"
    fi
else
    bad "aquarius-decky.desktop is not there — there would be no way to install Decky except a terminal"
fi

echo ""
if [ "${fails}" -ne 0 ]; then
    echo "${fails} check(s) failed." >&2
    exit 1
fi
echo "All checks passed."
