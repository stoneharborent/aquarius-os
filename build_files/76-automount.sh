#!/usr/bin/bash
# ==============================================================================
# STEP 76 — Every drive mounts by itself, with no password
# ==============================================================================
# WHAT THIS STEP IS FOR
#
# On AquariusOS, plugging in a USB stick, an SD card or an external SSD makes it
# appear on its own — no password, and you eject it from the dock the same way.
# Since 2026-10-19 the drives INSIDE the computer do the same: every one of them
# is mounted when you log in, with no question and no password, and shows in
# the dock. Royce:
#
#     "Remove verification for all internal and external drives. Just mount
#      them from login and show in dock."
#
# That retired the "ask once" feature (FEATURES 020: build_files/83-remembered-
# drives.sh, /usr/libexec/aquarius-remember-drive and its two polkit files),
# which used to ask "Mount every login?" and write a yes into /etc/fstab. Lines
# it already wrote on somebody's machine keep working; the agent sees them in
# fstab and leaves those drives to the machine. Decision record:
# ../docs/decision-2026-10-19-gnome-only-and-open-drives.md.
#
# It is four pieces:
#
#   1. udisks2 — Fedora's drive-mounting service. It is already installed by
#      step 20 (the hardware/media floor); this step confirms it, because the
#      other three are useless without it.
#   2. A small agent, /usr/libexec/aquarius-automount, that runs in the person's
#      session, watches udisks2 for a drive being plugged in, and asks it to
#      mount. This is the piece Fedora does not provide on its own.
#   3. A polkit rule, /usr/share/polkit-1/rules.d/49-aquarius-udisks.rules, that
#      lets the person at the screen mount/unmount/eject a drive — plugged in
#      OR inside the computer — with no password. Only the person at the screen.
#   4. A user service, switched on for the desktop session, that starts the
#      agent.
#
# ⚠️ AND THE SAFETY MOVED. Until 2026-10-19 the safety of internal disks was
# the polkit rule itself: it said nothing about udisks2's internal-disk action
# (filesystem-mount-system), so an internal disk asked for a password, and this
# step STOPPED THE BUILD if that action ever appeared in the rule. That gate is
# reversed on purpose now — the rule must grant it. What keeps the machine's
# own partitions safe instead is the agent's NEVER-TOUCH LIST (the disk the OS
# is on, the EFI partition, Windows Recovery, swap, hidden partitions, anything
# in fstab, encrypted drives…), and this step proves that list still holds by
# running tests/test-inside-drives.py against fake drives, most of which must
# be REFUSED.
#
# Pieces 2, 3 and 4 arrived in the image as plain files at step 50 (which copies
# everything under system_files/ into place). This step CHECKS the whole thing,
# because a drive that silently will not mount, or a password box for a USB
# stick, is exactly the kind of fault nobody sees until the one moment it
# matters.
#
# The filesystems those drives are formatted as — exFAT for camera cards, NTFS
# for Windows drives — are installed and checked by step 20.
#
# ⚠️ APFS (a Mac drive) IS NO LONGER OUT OF SCOPE, and this step is no longer the
# whole story. Since 2026-09-09 the agent takes a second path for exactly one
# kind of drive: a Mac drive, which udisks2 cannot mount because Linux has no
# APFS. It mounts those itself, read-only, with apfs-fuse, as the person. That
# half is installed and checked by build_files/82-apfs-drives.sh and explained in
# docs/restart/mac-drives.md. This step still owns everything else — udisks2, the
# polkit rule, the service — and it still runs tests/test-automount-mount.py,
# which now covers both paths.
#
# Plain-English guide: docs/restart/hardware.md, section "Plugging a drive in —
# and the bug that meant we never did".
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

AGENT="/usr/libexec/aquarius-automount"
UNIT="/usr/lib/systemd/user/aquarius-automount.service"
WANTS_LINK="/usr/lib/systemd/user/graphical-session.target.wants/aquarius-automount.service"
RULE="/usr/share/polkit-1/rules.d/49-aquarius-udisks.rules"

# ------------------------------------------------------------------------------
# 1. The machinery that actually mounts drives, and the filesystems it reads
# ------------------------------------------------------------------------------
say "The drive-mounting service and the filesystems creators plug in"
aq_installed \
    udisks2 \
    exfatprogs \
    ntfs-3g

# polkit itself has to be here, or a rule file is just text nobody reads.
aq_installed polkit

# ------------------------------------------------------------------------------
# 2. The agent — present, valid Python, and runnable with no screen
# ------------------------------------------------------------------------------
say "The auto-mount agent"
if [ -x "${AGENT}" ]; then
    ok "${AGENT} is present and runnable"
