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

# Our own GNOME toggle — the Mac-or-Windows switch in the quick settings menu.
# It is plain text files, shipped in system_files/ and copied in at step 50, so
# there is nothing to compile; this step only checks it. See part 7 below.
AQ_EXT_UUID="aquarius-keys@stoneharborent.github.io"
AQ_EXT_DIR="/usr/share/gnome-shell/extensions/${AQ_EXT_UUID}"

# Where the throwaway `kcm-build` stage left the compiled KDE settings page.
# Mounted by the Containerfile, exactly like /ctx-xremap above.
KCM_BUILD="/ctx-kcm"

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
# by the run script at login.
#
# ⚠️ IT IS STILL NOT LISTED IN THE IMAGE'S enabled-extensions DEFAULT, AND THAT
# IS NOW A DELIBERATE DIFFERENCE RATHER THAN A TEMPORARY ONE. That list lives in
# system_files/usr/share/glib-2.0/schemas/zz1-aquarius-20-shell.gschema.override.
# This one stays off it, because it belongs to the keyboard feature rather than
# to the desktop: the run script switches it on per account at login, beside
# everything else it does for the keyboard, and that keeps one feature's pieces
# in one place.
#
# ⚠️ AND SINCE 2026-09-17 THE RUN SCRIPT ALSO SWITCHES ON OUR OWN TOGGLE — the
# Mac-or-Windows switch in the quick settings menu, checked in part 7 below —
# even though that one IS in the enabled-extensions default. That is not a
# contradiction, it is the fix for a bug found on the bench:
#
#   a gschema default only applies while an account has never written the
#   setting itself, and the line above (`gnome-extensions enable`) writes the
#   WHOLE enabled-extensions list into the user's own settings at first login.
#   From that moment the image's default is dead for that account, so any
#   add-on we add to the default later never reaches an account that already
#   exists — which is exactly what the bench saw: installed, listed, Enabled:No.
#
# So: THE DEFAULT COVERS BRAND-NEW ACCOUNTS; THE LOGIN SCRIPT COVERS EXISTING
# ONES. The login script does it once per account and leaves a marker file, so
# turning the toggle off in the Extensions app sticks.
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
# The lock key is Ctrl+Cmd+Q on BOTH desktops. Cmd+L was the lock for one day,
# 2026-09-06, and never fired: this file turns Cmd+L into Ctrl+L for the address
# bar, so Super+L never reaches the desktop while Mac keys are on. So the one
# rule about the lock key is that this file must NOT touch it — a remap of
# Ctrl+Super+q here would kill the lock again, silently, on both desktops.
# (xremap spells the chord either way round.)
#
# The two halves that make Ctrl+Cmd+Q actually lock something are checked
# further down: zz1-aquarius-40-keys.gschema.override for GNOME and
# /etc/xdg/kglobalshortcutsrc for KDE Plasma.
if grep -qE '^ *(C-Super-q|Super-C-q|C-Super-Q|Super-C-Q) *:' "${KEYS_DIR}/mac.yaml"; then
    bad "mac.yaml remaps Ctrl+Cmd+Q — that is the lock key, and neither desktop would ever see it"
else
    ok "mac.yaml leaves Ctrl+Cmd+Q alone, so the lock key reaches the desktop"
fi
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
# ⚠️ AND THE ONE THAT CHANGED DIRECTION. Until 2026-09-08 this line checked the
# OPPOSITE: that mac.yaml carried `- resolve` in its exclusion list, so that
# DaVinci Resolve kept its Control keys in Mac mode.
#
# Royce's decision that day (feature 008 item 11) reversed it. The old reasoning
# was "a professional app where you have years of Control-key muscle memory";
# his years of Resolve are MAC years, so excluding it meant Command did nothing
# inside the one application this operating system exists for, while working
# everywhere else. Resolve follows the OS setting now: Mac mode maps Command
# inside Resolve, Windows mode leaves everything alone.
#
# So the check is inverted rather than deleted. A deleted check is a decision
# nobody can see being undone.
if grep -Eq '^[[:space:]]*- resolve([[:space:]]|$)' "${KEYS_DIR}/mac.yaml"; then
    bad "mac.yaml excludes DaVinci Resolve again — Command would do nothing inside Resolve while working everywhere else (Royce's decision, 2026-09-08)"
