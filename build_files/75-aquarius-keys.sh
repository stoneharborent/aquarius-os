#!/usr/bin/bash
# ==============================================================================
# STEP 75 — Aquarius Keys: Mac-style keyboard shortcuts, on by default
# ==============================================================================
# WHAT THIS STEP IS FOR
#
# AquariusOS behaves like a Mac when you type. Copy is Command-C. Quit is
# Command-Q. Search is Command-Space. Nobody else ships a Linux desktop that
# does this, and for a creator coming off a Mac it is the difference between
# "I have to relearn my hands" and "this is just my computer".
#
# The whole feature is four things, and this step assembles them:
#
#   1. Two small programs, compiled in the throwaway builder stage by
#      74-xremap-build.sh, that do the actual remapping.
#   2. Permission for the person logged in at the screen to read their own
#      keyboard, without any of it running as the administrator.
#   3. Two rule files — mac.yaml and windows.yaml — and a service that reads
#      whichever one the person chose.
#   4. `aq keys mac|windows|status`, the switch.
#
# Items 2, 3 and 4 are plain files. They arrived in the image at step 50, which
# copies everything under system_files/ into place. This step installs the two
# compiled programs, and then CHECKS THE WHOLE THING — because a keyboard
# feature that is subtly missing a piece produces a computer where some keys do
# nothing, and no error anywhere says why.
#
# ------------------------------------------------------------------------------
# WHY THE DEFAULT IS MAC AND WHERE THAT DECISION LIVES
# ------------------------------------------------------------------------------
# In exactly two places, and they must agree:
#
#   /etc/skel/.config/aquarius/keys.conf   what a NEW account gets: mode=mac
#   /usr/libexec/aquarius-keys-run         what an account with NO file gets
#
# The second one matters more than it looks. An account that existed before
# this feature was added has no settings file, and an operating system that
# only applied its own default to brand-new accounts would be lying about
# having a default. Both are checked below.
#
# ------------------------------------------------------------------------------
# THE PHYSICAL-KEY DECISION (Royce, 2026-09-03) — DO NOT REVISIT WITHOUT HIM
# ------------------------------------------------------------------------------
# On a PC keyboard, which key is Command? Two honest answers existed:
# the key in the Mac POSITION (next to the space bar — physically Alt), or the
# key with the matching LABEL (the Windows key). Royce chose POSITION, because
# muscle memory lives in the thumb, not in the printing on the key.
#
# So: Alt becomes Command, the Windows key becomes Option, and Apple keyboards
# are detected and left completely alone — they are already right.
# The rule that does it is the modmap at the top of mac.yaml.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

# Where the builder stage left its work. Mounted by the Containerfile.
XREMAP_BUILD="/ctx-xremap"

KEYS_DIR="/usr/share/aquarius/keys"
RUN_SCRIPT="/usr/libexec/aquarius-keys-run"
AQ_CLI="/usr/bin/aq"
UNIT="/usr/lib/systemd/user/aquarius-keys.service"
WANTS_LINK="/usr/lib/systemd/user/graphical-session.target.wants/aquarius-keys.service"
UDEV_RULE="/usr/lib/udev/rules.d/70-aquarius-input.rules"
MODULE_CONF="/usr/lib/modules-load.d/aquarius-uinput.conf"
SKEL_CONF="/etc/skel/.config/aquarius/keys.conf"
GNOME_EXT_UUID="xremap@k0kubun.com"
GNOME_EXT_DIR="/usr/share/gnome-shell/extensions/${GNOME_EXT_UUID}"

say "Aquarius Keys — installing the two remapper programs"

# ==============================================================================
# 1. The two compiled programs
# ==============================================================================
# There are two because no single program can do this job on both desktops —
# 74-xremap-build.sh explains why at length, with the line of upstream source
# that proves it. The service picks one at login.
for feature in wlroots gnome; do
    src="${XREMAP_BUILD}/bin/xremap-${feature}"
    if [ ! -s "${src}" ]; then
        bad "${src} was not produced by the builder stage"
        continue
    fi
    install -D -m 0755 "${src}" "/usr/bin/xremap-${feature}"
