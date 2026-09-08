#!/usr/bin/bash
# ==============================================================================
# STEP 79 — When the USB4 / Thunderbolt chip does not wake up, try it again
# ==============================================================================
# WHAT THIS STEP IS FOR
#
# Step 76 makes external drives mount by themselves. This step is about the boot
# where there IS no drive to mount, because the chip its socket hangs off never
# came up.
#
# A modern PC board has a chip on it that runs the fast USB-C sockets — the ones
# a Thunderbolt dock, a USB4 SSD or an eGPU plugs into. Linux calls it the USB4
# host router and it needs a driver, the same way a graphics card does. On
# Royce's bench PC (MSI MAG X870 TOMAHAWK WIFI, ASMedia ASM4242) on 7 September
# 2026, that driver gave up during boot:
#
#     thunderbolt 0000:70:00.0: enabling device (0000 -> 0002)
#     thunderbolt 0000:70:00.0: probe with driver thunderbolt failed with error -110
#
# -110 is "I asked and nothing answered in time". The chip was left with no
# driver, so every USB4 socket went quiet, and Royce's Corsair EX400U SSD on its
# Satechi Thunderbolt 5 dock was INVISIBLE — no udisks object, nothing for the
# automount agent to mount, nothing in `lsblk`. The eleven boots before it had
# been fine. Nothing was wrong with the drive, the dock or the mounting
# machinery; there was simply no drive for any of it to see.
#
# WHAT SHIPS, and what this step checks is really in the finished image:
#
#   1. /usr/libexec/aquarius-usb4-rescue — asks the kernel to attach that driver
#      again, and resets the chip once if asking is not enough.
#   2. /usr/lib/udev/rules.d/76-aquarius-usb4.rules — starts the rescue when a
#      PCI device of class 0x0c0340 (a USB4 host interface) turns up. This IS
#      the switch-on mechanism: udev replays an "add" event at every boot for
#      hardware that is already present ("coldplug"), so the rescue runs on
#      every boot of a machine that has such a chip and on no boot of a machine
#      that does not. That is why there is deliberately no `.wants` symlink here
#      and no [Install] section in the unit.
#   3. /usr/lib/systemd/system/aquarius-usb4-rescue.service — the unit udev
#      starts.
#   4. `aq usb4 status` and `sudo aq usb4 retry`, so a person has words for it.
#
# All four arrived in the image as plain files at step 5, which copies
# system_files/ into place. This step reads them.
#
# ⚠️ THE HONEST LIMIT, WHICH BELONGS IN EVERY DOC ABOUT THIS. A rebind and a
# reset ask the chip to start again from software. A chip whose own firmware has
# locked up comes back only with a full power-off — shut down, wait ten seconds,
# switch on. And as of 7 September 2026 this rescue has NEVER been seen to
# recover a real machine: its logic is proved against a fake set of files by
# tests/test-usb4-rescue.sh, which is not the same as a bench PC showing a bind
# that works.
#
# Plain-English guide: docs/restart/usb4.md
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

RESCUE="/usr/libexec/aquarius-usb4-rescue"
RULE="/usr/lib/udev/rules.d/76-aquarius-usb4.rules"
UNIT="/usr/lib/systemd/system/aquarius-usb4-rescue.service"
USB4_CLASS="0x0c0340"

# ------------------------------------------------------------------------------
# 1. The rescue program — present, runnable, and valid shell
# ------------------------------------------------------------------------------
say "The USB4 rescue program"
if [ -x "${RESCUE}" ]; then
    ok "${RESCUE} is present and runnable"
else
    bad "${RESCUE} is missing or not runnable — a USB4 controller that failed to"
    bad "come up would stay down, and every drive on a dock would be invisible"
fi

# It is bash. A syntax error must stop the build, not wait for a bench PC with a
# sulking controller — which is a fault nobody would connect to a typo in here.
if bash -n "${RESCUE}" 2> /tmp/aq-usb4-parse.txt; then
    ok "the rescue is valid shell"
else
    bad "the rescue does not parse as shell:"
    sed 's/^/       /' /tmp/aq-usb4-parse.txt
fi
rm -f /tmp/aq-usb4-parse.txt

