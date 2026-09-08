#!/usr/bin/env bash
# ==============================================================================
# Tests for the USB4 / Thunderbolt rescue
# ==============================================================================
# THE BUG THESE TESTS EXIST FOR
#
# 7 September 2026. Royce's external drive stopped being discoverable on the
# bench PC. The drive, the dock and the cable were all fine, and so was every
# piece of the auto-mounting machinery. What had happened was one line in the
# kernel log:
#
#     thunderbolt 0000:70:00.0: probe with driver thunderbolt failed with error -110
#
# The chip that runs the fast USB-C sockets did not get its driver, so nothing
# plugged into those sockets existed as far as the rest of the computer was
# concerned. /usr/libexec/aquarius-usb4-rescue asks the kernel to try again.
#
# A safety net whose trigger has never been executed is not a safety net; it is
# a comment. These tests execute it, on both sides, with fakes.
#
# ------------------------------------------------------------------------------
# HOW THE FAKING WORKS
# ------------------------------------------------------------------------------
# The rescue reads and writes ONE place: /sys, the kernel's folder of
# files-that-are-really-hardware. AQ_SYSFS_ROOT points it at a temporary folder
# instead, so every "write to the kernel" lands in an ordinary file this test
# can read back. Nothing here needs root and nothing here touches the machine
# it runs on.
#
# A fake machine is a handful of files:
#
#   bus/pci/devices/<address>/class          0x0c0340 makes it a USB4 chip
#   bus/pci/devices/<address>/driver         a symlink = "it has a driver"
#   bus/pci/devices/<address>/reset_method   non-empty = "it can be reset"
#   bus/pci/devices/<address>/reset          the rescue writes 1 here
#   bus/pci/drivers/thunderbolt/bind         the rescue writes the address here
#
# Because the fake `bind` is an ordinary file and no real kernel is behind it,
# writing to it does NOT make a driver appear — which is exactly the failing
# machine we want to test. The SUCCESS case is faked the other way round, on
# the modprobe hook: AQ_USB4_MODPROBE is pointed at a small script that creates
# the `driver` symlink, which is the real-life case of "the driver simply was
# not loaded yet, and once it was, the kernel probed the chip successfully".
#
# Two other knobs keep this test to a second rather than a minute:
#   AQ_USB4_WAIT=0      do not wait for the kernel to finish its own attempt
#   AQ_USB4_SETTLE=0    do not wait after a reset
#
# HOW TO RUN IT
#   ./tests/test-usb4-rescue.sh
#   ./tests/test-usb4-rescue.sh /usr/libexec/aquarius-usb4-rescue   (installed)
# ==============================================================================

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
RESCUE="${1:-${HERE}/../system_files/usr/libexec/aquarius-usb4-rescue}"

if [ ! -r "${RESCUE}" ]; then
    echo "test-usb4-rescue: cannot read ${RESCUE}" >&2
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

# The address of the chip in Royce's bench PC, used throughout so that the test
# output and the real journal read the same way.
BENCH="0000:70:00.0"
OTHER="0000:0e:00.0"

# ------------------------------------------------------------------------------
# scenario <name> — build a fake machine
# ------------------------------------------------------------------------------
# Every scenario starts the same: ONE USB4 chip, at the bench address, with NO
# driver attached and a kernel that says it can be reset ("pm bus", which is
# what the real bench PC reports). A case then changes one thing — the
# difference IS the test.
ROOT=""
scenario() {
    ROOT="${WORK}/$1"
    mkdir -p "${ROOT}/bus/pci/devices/${BENCH}"
    mkdir -p "${ROOT}/bus/pci/drivers/thunderbolt"
    printf '0x0c0340\n' > "${ROOT}/bus/pci/devices/${BENCH}/class"
    printf 'pm bus\n' > "${ROOT}/bus/pci/devices/${BENCH}/reset_method"
    : > "${ROOT}/bus/pci/devices/${BENCH}/reset"
    : > "${ROOT}/bus/pci/drivers/thunderbolt/bind"
}

