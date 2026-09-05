#!/usr/bin/bash
# ==============================================================================
# Step 8 — the boot path says AquariusOS
# ==============================================================================
# PLAIN ENGLISH
#
# Steps 1–7 built a working computer that calls itself AquariusOS once it is
# running. This step covers everything you see BEFORE that: the boot menu, the
# splash screen while it starts, and the text banner above a text login prompt.
#
# Left alone, all three of those say Fedora, and on most laptops and desktops
# the splash screen shows the computer manufacturer's logo — a Dell or ASUS or
# MSI badge — because that is what Fedora's default splash theme is designed to
# do. This step replaces all of it.
#
# Six jobs, in this order:
#
#   1. Put the Aquarius boot splash in place and make it the default.
#   2. Tell the boot menu to call itself AquariusOS.
#   3. Make the kernel actually ASK for a graphical splash at start-up.
#   4. Fix the text banners — /etc/issue, /etc/motd, /etc/fedora-release.
#  4b. Check that the banner has nothing to complain about — the "Failed Units"
#      line that used to print under it, every boot, for no real reason.
#   5. Replace the Fedora artwork that other programs still point at by name.
#   6. Rebuild the boot ramdisk, so that all of the above is really used.
#
# ------------------------------------------------------------------------------
# ⚠️ WHY THIS RUNS AFTER THE NVIDIA STEP, AND MUST KEEP RUNNING AFTER IT
# ------------------------------------------------------------------------------
# Job 6 is the important one and the easiest to get wrong.
#
# The "boot ramdisk" (its real name is the initramfs, and it is one file called
# initramfs.img) is a tiny, self-contained copy of just enough of the system to
# get the real system started. The boot splash lives INSIDE it — a copy of the
# splash theme is baked into that file. Changing the theme on disk and not
# rebuilding the ramdisk means the machine goes on showing the old splash
# forever, and nothing warns you.
#
# The ramdisk is built for ONE EXACT KERNEL VERSION. And build_files/60-nvidia.sh
# sometimes REPLACES this image's kernel — it has to, because an NVIDIA driver
# only works with the exact kernel it was compiled against, and that is the whole
# subject of docs/restart/nvidia-notes.md.
#
# So if this step ran before that one, it would build a ramdisk for a kernel that
# is then thrown away, and the NVIDIA image would have no usable ramdisk at all.
# **This step must stay last but for the cleanup.** The Containerfile's step
# numbering is what keeps that true; do not reorder it.
#
# A bonus that falls out of doing this at all: 60-nvidia.sh writes a setting that
# forces the NVIDIA driver into the boot ramdisk (so the screen does not go black
# and come back during start-up). Until this step existed, nothing ever rebuilt
# the ramdisk, so that setting was written and never acted on. Now it is.
# ==============================================================================

source "$(dirname "$0")/aq-lib.sh"

THEME_NAME="aquarius"
THEME_DIR="/usr/share/plymouth/themes/${THEME_NAME}"
SPINNER_DIR="/usr/share/plymouth/themes/spinner"
PLYMOUTH_CONF="/etc/plymouth/plymouthd.conf"
PLYMOUTH_DEFAULTS="/usr/share/plymouth/plymouthd.defaults"
KARGS_FILE="/usr/lib/bootc/kargs.d/05-aquarius-boot.toml"
GRUB_DEFAULTS="/etc/default/grub"

# The two Aquarius pictures this step reuses. Both are committed in the repo and
# were copied into the image by step 5.
AQ_MARK_PNG="/usr/share/aquarius/branding/aquarius-logo.png"          # 256x256, the mark alone
AQ_WIDE_PNG="/usr/share/aquarius/branding/aquarius-about-logo-white.png"  # 279x80, mark + word, white ink

PRETTY_NAME="AquariusOS"

# ==============================================================================
# 1. THE BOOT SPLASH
# ==============================================================================
say "The boot splash"

# Our theme's own files came in with step 5, from
# system_files/usr/share/plymouth/themes/aquarius/. Check they are really here
# before doing anything that depends on them.
if [ ! -r "${THEME_DIR}/${THEME_NAME}.plymouth" ]; then
    echo "AQUARIUS ERROR: ${THEME_DIR}/${THEME_NAME}.plymouth is missing." >&2
    echo "                Step 5 copies it in from" >&2
    echo "                system_files/usr/share/plymouth/themes/aquarius/." >&2
    echo "                Without it there is no AquariusOS boot splash." >&2
    exit 1
fi
if [ ! -s "${THEME_DIR}/watermark.png" ]; then
    echo "AQUARIUS ERROR: ${THEME_DIR}/watermark.png is missing or empty." >&2
    echo "                That is the mark-and-word picture in the middle of the" >&2
    echo "                boot screen. Re-draw it on the Mac with:" >&2
    echo "                    bash branding/render-plymouth-assets.sh" >&2
    exit 1
fi

AQ_FRAMES="$(find "${THEME_DIR}" -name 'throbber-*.png' -printf . | wc -c)"
echo "Aquarius splash pictures: watermark.png + ${AQ_FRAMES} throbber frames"
if [ "${AQ_FRAMES}" -lt 2 ]; then
    echo "AQUARIUS ERROR: only ${AQ_FRAMES} throbber frame(s) in ${THEME_DIR}." >&2
    echo "                The dots under the logo would not move. Re-draw them:" >&2
    echo "                    bash branding/render-plymouth-assets.sh" >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Borrow Fedora's password-box pictures
# ------------------------------------------------------------------------------
# If this machine's disk is encrypted, the boot splash has to draw a box to type
# the password into: a rounded rectangle, a padlock, and a dot per character.
# Those are plain grey shapes with no branding on them at all, and Fedora's
# `spinner` theme already ships them at exactly the sizes the two-step plug-in
# expects. Drawing our own would be three more pictures to maintain for no
# visible difference.
#
# `lock.png` is the one two-step genuinely requires, so a missing spinner theme
# is a hard stop rather than a shrug.
say "The password box (borrowed from Fedora's plain grey shapes)"