done

# The MIT licence travels with the program.
if [ -s "${XREMAP_BUILD}/licenses/xremap/LICENSE" ]; then
    install -D -m 0644 "${XREMAP_BUILD}/licenses/xremap/LICENSE" \
        /usr/share/licenses/xremap/LICENSE
    ok "xremap's licence is shipped alongside it"
else
    bad "xremap's LICENSE file did not come through from the builder stage"
fi

# ------------------------------------------------------------------------------
# Do they run, HERE, in the finished image?
# ------------------------------------------------------------------------------
# They ran in the builder stage, which had a compiler and every development
# library in it. This image has neither. A program that needs a library which
# is not here builds green, ships, and then fails at login with a message no
# ordinary person can act on. So ask it again, in the image that ships.
say "Checking the remappers run inside THIS image"
for feature in wlroots gnome; do
    bin="/usr/bin/xremap-${feature}"
    if [ ! -x "${bin}" ]; then
        bad "${bin} is missing"
        continue
    fi
    if version_line="$("${bin}" --version 2>&1)"; then
        ok "xremap-${feature}: ${version_line}"
    else
        bad "xremap-${feature} is installed but will not run: ${version_line}"
    fi
done

# What libraries do they actually need, and are they all here? `ldd` prints
# "not found" next to anything missing, which is the exact failure this is
# looking for.
say "Checking every library the remappers need is in the image"
for feature in wlroots gnome; do
    bin="/usr/bin/xremap-${feature}"
    [ -x "${bin}" ] || continue
    echo "--- ${bin} ---"
    ldd "${bin}" || true
    if ldd "${bin}" 2>&1 | grep -q "not found"; then
        bad "xremap-${feature} needs a library that is not in this image (see above)"
    else
        ok "xremap-${feature} has every library it needs"
    fi
done

# ==============================================================================
# 2. The GNOME add-on
# ==============================================================================
# GNOME's Wayland desktop does not let any program ask which window is focused.
# xremap's author writes a small GNOME add-on that answers on its behalf, and
# without it the app-specific rules — most importantly the terminal exception,
# where Command-C copies and the physical Control-C still interrupts — silently
# do not work.
#
# It is installed for the whole machine here, and switched on for each account
# by the run script at login. It is NOT listed in the image's
# enabled-extensions default on purpose: that list lives in
# system_files/usr/share/glib-2.0/schemas/zz1-aquarius-20-shell.gschema.override,
# which belongs to the desktop layer and is being edited by other work in
# progress. Switching it on per account does the same job and touches nothing
# shared.
say "The GNOME add-on that reports which app is focused"
if [ -d "${XREMAP_BUILD}/gnome-shell/extensions/${GNOME_EXT_UUID}" ]; then
    install -d -m 0755 "$(dirname "${GNOME_EXT_DIR}")"
    cp -a "${XREMAP_BUILD}/gnome-shell/extensions/${GNOME_EXT_UUID}" "${GNOME_EXT_DIR}"
    chmod -R a+rX,go-w "${GNOME_EXT_DIR}"
    aq_file_has "${GNOME_EXT_DIR}/metadata.json" "\"uuid\": \"${GNOME_EXT_UUID}\"" \
        "the add-on is installed and declares the right uuid"
    if [ -s "${GNOME_EXT_DIR}/extension.js" ]; then
        ok "the add-on's code is present"
    else
        bad "${GNOME_EXT_DIR}/extension.js is missing or empty"
    fi
else
    bad "the GNOME add-on did not come through from the builder stage"
fi

# ==============================================================================
# 3. Permission to read the keyboard, without running as the administrator
# ==============================================================================
# The udev rule and the driver-loading file are shipped as plain files (step 50
# copied them in). All this does is confirm they are really there and really
# say what they are supposed to say — because a permission rule that is missing
# produces a service that fails at login with a message about a device node,
# and that is not a message anybody should have to decode.
say "Permission to read the keyboard"
aq_file_has "${UDEV_RULE}" 'uinput' \
    "the udev rule mentions uinput, the invented-keyboard device"