# add_bound <address> — a second USB4 chip that already HAS its driver
add_bound() {
    local addr="$1"
    mkdir -p "${ROOT}/bus/pci/devices/${addr}"
    printf '0x0c0340\n' > "${ROOT}/bus/pci/devices/${addr}/class"
    printf 'pm bus\n' > "${ROOT}/bus/pci/devices/${addr}/reset_method"
    : > "${ROOT}/bus/pci/devices/${addr}/reset"
    ln -sf "../../drivers/thunderbolt" "${ROOT}/bus/pci/devices/${addr}/driver"
}

# add_unrelated <address> <class> — a device that is NOT a USB4 host router.
# It must be ignored, or the rescue would be resetting a graphics card.
add_unrelated() {
    mkdir -p "${ROOT}/bus/pci/devices/$1"
    printf '%s\n' "$2" > "${ROOT}/bus/pci/devices/$1/class"
    : > "${ROOT}/bus/pci/devices/$1/reset"
}

# A modprobe that pretends the driver loaded AND the kernel then probed the
# chip successfully — it creates the `driver` symlink the rescue looks for.
make_lucky_modprobe() {
    cat > "${ROOT}/modprobe-lucky" << STUB
#!/usr/bin/env bash
ln -sf "../../drivers/thunderbolt" "${ROOT}/bus/pci/devices/${BENCH}/driver"
exit 0
STUB
    chmod 0755 "${ROOT}/modprobe-lucky"
}

# ------------------------------------------------------------------------------
# run_rescue [arguments…] — the real program, against the fake machine
# ------------------------------------------------------------------------------
RC=0
run_rescue() {
    AQ_SYSFS_ROOT="${ROOT}" \
        AQ_USB4_WAIT=0 \
        AQ_USB4_SETTLE=0 \
        AQ_USB4_MODPROBE="${AQ_TEST_MODPROBE:-true}" \
        bash "${RESCUE}" "$@" > "${ROOT}/said.txt" 2>&1
    RC=$?
}

said() { cat "${ROOT}/said.txt"; }
show() { sed 's/^/       /' "${ROOT}/said.txt"; }

# ------------------------------------------------------------------------------
# Reading the fake kernel back
# ------------------------------------------------------------------------------
# ⚠️ A WRITE TO /sys REPLACES THE FILE, IT DOES NOT ADD TO IT. That is how the
# real kernel works — one write is one instruction — and the rescue does the
# same thing, so the fake `bind` file ends up holding only the LAST address
# written to it, however many times it was written.
#
# So the two questions are answered two ways, and both are needed:
#
#   * DID A WRITE REACH THE KERNEL, AND WITH WHAT? — read the file. A `bind`
#     file holding the chip's address is proof the rescue really wrote it, and
#     an empty one is proof it wrote nothing at all. This is the check that
#     matters for "it left the healthy machine alone".
#
#   * HOW MANY TIMES, AND IN WHAT ORDER? — count the rescue's own log lines.
#     That is weaker (it counts what the program says it did), which is why the
#     file contents above are checked as well.
bind_content() { cat "${ROOT}/bus/pci/drivers/thunderbolt/bind" 2> /dev/null; }
reset_content() { cat "${ROOT}/bus/pci/devices/${BENCH}/reset" 2> /dev/null; }

# "" for a file that was never written to, "yes" for one that was.
wrote_to() { [ -s "$1" ] && echo yes; }
bind_written() { wrote_to "${ROOT}/bus/pci/drivers/thunderbolt/bind"; }
reset_written() { wrote_to "${ROOT}/bus/pci/devices/${BENCH}/reset"; }

