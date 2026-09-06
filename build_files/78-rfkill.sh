#!/usr/bin/bash
# ==============================================================================
# STEP 78 — Bluetooth shows up in the Settings app, in our desktop too
# ==============================================================================
# WHAT THIS STEP IS FOR
#
# On the bench, on 6 September 2026, the Aquarius Desktop's Quick Settings had a
# Bluetooth tile that correctly listed a working Bluetooth mouse — and the arrow
# beside that tile opened GNOME's Settings app on a page that said
#
#     No Bluetooth Found
#
# at the same moment, on the same machine.
#
# The cause, read out of gnome-control-center's own source
# (panels/bluetooth/cc-bluetooth-panel.c): that page never asks Bluetooth
# whether a Bluetooth adapter exists. It reads one true/false value,
# `BluetoothHasAirplaneMode`, from a service on the message bus called
# org.gnome.SettingsDaemon.Rfkill — and when it is false, it draws the
# "no devices" screen.
#
# That service is a small program, /usr/libexec/gsd-rfkill, which comes with
# gnome-settings-daemon. It reads the kernel's list of radio kill switches
# ("rfkill" — the aeroplane-mode machinery) out of /dev/rfkill and publishes it.
# GNOME's session starts it automatically. The Aquarius session did not start
# it, so nothing was publishing, and the page was blind.
#
# THE FIX is a service of ours, system_files/usr/lib/systemd/user/
# aquarius-rfkill.service, switched on for the Aquarius session ONLY — because
# GNOME already runs its own copy and two would fight over one bus name.
#
# THIS STEP CHECKS THE FINISHED IMAGE, BY READING IT:
#   1. the program the service runs is really in there;
#   2. the service file is there and says the right things;
#   3. the "switched on" link is there, points at a real file, and hangs off
#      labwc-session.target and NOT graphical-session.target;
#   4. GNOME's own copy of the same service is printed in the build log, so a
#      future change to it is visible, and we confirm we copied nothing from it
#      that would stop ours starting;
#   5. the udev rule that lets the person at the screen open /dev/rfkill for
#      writing is present — without it the status can be READ but aeroplane
#      mode cannot be switched.
#
# Plain-English guide: docs/restart/aquarius-session.md, the section
# "Why the Bluetooth settings page said No Bluetooth Found".
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

HELPER="/usr/libexec/gsd-rfkill"
UNIT="/usr/lib/systemd/user/aquarius-rfkill.service"
WANTS_LINK="/usr/lib/systemd/user/labwc-session.target.wants/aquarius-rfkill.service"
GNOME_UNIT="/usr/lib/systemd/user/org.gnome.SettingsDaemon.Rfkill.service"
LABWC_TARGET="/usr/lib/systemd/user/labwc-session.target"

# ------------------------------------------------------------------------------
# 1. The program itself
# ------------------------------------------------------------------------------
# It is not packaged on its own: it arrives inside gnome-settings-daemon, which
# is installed at step 4 because GNOME is the fallback desktop. So this is two
# questions — is the package here, and is the one file we care about in it.
say "The rfkill helper the Settings app reads Bluetooth from"
aq_installed gnome-settings-daemon

if [ -x "${HELPER}" ]; then
    ok "${HELPER} is present and runnable"
else
    bad "${HELPER} is missing — the Settings app's Bluetooth page would say 'No Bluetooth Found' in the Aquarius Desktop"
fi

# Which package owns it, printed rather than asserted. If a future Fedora moves
# this program somewhere else, this line in the build log is what says so.
if aq_have rpm; then
    echo "  owned by: $(rpm -qf "${HELPER}" 2> /dev/null || echo 'nothing — that would be a surprise')"
fi

# ------------------------------------------------------------------------------
# 2. The service file we ship
# ------------------------------------------------------------------------------
say "Our own service that starts it in the Aquarius session"
if [ -r "${UNIT}" ]; then
    ok "${UNIT} is installed"
else
    bad "${UNIT} is missing — nothing would start the helper"
fi

aq_file_has "${UNIT}" '^ExecStart=/usr/libexec/gsd-rfkill$' \
    "the service runs the rfkill helper"
aq_file_has "${UNIT}" '^BusName=org\.gnome\.SettingsDaemon\.Rfkill$' \
    "it takes the bus name the Settings app looks for"
aq_file_has "${UNIT}" '^Type=dbus$' \
    "it is 'ready' when that name is taken, which is the honest definition here"
aq_file_has "${UNIT}" '^PartOf=graphical-session\.target$' \
    "it stops when the desktop does"
aq_file_has "${UNIT}" '^ConditionUser=!@system$' \
    "the LOGIN SCREEN does not run this — only real people, not the gdm account"
aq_file_has "${UNIT}" '^Restart=on-failure$' \
    "it retries if the message bus is a moment behind the login"