aq_file_has "${UDEV_RULE}" 'TAG\+="uaccess"' \
    "the udev rule uses uaccess — the permission that is granted at login and taken back at logout"
aq_file_has "${UDEV_RULE}" 'SUBSYSTEM=="input", KERNEL=="event\[0-9\]\*"' \
    "the udev rule covers the real keyboards as well"
aq_file_has "${MODULE_CONF}" '^uinput$' \
    "the uinput driver is set to load at every boot"

# ==============================================================================
# 4. The rule files
# ==============================================================================
say "The two keyboard profiles"
for profile in mac windows; do
    file="${KEYS_DIR}/${profile}.yaml"
    if [ -s "${file}" ]; then
        ok "${file} is installed"
    else
        bad "${file} is missing or empty"
        continue
    fi

    # -------------------------------------------------------------------------
    # ⚠️ THE PROFILES ARE CHECKED BY THE REMAPPER ITSELF, NOT BY A YAML PARSER.
    # -------------------------------------------------------------------------
    # A YAML parser only proves the punctuation is right. It would happily
    # accept `Super-Kommand: C-c`, a key name that does not exist, and the
    # service would then fail at login on a real person's machine.
    #
    # xremap reads and validates the whole file BEFORE it looks at any keyboard
    # (verified in its source: load_configs runs before select_input_devices).
    # So running it here with a device filter that matches nothing gets the
    # full validation and then stops — and any complaint about the FILE appears
    # as "Failed to load config", which is what is looked for.
    #
    # A complaint about missing devices is expected and is not a failure: there
    # is no keyboard inside a build.
    output="$(/usr/bin/xremap-wlroots --device /nonexistent-device-for-validation "${file}" 2>&1 || true)"
    if printf '%s' "${output}" | grep -q "Failed to load config"; then
        bad "${file} is not a valid profile — xremap says:"
        printf '%s\n' "${output}" | sed 's/^/       /'
    else
        ok "${file} is a profile xremap accepts"
    fi
done

# The rules Royce actually asked for, spot-checked by content. Not every line —
# that would be a copy of the file — but the ones whose absence would be a
# different feature from the one that was designed.
aq_file_has "${KEYS_DIR}/mac.yaml" '^ *Alt_L: Super_L$' \
    "mac.yaml makes the key beside the space bar Command (position, Royce 2026-09-03)"
aq_file_has "${KEYS_DIR}/mac.yaml" '^ *Super_L: Alt_L$' \
    "mac.yaml makes the Windows key Option"
aq_file_has "${KEYS_DIR}/mac.yaml" 'ids:0x05ac' \
    "mac.yaml recognises Apple keyboards and leaves them alone"
# Note the trailing `( |$)` on the next few: these lines have an explanatory
# comment after them in mac.yaml, so anchoring at the end of the line would
# never match. The alternative — dropping the anchor — would let
# `Super-c: C-copy-something-else` pass, which is exactly the mistake this is
# meant to catch.
aq_file_has "${KEYS_DIR}/mac.yaml" '^ *Super-c: C-c( |$)' \
    "mac.yaml: Command-C copies"
aq_file_has "${KEYS_DIR}/mac.yaml" '^ *Super-c: C-Shift-c( |$)' \
    "mac.yaml: in a terminal, Command-C copies instead of interrupting"
aq_file_has "${KEYS_DIR}/mac.yaml" '^ *Super-q: A-F4$' \
    "mac.yaml: Command-Q closes the window"
aq_file_has "${KEYS_DIR}/mac.yaml" '^ *Super-Shift-3: SYSRQ$' \
    "mac.yaml: Command-Shift-3 takes a screenshot"
aq_file_has "${KEYS_DIR}/mac.yaml" '^ *- Ptyxis( |$)' \
    "mac.yaml knows Ptyxis, the terminal this image ships, is a terminal"
aq_file_has "${KEYS_DIR}/mac.yaml" '^ *- resolve *#' \
    "mac.yaml leaves DaVinci Resolve's own shortcuts alone"

