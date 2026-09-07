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
#   1. Put the Aquarius boot animation in place and make it the default.
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
# 1. THE BOOT ANIMATION
# ==============================================================================
say "The boot animation"

# ------------------------------------------------------------------------------
# What has to be here, and why each piece matters
# ------------------------------------------------------------------------------
# The theme's own files came in with step 5, from
# system_files/usr/share/plymouth/themes/aquarius/. Since 2026-09-06 the theme is
# not a still picture with a row of dots under it — it is an ANIMATION, played by
# Plymouth's `script` plug-in, and it is made of:
#
#   aquarius.plymouth              names the plug-in and points at the two things
#                                  below. Three lines that matter.
#   aquarius.script                the little program that plays the animation and
#                                  draws the update and disk-password screens.
#   boot-0001 … boot-0066.png      the pour — 2.2 seconds at 30 pictures a second
#   hold.png                       what stays on screen after the pour finishes
#   shutdown-0001 … -0057.png      the wind — 1.9 seconds
#   box.png, bullet.png,           the furniture on the update and password
#   bar-track.png, bar-fill.png    screens
#
# docs/restart/boot-branding.md tells the whole story, including why this
# replaced the two-step theme that was here before.
AQ_THEME_FILE="${THEME_DIR}/${THEME_NAME}.plymouth"
AQ_SCRIPT_FILE="${THEME_DIR}/${THEME_NAME}.script"

# ⚠️ THESE FOUR NUMBERS MUST MATCH branding/pour.mjs,
# branding/render-plymouth-assets.sh AND the theme's own aquarius.script. All
# four say so. This is the only one of the four that can stop a build.
AQ_BOOT_FRAMES=66
AQ_WIND_FRAMES=57
AQ_FRAME_W=288
AQ_FRAME_H=389

for f in "${AQ_THEME_FILE}" "${AQ_SCRIPT_FILE}"; do
    if [ ! -r "$f" ]; then
        echo "AQUARIUS ERROR: $f is missing." >&2
        echo "                Step 5 copies it in from" >&2
        echo "                system_files/usr/share/plymouth/themes/aquarius/." >&2
        echo "                Without it there is no AquariusOS boot animation." >&2
        exit 1
    fi
done

# ------------------------------------------------------------------------------
# The plug-in that plays it
# ------------------------------------------------------------------------------
# The old theme used `two-step`, the plug-in Fedora's own themes use. It can only
# loop a fixed set of pictures in one place; it cannot play something once and
# stop, and it cannot tell starting up from shutting down. The designed animation
# needs both, so the theme moved to the `script` plug-in — which is a separate
# package, and a missing one means a machine that boots to a blank screen where
# the animation should be.
say "The scripting plug-in the animation needs"

if ! rpm -q plymouth-plugin-script > /dev/null 2>&1; then
    echo "AQUARIUS ERROR: plymouth-plugin-script is not installed, so nothing in" >&2
    echo "                this image can play the boot animation. It is asked" >&2
    echo "                for in build_files/20-hardware-media.sh." >&2
    echo "                Plymouth packages that ARE installed:" >&2
    rpm -qa 'plymouth*' | sort >&2
    exit 1
fi
ok "plymouth-plugin-script $(rpm -q --queryformat '%{VERSION}-%{RELEASE}' plymouth-plugin-script)"

echo "This image's Plymouth: $(rpm -q --queryformat '%{VERSION}-%{RELEASE}' plymouth)"
echo "What plymouth-plugin-script ships:"
rpm -ql plymouth-plugin-script | sed 's/^/  /'

AQ_SCRIPT_SO="$(rpm -ql plymouth-plugin-script | grep -E '/script\.so$' | head -n1 || true)"
if [ -z "${AQ_SCRIPT_SO}" ] || [ ! -r "${AQ_SCRIPT_SO}" ]; then
    bad "the script plug-in's own file (script.so) is not where the package says it is"
else
    ok "the plug-in itself is at ${AQ_SCRIPT_SO}"
fi