# ⚠️ THE SCOPE LINE, AND THE WHOLE POINT OF THIS STEP.
#
# GNOME reaches graphical-session.target as well, and GNOME already runs its own
# copy of this program. A second copy would race it for one bus name, and one of
# the two would lose — differently on each boot. So this service must be wanted
# by labwc-session.target, which only the Aquarius session starts, and must NOT
# be wanted by graphical-session.target.
aq_file_has "${UNIT}" '^WantedBy=labwc-session\.target$' \
    "it is switched on for the Aquarius session"
if grep -qE '^(WantedBy|RequiredBy)=.*graphical-session\.target' "${UNIT}"; then
    bad "${UNIT} asks to start with ANY graphical session — that includes GNOME, which already runs its own copy, and the two would fight over the bus name org.gnome.SettingsDaemon.Rfkill"
else
    ok "it does NOT start in GNOME, where a second copy would fight the first"
fi

# The target it hangs off has to exist, or the link below points at nothing that
# is ever started. It comes from labwc, built by stage-labwc.sh with
# -Dsystemd-session=enabled.
if [ -r "${LABWC_TARGET}" ]; then
    ok "labwc-session.target is in the image for it to hang off"
else
    bad "${LABWC_TARGET} is missing — labwc was built without -Dsystemd-session, and this service would never start"
fi

# ------------------------------------------------------------------------------
# 3. The "switched on" link
# ------------------------------------------------------------------------------
# Shipped in /usr so an update always restores it and no local change can
# silently lose it — the same mechanism as aquarius-keys and aquarius-automount.
# The long explanation is in aq-lib.sh next to aq_unit_is_on_from_usr. These are
# USER units, so the check is written out here rather than using that helper,
# which asks about the system-wide graphical.target.
say "The link that switches it on, and only for our desktop"
if [ -L "${WANTS_LINK}" ]; then
    aq_rf_target="$(readlink "${WANTS_LINK}")"
    echo "  ${WANTS_LINK} -> ${aq_rf_target}"
    if [ -e "${WANTS_LINK}" ]; then
        ok "the service is switched on by default, and the link points at a real file"
    else
        bad "the 'switched on' link is dangling — it points at ${aq_rf_target}, which is not there"
    fi
else
    bad "${WANTS_LINK} is missing — the service would be installed but never start"
fi

# Nothing of ours may be switched on through /etc; an update could lose that.
if [ -e "/etc/systemd/user/labwc-session.target.wants/aquarius-rfkill.service" ]; then
    bad "aquarius-rfkill is ALSO switched on through /etc — a build step ran an enable. See aq-lib.sh."
else
    ok "nothing switches it on through /etc"
fi

# And, again in the other direction: it must not have been wired into the
# both-desktops target by anybody.
if [ -e "/usr/lib/systemd/user/graphical-session.target.wants/aquarius-rfkill.service" ] \
    || [ -e "/etc/systemd/user/graphical-session.target.wants/aquarius-rfkill.service" ]; then
    bad "aquarius-rfkill is linked into graphical-session.target.wants — that starts it in GNOME too, and two copies fight over one bus name"
else
    ok "it is not linked into the both-desktops target"
fi

# ------------------------------------------------------------------------------
# 4. GNOME's own copy, printed — and what we deliberately did not take from it
# ------------------------------------------------------------------------------
# This is here so that a future Fedora changing that file is VISIBLE in a build
# log rather than discovered on a bench. Ours is a separate file on purpose (see
# the header of the unit), but if GNOME's ever grows an Environment= line or an
# ordering that our helper genuinely needs, this is where somebody notices.
say "What GNOME's own service for the same program says"
if [ -r "${GNOME_UNIT}" ]; then
    ok "${GNOME_UNIT} is in the image (this is what GNOME starts)"
    echo "  --- ${GNOME_UNIT} ---"
    sed 's/^/  /' "${GNOME_UNIT}"
    echo "  --- end ---"

    # The line that explains why we do not simply start GNOME's unit by hand.
    if grep -q '^RefuseManualStart=true$' "${GNOME_UNIT}"; then
        ok "it says RefuseManualStart=true — which is why we ship a service of our own rather than starting this one"
    else
        echo "  note   GNOME's unit no longer says RefuseManualStart=true. Ours is still"
        echo "         the right shape (its Requisite= targets do not exist in our"
        echo "         session), but this is worth a look next time somebody is here."
    fi

    # Anything GNOME sets in the environment, we would have to mirror. Today it
    # sets nothing. Printed either way rather than asserted, because a future
    # Fedora adding one is news, not a failure.
    if grep -q '^Environment=' "${GNOME_UNIT}"; then
        echo "  note   ⚠️ GNOME's unit now sets an environment variable:"
        grep '^Environment=' "${GNOME_UNIT}" | sed 's/^/         /'
        echo "         Check whether aquarius-rfkill.service needs the same line."
    else
        ok "GNOME's unit sets no Environment= — so there is nothing of that kind for ours to mirror"
    fi
else
    echo "  note   ${GNOME_UNIT} is not in this image. Ours does not depend on it;"
    echo "         it is read here only so a change to it would be visible."
fi