# Command-Space, Command-Tab and Command-` must NOT be remapped: they are how
# the desktop's own search and window switching are reached. A rule for any of
# them would take the search palette away and nothing would say why.
say "Checking the desktop's own keys are left alone"
for combo in 'Super-space' 'Super-Tab' 'Super-grave'; do
    if grep -Eq "^[[:space:]]+${combo}:" "${KEYS_DIR}/mac.yaml"; then
        bad "mac.yaml remaps ${combo} — that key belongs to the desktop (search / window switching)"
    else
        ok "${combo} is left for the desktop, as designed"
    fi
done

# ==============================================================================
# 5. The service, and the fact that it is switched on
# ==============================================================================
say "The service that starts it at login"
aq_file_has "${UNIT}" '^ExecStart=/usr/libexec/aquarius-keys-run$' \
    "the service runs the right program"
aq_file_has "${UNIT}" '^WantedBy=graphical-session\.target$' \
    "the service belongs to the graphical session"
aq_file_has "${UNIT}" '^PartOf=graphical-session\.target$' \
    "the service ends when the desktop does, rather than outliving it"

# ------------------------------------------------------------------------------
# ⚠️ EVERY LINE BELOW IS A FIX FOR THE BENCH BUG OF 2026-09-03, AND EVERY ONE OF
# THEM IS ONE EDIT AWAY FROM BEING LOST AGAIN.
# ------------------------------------------------------------------------------
# What happened, in one paragraph: a second remapper — the LOGIN SCREEN's, run
# from the same "switched on" link, because that link lives in /usr and applies
# to every account including gdm's — already had hold of both of Royce's
# keyboards. Ours was refused each one with "Device or resource busy", ended up
# holding nothing, and sat there while systemctl reported it active. Every
# shortcut was dead and it looked exactly like Windows mode.
#
# The full story is in docs/restart/aquarius-keys.md, under "It came up in
# Windows mode".
aq_file_has "${UNIT}" '^ConditionUser=!@system$' \
    "the LOGIN SCREEN does not run this — the 2026-09-03 root cause (a system account's remapper held the keyboards)"
aq_file_has "${UNIT}" '^Restart=always$' \
    "it keeps trying — a keyboard that is busy for a few seconds must not cost you your shortcuts for the whole session"
aq_file_has "${UNIT}" '^RestartSec=2$' \
    "it tries again two seconds later"
aq_file_has "${UNIT}" '^StartLimitIntervalSec=0$' \
    "it never gives up (the rate limiter that would stop it is switched off on purpose)"
aq_file_has "${UNIT}" '^RestartPreventExitStatus=64 78$' \
    "the two exits that mean 'retrying cannot help' are named: nothing to do (64) and broken image (78)"
aq_file_has "${UNIT}" '^ExecStartPre=-/usr/bin/pkill --uid %U --exact xremap-wlroots$' \
    "any leftover remapper of this person's own is cleared out of the way first"

# The run script's half of the same fix.
aq_file_has "${RUN_SCRIPT}" 'ignore=xremap' \
    "a leftover 'xremap' virtual keyboard can never be auto-selected as the only device (event16 on the bench)"
aq_file_has "${RUN_SCRIPT}" 'resource busy' \
    "a refused keyboard is treated as a failure of the run, so systemd retries — the bench's --watch dead end"
aq_file_has "${RUN_SCRIPT}" 'No device was selected' \
    "holding no keyboards at all is treated as a failure too"
aq_file_has "${RUN_SCRIPT}" 'remapping .* keyboard' \
    "it says how many keyboards it actually has hold of, so 'running' and 'working' can be told apart"
aq_file_has "${RUN_SCRIPT}" 'aq_wait 30 "GNOME Shell to be ready"' \
    "on GNOME it waits for the shell before asking it to switch the add-on on"
aq_file_has "${RUN_SCRIPT}" 'gnome-extensions info' \
    "and waits for that add-on to finish loading, not merely to be switched on"