# ------------------------------------------------------------------------------
# 2. The rehearsal (--dry-run), which is what proves it loads
# ------------------------------------------------------------------------------
# --dry-run is designed to work HERE — in a build container with no USB4
# controller at all. It writes nothing, states its rules, and exits 0. If this
# fails, the program could not even load on a real machine.
say "The rescue's rehearsal (--dry-run), which changes nothing"
if "${RESCUE}" --dry-run > /tmp/aq-usb4-dry.txt 2>&1; then
    ok "'aquarius-usb4-rescue --dry-run' runs and changes nothing"
    sed 's/^/       /' /tmp/aq-usb4-dry.txt
else
    bad "'aquarius-usb4-rescue --dry-run' failed — the rescue cannot load in this image:"
    sed 's/^/       /' /tmp/aq-usb4-dry.txt
fi

# The rehearsal must name the class number it looks for. That number IS the
# feature: get it wrong and the program searches for hardware that does not
# exist, finds nothing, reports success, and rescues nobody — silently, forever.
aq_file_has /tmp/aq-usb4-dry.txt "${USB4_CLASS}" \
    "the rehearsal states the PCI class it looks for (${USB4_CLASS} — USB4 host interface)"
aq_file_has /tmp/aq-usb4-dry.txt 'power-off' \
    "the rehearsal states the honest limit (a locked-up chip needs a full power-off)"
rm -f /tmp/aq-usb4-dry.txt

# ------------------------------------------------------------------------------
# 3. The udev rule — which IS how this service is switched on
# ------------------------------------------------------------------------------
say "The udev rule that starts the rescue on a machine that has the chip"
if [ -r "${RULE}" ]; then
    ok "${RULE} is installed"
else
    bad "${RULE} is missing — the rescue would be in the image and never run,"
    bad "because it is started by this rule and by nothing else"
fi

# Every clause of the one rule line, checked by name. The comments in the file
# explain all of them, so the checks read only the RULE lines — every line that
# is not blank and does not begin with a '#'. (The same care step 78 takes: a
# whole-file grep would pass a correct file for its own explanation, and would
# also pass a file whose explanation survived but whose rule was deleted.)
if [ -r "${RULE}" ]; then
    grep -vE '^[[:space:]]*(#|$)' "${RULE}" > /tmp/aq-usb4-rule.txt
    echo "  the rule lines this file actually contains:"
    sed 's/^/       /' /tmp/aq-usb4-rule.txt

    aq_file_has /tmp/aq-usb4-rule.txt 'ACTION=="add"' \
        "the rule fires when the chip appears (which includes every boot, via coldplug)"
    aq_file_has /tmp/aq-usb4-rule.txt 'SUBSYSTEM=="pci"' \
        "the rule is limited to chips on the board, not to USB devices"
    aq_file_has /tmp/aq-usb4-rule.txt "ATTR\\{class\\}==\"${USB4_CLASS}\"" \
        "the rule matches the USB4 host interface class (${USB4_CLASS})"
    aq_file_has /tmp/aq-usb4-rule.txt 'TAG\+="systemd"' \
        "the rule tells systemd this device exists, without which the next line does nothing"
    aq_file_has /tmp/aq-usb4-rule.txt 'SYSTEMD_WANTS.*aquarius-usb4-rescue\.service' \
        "the rule names the service to start"
    rm -f /tmp/aq-usb4-rule.txt
fi

# ------------------------------------------------------------------------------
# 4. The service file
# ------------------------------------------------------------------------------
say "The service the rule starts"
if [ -r "${UNIT}" ]; then
    ok "${UNIT} is installed"
else
    bad "${UNIT} is missing — the udev rule would ask for a service that is not there"
fi

aq_file_has "${UNIT}" '^Type=oneshot$' \
    "it runs once and finishes, rather than sitting there"
aq_file_has "${UNIT}" "^ExecStart=${RESCUE}\$" \
    "the service runs the rescue"
aq_file_has "${UNIT}" '^After=systemd-modules-load\.service' \
    "it starts after the machine's drivers are loaded, so it is not racing them"

# ⚠️ THE ABSENCE THAT IS DELIBERATE. There must be NO [Install] section: nothing
# enables this unit, because the udev rule starts it. If somebody adds one and
# then ships a .wants symlink to match, the rescue starts on every machine ever
# built from this image — including every laptop and handheld with no USB4 chip
# at all — to find nothing and say so in the journal, at every boot, forever.
if grep -qE '^\[Install\]' "${UNIT}"; then
    bad "${UNIT} has an [Install] section. It is started by ${RULE}, not by being"
    bad "enabled, and an [Install] section is an invitation to ship a .wants symlink"
    bad "that would run it on every machine including those with no USB4 chip."