count_said() {
    local n
    n="$(grep -c -- "$1" "${ROOT}/said.txt" 2> /dev/null)"
    printf '%s' "${n:-0}"
}
# Every line on which the rescue says it is writing into the bind file — the
# opening attempt, and the second try after a reset.
bind_attempts() {
    local a b
    a="$(count_said 'into .*thunderbolt/bind')"
    b="$(count_said 'trying the bind again after the reset')"
    printf '%s' "$((a + b))"
}
reset_attempts() { count_said 'Resetting the chip'; }

# ==============================================================================
echo "== a chip that already has its driver is left completely alone =="
# ==============================================================================
# This is the case that has to be right first. Resetting a working USB4
# controller would take out somebody's dock, their screen and their drive in one
# go, in the name of fixing them.
scenario bound-only
rm -rf "${ROOT}/bus/pci/devices/${BENCH}"          # remove the broken one
add_bound "${OTHER}"
run_rescue
if [ "${RC}" -ne 0 ]; then
    fail "it failed on a healthy machine (rc=${RC})"
    show
elif [ -n "$(bind_written)" ]; then
    fail "it wrote to the kernel on a machine where every chip already had a driver"
    show
elif ! said | grep -q "leaving it alone"; then
    fail "it said nothing about leaving the healthy chip alone"
    show
else
    pass "a bound chip is skipped: nothing written, nothing reset, and it says so"
fi

# And with one of each, only the broken one is touched.
scenario one-of-each
add_bound "${OTHER}"
run_rescue
if [ -z "$(reset_written)" ]; then
    fail "the broken chip was not reset at all"
    show
elif [ -e "${ROOT}/bus/pci/devices/${OTHER}/reset" ] \
    && [ -s "${ROOT}/bus/pci/devices/${OTHER}/reset" ]; then
    fail "it reset the chip that already had a driver"
    show
elif ! bind_content | grep -q "${BENCH}"; then
    fail "it never asked the driver to take the broken chip"
    show
elif bind_content | grep -q "${OTHER}"; then
    fail "it asked the driver to take the chip that already had one"
    show
else
    pass "with one broken and one healthy chip, only the broken one is touched"
fi

# ==============================================================================
echo ""
echo "== a chip with no driver gets a bind write =="
# ==============================================================================
scenario unbound
run_rescue
if ! bind_content | grep -q "^${BENCH}$"; then
    fail "the chip's address was never written to the driver's bind file"
    show
elif ! said | grep -q "\[usb4-rescue\]"; then
    fail "nothing was logged with the [usb4-rescue] tag a person would grep for"
    show
else
    pass "the address ${BENCH} is written into .../drivers/thunderbolt/bind"
fi

# ==============================================================================
echo ""
echo "== a bind that does not take is followed by a reset, then another bind =="
# ==============================================================================
# This is the actual rescue. The fake bind file cannot make a driver appear, so
# every attempt fails — which is precisely the machine this was written for.
scenario retry-with-reset
run_rescue
binds="$(bind_attempts)"
resets="$(reset_attempts)"
if [ "${resets}" -lt 1 ]; then
    fail "the bind failed and the chip was never reset (resets=${resets})"
    show
elif [ "${binds}" -lt 2 ]; then
    fail "the chip was reset but no second bind was attempted (binds=${binds})"
    show
elif [ "${binds}" -ne 6 ] || [ "${resets}" -ne 3 ]; then
    fail "expected 3 attempts of (bind, reset, bind) = 6 binds and 3 resets; got ${binds} binds and ${resets} resets"
    show
elif [ "$(bind_content)" != "${BENCH}" ]; then
    fail "the bind file does not hold the chip's address (it holds '$(bind_content)')"
    show
elif [ "$(reset_content)" != "1" ]; then
    fail "the reset file does not hold 1 (it holds '$(reset_content)')"
    show
else
    pass "3 attempts, each one bind → reset → bind: 6 bind writes, 3 resets"
    pass "the writes really landed: bind holds ${BENCH}, reset holds 1"
fi
if said | grep -q "Resetting the chip"; then
    pass "it says in plain words that it is resetting the chip"