else
    bad "${AGENT} is missing or not runnable — nothing would mount a drive on insert"
fi

# It is Python. A syntax error must stop the build, not wait for a login.
if python3 -c 'import py_compile, sys; py_compile.compile(sys.argv[1], cfile="/tmp/aq-automount.pyc", doraise=True)' "${AGENT}" 2> /tmp/aq-automount-py.txt; then
    ok "the agent is valid Python"
else
    bad "the agent has a syntax error:"
    sed 's/^/       /' /tmp/aq-automount-py.txt
fi
rm -f /tmp/aq-automount.pyc /tmp/aq-automount-py.txt

# --dry-run is designed to work HERE — in a build container with no udisks2 and
# no system bus. It imports gi (proving python3-gobject is in the image), states
# its rules, and exits 0 without touching D-Bus. If this fails, the agent could
# not even load on a real machine.
say "The agent's rehearsal (--dry-run), which is what proves it loads"
if "${AGENT}" --dry-run > /tmp/aq-automount-dry.txt 2>&1; then
    ok "'aquarius-automount --dry-run' runs and changes nothing"
    sed 's/^/       /' /tmp/aq-automount-dry.txt
else
    bad "'aquarius-automount --dry-run' failed — the agent cannot load in this image:"
    sed 's/^/       /' /tmp/aq-automount-dry.txt
fi
# The rehearsal must state the never-touch list, word by word, so a future edit
# that quietly drops "the EFI partition" from it is caught here rather than on
# a machine that mounts its own start-up partition.
aq_file_has /tmp/aq-automount-dry.txt 'no password' \
    "the agent's rehearsal states that mounting needs no password"
aq_file_has /tmp/aq-automount-dry.txt 'HintSystem = true' \
    "the agent's rehearsal states that drives INSIDE the computer are mounted too"
aq_file_has /tmp/aq-automount-dry.txt 'never-touch list' \
    "the agent's rehearsal states its never-touch list"
aq_file_has /tmp/aq-automount-dry.txt 'disk AquariusOS is installed on' \
    "  …which leaves alone the disk AquariusOS is installed on"
aq_file_has /tmp/aq-automount-dry.txt '/sysroot' \
    "  …found from /sysroot too (on bootc, / is not a disk)"
aq_file_has /tmp/aq-automount-dry.txt 'EFI System Partition' \
    "  …and the EFI System Partition"
aq_file_has /tmp/aq-automount-dry.txt 'Windows Recovery' \
    "  …and Windows Recovery"
aq_file_has /tmp/aq-automount-dry.txt 'Microsoft Reserved' \
    "  …and Microsoft Reserved"
aq_file_has /tmp/aq-automount-dry.txt 'swap' \
    "  …and swap"
aq_file_has /tmp/aq-automount-dry.txt 'hidden' \
    "  …and hidden partitions"
aq_file_has /tmp/aq-automount-dry.txt 'already listed in /etc/fstab' \
    "  …and anything already in /etc/fstab (where the old 'ask once' drives live)"
aq_file_has /tmp/aq-automount-dry.txt 'installer stick' \
    "  …and the AquariusOS installer stick"
aq_file_has /tmp/aq-automount-dry.txt 'encrypted' \
    "  …and encrypted drives, which stay locked"
aq_file_has /tmp/aq-automount-dry.txt 'READ-ONLY' \
    "  …and that an inside Windows drive is mounted read-only"
rm -f /tmp/aq-automount-dry.txt