if [ ! -d "${SPINNER_DIR}" ]; then
    echo "AQUARIUS ERROR: ${SPINNER_DIR} does not exist, so there are no" >&2
    echo "                password-box pictures to copy." >&2
    echo "                build_files/20-hardware-media.sh installs" >&2
    echo "                plymouth-theme-spinner for exactly this reason." >&2
    echo "                Themes actually present:" >&2
    ls -1 /usr/share/plymouth/themes/ >&2 || true
    exit 1
fi

echo "What Fedora's spinner theme actually ships (so a missing picture names itself):"
rpm -ql plymouth-theme-spinner 2> /dev/null | sed 's/^/  /' || echo "  (cannot list the package)"

# An explicit list, not a wildcard. A wildcard would also drag in spinner's own
# grey spinning animation, which would then fight our dots for the same spot on
# screen.
for f in lock.png entry.png entry-nolock.png bullet.png box.png \
    keyboard.png capslock.png keymap-render.png; do
    if [ -r "${SPINNER_DIR}/${f}" ]; then
        install -D -m 0644 "${SPINNER_DIR}/${f}" "${THEME_DIR}/${f}"
        echo "  copied ${f}"
    else
        echo "  NOTE ${f} is not in this Fedora's spinner theme — skipping (optional)"
    fi
done

if [ -s "${THEME_DIR}/lock.png" ]; then
    ok "the password box has its pictures (lock.png is the required one)"
else
    bad "${THEME_DIR}/lock.png is missing — a machine with an encrypted disk would show no password box"
fi

# Belt and braces: prove no Fedora-branded or competing animation art slipped in.
if compgen -G "${THEME_DIR}/animation-*.png" > /dev/null; then
    bad "${THEME_DIR} contains animation-*.png — those are Fedora's frames, not ours"
    ls -1 "${THEME_DIR}"/animation-*.png
else
    ok "no Fedora animation frames in our theme folder (correct)"
fi

# ------------------------------------------------------------------------------
# Make it the default
# ------------------------------------------------------------------------------
# Two files decide which splash a machine uses:
#
#   /usr/share/plymouth/plymouthd.defaults   what the DISTRIBUTION ships as the
#                                            default (Fedora writes Theme=bgrt
#                                            here — bgrt is the theme whose whole
#                                            job is showing the manufacturer's
#                                            badge)
#   /etc/plymouth/plymouthd.conf             what THIS MACHINE has been set to,
#                                            which wins
#
# We write both. The /etc one is what `plymouth-set-default-theme` writes and is
# the setting that takes effect; changing the /usr one as well means that if
# anything ever resets this machine's own settings, it falls back to our splash
# rather than to Fedora's.
say "Making the Aquarius splash the default"

install -d -m 0755 /etc/plymouth

if aq_have plymouth-set-default-theme; then
    # `|| true` on purpose. This helper's exit status has meant different things
    # in different Plymouth releases, and it is not what we are relying on — the
    # file it writes is, and that is checked immediately below.
    plymouth-set-default-theme "${THEME_NAME}" || true
    echo "plymouth-set-default-theme ${THEME_NAME} — ran"
else
    echo "NOTE: plymouth-set-default-theme is not in this image; writing the"
    echo "      settings file directly instead."
fi

# Whether the command ran or not, make sure the file says what it has to say.
# (The command's exact behaviour has changed between Plymouth releases; the file
# content is the thing that matters, so that is what we assert.)
if ! grep -q "^Theme=${THEME_NAME}$" "${PLYMOUTH_CONF}" 2> /dev/null; then
    cat > "${PLYMOUTH_CONF}" << EOF
[Daemon]
Theme=${THEME_NAME}
EOF
fi

echo "--- ${PLYMOUTH_CONF} ---"
cat "${PLYMOUTH_CONF}"
echo "---"
aq_file_has "${PLYMOUTH_CONF}" "^Theme=${THEME_NAME}$" \
    "this machine's splash is set to '${THEME_NAME}'"

# The distribution-default file: change only the Theme line and leave every
# other setting Fedora chose (how long to wait before showing anything, how long
# to wait for a graphics card) exactly as it was. Those are tuning decisions we
# have no reason to second-guess.
if [ -r "${PLYMOUTH_DEFAULTS}" ]; then
    if grep -q '^Theme=' "${PLYMOUTH_DEFAULTS}"; then
        sed -i "s|^Theme=.*|Theme=${THEME_NAME}|" "${PLYMOUTH_DEFAULTS}"
    else
        printf '\nTheme=%s\n' "${THEME_NAME}" >> "${PLYMOUTH_DEFAULTS}"
    fi
    echo "--- ${PLYMOUTH_DEFAULTS} ---"
    cat "${PLYMOUTH_DEFAULTS}"
    echo "---"
    aq_file_has "${PLYMOUTH_DEFAULTS}" "^Theme=${THEME_NAME}$" \
        "the fallback default is '${THEME_NAME}' too"
else
    echo "NOTE ${PLYMOUTH_DEFAULTS} does not exist in this image — nothing to change."
fi

echo "Every splash theme installed on this image:"
ls -1 /usr/share/plymouth/themes/

# ------------------------------------------------------------------------------
# Ask for our fonts inside the boot ramdisk
# ------------------------------------------------------------------------------
# The boot ramdisk is deliberately tiny and carries almost no fonts. That only
# matters for the one or two lines of text a boot splash ever draws (the password
# prompt, an update message), and Plymouth falls back to whatever it can find, so
# nothing breaks either way. `install_optional_items` means "put these in if they
# exist" — it can never fail the build.
say "Asking for the AquariusOS fonts in the boot ramdisk"
install -d -m 0755 /usr/lib/dracut/dracut.conf.d
cat > /usr/lib/dracut/dracut.conf.d/99-aquarius-plymouth.conf << 'EOF'
# AquariusOS: try to carry our own faces into the boot ramdisk, so the rare line
# of text on the boot splash is set in Inter rather than in a fallback face.
# "optional" means a missing file is skipped silently rather than failing.
# NOTE the paths are globs. The Sora file is really called "Sora[wght].ttf",
# and square brackets mean "one of these letters" to a glob, so naming it
# literally would match nothing. The folder glob below is the way to say it.
install_optional_items+=" /usr/share/fonts/sora-fonts/* /usr/share/fonts/rsms-inter-fonts/* /usr/share/fonts/jetbrains-mono-fonts/* /etc/fonts/fonts.conf "
EOF
cat /usr/lib/dracut/dracut.conf.d/99-aquarius-plymouth.conf