# And the front door has to be able to answer the question Royce could not.
aq_file_has "${AQ_CLI}" 'Keyboards :' \
    "'aq keys status' reports how many keyboards are being remapped"
aq_file_has "${AQ_CLI}" 'reset-failed' \
    "'aq keys mac' clears an earlier failure before restarting, so it cannot report success over a service that did not start"

# The two commands the service and the run script shell out to. Neither is
# fatal — the ExecStartPre lines are prefixed with `-`, and pgrep is fenced —
# but a missing one quietly removes a piece of the 2026-09-03 fix, so it should
# be a decision rather than a surprise.
say "The commands the keyboard service uses"
for aq_cmd in pkill pgrep; do
    if aq_have "${aq_cmd}"; then
        ok "${aq_cmd} ($(command -v "${aq_cmd}"))"
    else
        bad "${aq_cmd} is missing — a leftover remapper could not be cleared out of the way"
    fi
done
if [ -x /usr/bin/pkill ]; then
    ok "/usr/bin/pkill is exactly where the service file says it is"
else
    bad "the service file runs /usr/bin/pkill and there is nothing there — the ExecStartPre lines would do nothing"
fi

# The keyboards on Royce's bench are a Logitech K780 and a Razer Cynosa Chroma
# Pro. Both are ordinary PC keyboards and BOTH must get the PC swap — neither
# should be caught by the Apple exclusion. Checking the exclusion is exactly the
# four Apple-only entries is how a future "and Logitech" typo gets caught here
# rather than on a machine.
say "The Apple exclusion catches Apple keyboards and nothing else"
# Only the FIRST `not:` block — the one in the modmap, which is the keyboard
# exclusion. There is a second `not:` further down for applications, and a range
# match would run straight into it.
aq_apple_entries="$(awk '/^ *not:/ { inside = 1; next }
                         inside && /^ *remap:/ { exit }
                         inside && /^ *- / { sub(/^ *- */, ""); gsub(/"/, ""); print }' \
    "${KEYS_DIR}/mac.yaml")"
echo "${aq_apple_entries}" | sed 's/^/    /'
aq_apple_expected="ids:0x05ac:0x0000
ids:0x004c:0x0000
Apple
Magic Keyboard"
if [ "${aq_apple_entries}" = "${aq_apple_expected}" ]; then
    ok "only Apple's own devices are excluded — a Logitech K780 and a Razer Cynosa both get Mac keys"
else
    bad "the Apple exclusion list has changed. It must be exactly Apple's two maker numbers, 'Apple' and 'Magic Keyboard' — anything broader would silently stop remapping an ordinary PC keyboard."
fi

# ------------------------------------------------------------------------------
# ⚠️ WHY THE "SWITCHED ON" LINK IS IN /usr AND NOT /etc
# ------------------------------------------------------------------------------
# `systemctl --global enable` would write this link into /etc. On an
# image-based system /etc is merged three ways at every update — ours, yours,
# and the previous version's — and a link that lands there can be lost, kept
# when it should not be, or argued over. A link inside the read-only half of
# the system is simply true, on every machine, from the first boot.
#
# The trade-off, written down because it surprises people: `systemctl --user
# disable` then has nothing in /etc to delete, so it does not turn this off.
# `systemctl --user mask --now aquarius-keys` does, and that is the command the
# documentation gives.
if [ -L "${WANTS_LINK}" ]; then
    target="$(readlink "${WANTS_LINK}")"
    echo "  ${WANTS_LINK} -> ${target}"
    if [ -e "${WANTS_LINK}" ]; then
        ok "the service is switched on by default, and the link points at a real file"
    else
        bad "the 'switched on' link is dangling — it points at ${target}, which is not there"
    fi
else
    bad "${WANTS_LINK} is missing — the service would be installed but never start"
fi

# systemd is fussy about unit files and says so only at runtime, on a user's
# machine, in a log they will never read. Ask it here instead. Its verdict is
# advisory (it also warns about things that are fine in a container), so its
# output is printed and only a hard parse failure is treated as a fault.
if aq_have systemd-analyze; then
    say "systemd's own opinion of the service file"
    aq_verify="$(systemd-analyze verify --user "${UNIT}" 2>&1 || true)"
    printf '%s\n' "${aq_verify}" | sed 's/^/  /'

    # Most of what systemd-analyze says in a container is noise about units that
    # only exist on a real machine. Two things are NOT noise, and both mean the
    # file would be ignored at somebody's login:
    #
    #   "Unknown key"/"Unknown lvalue"  a setting spelled wrong. systemd skips
    #                                   the line and starts anyway, so a typo in
    #                                   ConditionUser= or RestartPreventExitStatus=
    #                                   would silently un-do the 2026-09-03 fix.
    #   "Failed to parse"               the file is not readable at all.
    # ⚠️ AND CHECK THAT IT ACTUALLY LOOKED. Observed in the 2026-09-03 build:
    # inside a container systemd-analyze cannot start a manager at all —
    #
    #   Failed to lookup RuntimeDirectory path: No such device or address
    #   Failed to initialize manager: No such device or address
    #
    # — so it never reaches the file, prints no complaint, and a check that only
    # looks for complaints reports a confident OK over a tool that did nothing.
    # A green tick nobody earned is worse than no tick, so say which happened.
    if printf '%s' "${aq_verify}" | grep -Eqi "failed to initialize manager|failed to lookup runtimedirectory"; then
        echo "  note   systemd-analyze could not start inside this container, so it"
        echo "         did not read the file. The line-by-line checks above are"
        echo "         what actually guard this unit."
    elif printf '%s' "${aq_verify}" | grep -Eqi "unknown (key|lvalue)|failed to parse"; then
        bad "systemd cannot understand part of ${UNIT} (see above). A setting it"
        bad "cannot read is a setting that does nothing, silently."
    else
        ok "systemd read the service file and understood every line of it"
    fi
fi

# ==============================================================================
# 6. The switch, and the default
# ==============================================================================
say "The 'aq keys' command and the default setting"

for script in "${RUN_SCRIPT}" "${AQ_CLI}"; do
    if [ ! -f "${script}" ]; then
        bad "${script} is missing"
        continue
    fi
    # system_files is copied with cp -a, which preserves the mode from git.
    # Setting it again costs nothing and means a file added later with the
    # wrong permissions cannot ship a command nobody can run.
    chmod 0755 "${script}"
    if bash -n "${script}"; then
        ok "$(basename "${script}") is valid shell"
    else
        bad "$(basename "${script}") has a syntax error"
    fi
done

# Does the command actually work? Both of these run to completion here, with no
# desktop and no logged-in person, which is itself the test: `aq keys status`
# has to explain the situation rather than fall over.
say "Running 'aq' for real"
if "${AQ_CLI}" --help > /dev/null; then
    ok "aq --help works"
else
    bad "aq --help failed"
fi
echo "--- aq keys status ---"
if "${AQ_CLI}" keys status; then
    ok "aq keys status works with no desktop running"
else
    bad "aq keys status failed"
fi
echo "---"

# `aq display` is the other half of the 2026-09-03 work. It has to survive being
# run in a container with no screen at all, because that is very close to being
# run over SSH, which is a thing people do.
echo "--- aq display status ---"
if "${AQ_CLI}" display status; then
    ok "aq display status works with no screen attached"
else
    bad "aq display status failed"
fi
echo "---"
if "${AQ_CLI}" display --help > /dev/null; then
    ok "aq display --help works"
else
    bad "aq display --help failed"
fi
if "${AQ_CLI}" display scale banana > /dev/null 2>&1; then
    bad "aq display accepted 'banana' as a size"
else
    ok "aq display refuses a size that is not a number"
fi

# The default, in both of the two places it is written.
aq_file_has "${SKEL_CONF}" '^mode=mac$' \
    "a brand-new account gets Mac shortcuts (${SKEL_CONF})"
aq_file_has "${RUN_SCRIPT}" '^AQ_MODE="mac"$' \
    "an account with no settings file also gets Mac shortcuts"

aq_finish "Aquarius Keys"
