#!/usr/bin/env bash
# ==============================================================================
# Tests for aquarius-media-dir — the folder every drive appears in
# ==============================================================================
# WHAT THIS PROGRAM IS, AND WHY IT IS WORTH TESTING
#
# /usr/libexec/aquarius-media-dir creates /run/media/<you> at the start of every
# login. Two things depend on it and both fail invisibly:
#
#   * the dock lists your drives by WATCHING that folder, and Qt's directory
#     watcher silently lists the program's working directory — your home folder —
#     when the folder it was given does not exist. That is the bug that drew
#     thirty of Royce's home folders as "drives" on 6 September 2026.
#   * a Mac drive is mounted by the PERSON, with apfs-fuse, so the person has to
#     be able to create a folder in there. udisks2's own version of this folder
#     is read-only to them.
#
# ⚠️ AND IT RUNS ON THE LOGIN PATH. systemd runs it before your session starts.
# A program that can fail there is a program that can stop somebody logging in,
# so "it always exits 0" is not a nicety here — it is the most important thing
# this file checks, and it is checked against every way it can go wrong.
#
# ------------------------------------------------------------------------------
# HOW THE FAKING WORKS
# ------------------------------------------------------------------------------
# Two knobs, both of which exist only for this test:
#
#   AQ_MEDIA_BASE   where /run/media is. Pointed at a temporary folder, so
#                   nothing here touches the machine it runs on and none of it
#                   needs root.
#   AQ_FIRST_UID    the lowest user number that counts as a real person.
#
# and one fake command: a `getent` earlier on the PATH than the real one, which
# answers with whatever account this test wants to pretend exists. The user
# number it answers with is THIS test's own, so that the chown the program does
# is a real chown that really succeeds — a test that ran as root would prove
# something a login never does.
#
# HOW TO RUN IT
#   ./tests/test-media-dir.sh
#   ./tests/test-media-dir.sh /usr/libexec/aquarius-media-dir   (installed)
# ==============================================================================

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
HELPER="${1:-${HERE}/../system_files/usr/libexec/aquarius-media-dir}"

if [ ! -r "${HELPER}" ]; then
    echo "test-media-dir: cannot read ${HELPER}" >&2
    exit 1
fi

export LC_ALL=C

PASSED=0
FAILED=0
pass() {
    echo "  ok   $*"
    PASSED=$((PASSED + 1))
}
fail() {
    echo "  FAIL $*"
    FAILED=$((FAILED + 1))
}

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

ME_UID="$(id -u)"
ME_GID="$(id -g)"

# ------------------------------------------------------------------------------
# The fake `getent`, which is the only way this program learns about accounts
# ------------------------------------------------------------------------------
mkdir -p "${WORK}/bin"
cat > "${WORK}/bin/getent" << EOF
#!/usr/bin/env bash
# Answers for exactly three made-up accounts and nothing else, in the same
# colon-separated shape the real getent uses:
#   name:password:uid:gid:comment:home:shell
case "\$2" in
    tester | ${ME_UID}) echo "tester:x:${ME_UID}:${ME_GID}:Test person:/home/tester:/bin/bash" ;;
    machine | 42)       echo "machine:x:42:42:A system account:/var/lib/machine:/sbin/nologin" ;;
    odd/name)           echo "odd/name:x:${ME_UID}:${ME_GID}::/home/odd:/bin/bash" ;;
    *) exit 2 ;;
esac
EOF
chmod +x "${WORK}/bin/getent"
export PATH="${WORK}/bin:${PATH}"

run_helper() {
    # Runs the helper against a fresh /run/media and prints its exit code.
    AQ_MEDIA_BASE="$1" AQ_FIRST_UID=1000 bash "${HELPER}" "${2:-}" > "${WORK}/out.txt" 2>&1
    echo "$?"
}

echo "== aquarius-media-dir: the folder every drive appears in =="
echo "   under test: ${HELPER}"
echo ""

# ------------------------------------------------------------------------------
# 1. An ordinary person logging in
# ------------------------------------------------------------------------------
BASE="${WORK}/case1"
code="$(run_helper "${BASE}" "${ME_UID}")"
if [ "${code}" = "0" ]; then
    pass "it exits 0 for an ordinary login"
else
    fail "it exited ${code} for an ordinary login — that could stop somebody logging in"
    sed 's/^/       /' "${WORK}/out.txt"
fi

if [ -d "${BASE}/tester" ]; then
    pass "it creates ${BASE}/tester"
else
    fail "it did not create ${BASE}/tester — the dock would have no folder to watch"
fi

if [ -d "${BASE}" ]; then
    mode="$(stat -c '%a' "${BASE}")"
    if [ "${mode}" = "755" ]; then
        pass "/run/media itself is mode 0755, exactly as udisks2 makes it"
    else
        fail "/run/media is mode ${mode}, expected 755 (what udisks2 makes)"
    fi
fi