else
    ok "DaVinci Resolve follows the OS's keyboard setting, like everything else"
fi

# Command-Space, Command-Tab and Command-` must NOT be remapped: they are how
# the desktop's own search and window switching are reached. A rule for any of
# them would take the search away and nothing would say why.
say "Checking the desktop's own keys are left alone"
for combo in 'Super-space' 'Super-Tab' 'Super-grave'; do
    if grep -Eq "^[[:space:]]+${combo}:" "${KEYS_DIR}/mac.yaml"; then
        bad "mac.yaml remaps ${combo} — that key belongs to the desktop (search / window switching)"
    else
        ok "${combo} is left for the desktop, as designed"
    fi
done

# ==============================================================================
# 4b. ...and the desktop is actually listening for them — on BOTH desktops
# ==============================================================================
# ⚠️ THIS SECTION IS NEW ON 2026-09-15 AND IT IS THE HALF THAT USED TO BE
# SOMEBODY ELSE'S JOB. Until that day, "the desktop answers Command-Tab" was a
# fact about the Aquarius Session, written in a labwc file this repository
# owned, and checked by the shell's own drift test. That desktop is retired
# (../docs/decision-2026-09-15-two-desktops.md) and the same fact is now two
# facts, one per desktop — which is exactly the sort of thing that goes quietly
# missing on whichever one nobody used that week.
#
# GNOME answers Super-Tab and Super-` from the factory. It answers nothing for
# the lock in Mac mode, which is what the gschema override fixes.
# KWin answers Alt-Tab and Alt-` from the factory and nothing for Meta-Tab,
# which is what the kglobalshortcutsrc adds — without removing the Alt ones.
say "Both desktops are listening for the Mac keys"

AQ_GNOME_KEYS=/usr/share/glib-2.0/schemas/zz1-aquarius-40-keys.gschema.override
aq_file_has "${AQ_GNOME_KEYS}" "^screensaver=.*<Control><Super>q" \
    "GNOME: Control-Command-Q locks the screen (the key that survives Mac mode)"
aq_file_has "${AQ_GNOME_KEYS}" "^screensaver=.*<Super>l" \
    "GNOME: and Super+L still locks it too, for anybody in Windows mode"
# The setting has to be REAL, not just written down. A typo in a schema or a key
# name makes glib-compile-schemas fail the whole image, which step 5 would have
# caught — but a key that compiles and is simply never read would not be caught
# anywhere, so ask gsettings what the finished image actually says.
if aq_have gsettings; then
    AQ_LOCK_KEYS="$(gsettings get org.gnome.settings-daemon.plugins.media-keys screensaver 2> /dev/null || echo "")"
    echo "  GNOME's lock keys in this image: ${AQ_LOCK_KEYS:-(no answer)}"
    case "${AQ_LOCK_KEYS}" in
        *"<Control><Super>q"*) ok "GNOME really reports Control-Command-Q as a lock key" ;;
        *) bad "GNOME reports its lock keys as '${AQ_LOCK_KEYS}' — our override did not take effect" ;;
    esac
fi

AQ_KDE_KEYS=/etc/xdg/kglobalshortcutsrc
if [ ! -r "${AQ_KDE_KEYS}" ]; then
    bad "${AQ_KDE_KEYS} is missing — on KDE Plasma, Command-Tab would do nothing at all"
else
    aq_file_has "${AQ_KDE_KEYS}" '^Walk Through Windows=.*Meta\+Tab' \
        "KDE: Command-Tab switches apps"
    aq_file_has "${AQ_KDE_KEYS}" '^Walk Through Windows=Alt\+Tab' \
        "KDE: and Alt-Tab still does too (it is listed first, so it is not replaced)"
    aq_file_has "${AQ_KDE_KEYS}" '^Walk Through Windows of Current Application=.*Meta\+`' \
        "KDE: Command-\` switches between one app's windows"
    aq_file_has "${AQ_KDE_KEYS}" '^Lock Session=.*Ctrl\+Meta\+Q' \
        "KDE: Control-Command-Q locks the screen"
    aq_file_has "${AQ_KDE_KEYS}" '^_launch=.*Meta\+Space' \
        "KDE: Command-Space opens the search box (KRunner)"
    # KDE's format is "now,factory,name" and a missing field silently disables
    # the line. Count the commas rather than trusting the eye.
    if awk -F= '/^(Walk Through|Lock Session|_launch)/ { n=split($2, parts, ","); if (n != 3) { print "  FAIL " $1 " has " n " fields, not 3"; bad=1 } } END { exit bad }' "${AQ_KDE_KEYS}"; then
        ok "every shortcut line has all three fields KDE expects"
    else
        bad "a shortcut line in ${AQ_KDE_KEYS} is malformed — KDE would ignore it in silence"
    fi