# ------------------------------------------------------------------------------
# ⚠️ EVERY PLYMOUTH INSTRUCTION THE THEME USES REALLY EXISTS IN THIS PLYMOUTH
# ------------------------------------------------------------------------------
# This is the check that would have caught the mistake this whole rewrite was
# most likely to make.
#
# aquarius.script talks to Plymouth by name — `Plymouth.SetRefreshFunction`,
# `Plymouth.SetSystemUpdateFunction`, and so on. Those names have changed between
# Plymouth releases, and a name that does not exist FAILS SILENTLY: the theme
# loads, the screen appears, and that one thing simply never happens. Nothing is
# printed anywhere.
#
# So rather than trusting the documentation, this reads the names out of the
# plug-in's own compiled file — they are stored in it as plain text, because that
# is how it registers them — and checks that every name the theme uses is one of
# them.
say "Every Plymouth instruction the theme uses exists in THIS Plymouth"

# ⚠️ READ THE NAMES OUT OF THE BINARY WITH `grep -a`, NOT WITH `strings`.
# `strings` comes from the binutils package, which this image does not
# necessarily install — and a check that quietly does not run is worse than no
# check at all, because it prints nothing and everybody assumes it passed.
# `grep -a` is in every image there is and answers the same question.
if [ -r "${AQ_SCRIPT_SO}" ]; then
    # Pull `Plymouth.Something` out of the theme, ignoring comment lines.
    grep -vE '^[[:space:]]*#' "${AQ_SCRIPT_FILE}" \
        | grep -oE 'Plymouth\.[A-Za-z]+' | sed 's/^Plymouth\.//' | sort -u \
        > /tmp/aq-theme-uses.txt

    AQ_USES="$(wc -l < /tmp/aq-theme-uses.txt | tr -d ' ')"
    echo "The theme uses ${AQ_USES} Plymouth instructions:"
    sed 's/^/  /' /tmp/aq-theme-uses.txt

    if [ "${AQ_USES}" -lt 5 ]; then
        # Fewer than five means the search above found almost nothing, which
        # means it is broken rather than that the theme is simple. Say so
        # instead of reporting a confident pass over a check that did nothing.
        bad "only ${AQ_USES} Plymouth instructions found in the theme — that is too"
        bad "few to be true, so the search that looks for them is broken."
    else
        aq_unknown=0
        while IFS= read -r name; do
            if grep -a -q "${name}" "${AQ_SCRIPT_SO}"; then
                ok "Plymouth.${name} exists in this Plymouth"
            else
                bad "Plymouth.${name} does NOT exist in this Plymouth. That"
                bad "instruction would do nothing at all, silently. The name has"
                bad "probably been renamed in this release — check the plug-in's"
                bad "own source before changing the theme."
                aq_unknown=1
            fi
        done < /tmp/aq-theme-uses.txt

        if [ "${aq_unknown}" -eq 0 ]; then
            ok "all ${AQ_USES} Plymouth instructions the boot animation uses are real"
        fi
    fi
    rm -f /tmp/aq-theme-uses.txt
else
    bad "the script plug-in's own file could not be read, so the instruction names"
    bad "the theme uses could not be checked against it."
fi

# ------------------------------------------------------------------------------
# The theme file says what it has to say
# ------------------------------------------------------------------------------
say "The theme file"
echo "--- ${AQ_THEME_FILE} (settings only, comments stripped) ---"
grep -vE '^[[:space:]]*(#|$)' "${AQ_THEME_FILE}" || true
echo "---"

aq_file_has "${AQ_THEME_FILE}" '^ModuleName=script$' \
    "the theme is played by the script plug-in"
aq_file_has "${AQ_THEME_FILE}" "^ScriptFile=${AQ_SCRIPT_FILE}$" \
    "the theme points at the script that is really installed"
aq_file_has "${AQ_THEME_FILE}" "^ImageDir=${THEME_DIR}$" \
    "the theme looks for its pictures in the folder they are really in"

# The old plug-in's settings must all be gone. Leaving one behind would be
# harmless in effect — the script plug-in ignores them — and confusing forever,
# because a person reading the file would believe a setting that does nothing.
if grep -qE '^(ModuleName=two-step|\[two-step\]|UseFirmwareBackground=|ProgressBar[A-Za-z]*=|Watermark[A-Za-z]*=|UseAnimation=)' "${AQ_THEME_FILE}"; then
    bad "the theme file still carries settings from the old two-step boot screen:"
    grep -nE '^(ModuleName=two-step|\[two-step\]|UseFirmwareBackground=|ProgressBar[A-Za-z]*=|Watermark[A-Za-z]*=|UseAnimation=)' "${AQ_THEME_FILE}" >&2
else
    ok "no left-over settings from the old two-step boot screen"
fi