else
    ok "it has no [Install] section — it is started by the udev rule, on the machines that have the hardware"
fi

# And, in the other direction: nobody may have wired it on the usual way either.
if [ -e "/usr/lib/systemd/system/graphical.target.wants/aquarius-usb4-rescue.service" ] \
    || [ -e "/usr/lib/systemd/system/multi-user.target.wants/aquarius-usb4-rescue.service" ]; then
    bad "aquarius-usb4-rescue has a .wants symlink. It is started by udev on the"
    bad "machines that have a USB4 chip; a symlink runs it on all the others too."
else
    ok "no .wants symlink switches it on — udev does that, only where the hardware is"
fi

if [ -e "/etc/systemd/system/multi-user.target.wants/aquarius-usb4-rescue.service" ] \
    || [ -e "/etc/systemd/system/graphical.target.wants/aquarius-usb4-rescue.service" ]; then
    bad "aquarius-usb4-rescue is switched on through /etc — a build step ran 'systemctl enable'. See aq-lib.sh."
else
    ok "nothing switches it on through /etc (an update could lose that)"
fi

# ------------------------------------------------------------------------------
# 5. systemd's own opinion of the service file
# ------------------------------------------------------------------------------
# Advisory, and reported honestly: a container where the manager cannot start is
# said out loud rather than counted as a green tick nobody earned. The
# line-by-line checks above are what actually guard this unit. (Copied from step
# 76 and step 78 deliberately — three copies of one honest check beat one clever
# shared one nobody can read.)
if aq_have systemd-analyze; then
    say "systemd's own opinion of the service file"
    aq_u4_verdict="$(systemd-analyze verify "${UNIT}" 2>&1 || true)"
    printf '%s\n' "${aq_u4_verdict}" | sed 's/^/  /'
    if printf '%s' "${aq_u4_verdict}" | grep -Eqi "failed to initialize manager|failed to lookup runtimedirectory"; then
        echo "  note   systemd-analyze could not start inside this container, so it"
        echo "         did not read the file. The checks above are what guard it."
    elif printf '%s' "${aq_u4_verdict}" | grep -Eqi "unknown (key|lvalue)|failed to parse"; then
        bad "systemd cannot understand part of ${UNIT} (see above)."
    else
        ok "systemd read the service file and understood every line of it"
    fi
fi

# ------------------------------------------------------------------------------
# 6. The two programs the rescue leans on
# ------------------------------------------------------------------------------
# `modprobe` loads the driver. It comes with kmod and is on every Linux machine
# ever made — but the rescue's first act is to run it, so if it were somehow
# absent the first line of the journal would be a confusing one.
say "What the rescue needs to be in the image"
if aq_have modprobe; then
    ok "modprobe is present — the rescue can make sure the 'thunderbolt' driver is loaded"
else
    bad "modprobe is missing, so the rescue cannot load the thunderbolt driver"
fi

# bolt is Fedora's Thunderbolt device manager. The rescue does not need it to
# work — it talks to the kernel directly — but `aq usb4 status` prints
# `boltctl list`, which is the one command that shows a person their dock and
# their drive by name, and it is what docs/restart/usb4.md tells them to run.
#
# It is asked for BY NAME here rather than assumed. It usually arrives anyway,
# pulled in by the GNOME desktop, and that is exactly the kind of thing that
# quietly stops being true one Fedora later — the same way the Wi-Fi firmware
# stopped arriving with linux-firmware and left the bench with no Wi-Fi on
# 2026-09-05 (docs/restart/hardware.md). Installing a package that is already
# installed costs nothing.
aq_dnf install bolt
aq_installed bolt
if aq_have boltctl; then
    ok "boltctl is present — 'aq usb4 status' can list the Thunderbolt devices by name"
else
    bad "boltctl is missing — 'aq usb4 status' would have no device list to show"
fi

# ------------------------------------------------------------------------------
# 7. The words a person has for it
# ------------------------------------------------------------------------------
say "The 'aq usb4' commands"
aq_file_has /usr/bin/aq '^AQ_USB4_RESCUE="/usr/libexec/aquarius-usb4-rescue"$' \
    "aq knows where the rescue lives"
aq_file_has /usr/bin/aq '^    usb4\)$' \
    "'aq usb4' is wired into the command"
aq_file_has /usr/bin/aq 'aq usb4 status' \
    "'aq usb4 status' is listed in aq's own help, so somebody can find it"

aq_finish "USB4 / Thunderbolt rescue"