else
    fail "the reset happens but the log does not say so"
    show
fi

# A chip the kernel says cannot be reset must NOT be reset — an empty
# reset_method is the kernel saying "I know no safe way to do that".
scenario no-reset-method
: > "${ROOT}/bus/pci/devices/${BENCH}/reset_method"
run_rescue
if [ -n "$(reset_written)" ]; then
    fail "it reset a chip whose reset_method file was empty"
    show
elif ! said | grep -q "no way to reset"; then
    fail "it skipped the reset but did not say why"
    show
else
    pass "an empty reset_method means no reset is attempted, and it says why"
fi

# ==============================================================================
echo ""
echo "== the driver simply not being loaded yet is handled without any bind =="
# ==============================================================================
# The commonest harmless case: modprobe loads the driver, the kernel probes the
# chip on its own, and there is nothing left for the rescue to do.
scenario modprobe-is-enough
make_lucky_modprobe
AQ_TEST_MODPROBE="${ROOT}/modprobe-lucky" run_rescue
if [ "${RC}" -ne 0 ]; then
    fail "it failed on a machine it had just rescued (rc=${RC})"
    show
elif [ -n "$(bind_written)" ] || [ -n "$(reset_written)" ]; then
    fail "the driver attached after modprobe and it forced a bind anyway"
    show
elif ! said | grep -qi "driver"; then
    fail "it rescued the machine and said nothing about it"
    show
else
    pass "when loading the driver is enough, nothing is bound and nothing is reset"
fi

# ==============================================================================
echo ""
echo "== service mode always exits 0; --rescue tells a person the truth =="
# ==============================================================================
# ⚠️ THE RULE THIS PROTECTS. A rescue must never be the reason a boot goes
# wrong. Service mode exits 0 even having failed, so a machine does not carry a
# red line in `systemctl status` for the rest of its life. A person who TYPED
# the command needs the opposite: they have to be told it did not work.
scenario service-mode-fails
run_rescue
if [ "${RC}" -ne 0 ]; then
    fail "service mode exited ${RC} after a failed rescue — it must always exit 0"
    show
elif ! said | grep -q "must never be the reason a boot goes wrong"; then
    fail "service mode exited 0 but did not say why in the journal"
    show
else
    pass "service mode exits 0 even when the rescue failed, and says so"
fi
if said | grep -q "power-off"; then
    pass "a failed rescue tells the person the one thing left to try (a full power-off)"
else
    fail "a failed rescue does not mention the full power-off"
    show
fi

scenario rescue-mode-fails
run_rescue --rescue
if [ "${RC}" -ne 1 ]; then
    fail "'--rescue' exited ${RC} after failing — a person must be told it did not work (expected 1)"
    show
else
    pass "'--rescue' exits 1 when the chip still has no driver"
fi

scenario rescue-mode-succeeds
make_lucky_modprobe
AQ_TEST_MODPROBE="${ROOT}/modprobe-lucky" run_rescue --rescue
if [ "${RC}" -ne 0 ]; then
    fail "'--rescue' exited ${RC} after a successful rescue (expected 0)"
    show
else
    pass "'--rescue' exits 0 when the chip ends up with a driver"
fi

# A machine with no USB4 chip at all is not a failure — most machines are that.
scenario no-usb4-hardware
rm -rf "${ROOT}/bus/pci/devices/${BENCH}"
add_unrelated "0000:01:00.0" "0x030000"      # a graphics card
run_rescue --rescue
if [ "${RC}" -ne 0 ]; then
    fail "a machine with no USB4 chip was reported as a failure (rc=${RC})"
    show
elif [ -s "${ROOT}/bus/pci/devices/0000:01:00.0/reset" ]; then
    fail "IT RESET THE GRAPHICS CARD. Only class 0x0c0340 may be touched."
    show
else
    pass "a machine with no USB4 chip is fine, and unrelated hardware is never touched"