# ------------------------------------------------------------------------------
# ⚠️ AND THE ONE CHECK THAT WOULD HAVE CAUGHT THE BENCH FAULT: really mount
# ------------------------------------------------------------------------------
# THE FAULT, 2026-09-08. Royce plugged in his drives; they appeared in Files but
# not in the dock. The agent had crashed on EVERY mount since it shipped:
#
#     File ".../gi/overrides/GLib.py", line 396, in __getitem__
#     KeyError: 0
#
# One line built udisks2's Mount argument the wrong way round — a GLib.Variant
# wrapped inside another GLib.Variant, where PyGObject wants a plain dictionary.
# The two drives in /run/media had been mounted by the Files app, not by us.
#
# ⚠️ AND WHY THIS STEP DID NOT NOTICE. The two checks above are `py_compile` and
# "can Python import gi". Both passed, on every build, for five days. The broken
# line was perfectly valid Python and the fault only exists at the moment
# PyGObject actually builds the value — which nothing in this build ever asked
# it to do. A check that cannot fail is not a check.
#
# So tests/test-automount-mount.py calls mount() for real against a fake bus.
# The Variant is genuinely constructed, by the same PyGObject that is in this
# image, and the argument's type string is read back and compared. It also proves
# a refused mount logs a plain sentence instead of a traceback, and that an
# unexpected error — the exact shape of the fault above — is caught rather than
# escaping.
say "The agent really mounts a drive (against a fake bus)"
if [ -r /ctx/tests/test-automount-mount.py ]; then
    # -B: the test loads the agent as a module, and Python would otherwise
    # leave /usr/libexec/__pycache__ behind in the finished image — the third
    # build of this step (run 34301516538) failed on exactly that.
    if python3 -B /ctx/tests/test-automount-mount.py "${AGENT}"; then
        ok "the agent asks udisks2 to mount, in the shape udisks2 expects"
    else
        bad "the agent would NOT mount a drive — see the lines above. This is the"
        bad "2026-09-08 bench fault: drives appear in Files and never in the dock."
    fi
    # Belt and braces beside -B above: nothing of the test may stay in the image.
    # /usr/lib/aquarius/python is in the list because the agent imports the
    # shared Mac-drive reader from there, and Python writes a __pycache__ folder
    # beside any module it imports.
    rm -rf /usr/libexec/__pycache__ /usr/lib/aquarius/python/__pycache__
else
    bad "/ctx/tests/test-automount-mount.py is missing — the only check that proves a drive is really mounted"
fi

# ⚠️ THE NEVER-TOUCH LIST, PROVEN RATHER THAN READ. Since 2026-10-19 this list
# is the whole safety of mounting inside drives, and no amount of reading proves
# a refusal. This runs the agent's real decision code against fake drives — the
# EFI partition, Windows Recovery, a partition of the system disk, swap, an
# encrypted drive, a hidden recovery partition, the installer stick, a drive
# already in fstab — inside the finished image, with the Python really in it.
say "Every drive mounts at login — and the never-touch list holds (fake drives)"
if [ -r /ctx/tests/test-inside-drives.py ]; then
    if python3 -B /ctx/tests/test-inside-drives.py "${AGENT}"; then
        ok "inside drives are mounted, and every never-touch drive is refused"
    else
        bad "a drive that must NEVER be mounted was mounted, or an ordinary inside"
        bad "drive was not. See the lines above — this is the safety of the feature."
    fi
    rm -rf /usr/libexec/__pycache__ /usr/lib/aquarius/python/__pycache__
else
    bad "/ctx/tests/test-inside-drives.py is missing — the only check that proves a refusal"
fi

# Python must be able to reach GLib and Gio in this image — the two the agent
# imports. This is the automount equivalent of the GTK import check the Resolve
# window has, and it catches a missing python3-gobject.
if python3 -c 'import gi; gi.require_version("GLib","2.0"); gi.require_version("Gio","2.0"); from gi.repository import GLib, Gio' 2> /tmp/aq-gi.txt; then
    ok "Python can reach GLib and Gio — the agent's only dependency"
else
    bad "Python cannot import GLib and Gio — the agent would not run"
    sed 's/^/       /' /tmp/aq-gi.txt
fi
rm -f /tmp/aq-gi.txt
aq_installed python3-gobject

# ⚠️ AND THE SHAPE ITSELF, READ BACK OUT OF THE FILE. The test above is the real
# guard; this is the cheap one that names the mistake, so that a future edit
# reintroducing it is refused with the reason attached rather than with a type
# string nobody can read.
# Comment lines are dropped before looking, because the agent's own comment
# quotes the wrong shape to explain it — and the first build of this check
# (run 34299873627) failed on exactly that quotation.
if grep -v '^[[:space:]]*#' "${AGENT}" | grep -q 'GLib.Variant("(a{sv})", (options,))' \
    && grep -v '^[[:space:]]*#' "${AGENT}" | grep -q 'options = GLib.Variant("a{sv}"'; then
    bad "the agent wraps a GLib.Variant inside another GLib.Variant again — that is"
    bad "the 2026-09-08 'KeyError: 0' and it kills every mount. Pass a plain dict."
elif grep -v '^[[:space:]]*#' "${AGENT}" | grep -q '^[[:space:]]*options = {'; then
    ok "the mount options are a plain dictionary, not a Variant inside a Variant"
else
    bad "could not find 'options = {' in the agent — the mount-options shape has changed; read mount() and update this check"
fi