fi

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
# ⚠️ AND THE GDM 50 HALF OF THAT, FOUND ON THE BENCH ON 2026-09-19. GDM 50 runs
# the login screen as a systemd DYNAMIC user called `gdm-greeter`, whose user
# number comes from the 61184-65519 range — ABOVE the ordinary range, so
# `!@system` does not catch it, and the 2026-09-03 bug had quietly come back:
# the bench journal has this service running at the login screen, saying
# `desktop is 'GNOME-Greeter:GNOME'`.
aq_file_has "${UNIT}" '^ConditionUser=!gdm-greeter$' \
    "and GDM 50's dynamic greeter account does not run it either"
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
# ------------------------------------------------------------------------------
# ⚠️ AND THE 2026-09-24 FIX, WHICH IS THE OPPOSITE OF THE LINE THAT USED TO BE
# HERE. IT IS ONE EDIT AWAY FROM BEING LOST, AND LOSING IT IS EXPENSIVE.
# ------------------------------------------------------------------------------
# Until 2026-09-24 this file checked that "no keyboards at all" was ALSO treated
# as a failure of the run. On the bench that turned out to be the wrong call and
# it cost 60,945 restarts over three days — once every two and a half seconds,
# for three days, each one inventing another virtual keyboard — because Royce's
# only keyboard is a Bluetooth K780 that disconnects when it is left alone, and
# while it is away "no keyboards at all" is simply true.
#
# It is not a failure, and restarting never helped: --watch=device means the
# remapper is already waiting for a keyboard to appear and takes hold of it by
# itself when one does. That was measured on the bench, not assumed.
#
# So the run script must still RECOGNISE the line, and must NOT turn it into a
# failure. Both halves are checked, because recognising it and then failing
# anyway is exactly the bug.
aq_file_has "${RUN_SCRIPT}" 'No device was selected' \
    "it still recognises the remapper's 'no keyboard' line"
aq_file_has "${RUN_SCRIPT}" 'no keyboard is connected at the moment' \
    "and answers it by waiting, in a line that says nothing is wrong"
if grep -q 'aq_problem="none"' "${RUN_SCRIPT}"; then
    bad "'no keyboard at all' is still treated as a failure — this is the 2026-09-24 restart loop, back again"
else
    ok "'no keyboard at all' is NOT treated as a failure (no aq_problem=\"none\" anywhere)"
fi
aq_file_has "${RUN_SCRIPT}" '^                aq_count=0$' \
    "the keyboard tally restarts when the remapper re-lists devices, so a later arrival is not double-counted"

# The brake on the retry loop, added the same day. The run script fix cures the
# loop we found; these two lines are what stops the next one we have not.
aq_file_has "${UNIT}" '^RestartSteps=10$' \
    "a failure that cannot fix itself is retried more and more slowly, instead of every two seconds forever"
aq_file_has "${UNIT}" '^RestartMaxDelaySec=5min$' \
    "and never slower than once every five minutes, so it still recovers by itself"
aq_file_has "${RUN_SCRIPT}" 'remapping .* keyboard' \
    "it says how many keyboards it actually has hold of, so 'running' and 'working' can be told apart"
# ⚠️ AND IT MUST STOP IN GAME MODE, THE BENCH FIX OF 2026-09-19. In the
# gamescope session there is no desktop to remap for, and the journal of that
# evening shows this waiting thirty seconds for a screen, starting anyway, and
# taking hold of four keyboards including a game controller's keyboard
# interface. It now recognises Game Mode and exits 64 — one of the two
# statuses RestartPreventExitStatus= names, so systemd does not start it again
# every two seconds for the whole gaming session.
aq_file_has "${RUN_SCRIPT}" '^aq_in_game_mode\(\)' \
    "the remapper knows how to recognise Game Mode"