# ------------------------------------------------------------------------------
# The script says what it has to say
# ------------------------------------------------------------------------------
# The one colour that is set by the script rather than baked into a picture: the
# Midnight ground the whole screen is painted with. It is written as the three
# 0-to-255 parts of #0B1220, put through the script's own `channel` helper.
say "The boot screen's own script"

aq_file_has "${AQ_SCRIPT_FILE}" '^BG_RED    = channel\(11\);   BG_GREEN    = channel\(18\);   BG_BLUE    = channel\(32\);$' \
    "the ground is Midnight bg (#0B1220 = 11, 18, 32)"
aq_file_has "${AQ_SCRIPT_FILE}" '^BOOT_FRAMES  = '"${AQ_BOOT_FRAMES}"';' \
    "the script plays all ${AQ_BOOT_FRAMES} frames of the pour"
aq_file_has "${AQ_SCRIPT_FILE}" '^WIND_FRAMES  = '"${AQ_WIND_FRAMES}"';' \
    "the script plays all ${AQ_WIND_FRAMES} frames of the wind"
aq_file_has "${AQ_SCRIPT_FILE}" 'Plymouth.SetDisplayPasswordFunction' \
    "the script draws a disk-password box (the piece two-step used to give us free)"
aq_file_has "${AQ_SCRIPT_FILE}" 'Plymouth.SetSystemUpdateFunction' \
    "the script draws the 'installing updates' screen"

# A retired colour must not be SET anywhere in the script. Comment lines are
# skipped: the file's own notes name the old palette to explain what replaced it,
# which is the point of writing it down.
if grep -vE '^[[:space:]]*#' "${AQ_SCRIPT_FILE}" \
    | grep -Eqi '(8AB4FF|5B4BE0|E6DDB8|06070C)'; then
    bad "the boot script still names a retired Starlight colour"
    grep -nEi '(8AB4FF|5B4BE0|E6DDB8|06070C)' "${AQ_SCRIPT_FILE}" | grep -vE ':[[:space:]]*#' >&2
else
    ok "no retired Starlight colour in the boot script"
fi

# ------------------------------------------------------------------------------
# The pictures — counted, and their sizes read back out of the files
# ------------------------------------------------------------------------------
# A picture of the wrong size is not a crash. It is a boot screen that looks
# slightly wrong, which nobody notices. A MISSING one is worse: the script counts
# up from 0001 and a gap is a frame that silently never appears. So both are read
# out of the actual files rather than assumed.
#
# The sizes come out of each PNG's own header — bytes 17 to 24 of the file, which
# is where PNG stores its width and height — so this needs no image library on the
# build machine.
say "The animation's pictures"

if python3 - "${THEME_DIR}" "${AQ_BOOT_FRAMES}" "${AQ_WIND_FRAMES}" \
    "${AQ_FRAME_W}" "${AQ_FRAME_H}" << 'PY'; then
import glob
import os
import struct
import sys

theme_dir = sys.argv[1]
boot_frames, wind_frames, frame_w, frame_h = (int(a) for a in sys.argv[2:6])
faults = []