# ⚠️ The four GNOME-only lines that must NEVER appear in ours. Requisite= means
# "refuse to start unless that target is already up", and those targets do not
# exist in the Aquarius session — so copying one would make the service refuse
# to start, which is the very bug it exists to fix.
#
# The check reads only the SETTING lines — every line that is not blank and does
# not begin with a `#`. That matters: the unit's header names all four of these
# on purpose, to explain why each is absent, and a whole-file grep would fail a
# correct file for its own explanation. (Exactly the mistake the menu.xml
# Settings check made on 2026-09-06 and had to be corrected for.)
say "None of GNOME's session gating was copied into ours"
grep -vE '^[[:space:]]*(#|$)' "${UNIT}" > /tmp/aq-rfkill-settings.txt
echo "  the settings this unit actually contains:"
sed 's/^/       /' /tmp/aq-rfkill-settings.txt

aq_rf_gating=0
for aq_rf_line in 'Requisite=' 'ExecStopPost=' 'RefuseManualStart=' 'RefuseManualStop=' 'gnome-session'; do
    if grep -qF "${aq_rf_line}" /tmp/aq-rfkill-settings.txt; then
        bad "${UNIT} has a live '${aq_rf_line}' setting copied from GNOME's unit — that is GNOME session gating, and it would make the service refuse to start in ours"
        aq_rf_gating=1
    fi
done
if [ "${aq_rf_gating}" -eq 0 ]; then
    ok "ours carries none of GNOME's Requisite=, ExecStopPost=, RefuseManualStart/Stop= or gnome-session ordering"
fi
rm -f /tmp/aq-rfkill-settings.txt

# ------------------------------------------------------------------------------
# 5. /dev/rfkill has to be openable for WRITING by the person at the screen
# ------------------------------------------------------------------------------
# The helper reads the kernel's switch list from /dev/rfkill. That file is
# world-readable by default, so DETECTING Bluetooth would work regardless — but
# TOGGLING aeroplane mode needs to write to it, and an ordinary user cannot
# write to a root-owned device file unless somebody says so.
#
# The somebody is udev. systemd ships a rule that tags rfkill devices `uaccess`,
# which means "give read AND write to whoever is logged in at the screen right
# now". gnome-settings-daemon ships an identical rule of its own
# (61-gnome-settings-daemon-rfkill.rules) for older systems. Either will do.
#
# This is checked here rather than assumed because a missing rule is invisible:
# the Bluetooth page would look right and the aeroplane-mode switch would just
# not move.
say "Whether the person at the screen may switch the radios, not only read them"
grep -rls 'rfkill' /usr/lib/udev/rules.d /etc/udev/rules.d 2> /dev/null | sort > /tmp/aq-rfkill-rules.txt || true
if [ -s /tmp/aq-rfkill-rules.txt ]; then
    echo "  udev rule files that mention rfkill:"
    sed 's/^/       /' /tmp/aq-rfkill-rules.txt
    echo "  the rule lines themselves:"
    while read -r aq_rf_file; do
        grep -hE '^[^#]*rfkill' "${aq_rf_file}" 2> /dev/null | sed 's/^/       /'
    done < /tmp/aq-rfkill-rules.txt
else
    echo "  no udev rule file in this image mentions rfkill at all"
fi
rm -f /tmp/aq-rfkill-rules.txt

if grep -rhE '^[^#]*KERNEL=="rfkill"' /usr/lib/udev/rules.d /etc/udev/rules.d 2> /dev/null \
    | grep -q 'uaccess'; then
    ok "a udev rule tags rfkill devices 'uaccess' — the person at the screen can open /dev/rfkill for writing, so aeroplane mode can be switched"
else
    bad "no udev rule tags rfkill devices 'uaccess'. Bluetooth would still be DETECTED (/dev/rfkill is world-readable), but the aeroplane-mode switch would not move. systemd's 70-uaccess.rules normally provides this."
fi

# ------------------------------------------------------------------------------
# 6. systemd's own opinion of our file
# ------------------------------------------------------------------------------
# Advisory, and reported honestly: a container where the user manager cannot
# start is said out loud rather than counted as a green tick nobody earned. The
# line-by-line checks above are what actually guard this unit.
if aq_have systemd-analyze; then
    say "systemd's own opinion of the service file"
    aq_rf_verdict="$(systemd-analyze verify --user "${UNIT}" 2>&1 || true)"
    printf '%s\n' "${aq_rf_verdict}" | sed 's/^/  /'
    if printf '%s' "${aq_rf_verdict}" | grep -Eqi "failed to initialize manager|failed to lookup runtimedirectory"; then
        echo "  note   systemd-analyze could not start inside this container, so it"
        echo "         did not read the file. The checks above are what guard it."
    elif printf '%s' "${aq_rf_verdict}" | grep -Eqi "unknown (key|lvalue)|failed to parse"; then
        bad "systemd cannot understand part of ${UNIT} (see above)."
    else
        ok "systemd read the service file and understood every line of it"
    fi
fi

aq_finish "Bluetooth status for the Settings app"