aq_file_has "${RUN_SCRIPT}" 'this is Game Mode, not a desktop' \
    "and says so in one plain line before stopping"
aq_file_has "${RUN_SCRIPT}" 'if aq_in_game_mode; then' \
    "and the test really is used, before the thirty-second wait for a screen"
if [ "$(grep -n 'if aq_in_game_mode; then' "${RUN_SCRIPT}" | cut -d: -f1)" \
    -lt "$(grep -n 'aq_wait 30 "the desktop.s screen"' "${RUN_SCRIPT}" | cut -d: -f1)" ]; then
    ok "the Game Mode test comes BEFORE the wait — no thirty seconds wasted in a game"
else
    bad "the Game Mode test comes after the wait for a screen, which is the whole thing it avoids"
fi

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

# ------------------------------------------------------------------------------
# 6b. The window buttons are NOT part of this choice (Royce, 2026-09-17)
# ------------------------------------------------------------------------------
# From 6 to 17 September 2026, `aq keys mac` also moved the close, minimise and
# maximise buttons to the LEFT of the title bar. It was dropped because it could
# not be made universal: applications that draw their own title bar (Chrome's
# Flatpak on the bench) ignored it, so some windows moved and some did not.
#
# The buttons are now stock and on the RIGHT, on both desktops, for everybody.
# Three things have to be true for that, and losing any one of them brings the
# old behaviour back in a way nobody would notice until the bench.
say "The window buttons are stock, on the right, and nothing moves them"

# 1. The image's default really is the right-hand layout. Asked of the settings
#    system the same way a brand-new account asks it.
if aq_have gsettings; then
    if aq_output_has ":minimize,maximize,close" \
        env GSETTINGS_BACKEND=memory gsettings get org.gnome.desktop.wm.preferences button-layout; then
        ok "a new account gets all three buttons, on the right"
    else
        bad "the image's button-layout default is not ':minimize,maximize,close' — fix system_files/usr/share/glib-2.0/schemas/zz1-aquarius-10-look.gschema.override"
    fi
fi

# 2. Nothing in `aq` moves them any more. The old function was called
#    apply_window_buttons; if it ever comes back, this catches it.
if grep -q "apply_window_buttons" "${AQ_CLI}"; then
    bad "${AQ_CLI} still has apply_window_buttons — the Mac/Windows switch would move the buttons again"
else
    ok "'aq keys' no longer moves the window buttons; it is the keyboard only"
fi

# 3. ⚠️ AND THE ACCOUNTS THAT ALREADY HAVE A LEFT-HAND LAYOUT WRITTEN INTO THEM
#    ARE PUT BACK. The default in point 1 only reaches accounts that have never
#    written this setting themselves, and `aq keys` wrote it into every account
#    that ever ran it. So the login script undoes our own handwriting, once per
#    account, marked by a file. Both halves are checked, because without either
#    one those accounts keep left-hand buttons forever.
aq_file_has "${RUN_SCRIPT}" "button-layout" \
    "the login script puts an old left-hand layout back to the default"
aq_file_has "${RUN_SCRIPT}" "window-buttons-unpinned" \
    "and does it once per account, remembered by a marker file"
aq_file_has "${RUN_SCRIPT}" "ButtonsOnLeft" \
    "it clears the KDE half of the old layout out of kwinrc too"

# ==============================================================================
# 7. The two graphical switches (added 2026-09-16)
# ==============================================================================
# WHAT THIS PART IS FOR
#
# Everything above gives the computer Mac-style keys and one command to change
# them. What it did NOT give anybody was a way to FIND that choice again. The
# Welcome window asks it once, on a person's first login, and after that the
# only answer was to know that a command called `aq` exists.
#
# So since 2026-09-16 the same choice has a switch on each desktop:
#
#   GNOME   a toggle in the quick settings menu at the top-right of the screen,
#           beside Wi-Fi and Dark Style. It is a small add-on of ours, plain
#           text files, shipped in system_files/ and switched on for everybody
#           in the image's own list of add-ons.
#   KDE     a page called "Mac or Windows" in System Settings, under
#           "Appearance & Style". It is a compiled plugin, built in the
#           throwaway `kcm-build` stage by build_files/73-keys-kcm-build.sh.
#
# ⚠️ NEITHER OF THEM DECIDES ANYTHING. Both read the same settings file this
# whole step is about, and both change it by running `aq keys mac` or
# `aq keys windows` — the same command a person would type. There is one owner
# of this setting and it is /usr/bin/aq.