# ==============================================================================
# 2. THE BOOT MENU
# ==============================================================================
# ------------------------------------------------------------------------------
# WHERE THE WORDS IN THE BOOT MENU ACTUALLY COME FROM
# ------------------------------------------------------------------------------
# This one surprises people, so it is worth writing down properly.
#
# On an ordinary Linux computer the boot menu text comes from a setting called
# GRUB_DISTRIBUTOR in /etc/default/grub, and a program regenerates the menu from
# it.
#
# AquariusOS is not an ordinary Linux computer. It is an image-based system, and
# on those the boot menu is not generated from that file at all. Each entry is a
# small file under /boot/loader/entries/, written fresh every time a new version
# of the OS is installed, and the line a person reads is the `title` line in it.
# That title is seeded from PRETTY_NAME in /etc/os-release.
#
# So THE REAL CONTROL IS PRETTY_NAME, and build_files/70-image-info.sh already
# set it to "AquariusOS". The boot menu will read:
#
#     AquariusOS 44.<date> (ostree:0)
#     AquariusOS 44.<earlier date> (ostree:1)     ← the rollback entry
#
# We set GRUB_DISTRIBUTOR anyway. It costs one line, it is what someone will go
# looking for, and it is what would be used if this machine were ever booted
# through a path that does read it.
say "The boot menu"

echo "PRETTY_NAME (what the boot menu entries are named after):"
grep '^PRETTY_NAME=' /usr/lib/os-release

install -d -m 0755 "$(dirname "${GRUB_DEFAULTS}")"
if [ -f "${GRUB_DEFAULTS}" ] && grep -q '^GRUB_DISTRIBUTOR=' "${GRUB_DEFAULTS}"; then
    sed -i "s|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR=\"${PRETTY_NAME}\"|" "${GRUB_DEFAULTS}"
elif [ -f "${GRUB_DEFAULTS}" ]; then
    printf '\nGRUB_DISTRIBUTOR="%s"\n' "${PRETTY_NAME}" >> "${GRUB_DEFAULTS}"
else
    cat > "${GRUB_DEFAULTS}" << EOF
# AquariusOS. See build_files/80-boot-branding.sh for why this file is mostly
# decorative on an image-based system: the boot menu really takes its wording
# from PRETTY_NAME in /etc/os-release.
GRUB_DISTRIBUTOR="${PRETTY_NAME}"
EOF
fi

echo "--- ${GRUB_DEFAULTS} ---"
cat "${GRUB_DEFAULTS}"
echo "---"
aq_file_has "${GRUB_DEFAULTS}" "^GRUB_DISTRIBUTOR=\"${PRETTY_NAME}\"$" \
    "the boot menu's distributor name is ${PRETTY_NAME}"
aq_file_has /usr/lib/os-release "^PRETTY_NAME=\"${PRETTY_NAME}\"$" \
    "PRETTY_NAME — the name the boot entries are really built from"

# ==============================================================================
# 3. ASK THE KERNEL FOR A GRAPHICAL SPLASH
# ==============================================================================
# Plymouth starts on every boot, but it only draws the GRAPHICAL splash if the
# kernel command line asks for it. Reading Plymouth's own source
# (plymouth_should_show_default_splash in src/main.c), either of two words does
# it — `splash` or `rhgb` — and `quiet` is what stops kernel log messages
# scrolling over the top of it.
#
# We pass all three. `splash` is the modern name, `rhgb` is the older Red Hat
# one that some tooling still looks for, and passing both is free.
#
# /usr/lib/bootc/kargs.d/ is how an image ships kernel options: a machine picks
# them up when it installs or updates from this image, so nobody has to type
# anything.
say "Kernel options for the boot splash"

install -d -m 0755 /usr/lib/bootc/kargs.d
cat > "${KARGS_FILE}" << 'EOF'
# AquariusOS: show the graphical boot splash and keep the kernel quiet while it
# does. `splash` and `rhgb` each independently tell Plymouth to draw the splash
# rather than a wall of white text; `quiet` stops log messages drawing over it.
kargs = ["quiet", "splash", "rhgb"]
EOF
cat "${KARGS_FILE}"
aq_file_has "${KARGS_FILE}" 'kargs = \["quiet", "splash", "rhgb"\]' \
    "the boot options ask for a graphical splash"