def size(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        faults.append(f"{path} is not a PNG file at all")
        return None
    return struct.unpack(">II", data[16:24])


def check_run(prefix, count):
    found = sorted(glob.glob(os.path.join(theme_dir, f"{prefix}-*.png")))
    if len(found) != count:
        faults.append(f"{len(found)} {prefix} frames in the image, expected {count}")
        return
    for i, path in enumerate(found, start=1):
        want = f"{prefix}-{i:04d}.png"
        if os.path.basename(path) != want:
            faults.append(f"expected {want}, found {os.path.basename(path)} — the "
                          "frames must be numbered with no gaps")
            return
        got = size(path)
        if got and got != (frame_w, frame_h):
            faults.append(f"{want} is {got[0]}x{got[1]}, expected {frame_w}x{frame_h}")
            return
    print(f"  OK   {count} {prefix} frames, all {frame_w}x{frame_h}")


check_run("boot", boot_frames)
check_run("shutdown", wind_frames)

# The hold has to be the pour's LAST frame, exactly. A hold that differs by one
# pixel is a visible flicker at the moment the animation stops.
last = os.path.join(theme_dir, f"boot-{boot_frames:04d}.png")
hold = os.path.join(theme_dir, "hold.png")
if not os.path.exists(hold):
    faults.append("hold.png is missing — there would be nothing on screen after the pour")
elif open(hold, "rb").read() != open(last, "rb").read():
    faults.append(f"hold.png is not byte-for-byte boot-{boot_frames:04d}.png — the "
                  "animation would flicker when it stops")
else:
    print(f"  OK   hold.png is byte-for-byte boot-{boot_frames:04d}.png (no flicker at the end)")

# The furniture on the update and disk-password screens.
for name, want_w, want_h, what in [
    ("box.png", 420, 48, "the disk-password box"),
    ("bullet.png", 18, 18, "one typed dot"),
    ("bar-track.png", 320, 3, "the empty progress bar"),
    ("bar-fill.png", 320, 3, "the blue that fills it"),
]:
    path = os.path.join(theme_dir, name)
    if not os.path.exists(path):
        faults.append(f"{name} is missing — {what} would not be drawn")
        continue
    got = size(path)
    if got and got != (want_w, want_h):
        faults.append(f"{name} is {got[0]}x{got[1]}, expected {want_w}x{want_h}")
    else:
        print(f"  OK   {name} is {want_w}x{want_h} ({what})")

# Nothing from the old two-step boot screen may still be here. It would not be
# drawn, but it would be carried into the boot ramdisk, and the ramdisk is the
# one file in this image whose size is worth caring about.
for stale in sorted(glob.glob(os.path.join(theme_dir, "throbber-*.png"))
                    + glob.glob(os.path.join(theme_dir, "watermark.png"))):
    faults.append(f"{stale} is left over from the old boot screen and should be deleted")

for fault in faults:
    print(f"  FAIL {fault}")
sys.exit(1 if faults else 0)
PY
    aq_pictures_ok=1
else
    aq_pictures_ok=0
fi

if [ "${aq_pictures_ok}" -eq 1 ]; then
    ok "every picture the boot animation needs is present and the right size"
else
    bad "the boot animation's pictures are not what the theme expects (see above)"
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
# The boot ramdisk is deliberately tiny and carries almost no fonts.
#
# ⚠️ THAT MATTERS MORE THAN IT USED TO. Until 2026-09-06 the boot screen was a
# picture with a row of dots under it and text was a rarity. Now it draws real
# headings — "Installing updates", "Unlock the disk" — and if a font file is not
# in the ramdisk, Plymouth quietly falls back to whatever face it can find and
# nobody notices until they look at a photograph of the screen.
#
# So the three faces are asked for here, and the read-back after the ramdisk is
# rebuilt CHECKS THAT THEY ARRIVED rather than hoping. (The word "AquariusOS"
# under the mark is not affected either way: it is drawn into the animation's
# pictures as a shape on the Mac, so it can never fall back.)
#
# `install_optional_items` means "put these in if they exist" — it can never
# fail the build, which is why the check afterwards is the thing that guards it.
say "Asking for the AquariusOS fonts in the boot ramdisk"
install -d -m 0755 /usr/lib/dracut/dracut.conf.d
cat > /usr/lib/dracut/dracut.conf.d/99-aquarius-plymouth.conf << 'EOF'
# AquariusOS: carry our own faces into the boot ramdisk, so the headings and
# prompts on the boot screen are set in Sora, Inter and JetBrains Mono rather
# than in whatever face Plymouth can find to fall back to.
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
# The login screen is held back until the pour has played (bench, 2026-09-07:
# a five-second boot and a television that took two of them to wake). One
# oneshot unit, ordered before the login screen, switched on from /usr.
AQ_HOLD_UNIT="/usr/lib/systemd/system/aquarius-boot-hold.service"
AQ_HOLD_LINK="/usr/lib/systemd/system/graphical.target.wants/aquarius-boot-hold.service"
say "The login screen waits for the pour"
aq_file_has "${AQ_HOLD_UNIT}" '^Before=display-manager.service$' \
    "aquarius-boot-hold finishes before the login screen starts"
aq_file_has "${AQ_HOLD_UNIT}" '^After=plymouth-start.service$' \
    "and it does not start counting until the boot screen is up"
aq_file_has "${AQ_HOLD_UNIT}" '^ConditionKernelCommandLine=splash$' \
    "and it only runs when a boot screen was asked for"
aq_file_has "${AQ_HOLD_UNIT}" '^Type=oneshot$' \
    "it is a oneshot, which is what gives Before= something to wait for"
if [ -L "${AQ_HOLD_LINK}" ]; then
    ok "it is switched on ($(readlink "${AQ_HOLD_LINK}"))"
else
    bad "${AQ_HOLD_LINK} is missing, so the hold is installed and would never run"
fi
aq_file_has "${THEME_DIR}/aquarius.script" '^BOOT_DELAY *= *45;' \
    "the pour starts 1.5 s late at boot, so a slow screen is awake for it"

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
# if our own dconf setting (step 5) were ever removed. fedora-logo-small.png is
# the little square copy some menus and dialogs open by that exact path.
replace_logo /usr/share/pixmaps/fedora-logo.png square
replace_logo /usr/share/pixmaps/fedora-logo-small.png square
replace_logo /usr/share/pixmaps/fedora-logo-sprite.png square
replace_logo /usr/share/pixmaps/fedora-gdm-logo.png wide
replace_logo /usr/share/pixmaps/system-logo-white.png wide

# Icon-theme copies, at every size Fedora ships one.
while IFS= read -r icon; do
    replace_logo "${icon}" square
done < <(find /usr/share/icons -name 'fedora-logo-icon.png' 2> /dev/null | sort)

# ------------------------------------------------------------------------------
# The installer (Anaconda) artwork, IF it is in this image
# ------------------------------------------------------------------------------
# ⚠️ READ docs/restart/installer.md BEFORE CHANGING THIS. What we replace here
# does NOT reach the picture on the USB-stick installer's own pages. The ISO
# builder (osbuild image-builder, `anaconda-iso`) assembles a SEPARATE little
# system for the installer to run in, and it fills it by reading this image's
# repository files and DOWNLOADING fedora-logos fresh from Fedora — it does not
# copy the files we replace below. So the stick's installer keeps Fedora's
# picture no matter what we put here. That is a boundary of the tool, written up
# with the two ways out (an `aquarius-logos` package, or the `bootc-installer`
# image type) in docs/restart/installer.md.
#
# What this DOES cover is the other way somebody meets Anaconda: running it on a
# machine that is already up (it is in this image's package set). Cheap, real,
# and worth getting right — and it is also the artwork an `aquarius-logos`
# package would reuse, so completeness here is groundwork, not just polish.
#
# ⚠️ WHERE THE LOGO ACTUALLY LIVES CHANGED. Older Fedora kept one
# `sidebar-logo.png` at `/usr/share/anaconda/pixmaps/`. Fedora 44's fedora-logos
# does NOT: it ships a `sidebar-logo.png` (and a `topbar-bg.png`) inside a
# per-product folder — `/usr/share/anaconda/{atomic,cloud,server,silverblue,
# workstation}/` — and there is nothing at the old flat path. The previous
# version of this loop named only the old flat path, so it replaced nothing on
# this base and the installer's sidebar stayed Fedora's even after boot. We now
# find every `sidebar-logo.png` under /usr/share/anaconda/ instead of guessing
# one path. `topbar-bg.png` is a plain background strip with no logo on it, so it
# is deliberately left alone — replacing a background with a logo looks wrong.
#
# `anaconda_header.png` (the old top banner) and the two boot splashes are still
# at fixed paths, so they stay named directly.
say "The installer's own artwork (covers Anaconda run after boot; see installer.md)"

replace_logo /usr/share/anaconda/pixmaps/anaconda_header.png wide
replace_logo /usr/share/anaconda/boot/splash.png wide
replace_logo /usr/share/anaconda/boot/syslinux-splash.png wide

# Every per-product sidebar logo fedora-logos ships, whichever folders exist.
AQ_ANACONDA_SIDEBARS=0
while IFS= read -r sb; do
    replace_logo "${sb}" wide
    AQ_ANACONDA_SIDEBARS=$((AQ_ANACONDA_SIDEBARS + 1))
done < <(find /usr/share/anaconda -type f -name 'sidebar-logo.png' 2> /dev/null | sort)
if [ "${AQ_ANACONDA_SIDEBARS}" -eq 0 ]; then
    echo "  note   no per-product sidebar-logo.png found under /usr/share/anaconda"
    echo "         (expected only if fedora-logos is not installed — reported above)"
else
    echo "  found ${AQ_ANACONDA_SIDEBARS} per-product Anaconda sidebar logo(s)"
fi

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

# And the actual point of the exercise: is OUR boot animation in there?
say "Is the Aquarius boot animation really inside the ramdisk?"
lsinitrd "${AQ_INITRAMFS}" 2> /dev/null | grep -i plymouth > /tmp/aq-initrd-plymouth.txt || true
echo "Everything Plymouth-related inside the ramdisk:"
sed 's/^/       /' /tmp/aq-initrd-plymouth.txt || true
echo

# Six things have to be in there, and each one is a different way for the boot
# animation to be broken on a real machine while every file on disk looks fine.
aq_in_ramdisk() {   # aq_in_ramdisk <path fragment> <what it is> <what breaks without it>
    if grep -qF "$1" /tmp/aq-initrd-plymouth.txt; then
        ok "in the ramdisk: $2"
    else
        bad "$1 is NOT inside the ramdisk — $3"
    fi
}

aq_in_ramdisk "plymouth/themes/${THEME_NAME}/" \
    "the '${THEME_NAME}' theme folder" \
    "the machine would show Fedora's boot screen"
aq_in_ramdisk "plymouth/themes/${THEME_NAME}/${THEME_NAME}.plymouth" \
    "the theme file" \
    "there would be nothing naming the script plug-in"
aq_in_ramdisk "plymouth/themes/${THEME_NAME}/${THEME_NAME}.script" \
    "the script that plays the animation" \
    "the screen would be blank — the theme file points at a file that is not there"
aq_in_ramdisk "plymouth/themes/${THEME_NAME}/boot-0001.png" \
    "the first frame of the pour" \
    "the animation would have no pictures to play"
aq_in_ramdisk "plymouth/themes/${THEME_NAME}/hold.png" \
    "the hold" \
    "the screen would go blank the moment the pour finished"
aq_in_ramdisk "plymouth/themes/${THEME_NAME}/shutdown-0001.png" \
    "the first frame of the wind" \
    "shutting down would show nothing"
aq_in_ramdisk "plymouth/themes/${THEME_NAME}/box.png" \
    "the disk-password box" \
    "a machine with an encrypted disk would appear to hang at a blank screen"

# ⚠️ AND THE PLUG-IN ITSELF. This is the one that would be easiest to miss: the
# theme can be in the ramdisk in full, and if the plug-in that PLAYS it was not
# carried in with it the screen is simply black. dracut's plymouth part is what
# puts it there, and it goes on the strength of what is installed on disk.
if grep -qE 'plymouth/(plugins/)?script\.so' /tmp/aq-initrd-plymouth.txt; then
    ok "in the ramdisk: the script plug-in that plays the animation"
else
    bad "the script plug-in (script.so) is NOT inside the ramdisk. Every picture"
    bad "could be in there and the boot screen would still be black, because"
    bad "nothing in the ramdisk would know how to play them."
fi

# ------------------------------------------------------------------------------
# The three faces the boot screen sets its words in
# ------------------------------------------------------------------------------
# Asked for further up, in the dracut settings file. `install_optional_items`
# cannot fail, so this is the only thing standing between a missing font and a
# boot screen whose headings are set in something else entirely.
say "Are the AquariusOS fonts inside the ramdisk?"
lsinitrd "${AQ_INITRAMFS}" 2> /dev/null | grep -iE 'fonts/(sora|rsms-inter|jetbrains)' \
    > /tmp/aq-initrd-fonts.txt || true
echo "Font files inside the ramdisk:"
sed 's/^/       /' /tmp/aq-initrd-fonts.txt || true
for aq_face in "sora-fonts:Sora, for the headings" \
               "rsms-inter-fonts:Inter, for the lines of explanation" \
               "jetbrains-mono-fonts:JetBrains Mono, for the percentage"; do
    aq_dir="${aq_face%%:*}"
    aq_what="${aq_face##*:}"
    if grep -q "fonts/${aq_dir}/" /tmp/aq-initrd-fonts.txt; then
        ok "in the ramdisk: ${aq_what}"
    else
        bad "no ${aq_dir} inside the ramdisk — ${aq_what%%,*} would fall back to"
        bad "another face on the boot screen, silently."
    fi
done
rm -f /tmp/aq-initrd-fonts.txt

# The old boot screen's pictures must not still be riding along. They are dead
# weight in the single largest file in the image.
for aq_stale in watermark.png throbber-0001.png; do
    if grep -qF "plymouth/themes/${THEME_NAME}/${aq_stale}" /tmp/aq-initrd-plymouth.txt; then
        bad "${aq_stale} from the old boot screen is still inside the ramdisk"
    fi
done

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
