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
# 3d. The SELinux label — the 20 September 2026 bench bug
# -----------------------------------------------------------------------------
# ⚠️ WHAT WENT WRONG, AND WHY IT NEEDS A TEST.
#
# Decky installed on Royce's bench PC with no errors at all, and then never
# appeared in Game Mode. The reason was three lines down in the system journal:
#
#   plugin_loader.service: Failed at step EXEC ... status=203/EXEC
#   avc: denied { execute } for comm="(PluginLoader)" name="PluginLoader"
#       scontext=system_u:system_r:init_t:s0
#       tcontext=unconfined_u:object_r:user_home_t:s0 tclass=file
#
# SELinux — Fedora's guard — labels anything downloaded into a home folder as
# "one of this person's documents", and it will not let systemd start a
# document as a service. /usr/libexec/aquarius-decky-label is what gives the
# file the label of a program instead.
#
# NONE OF THAT CAN BE REHEARSED HONESTLY IN A CONTAINER: the CI container has
# no SELinux, no semanage and no systemd, and a test that only ran on a machine
# with all three would never run at all. So this does what the rest of this
# file does with HOME — it builds a pretend world. `semanage`, `restorecon`,
# `chcon`, `getenforce` and `stat` are replaced with small scripts that keep
# their answers in two text files, and the test then checks the DECISIONS the
# program makes: which spelling of the rule it writes, whether it reads the
# label back off the file instead of trusting a command's silence, and whether
# it refuses when the label is still wrong.
echo ""
echo "-- the SELinux label (the 20 Sept 2026 bench bug) --"

LABELER="$(cd "$(dirname "$0")/.." && pwd)/system_files/usr/libexec/aquarius-decky-label"
if [ ! -r "${LABELER}" ] && [ -r /usr/libexec/aquarius-decky-label ]; then
    LABELER=/usr/libexec/aquarius-decky-label
fi

if [ ! -r "${LABELER}" ]; then
    bad "aquarius-decky-label is not there — 'aq decky install' has nothing to label the loader with"
else
    ok "${LABELER} is there"
    if bash -n "${LABELER}" 2> "${WORK}/lsyn.txt"; then
        ok "it is valid shell"
    else
        sed 's/^/       /' "${WORK}/lsyn.txt" >&2
        bad "aquarius-decky-label does not parse"
    fi

    # -------------------------------------------------------------------------
    # The pretend world
    # -------------------------------------------------------------------------
    #   ${WORK}/label   the one label our pretend file is wearing right now
    #   ${WORK}/rules   the SELinux rules our pretend semanage has been given
    #   ${WORK}/match   which ONE rule our pretend restorecon actually honours
    #
    # Putting the stand-ins first on PATH is the whole trick: the program under
    # test calls `semanage`, and gets ours.
    STUB="${WORK}/stub"
    mkdir -p "${STUB}"

    cat > "${STUB}/getenforce" << 'EOF'
#!/usr/bin/bash
echo Enforcing
EOF

    # `stat -c %C <file>` is how the program reads a label back. Anything else
    # is handed to the real stat, so the rest of the world still works.
    cat > "${STUB}/stat" << 'EOF'
#!/usr/bin/bash
if [ "${1:-}" = "-c" ] && [ "${2:-}" = "%C" ]; then
    printf 'unconfined_u:object_r:%s:s0\n' "$(cat "${AQ_TEST_LABEL}")"
    exit 0
fi
exec /usr/bin/stat "$@"
EOF

    # A rule book that remembers. -l lists, -a adds, -m changes, -d deletes.
    cat > "${STUB}/semanage" << 'EOF'
#!/usr/bin/bash
[ "${1:-}" = "fcontext" ] || exit 0
shift
case "${1:-}" in
    -l) cat "${AQ_TEST_RULES}" 2> /dev/null; exit 0 ;;
    -d)
        grep -vxF -- "${2:-}" "${AQ_TEST_RULES}" > "${AQ_TEST_RULES}.new" 2> /dev/null
        mv -f "${AQ_TEST_RULES}.new" "${AQ_TEST_RULES}"
        exit 0
        ;;
    -a | -m)
        # -a/-m -t <type> <spec>
        printf '%s\n' "${4:-}" >> "${AQ_TEST_RULES}"
        exit 0
        ;;