# ------------------------------------------------------------------------------
# 3. The polkit rule — every drive, but only for the person at the screen
# ------------------------------------------------------------------------------
# This is the security-sensitive part, so it is checked in both directions:
# what it MUST say, and what it must NEVER say.
say "The no-password rule, and the limits on it"
if [ -r "${RULE}" ]; then
    ok "${RULE} is installed"
else
    bad "${RULE} is missing — mounting a drive would ask for a password"
fi

# The `//` comments are stripped before every check below. The comments explain
# what the rule deliberately does NOT grant, by name, and must not trip the
# alarms they describe.
RULE_CODE="$(sed 's://.*::' "${RULE}" 2> /dev/null)"

rule_code_has() {
    if grep -Eq -- "$1" <<< "${RULE_CODE}"; then ok "$2"; else bad "$3"; fi
}
rule_code_lacks() {
    if grep -Eq -- "$1" <<< "${RULE_CODE}"; then bad "$3"; else ok "$2"; fi
}

# What it must say: only the person physically at the machine, only in the
# session that owns the screen. THIS DID NOT CHANGE on 2026-10-19.
rule_code_has 'subject\.local' \
    "the rule is limited to the LOCAL session (not someone over SSH)" \
    "the rule no longer checks subject.local — someone over SSH could mount drives"
rule_code_has 'subject\.active' \
    "the rule is limited to the ACTIVE session (the one at the screen now)" \
    "the rule no longer checks subject.active — a switched-away session could mount drives"
rule_code_has '!\(subject\.local && subject\.active\)' \
    "and anybody else is handed back to polkit's defaults before anything is granted" \
    "the local-and-active guard is not the first thing the rule checks"

# What it must grant.
rule_code_has '"org\.freedesktop\.udisks2\.filesystem-mount"' \
    "the rule allows mounting a plugged-in drive (filesystem-mount)" \
    "the rule does not allow filesystem-mount — a USB stick would ask for a password"
# ⚠️ THE REVERSED GATE (2026-10-19). Until that day the build STOPPED if this
# action name appeared in the rule's code. Royce asked for every inside drive to
# mount with no password, so now the build stops if it is MISSING.
rule_code_has '"org\.freedesktop\.udisks2\.filesystem-mount-system"' \
    "the rule allows mounting a drive INSIDE the computer (filesystem-mount-system) — reversed on purpose 2026-10-19" \
    "the rule does not grant filesystem-mount-system — every inside drive would ask for a password at login"
rule_code_has '"org\.freedesktop\.udisks2\.eject-media"' \
    "the rule allows ejecting removable media" \
    "the rule does not allow eject-media"
rule_code_has 'polkit\.Result\.YES' \
    "the rule actually grants something (returns YES)" \
    "the rule never returns YES — it grants nothing"

# ⚠️ What it must NEVER say. Mounting is reading and writing files. Unlocking an
# encrypted drive, mounting for another seat, unmounting somebody else's mount,
# or reshaping a disk (format, partition, change a filesystem) is something
# else, and must still ask.
rule_code_lacks 'encrypted-unlock' \
    "the rule says nothing about unlocking encrypted drives — those still need their own passphrase" \
    "the rule grants encrypted-unlock — an encrypted drive must never open without its key"
rule_code_lacks 'other-seat' \
    "the rule says nothing about drives on another seat" \
    "the rule grants an -other-seat action, which nothing here needs"
rule_code_lacks 'unmount-others' \
    "the rule does not let you unmount somebody else's drive" \
    "the rule grants filesystem-unmount-others"
rule_code_lacks 'modify-device|modify-system|format|filesystem-take-ownership|loop-setup|manage-' \
    "the rule grants nothing that formats, partitions or changes a disk" \
    "the rule grants an action that changes a disk — mounting is all it may grant"
rule_code_lacks 'action\.id\.indexOf|action\.id\.startsWith|action\.id\.match|udisks2\.\*' \
    "every action is named in full — no wildcard that could match more than it says" \
    "the rule matches actions by pattern; name each one in full instead"

# The retired "ask once" pieces must be GONE. A leftover policy file would put
# a second, dead route to editing /etc/fstab on every machine.
for aq_gone in \
    /usr/libexec/aquarius-remember-drive \
    /usr/share/polkit-1/actions/org.aquariusos.rememberdrive.policy \
    /usr/share/polkit-1/rules.d/50-aquarius-remember-drive.rules; do
    if [ -e "${aq_gone}" ]; then
        bad "${aq_gone} is still in the image — the 'ask once' feature was retired on 2026-10-19"
    else
        ok "${aq_gone} is gone (the retired 'ask once' feature)"
    fi