# ------------------------------------------------------------------------------
# 7a. The GNOME toggle
# ------------------------------------------------------------------------------
say "The GNOME quick-settings toggle"

if [ ! -r "${AQ_EXT_DIR}/metadata.json" ]; then
    bad "${AQ_EXT_DIR}/metadata.json is missing — the toggle would simply not exist"
elif [ ! -s "${AQ_EXT_DIR}/extension.js" ]; then
    bad "${AQ_EXT_DIR}/extension.js is missing or empty"
else
    ok "the add-on's files are in the image"

    # ⚠️ THE FOLDER NAME AND THE ID INSIDE THE FILE HAVE TO MATCH, EXACTLY.
    # GNOME finds an add-on by folder name and then believes the id written
    # inside it. If the two disagree, the add-on is loaded and then refuses to
    # start, with nothing anywhere saying why.
    if python3 - "${AQ_EXT_DIR}/metadata.json" "${AQ_EXT_UUID}" << 'PY'; then
import json
import sys

meta = json.load(open(sys.argv[1]))
print(f"       it calls itself {meta['uuid']!r}, version name {meta.get('version-name', '?')!r}")
print(f"       it says it works with GNOME Shell {', '.join(str(v) for v in meta['shell-version'])}")
sys.exit(0 if meta["uuid"] == sys.argv[2] else 1)
PY
        ok "metadata.json is valid and its id matches the folder it lives in"
    else
        bad "metadata.json is not valid, or its id is not ${AQ_EXT_UUID} — GNOME would refuse to start it"
    fi

    # It has to declare support for THIS GNOME Shell, or the shell refuses to
    # load it — silently, with no toggle and no error anywhere. Same trap the
    # dock hits; see build_files/40-gnome-desktop.sh.
    if aq_have gnome-shell; then
        gnome-shell --version > /tmp/aq-keys-shell-version.txt
        AQ_SHELL_MAJOR="$(awk '{print $3}' /tmp/aq-keys-shell-version.txt | cut -d. -f1)"
        rm -f /tmp/aq-keys-shell-version.txt
        if python3 - "${AQ_EXT_DIR}/metadata.json" "${AQ_SHELL_MAJOR}" << 'PY'; then
import json
import sys

meta = json.load(open(sys.argv[1]))
sys.exit(0 if sys.argv[2] in [str(v) for v in meta["shell-version"]] else 1)
PY
            ok "it supports the GNOME Shell this image ships (${AQ_SHELL_MAJOR})"
        else
            bad "it does not list GNOME Shell ${AQ_SHELL_MAJOR} — the toggle would never appear. Edit shell-version in ${AQ_EXT_DIR}/metadata.json."
        fi
    fi

    # ⚠️ AN ADD-ON THAT IS INSTALLED BUT NOT SWITCHED ON IS INVISIBLE, and
    # nothing says so. The list of add-ons GNOME switches on is a DEFAULT
    # compiled into the image's settings, so the honest way to check it is to
    # ask the settings system the same question a new account asks on its first
    # login. GSETTINGS_BACKEND=memory means "read the compiled defaults", which
    # is the only thing that can work in a build with no desktop running.
    if aq_have gsettings; then
        if aq_output_has "${AQ_EXT_UUID}" \
            env GSETTINGS_BACKEND=memory gsettings get org.gnome.shell enabled-extensions; then
            ok "it is switched on by default for every new account"
        else
            bad "${AQ_EXT_UUID} is not in the image's enabled-extensions default — it would be installed and invisible. Add it in system_files/usr/share/glib-2.0/schemas/zz1-aquarius-20-shell.gschema.override."
        fi
    fi

    # It runs `aq keys`, so it has to name the real command.
    aq_file_has "${AQ_EXT_DIR}/extension.js" "'/usr/bin/aq'" \
        "the toggle runs /usr/bin/aq rather than writing the settings file itself"

    # ⚠️ THE DEFAULT ABOVE ONLY REACHES BRAND-NEW ACCOUNTS (bench, 2026-09-17).
    # An account that has logged in before already owns its own copy of
    # enabled-extensions — the run script's `gnome-extensions enable` wrote it —
    # and a default never beats a value. So the run script has to switch this
    # toggle on as well, once per account, marked by a file so that a person who
    # turns it off in the Extensions app stays off. Both halves are checked here,
    # because losing either one brings the invisible-toggle bug straight back.
    aq_file_has "${RUN_SCRIPT}" "${AQ_EXT_UUID}" \
        "the login script switches the toggle on for accounts that already exist"
    aq_file_has "${RUN_SCRIPT}" "keys-toggle-enabled" \
        "and does it once per account, remembered by a marker file"