esac
exit 0
EOF

    # ⚠️ THE POINT OF THE WHOLE PRETENCE. The real restorecon only labels a
    # file if a rule MATCHES IT, and on this system whether a rule matches
    # depends on the /home versus /var/home spelling. So ours labels the file
    # only when the rule book contains the one exact spelling named in
    # ${WORK}/match — and otherwise does nothing at all, quietly, exactly as
    # the real one does when a rule does not reach the file.
    cat > "${STUB}/restorecon" << 'EOF'
#!/usr/bin/bash
want="$(cat "${AQ_TEST_MATCH}" 2> /dev/null || true)"
if [ -n "${want}" ] && grep -qxF -- "${want}" "${AQ_TEST_RULES}" 2> /dev/null; then
    echo "bin_t" > "${AQ_TEST_LABEL}"
fi
exit 0
EOF

    cat > "${STUB}/chcon" << 'EOF'
#!/usr/bin/bash
if [ "${AQ_TEST_CHCON_WORKS:-1}" = "1" ]; then
    echo "bin_t" > "${AQ_TEST_LABEL}"
fi
exit 0
EOF

    chmod +x "${STUB}"/*

    LOADER="${WORK}/home/homebrew/services/PluginLoader"
    # The rule the program should write first: the /home spelling, which is the
    # one Fedora's rules are written in even though the file really lives under
    # /var/home. See the long note at the top of aquarius-decky-label.
    SPEC_HOME='/home/[^/]+/homebrew/services/PluginLoader'
    # And the fallback: the file's own real path with the person's name turned
    # into "any one folder name".
    SPEC_REAL="$(printf '%s' "${WORK}/home/homebrew/services/PluginLoader" \
        | sed -E 's![^/]+/homebrew/services/PluginLoader$![^/]+/homebrew/services/PluginLoader!')"

    label_world() { # label_world <which spelling restorecon honours, or nothing>
        fresh_home
        mkdir -p "${WORK}/home/homebrew/services"
        : > "${LOADER}"
        chmod +x "${LOADER}"
        echo "user_home_t" > "${WORK}/label"
        : > "${WORK}/rules"
        printf '%s' "${1:-}" > "${WORK}/match"
    }

    run_labeler() {
        PATH="${STUB}:${PATH}" \
            AQ_TEST_LABEL="${WORK}/label" \
            AQ_TEST_RULES="${WORK}/rules" \
            AQ_TEST_MATCH="${WORK}/match" \
            AQ_TEST_CHCON_WORKS="${CHCON_WORKS:-1}" \
            bash "${LABELER}" "$@" > "${OUT}" 2>&1
        return $?
    }

    # --- the ordinary case: the /home spelling reaches the file --------------
    label_world "${SPEC_HOME}"
    CHCON_WORKS=1
    run_labeler "${LOADER}"
    rc=$?
    if [ "${rc}" -eq 0 ]; then
        ok "labelling succeeds when the /home rule reaches the file"
    else
        sed 's/^/       /' "${OUT}" >&2
        bad "labelling failed even though the /home rule reached the file (exit ${rc})"
    fi
    if grep -qxF -- "${SPEC_HOME}" "${WORK}/rules"; then
        ok "and it wrote the LASTING rule, in the /home spelling"
    else
        sed 's/^/       /' "${WORK}/rules" >&2
        bad "no ${SPEC_HOME} rule was written — a relabel would undo the label"
    fi
    if [ "$(cat "${WORK}/label")" = "bin_t" ]; then
        ok "and the file ends up labelled bin_t — a program"
    else
        bad "the file is still labelled $(cat "${WORK}/label")"
    fi
    says 'rule says so' "and it says the label will survive a relabel"

    # --- the machine where only the real path matches ------------------------
    # This is what a system without Fedora's /var/home equivalency looks like.
    # The program must notice that the first rule did nothing — by READING THE
    # LABEL BACK, not by believing semanage's silence — and try the other
    # spelling before giving up.
    label_world "${SPEC_REAL}"
    run_labeler "${LOADER}"
    rc=$?
    if [ "${rc}" -eq 0 ] && [ "$(cat "${WORK}/label")" = "bin_t" ]; then
        ok "when the /home rule does not reach the file, it tries the real path and succeeds"
    else
        sed 's/^/       /' "${OUT}" >&2
        bad "it gave up when the /home spelling did not take (exit ${rc}, label $(cat "${WORK}/label"))"
    fi
    says 'real path' "and says which spelling it fell back to"

    # --- no semanage at all: chcon, and say that nothing remembers it --------
    mv "${STUB}/semanage" "${WORK}/semanage.away"
    label_world ""
    run_labeler "${LOADER}"
    rc=$?
    mv "${WORK}/semanage.away" "${STUB}/semanage"
    if [ "${rc}" -eq 0 ] && [ "$(cat "${WORK}/label")" = "bin_t" ]; then
        ok "with no semanage it falls back to chcon and the file is still labelled"
    else
        sed 's/^/       /' "${OUT}" >&2
        bad "with no semanage it did not fall back to chcon (exit ${rc})"
    fi
    says 'NOTHING REMEMBERS IT' "and warns plainly that the fallback does not survive a relabel"

    # --- everything fails: REFUSE, and never call it done --------------------
    # ⚠️ THE HEART OF THE BENCH BUG. The old code ran one chcon, ignored the
    # answer and carried on, so an install that could not label anything still
    # ended with "Decky Loader is installed and running". Here every way of
    # labelling does nothing, and the program must say so and exit non-zero, so
    # that 'aq decky install' stops instead of switching on a service that
    # cannot start.
    label_world ""
    CHCON_WORKS=0
    run_labeler "${LOADER}"
    rc=$?
    CHCON_WORKS=1
    if [ "${rc}" -ne 0 ]; then
        ok "when nothing can label the file it REFUSES, instead of claiming success"
    else
        sed 's/^/       /' "${OUT}" >&2
        bad "it reported success with the file still labelled $(cat "${WORK}/label")"
    fi
    says 'user_home_t' "and names the wrong label the file is still wearing"
    says '203/EXEC' "and names the failure a person will see in the journal"
    says 'decky.md' "and points at the guide"

    # --- --forget takes our rule away again ---------------------------------
    label_world "${SPEC_HOME}"
    run_labeler "${LOADER}"
    run_labeler --forget "${LOADER}"
    rc=$?
    if [ "${rc}" -eq 0 ]; then
        ok "'--forget' succeeds"
    else
        sed 's/^/       /' "${OUT}" >&2
        bad "'--forget' exited ${rc}"
    fi
    if grep -qxF -- "${SPEC_HOME}" "${WORK}/rules"; then
        sed 's/^/       /' "${WORK}/rules" >&2
        bad "'aq decky remove' would leave the SELinux rule behind"
    else
        ok "and the rule is gone, so 'aq decky remove' leaves no policy behind"
    fi

    # --- aq really calls it -------------------------------------------------
    # A perfect helper nobody runs is the same as no helper at all.
    if grep -q 'aquarius-decky-label' "${AQ}"; then
        ok "'aq decky' calls the labelling program"
    else
        bad "'aq decky' never calls aquarius-decky-label — the loader would go unlabelled"
    fi
    # Once where it is defined, and once in each of install, update and remove.
    if [ "$(grep -c 'AQ_DECKY_LABEL' "${AQ}")" -ge 4 ]; then
        ok "install, update and remove all hand it the labelling program"
    else
        bad "not every part of 'aq decky' passes AQ_DECKY_LABEL through to its administrator half"
    fi
fi

# -----------------------------------------------------------------------------
# 3e. `aq decky status` shows the label
# -----------------------------------------------------------------------------
# The label is the first thing to look at when Decky is installed and simply
# never appears, so it belongs in the ordinary report rather than in a fault
# path nobody finds.
echo ""
echo "-- status reports the SELinux label --"
fresh_home
mkdir -p "${WORK}/home/homebrew/services"
: > "${WORK}/home/homebrew/services/PluginLoader"
chmod +x "${WORK}/home/homebrew/services/PluginLoader"
run_aq decky status
says 'SELinux label' "status has a line for the SELinux label"

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