if [ -d "${BASE}/tester" ]; then
    mode="$(stat -c '%a' "${BASE}/tester")"
    owner="$(stat -c '%u' "${BASE}/tester")"
    if [ "${mode}" = "700" ]; then
        pass "the person's folder is mode 0700 — nobody else on the machine can look in"
    else
        fail "the person's folder is mode ${mode}, expected 700"
    fi
    if [ "${owner}" = "${ME_UID}" ]; then
        pass "and it BELONGS to them, which is what lets a Mac drive be mounted by their own session"
    else
        fail "the folder belongs to uid ${owner}, not ${ME_UID} — apfs-fuse could not create a mount folder in it"
    fi
    # The whole point of owning it: they can make a folder inside it.
    if mkdir "${BASE}/tester/SHOOT 2026" 2> /dev/null; then
        pass "and they really can create a mount folder in it (the thing udisks2's own version forbids)"
        rmdir "${BASE}/tester/SHOOT 2026"
    else
        fail "a mount folder could NOT be created inside it — every Mac drive would fail with permission denied"
    fi
fi

# ------------------------------------------------------------------------------
# 2. The machine's own accounts are left alone
# ------------------------------------------------------------------------------
BASE="${WORK}/case2"
code="$(run_helper "${BASE}" "42")"
if [ "${code}" = "0" ] && [ ! -d "${BASE}/machine" ]; then
    pass "a system account (user number below 1000) gets no folder and no complaint"
else
    fail "a system account produced exit ${code} and $( [ -d "${BASE}/machine" ] && echo "a folder" || echo "no folder")"
fi

# ------------------------------------------------------------------------------
# 3. Running twice changes nothing (every login runs it)
# ------------------------------------------------------------------------------
BASE="${WORK}/case3"
run_helper "${BASE}" "${ME_UID}" > /dev/null
chmod 0711 "${BASE}/tester"
before="$(stat -c '%a %u' "${BASE}/tester")"
code="$(run_helper "${BASE}" "${ME_UID}")"
after="$(stat -c '%a %u' "${BASE}/tester")"
if [ "${code}" = "0" ] && [ "${before}" = "${after}" ]; then
    pass "a second login leaves a folder that is already there exactly as it is"
else
    fail "a second login changed the folder from '${before}' to '${after}' (exit ${code})"
fi

# ------------------------------------------------------------------------------
# 4. ⚠️ Every way it can go wrong still exits 0
# ------------------------------------------------------------------------------
# This is the group that matters most. Each of these is a real situation and
# none of them may stop a login.
BASE="${WORK}/case4"
code="$(run_helper "${BASE}" "nobody-by-that-name")"
if [ "${code}" = "0" ]; then
    pass "an account that does not exist: exits 0"
else
    fail "an account that does not exist exited ${code} — that would stop a login"
fi

code="$(run_helper "${BASE}" "")"
if [ "${code}" = "0" ]; then
    pass "no argument at all: exits 0"
else
    fail "no argument exited ${code} — that would stop a login"
fi

code="$(run_helper "${BASE}" "odd/name")"
if [ "${code}" = "0" ]; then
    pass "an account name with a slash in it: exits 0 and leaves it to udisks2"
else
    fail "a name with a slash exited ${code} — that would stop a login"
fi

# A place it cannot possibly create anything. /proc is a kernel folder and
# nothing can be made in it, by anybody, ever.
code="$(run_helper "/proc/aquarius-cannot-exist" "${ME_UID}")"
if [ "${code}" = "0" ]; then
    pass "a folder it is not allowed to create: exits 0, and says so plainly"
    if grep -qi "could not create" "${WORK}/out.txt"; then
        pass "and the message is a sentence, not a shell error"
    else
        fail "it said nothing useful when it could not create the folder:"
        sed 's/^/       /' "${WORK}/out.txt"
    fi
else
    fail "an uncreatable folder exited ${code} — THAT WOULD STOP A LOGIN"
    sed 's/^/       /' "${WORK}/out.txt"
fi

# ------------------------------------------------------------------------------
# 5. The rehearsal the build runs
# ------------------------------------------------------------------------------
if AQ_MEDIA_BASE="${WORK}/case5" bash "${HELPER}" --dry-run > "${WORK}/dry.txt" 2>&1; then
    pass "--dry-run runs and exits 0"
else
    fail "--dry-run failed"
fi
if [ -d "${WORK}/case5" ]; then
    fail "--dry-run created something — it must change nothing at all"
else
    pass "and creates nothing"
fi
if grep -q "0700" "${WORK}/dry.txt" && grep -qi "owned by" "${WORK}/dry.txt"; then
    pass "and states the permissions it makes, so a change to them is visible in the build log"
else
    fail "--dry-run does not state what it makes:"
    sed 's/^/       /' "${WORK}/dry.txt"
fi

echo ""
echo "  ${PASSED} passed, ${FAILED} failed"
if [ "${FAILED}" -ne 0 ]; then
    echo "::error::aquarius-media-dir is not behaving. See docs/restart/mac-drives.md."
    exit 1
fi
echo "All aquarius-media-dir checks passed."
exit 0