echo "Every kernel-option file this image ships:"
ls -l /usr/lib/bootc/kargs.d/
for f in /usr/lib/bootc/kargs.d/*.toml; do
    echo "--- ${f} ---"
    cat "${f}"
done

# ==============================================================================
# 4. THE TEXT BANNERS
# ==============================================================================
# Three files nobody thinks about until they see Fedora's name in one of them:
#
#   /etc/issue      printed above the login prompt on a text console — the
#                   screen you land on if the desktop ever fails to start, which
#                   is exactly when you want to be sure what machine you are on
#   /etc/issue.net  the same thing for a network login
#   /etc/motd       printed AFTER logging in over ssh
#
# and one more, which is a bit different:
#
#   /etc/fedora-release   a one-line plain-text description, kept for the sake
#                         of old programs that grew up reading it
say "The text banners"

# \r is the kernel version and \m is the processor type; both are filled in by
# the login program. Writing "AquariusOS" as literal text rather than using the
# \S shortcut (which expands to PRETTY_NAME) means what this file says is
# obvious to anyone reading it.
cat > /etc/issue << 'EOF'
AquariusOS
Kernel \r on \m

EOF
chmod 0644 /etc/issue

cat > /etc/issue.net << 'EOF'
AquariusOS
EOF
chmod 0644 /etc/issue.net

# Deliberately empty. A message-of-the-day prints on every single ssh login, and
# a machine that greets you by name every time you connect gets old fast. The
# name is already on the screen above the login prompt, in /etc/issue.
: > /etc/motd
chmod 0644 /etc/motd

# ------------------------------------------------------------------------------
# /etc/fedora-release — and why this is safe
# ------------------------------------------------------------------------------
# The `fedora-release` package ships this file containing "Fedora release 44
# (…)", and makes /etc/system-release and /etc/redhat-release symbolic links
# pointing at it. So there is one file to change, and all three follow.
#
# WHAT WE DO NOT DO: remove the package. It carries the repository definitions,
# the version macros that `rpm` and `dnf` read, and the CPE identifier below.
# Removing it would break software installation. We change the human-readable
# sentence inside one of its files and nothing else.
#
# WHAT READS THIS FILE: essentially nothing that matters any more. Modern tools
# — rpm, dnf, bootc, systemd, GNOME — read /etc/os-release instead, which step 7
# already set. `rpm -E %fedora` comes from a macro file, not from here. This file
# is a compatibility surface for old scripts that pattern-match a sentence.
#
# WHAT WE LEAVE ALONE ON PURPOSE: /etc/system-release-cpe. That one is not a
# sentence for a person, it is a machine-readable identifier
# (cpe:/o:fedoraproject:fedora:44) that security scanners use to work out which
# published vulnerabilities apply to this machine. AquariusOS really is Fedora 44
# underneath, so telling a scanner otherwise would make it check the wrong list.
# It stays Fedora, on purpose, and the check in the workflow allows for it.
AQ_FEDORA_VERSION="$(rpm -E %fedora)"
echo "Before:"
for f in /etc/fedora-release /etc/system-release /etc/redhat-release; do
    if [ -L "$f" ]; then
        echo "  ${f} -> $(readlink "$f") : $(cat "$f" 2> /dev/null || echo '(unreadable)')"
    elif [ -e "$f" ]; then
        echo "  ${f} : $(cat "$f")"
    else
        echo "  ${f} does not exist"
    fi
done

echo "${PRETTY_NAME} release ${AQ_FEDORA_VERSION}" > /etc/fedora-release
chmod 0644 /etc/fedora-release

# If either of the other two turns out NOT to be a link to the file we just
# wrote, write it directly as well, rather than assuming.
for f in /etc/system-release /etc/redhat-release; do
    if [ -L "$f" ] && [ "$(readlink -f "$f")" = /etc/fedora-release ]; then
        echo "  ${f} is a link to /etc/fedora-release — it follows automatically"
    else
        echo "  ${f} is NOT a link to /etc/fedora-release — writing it directly"
        echo "${PRETTY_NAME} release ${AQ_FEDORA_VERSION}" > "$f"
        chmod 0644 "$f"
    fi
done

echo "After:"
for f in /etc/issue /etc/issue.net /etc/fedora-release /etc/system-release /etc/redhat-release; do
    echo "--- ${f} ---"
    cat "$f"
done
echo "--- /etc/motd (should be empty) ---"
cat /etc/motd
echo "--- /etc/system-release-cpe (deliberately still Fedora) ---"
cat /etc/system-release-cpe 2> /dev/null || echo "(not present)"
echo "---"

aq_file_has /etc/issue '^AquariusOS$' "the console login banner says AquariusOS"
aq_file_has /etc/issue.net '^AquariusOS$' "the network login banner says AquariusOS"
aq_file_has /etc/fedora-release "^${PRETTY_NAME} release ${AQ_FEDORA_VERSION}$" \
    "the old-style release line says ${PRETTY_NAME}"
if [ -s /etc/motd ]; then
    bad "/etc/motd is not empty — every ssh login would print it"
else
    ok "/etc/motd is empty (deliberate)"
fi

# ==============================================================================
# 4b. THE OTHER THING PRINTED ON THAT SAME SCREEN: "Failed Units: 1"
# ==============================================================================
# Directly under the banner section 4 just wrote, every boot printed this:
#
#     Failed Units: 1
#       systemd-remount-fs.service
#
# Nothing was wrong. Nothing was missing. The machine worked perfectly. But a
# person who reads "Failed" on their screen every morning, forever, reasonably
# assumes something is wrong with their computer — and the next time something
# genuinely IS wrong, that line is already there and means nothing. A warning
# that is always on is not a warning, and section 4 above is about exactly this
# screen, so this belongs here.
#
# ------------------------------------------------------------------------------
# WHY THAT SERVICE COULD NEVER SUCCEED HERE
# ------------------------------------------------------------------------------
# systemd-remount-fs.service exists to re-mount `/` to match /etc/fstab, which
# is a sensible thing to do on an ordinary computer where `/` is a disk.
#
# On AquariusOS `/` is not a disk. It is a read-only, checksummed image with a
# writable layer on top (composefs), assembled in the boot ramdisk before
# systemd starts and already mounted correctly. The kernel REFUSES to re-mount
# an overlay with different options — that is the exact journal message:
#
#     mount: /: fsconfig system call failed: overlay: No changes allowed in reconfigure.
#
# So the service asks a question this kind of computer has no answer to, is told
# no, and reports failure. Every boot.
#
# The fix ships as a drop-in file that arrived at step 5 with the rest of
# system_files/. It adds one line — "skip this on an image-mode boot" — and the
# whole story, including the upstream links, is written inside the file itself.
#
# ⚠️ IT IS CHECKED HERE, NOT AT STEP 2 WHERE THE FILESYSTEMS ARE. Step 2 runs
# BEFORE step 5, so at step 2 this file does not exist yet and the check would
# fail on a perfectly good image. This step runs after step 5, and is about this
# screen anyway.
say "The boot banner has nothing to complain about"

AQ_REMOUNT_DROPIN=/usr/lib/systemd/system/systemd-remount-fs.service.d/10-aquarius-ostree.conf

# Contents, never timestamps — the rule at the top of aq-lib.sh. This reads the
# actual setting out of the actual file in the actual image.
aq_file_has "${AQ_REMOUNT_DROPIN}" \
    '^ConditionPathExists=!/run/ostree-booted$' \
    "the drop-in tells systemd-remount-fs to skip an image-mode boot"

# The service it is a drop-in FOR has to exist, or that folder is just a folder
# with a file in it that nothing will ever read. systemd matches drop-ins to
# units by folder name and says nothing at all when the name is wrong.
if [ -f /usr/lib/systemd/system/systemd-remount-fs.service ]; then
    ok "systemd-remount-fs.service is present, so the drop-in has something to attach to"
else
    bad "systemd-remount-fs.service does not exist — the drop-in folder is misnamed,"
    bad "or systemd renamed the unit. Either way the drop-in does nothing."
fi

# ⚠️ THE MARKER FILE CANNOT BE CHECKED HERE, AND THAT IS NOT A GAP.
# /run/ostree-booted is created by ostree in the boot ramdisk — touch_run_ostree()
# in ostree's switchroot code — on every boot of an image-mode machine, before
# systemd starts. It is what bootc itself uses to ask the same question. This is
# a container being built, not a booted machine, so it is legitimately absent.
# Its presence HERE would mean the condition might skip the service in contexts
# we never intended, so absence is what we assert.
#
# The real proof is the bench console after a reboot. docs/restart/bench-rebase.md
# says exactly what to look for.
if [ -e /run/ostree-booted ]; then
    bad "/run/ostree-booted exists during the BUILD. That is not expected and the"
    bad "condition's behaviour should be re-checked before publishing this image."
else
    ok "/run/ostree-booted is absent at build time, as expected (it is a boot-time marker)"
fi

# systemd is fussy about unit files and says so only at runtime, on somebody's
# machine, in a log they will never read. Ask it here instead. Its verdict is
# advisory — in a container it also warns about units that only exist on a real
# machine — so the output is printed and only a real parse failure is a fault.
if aq_have systemd-analyze; then
    aq_remount_verify="$(systemd-analyze verify systemd-remount-fs.service 2>&1 || true)"
    printf '%s\n' "${aq_remount_verify}" | sed 's/^/  /'

    # ⚠️ AND CHECK THAT IT ACTUALLY LOOKED. Inside a container systemd-analyze
    # often cannot start a manager at all, never reaches the file, prints no
    # complaint — and a check that only looks for complaints then reports a
    # confident OK over a tool that did nothing. A green tick nobody earned is
    # worse than no tick, so say which of the two happened. (This trap cost us
    # the 2026-09-03 build; see the same guard in 75-aquarius-keys.sh.)
    if printf '%s' "${aq_remount_verify}" \
        | grep -Eqi "failed to initialize manager|failed to lookup runtimedirectory"; then
        echo "  note   systemd-analyze could not start inside this container, so it did"
        echo "         not read the drop-in. The content check above is what guards it."
    elif printf '%s' "${aq_remount_verify}" \
        | grep -Eqi "unknown (key|lvalue)|failed to parse"; then
        bad "systemd cannot understand part of the drop-in (see above). A setting it"
        bad "cannot read is a setting that does nothing, silently — and the banner stays."
    else
        ok "systemd read systemd-remount-fs.service with our drop-in and understood it"
    fi
fi

# ==============================================================================
# 5. THE FEDORA ARTWORK OTHER PROGRAMS STILL POINT AT BY NAME
# ==============================================================================
# Some programs do not look a logo up by name — they open a specific file path,
# baked into the program when it was compiled. Fedora's artwork package,
# `fedora-logos`, is what puts pictures at those paths.
#
# Step 5 already does this for the two pictures GNOME's Settings > About page
# opens (see build_files/50-aquarius-desktop.sh — that is where the trick is
# explained at length, and where it was proved necessary on the bench on
# 2026-08-31). This section does the same for the rest of them, so that anything
# on the machine still reaching for one of these paths gets our mark.
#
# ⚠️ THE TWO ABOUT-PAGE FILES ARE DELIBERATELY NOT IN THE LIST BELOW.
# They are fedora_logo_med.png and fedora_whitelogo_med.png, step 5 owns them,
# and they need a specific 279x80 picture. Adding them here — or replacing this
# list with a wildcard like fedora*logo*.png — would overwrite step 5's work
# with a differently-shaped picture and quietly break the About page.
say "Replacing the Fedora artwork that programs open by path"

if ! rpm -q fedora-logos > /dev/null 2>&1; then
    echo "NOTE fedora-logos is not installed in this image, so most of the paths"
    echo "     below will not exist. That is fine — nothing can be pointing at"
    echo "     them either. Each one is reported individually."
else
    echo "fedora-logos is installed: $(rpm -q fedora-logos)"
fi

for f in "${AQ_MARK_PNG}" "${AQ_WIDE_PNG}"; do
    if [ ! -s "$f" ]; then
        echo "AQUARIUS ERROR: ${f} is missing or empty." >&2
        echo "                Step 5 copies the Aquarius pictures in. Without" >&2
        echo "                them there is nothing to replace Fedora's with." >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# replace_logo <destination> <square|wide>
# ------------------------------------------------------------------------------
# "square" gets the mark on its own; "wide" gets the mark with the word beside
# it. Which one a path wants depends on the shape of the space it is drawn in,
# and getting it backwards produces a squashed logo rather than an error, so the
# shape is stated for every path rather than guessed.
#
# A path that does not exist is REPORTED and skipped, never created. Creating a
# file nothing reads would just be litter, and it would hide the day Fedora
# renames one of these.
AQ_REPLACED=0
AQ_ABSENT=0
replace_logo() {
    local dest="$1" shape="$2" src
    case "${shape}" in
        square) src="${AQ_MARK_PNG}" ;;
        wide) src="${AQ_WIDE_PNG}" ;;
        *)
            bad "replace_logo called with shape '${shape}' — must be square or wide"
            return
            ;;
    esac

    if [ ! -e "${dest}" ]; then
        echo "  absent  ${dest}"
        AQ_ABSENT=$((AQ_ABSENT + 1))
        return
    fi

    install -D -m 0644 "${src}" "${dest}"
    if cmp -s "${src}" "${dest}"; then
        echo "  ours    ${dest}  (${shape})"
        AQ_REPLACED=$((AQ_REPLACED + 1))
    else
        bad "${dest} did not take our picture"
    fi
}

# The boot splash art that Fedora's own themes use. `bgrt`, Fedora's default
# theme, does not ship any pictures of its own — it borrows spinner's. So
# replacing spinner's watermark means that even if something ever switched the
# splash back to a Fedora theme, the logo on screen would still be ours.
replace_logo "${SPINNER_DIR}/watermark.png" wide
replace_logo /usr/share/plymouth/themes/charge/watermark.png wide

# The boot-loader stage.
replace_logo /usr/share/pixmaps/bootloader/bootlogo_128.png square
replace_logo /usr/share/pixmaps/bootloader/bootlogo_256.png square

# General-purpose logos. fedora-gdm-logo is the one the login screen would use
# if our own dconf setting (step 5) were ever removed.
replace_logo /usr/share/pixmaps/fedora-logo.png square
replace_logo /usr/share/pixmaps/fedora-logo-sprite.png square
replace_logo /usr/share/pixmaps/fedora-gdm-logo.png wide
replace_logo /usr/share/pixmaps/system-logo-white.png wide

# Icon-theme copies, at every size Fedora ships one.
while IFS= read -r icon; do
    replace_logo "${icon}" square
done < <(find /usr/share/icons -name 'fedora-logo-icon.png' 2> /dev/null | sort)

# The installer's own artwork, IF it is in this image. See
# docs/restart/boot-branding.md — the installer a USB stick actually runs does
# not read these copies, but a machine that has the installer software on it
# would, and replacing them costs nothing.
for p in /usr/share/anaconda/pixmaps/sidebar-logo.png \
    /usr/share/anaconda/pixmaps/anaconda_header.png \
    /usr/share/anaconda/boot/splash.png \
    /usr/share/anaconda/boot/syslinux-splash.png; do
    replace_logo "${p}" wide
done

echo
echo "Replaced ${AQ_REPLACED} Fedora picture(s); ${AQ_ABSENT} of the paths checked are not in this image."
if [ "${AQ_REPLACED}" -eq 0 ]; then
    echo "NOTE nothing was replaced. On an image with no fedora-logos package that"
    echo "     is expected and harmless — the About-page pictures, which are the"
    echo "     ones that actually matter, are step 5's job and are checked there."
fi

# The two About-page pictures must still be step 5's. This is the check that
# catches the mistake the warning above is about.
# ⚠️ Written as a POSITIVE assertion — each path must hold its own specific
# picture — and not as "is this one of ours?". The first version of this check
# asked the latter, and failed the build: the dark About-page picture IS one of
# the two pictures this step hands out, so "it matches one of ours" is true when
# everything is correct. What we actually care about is that the LIGHT page has
# the light picture and the DARK page has the dark one, which is a different
# question with a different answer.
say "Making sure the About page was not trampled"
aq_about_pair() { # aq_about_pair <destination> <the picture it must hold>
    if [ ! -s "$1" ]; then
        bad "$1 is missing — step 5 should have written it"
    elif cmp -s "$2" "$1"; then
        ok "$(basename "$1") still holds $(basename "$2")"
    else
        bad "$(basename "$1") does not hold $(basename "$2") — something overwrote step 5's About-page picture"
    fi
}
aq_about_pair /usr/share/pixmaps/fedora_logo_med.png \
    /usr/share/aquarius/branding/aquarius-about-logo.png
aq_about_pair /usr/share/pixmaps/fedora_whitelogo_med.png \
    /usr/share/aquarius/branding/aquarius-about-logo-white.png

# ==============================================================================
# 6. THE FIRST-LOOK EXTRAS
# ==============================================================================
# Two GNOME programs introduce a new machine to its owner, and both of them say
# Fedora while doing it. Neither is in this image's package list, but GNOME can
# pull them in as an optional extra, so this checks rather than assumes.
say "The GNOME welcome tour and first-run setup"

for pkg in gnome-tour gnome-initial-setup; do
    if rpm -q "${pkg}" > /dev/null 2>&1; then
        echo "${pkg} got pulled in as an optional extra. Removing it —"
        echo "it shows a 'Welcome to Fedora' screen we do not want."
        aq_dnf remove --no-autoremove "${pkg}" || true
    fi
    if rpm -q "${pkg}" > /dev/null 2>&1; then
        bad "${pkg} is still installed — it would show a Fedora welcome screen"
    else
        ok "${pkg} is not installed (correct)"
    fi
done

# ==============================================================================
# 7. REBUILD THE BOOT RAMDISK
# ==============================================================================
# See the long note at the top of this file for why this is the whole point of
# the step and why it has to happen here, after the NVIDIA kernel swap.
say "Rebuilding the boot ramdisk"

if ! aq_have dracut; then
    echo "AQUARIUS ERROR: dracut is not in this image, so the boot ramdisk cannot" >&2
    echo "                be rebuilt — and without rebuilding it the machine" >&2
    echo "                would keep showing Fedora's boot splash forever." >&2
    exit 1
fi

# ⚠️ The kernel version has to be stated explicitly. Inside a container build
# there is no running kernel for dracut to ask about, so left to itself it reads
# the version of the machine doing the BUILD (a GitHub runner) and either fails
# or, worse, builds a ramdisk for the wrong kernel. Red Hat's own bootc
# documentation makes the same point in the same words.
AQ_KVER="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"
AQ_INITRAMFS="/usr/lib/modules/${AQ_KVER}/initramfs.img"
echo "This image's kernel : ${AQ_KVER}"
echo "Ramdisk to rebuild  : ${AQ_INITRAMFS}"

if [ ! -d "/usr/lib/modules/${AQ_KVER}" ]; then
    echo "AQUARIUS ERROR: there is no /usr/lib/modules/${AQ_KVER}." >&2
    echo "                The installed kernel package and the kernel files on" >&2
    echo "                disk do not agree. Folders that ARE there:" >&2
    ls -1 /usr/lib/modules/ >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Write down what the OLD ramdisk contained, before replacing it
# ------------------------------------------------------------------------------
# This is the safety net, and it is the "read the result back" rule applied to
# the single most dangerous file in the image.
#
# Fedora's bare bootable image already ships a working ramdisk. Ours has to be
# at least as capable — in particular it MUST still contain the piece that knows
# how to find and mount an image-based system (`ostree`). A ramdisk missing that
# produces an image that builds perfectly, publishes perfectly, and then stops
# at a black screen on the machine it is installed on.
#
# So: list what the old one had, build the new one, and compare.
AQ_OLD_MODULES=/tmp/aq-initramfs-modules-before.txt
AQ_NEW_MODULES=/tmp/aq-initramfs-modules-after.txt
: > "${AQ_OLD_MODULES}"

# `lsinitrd -m` prints a header and the early-CPIO file listing BEFORE the
# module names. Sorting its whole output gives a "module list" with file
# permissions and 1970 dates in it, which is useless for comparing. Everything
# after the line "dracut modules:" is the real list.
aq_module_list() { # aq_module_list <ramdisk> <output file>
    lsinitrd -m "$1" > /tmp/aq-lsinitrd-raw.txt 2> /dev/null || true
    awk '/^dracut modules:/ { seen = 1; next } seen' /tmp/aq-lsinitrd-raw.txt \
        | tr -d '[:blank:]' | grep -E '^[a-z0-9][a-z0-9._-]*$' | sort -u > "$2" || true
    rm -f /tmp/aq-lsinitrd-raw.txt
}

if [ -s "${AQ_INITRAMFS}" ] && aq_have lsinitrd; then
    echo "The ramdisk Fedora shipped: $(stat -c '%s' "${AQ_INITRAMFS}") bytes"
    aq_module_list "${AQ_INITRAMFS}" "${AQ_OLD_MODULES}"
    echo "It was built from these $(wc -l < "${AQ_OLD_MODULES}") parts:"
    tr '\n' ' ' < "${AQ_OLD_MODULES}"
    echo
else
    echo "NOTE there is no readable ramdisk to compare against yet"
    echo "     (exists: $([ -e "${AQ_INITRAMFS}" ] && echo yes || echo no),"
    echo "      lsinitrd available: $(aq_have lsinitrd && echo yes || echo no))."
fi

# ------------------------------------------------------------------------------
# Build it
# ------------------------------------------------------------------------------
# The flags, and why each one is there. This is the same invocation Universal
# Blue uses in ublue-os/main and Bazzite, which is the best-tested version of
# this operation in the whole Fedora image-building world:
#
#   --force            overwrite the existing file
#   --no-hostonly      build a ramdisk that works on ANY computer. The opposite
#                      (the default) tailors it to the machine doing the build —
#                      which here is a GitHub runner, so the result would be
#                      useless on real hardware.
#   --kver <version>   see the warning above
#   --add ostree       the part that knows how to boot an image-based system.
#                      Not optional. Checked for, and checked again afterwards.
#   --reproducible     build the same bytes from the same input, so an update
#                      that changes nothing downloads nothing
#   -v                 print what it is doing, so the build log is useful
#
# DRACUT_NO_XATTR is Universal Blue's fix for extended file attributes not
# surviving a container build.
export DRACUT_NO_XATTR=1

AQ_DRACUT_ARGS=(--force --no-hostonly --reproducible --kver "${AQ_KVER}" -v)

# ⚠️ ASK FOR THE LIST ONCE, INTO A FILE, AND GREP THE FILE. Do not write
# `dracut --list-modules | grep -q ...`. That form reported "ostree is not
# available" on 2026-09-03 while ostree was plainly in the list, and the reason
# is the trap this repo already has a scar from: `grep -q` stops reading the
# moment it matches, the program on the left of the pipe is killed by SIGPIPE,
# and `pipefail` then reports the whole pipeline as failed — so a SUCCESSFUL
# match looks like a failure. It is the same bug that made every font check lie
# earlier in the same week.
AQ_DRACUT_MODULES=/tmp/aq-dracut-modules.txt
dracut --list-modules > "${AQ_DRACUT_MODULES}" 2> /dev/null || true
echo "Parts dracut can build a ramdisk out of ($(wc -l < "${AQ_DRACUT_MODULES}") of them):"
sort "${AQ_DRACUT_MODULES}" | tr '\n' ' '
echo

# ostree and bootc are the two parts that know how to find and start an
# image-based system. Both are in the ramdisk Fedora ships with this base image,
# so both have to be in ours. A ramdisk without them produces an image that
# installs perfectly, publishes perfectly, and then stops at a black screen.
#
# plymouth is normally pulled in on its own when it is installed, but naming it
# turns "it silently was not there" into a loud failure at build time rather than
# a Fedora splash on a real machine.
for part in ostree bootc plymouth; do
    if grep -qx "${part}" "${AQ_DRACUT_MODULES}"; then
        ok "the '${part}' ramdisk part is available to dracut"
        AQ_DRACUT_ARGS+=(--add "${part}")
    else
        echo "AQUARIUS ERROR: dracut does not know about the '${part}' part." >&2
        case "${part}" in
            ostree | bootc)
                echo "                That is a piece that lets an image-based system" >&2
                echo "                boot at all. Building a ramdisk without it would" >&2
                echo "                produce an image that installs and then will not" >&2
                echo "                start. Stopping instead." >&2
                ;;
            plymouth)
                echo "                So the boot splash could not be put into the" >&2
                echo "                ramdisk at all. Is the plymouth package" >&2
                echo "                installed? Step 2 installs it." >&2
                ;;
        esac
        echo "                The parts it DOES know about are listed above." >&2
        exit 1
    fi
done

echo "Running: dracut ${AQ_DRACUT_ARGS[*]} ${AQ_INITRAMFS}"
dracut "${AQ_DRACUT_ARGS[@]}" "${AQ_INITRAMFS}"

# Universal Blue and Bazzite both do this. A boot ramdisk can end up carrying
# key material from the encryption parts, so it should not be world-readable.
chmod 0600 "${AQ_INITRAMFS}"

if [ ! -s "${AQ_INITRAMFS}" ]; then
    echo "AQUARIUS ERROR: ${AQ_INITRAMFS} is missing or empty after dracut ran." >&2
    exit 1
fi
ok "the new ramdisk is $(stat -c '%s' "${AQ_INITRAMFS}") bytes, mode $(stat -c '%a' "${AQ_INITRAMFS}")"

# ------------------------------------------------------------------------------
# Read the result back
# ------------------------------------------------------------------------------
say "Checking what is actually inside the new boot ramdisk"

if ! aq_have lsinitrd; then
    bad "lsinitrd is not in this image, so the new ramdisk cannot be inspected"
    aq_finish "The boot path"
fi

aq_module_list "${AQ_INITRAMFS}" "${AQ_NEW_MODULES}"
echo "Built from these $(wc -l < "${AQ_NEW_MODULES}") parts:"
tr '\n' ' ' < "${AQ_NEW_MODULES}"
echo

# Nothing the old ramdisk had may go missing. Anything that does is printed by
# name, and the ones that would stop the machine booting are a hard failure.
if [ -s "${AQ_OLD_MODULES}" ]; then
    comm -23 "${AQ_OLD_MODULES}" "${AQ_NEW_MODULES}" > /tmp/aq-initramfs-lost.txt || true
    if [ -s /tmp/aq-initramfs-lost.txt ]; then
        echo "These parts were in Fedora's ramdisk and are NOT in ours:"
        sed 's/^/       /' /tmp/aq-initramfs-lost.txt
        # The must-haves. Losing one of these is the "builds fine, will not
        # boot" failure this whole section exists to prevent.
        for critical in ostree bootc systemd systemd-initrd dracut-systemd \
            btrfs rootfs-block usrmount kernel-modules crypt dm; do
            if grep -qx "${critical}" /tmp/aq-initramfs-lost.txt; then
                bad "the new ramdisk lost '${critical}' — this image would not boot"
            fi
        done
    else
        ok "the new ramdisk kept every part Fedora's had"
    fi
fi

for want in plymouth ostree bootc; do
    if grep -qx "${want}" "${AQ_NEW_MODULES}"; then
        ok "the ramdisk contains the '${want}' part"
    else
        bad "the ramdisk has no '${want}' part"
    fi
done

# And the actual point of the exercise: is OUR splash in there?
say "Is the Aquarius splash really inside the ramdisk?"
lsinitrd "${AQ_INITRAMFS}" 2> /dev/null | grep -i plymouth > /tmp/aq-initrd-plymouth.txt || true
echo "Everything Plymouth-related inside the ramdisk:"
sed 's/^/       /' /tmp/aq-initrd-plymouth.txt || true
echo

if grep -q "plymouth/themes/${THEME_NAME}/" /tmp/aq-initrd-plymouth.txt; then
    ok "the '${THEME_NAME}' splash theme is inside the boot ramdisk"
else
    bad "no plymouth/themes/${THEME_NAME}/ inside the ramdisk — the machine would show Fedora's splash"
fi
if grep -q "plymouth/themes/${THEME_NAME}/watermark.png" /tmp/aq-initrd-plymouth.txt; then
    ok "and so is the mark-and-word picture"
else
    bad "watermark.png is not inside the ramdisk — the splash would have no logo"
fi
if grep -qE "plymouth/themes/${THEME_NAME}/throbber-0001\.png" /tmp/aq-initrd-plymouth.txt; then
    ok "and so are the dots"
else
    bad "throbber-0001.png is not inside the ramdisk — the dots would not appear"
fi

# The settings file inside the ramdisk is what the splash program reads while
# the machine is starting. If it named a Fedora theme, everything above would be
# decoration.
# Two files could carry it — this machine's own setting, or the fallback
# default — and which one Plymouth copies in has changed between releases. Either
# is fine as long as one of them names our theme.
echo "The splash setting baked into the ramdisk:"
: > /tmp/aq-initrd-conf.txt
AQ_CONF_FOUND=0
for c in /etc/plymouth/plymouthd.conf /usr/share/plymouth/plymouthd.defaults; do
    # Files inside a ramdisk are stored without a leading slash. lsinitrd is
    # documented to cope with either spelling; asking both ways costs nothing
    # and removes a guess.
    if { lsinitrd -f "${c}" "${AQ_INITRAMFS}" > /tmp/aq-one-conf.txt 2> /dev/null \
        || lsinitrd -f "${c#/}" "${AQ_INITRAMFS}" > /tmp/aq-one-conf.txt 2> /dev/null; } \
        && [ -s /tmp/aq-one-conf.txt ]; then
        AQ_CONF_FOUND=1
        echo "       --- ${c} (inside the ramdisk) ---"
        sed 's/^/       /' /tmp/aq-one-conf.txt
        cat /tmp/aq-one-conf.txt >> /tmp/aq-initrd-conf.txt
    else
        echo "       (${c} is not inside the ramdisk)"
    fi
done
rm -f /tmp/aq-one-conf.txt

if [ "${AQ_CONF_FOUND}" -eq 0 ]; then
    bad "the ramdisk carries no splash setting at all, so it would fall back to Fedora's default"
elif grep -q "^Theme=${THEME_NAME}$" /tmp/aq-initrd-conf.txt; then
    ok "the setting inside the ramdisk says Theme=${THEME_NAME}"
else
    bad "the setting inside the ramdisk does NOT say Theme=${THEME_NAME}"
fi

# Neither of Fedora's own themes may be the one in there.
for unwanted in bgrt spinner charge; do
    if grep -q "plymouth/themes/${unwanted}/" /tmp/aq-initrd-plymouth.txt; then
        echo "       NOTE Fedora's '${unwanted}' theme files are also inside the ramdisk."
        echo "            That is harmless as long as the setting above names"
        echo "            ${THEME_NAME}, which is what decides."
    fi
done

rm -f /tmp/aq-initrd-plymouth.txt /tmp/aq-initrd-conf.txt \
    /tmp/aq-initramfs-lost.txt "${AQ_OLD_MODULES}" "${AQ_NEW_MODULES}"

aq_finish "The boot path"