fi

# ==============================================================================
echo ""
echo "== --dry-run writes nothing at all =="
# ==============================================================================
# This is what the build step runs, inside a container with no such hardware.
scenario dry-run
run_rescue --dry-run
if [ "${RC}" -ne 0 ]; then
    fail "--dry-run exited ${RC} (it must always exit 0)"
    show
elif [ -n "$(bind_written)" ] || [ -n "$(reset_written)" ]; then
    fail "--dry-run wrote to the kernel. It must change nothing."
    show
elif ! said | grep -q "0x0c0340"; then
    fail "--dry-run does not state the class number it looks for"
    show
elif ! said | grep -q "power-off"; then
    fail "--dry-run does not state the honest limit"
    show
else
    pass "--dry-run writes nothing, names the class 0x0c0340, and states its limit"
fi

# ==============================================================================
echo ""
echo "== --status looks and never touches =="
# ==============================================================================
scenario status
run_rescue --status
if [ "${RC}" -ne 0 ]; then
    fail "--status exited ${RC}"
    show
elif [ -n "$(bind_written)" ] || [ -n "$(reset_written)" ]; then
    fail "--status wrote to the kernel"
    show
elif ! said | grep -q "${BENCH}"; then
    fail "--status did not mention the chip it can see"
    show
elif ! said | grep -q "driver attached : NO"; then
    fail "--status did not say the chip has no driver"
    show
else
    pass "--status reports the chip and its missing driver, and writes nothing"
fi

# ==============================================================================
echo ""
echo "== the rules that cannot be checked by running it =="
# ==============================================================================
if bash -n "${RESCUE}"; then
    pass "the rescue is valid shell"
else
    fail "the rescue does not parse as shell"
fi

# --help must print the header, because the header is the documentation.
scenario help
run_rescue --help
if [ "${RC}" -eq 0 ] && said | grep -q "aquarius-usb4-rescue"; then
    pass "--help prints the program's own header"
else
    fail "--help did not print the header"
    show
fi

# Something it does not understand must be an error, not a silent rescue.
scenario nonsense
run_rescue --burn-it-down
if [ "${RC}" -eq 1 ] && [ -z "$(bind_written)" ]; then
    pass "an argument it does not understand is refused, and nothing is written"
else
    fail "an unknown argument was not refused cleanly (rc=${RC})"
    show
fi

# ⚠️ The class number is the feature. Written wrong, the program searches for
# hardware that does not exist, finds nothing, reports success, and rescues
# nobody — silently, forever. It is checked here as literal text as well as by
# behaviour above.
if grep -q 'AQ_USB4_CLASS="0x0c0340"' "${RESCUE}"; then
    pass "it looks for PCI class 0x0c0340 (USB4 host interface)"
else
    fail "the PCI class the rescue looks for is not 0x0c0340"
fi

# It must never write anywhere but the fake root in a test — i.e. every path it
# touches has to be built from AQ_SYSFS_ROOT.
if grep -qE '^AQ_PCI_DEVICES="\$\{AQ_SYSFS_ROOT\}' "${RESCUE}" \
    && grep -qE '^AQ_TB_DRIVER="\$\{AQ_SYSFS_ROOT\}' "${RESCUE}"; then
    pass "every path it writes to is built from AQ_SYSFS_ROOT, so a test cannot touch the real machine"
else
    fail "a path in the rescue is hard-coded to /sys — a test would write to the real kernel"
fi

echo ""
echo "  passed ${PASSED}, failed ${FAILED}"
if [ "${FAILED}" -ne 0 ]; then
    echo "  The retry that is supposed to bring a sulking USB4 controller back would"
    echo "  not bring it back. See docs/restart/usb4.md."
    exit 1
fi
echo "  The rescue leaves working chips alone, and retries a chip with no driver:"
echo "  bind, reset, bind, three times, then says honestly that it could not."
exit 0