done
if grep -q 'pkexec\|notify-send' < <(grep -v '^[[:space:]]*#' "${AGENT}"); then
    bad "the agent still runs pkexec or notify-send — the inside-drive QUESTION is back"
else
    ok "the agent puts no question on screen and asks for no password"
fi

# ------------------------------------------------------------------------------
# The dock shows the drives
# ------------------------------------------------------------------------------
# "Show in dock" is half of what Royce asked for. Dash to Dock shows a tile for
# every mounted drive when show-mounts is on; the keys are set out loud in our
# override file so a future upstream default cannot quietly hide them.
DOCK_OVERRIDE="/usr/share/glib-2.0/schemas/zz1-aquarius-30-dash-to-dock.gschema.override"
say "Mounted drives show in the dock"
aq_file_has "${DOCK_OVERRIDE}" '^show-mounts=true$' \
    "the dock shows mounted drives (show-mounts=true)"
aq_file_has "${DOCK_OVERRIDE}" '^show-mounts-only-mounted=true$' \
    "and only MOUNTED ones — never a tile for a partition the never-touch list left alone"
aq_file_has "${DOCK_OVERRIDE}" '^show-mounts-network=true$' \
    "and a network share you opened in Files too"

# polkit refuses to load a rule file it cannot parse, silently, at runtime. If
# the tool that checks that is in the image, use it; if not, say so honestly
# rather than claim a check that did not run (the aq-lib.sh rule).
if aq_have polkit; then
    :
fi
if [ -x /usr/bin/pkcheck ] || [ -x /usr/lib/polkit-1/polkitd ]; then
    ok "polkit is present to load this rule at runtime"
else
    bad "polkitd is not in the image — no rule would be read at all"
fi

# ------------------------------------------------------------------------------
# 4. The service, and the fact that it is switched on for the desktop
# ------------------------------------------------------------------------------
say "The service that starts the agent at login"
aq_file_has "${UNIT}" '^ExecStart=/usr/libexec/aquarius-automount$' \
    "the service runs the agent"
aq_file_has "${UNIT}" '^PartOf=graphical-session\.target$' \
    "the service ends when the desktop does"
aq_file_has "${UNIT}" '^WantedBy=graphical-session\.target$' \
    "the service belongs to the graphical session (which GNOME reaches)"
aq_file_has "${UNIT}" '^ConditionUser=!@system$' \
    "the LOGIN SCREEN does not run this — only real people, not the gdm account"

# The "switched on" link, shipped in /usr so an update always restores it and no
# local change can silently lose it. Same mechanism, and same trade-off, as
# aquarius-keys — the long explanation is in aq-lib.sh next to
# aq_unit_is_on_from_usr. This is a USER unit, so the check is written out here
# rather than using that helper (which checks the system graphical.target).
if [ -L "${WANTS_LINK}" ]; then
    target="$(readlink "${WANTS_LINK}")"
    echo "  ${WANTS_LINK} -> ${target}"
    if [ -e "${WANTS_LINK}" ]; then
        ok "the service is switched on by default, and the link points at a real file"
    else
        bad "the 'switched on' link is dangling — it points at ${target}, which is not there"
    fi
else
    bad "${WANTS_LINK} is missing — the agent would be installed but never start"
fi

# Nothing of ours may be switched on through /etc — an update could lose that.
if [ -e "/etc/systemd/user/graphical-session.target.wants/aquarius-automount.service" ]; then
    bad "aquarius-automount is ALSO switched on through /etc — a build step ran an enable. See aq-lib.sh."
else
    ok "nothing switches the agent on through /etc"
fi

# systemd's own opinion of the unit file, where it can give one. Advisory, so it
# is printed and only a real parse fault is treated as failure — and, as the
# keys step learned, a container where the manager cannot start is reported
# honestly rather than as a green tick nobody earned.
if aq_have systemd-analyze; then
    say "systemd's own opinion of the service file"
    verdict="$(systemd-analyze verify --user "${UNIT}" 2>&1 || true)"
    printf '%s\n' "${verdict}" | sed 's/^/  /'
    if printf '%s' "${verdict}" | grep -Eqi "failed to initialize manager|failed to lookup runtimedirectory"; then
        echo "  note   systemd-analyze could not start inside this container, so it"
        echo "         did not read the file. The line-by-line checks above are"
        echo "         what actually guard this unit."
    elif printf '%s' "${verdict}" | grep -Eqi "unknown (key|lvalue)|failed to parse"; then
        bad "systemd cannot understand part of ${UNIT} (see above)."
    else
        ok "systemd read the service file and understood every line of it"
    fi
fi

aq_finish "Every drive automounts"