fi

# ------------------------------------------------------------------------------
# 7b. The KDE System Settings page
# ------------------------------------------------------------------------------
say "The KDE 'Mac or Windows' page in System Settings"

if [ ! -s "${KCM_BUILD}/kcm/kcm_aquariuskeys.so" ]; then
    bad "the settings page did not come through from the kcm-build stage"
elif [ ! -s "${KCM_BUILD}/kcm/install-path" ]; then
    bad "${KCM_BUILD}/kcm/install-path is missing — the build did not say where the page belongs"
else
    # The build stage wrote down the exact folder its own KDE libraries chose,
    # rather than us guessing between lib and lib64.
    KCM_DEST="$(cat "${KCM_BUILD}/kcm/install-path")"
    install -D -m 0755 "${KCM_BUILD}/kcm/kcm_aquariuskeys.so" "${KCM_DEST}"
    ok "installed at ${KCM_DEST}"

    # ⚠️ IT IS ONLY A SETTINGS PAGE IF IT IS IN THE ONE FOLDER SYSTEM SETTINGS
    # READS. Anywhere else and it is just a file.
    case "${KCM_DEST}" in
        */plasma/kcms/systemsettings/kcm_aquariuskeys.so)
            ok "that is the folder System Settings looks in"
            ;;
        *)
            bad "${KCM_DEST} is not a folder System Settings reads — the page would never appear"
            ;;
    esac

    # Does it have every library it needs, HERE, in the image that ships? This
    # is the check the header of 73-keys-kcm-build.sh promises: the page was
    # compiled in a different container, and `ldd` prints "not found" beside
    # anything missing.
    echo "--- what the page needs ---"
    ldd "${KCM_DEST}" || true
    echo "---"
    if ldd "${KCM_DEST}" 2>&1 | grep -q "not found"; then
        bad "the settings page needs a library that is not in this image (see above) — it would fail to load"
    else
        ok "every library the page needs is in the image"
    fi

    # The page's name, its search words and WHERE IT APPEARS are baked into the
    # plugin as text. Read them back out of the finished file: if the
    # description did not make it in, System Settings shows nothing at all.
    for aq_kcm_text in \
        "Mac or Windows" \
        "X-KDE-System-Settings-Parent-Category" \
        "appearance"; do
        if grep -aq -- "${aq_kcm_text}" "${KCM_DEST}"; then
            ok "the page carries its own description: ${aq_kcm_text}"
        else
            bad "the page does not contain '${aq_kcm_text}' — System Settings would not know what it is or where to put it"
        fi
    done

    # ⚠️ IT MUST NOT TURN UP IN GNOME. Both desktops read
    # /usr/share/applications/, so a menu entry for a KDE-only settings page
    # would be a dead icon in GNOME's app grid. The build is told not to make
    # one; this is what catches it if that ever changes.
    if ls /usr/share/applications/kcm_aquariuskeys* > /dev/null 2>&1; then
        bad "a menu entry for the KDE page was installed — it would appear in GNOME's app grid"
    else
        ok "it has no menu entry, so GNOME never shows it"
    fi
fi

aq_finish "Aquarius Keys"
