#!/usr/bin/bash
# ==============================================================================
# AquariusOS identity — make the OS say "AquariusOS" instead of "Bazzite"
# ==============================================================================
# WHAT THIS IS FOR
#
# Every Linux system keeps a small text file that says what it is called. It
# lives at /usr/lib/os-release (and /etc/os-release is just a shortcut pointing
# at it). Almost everything that displays the name of the OS reads that file:
#
#   - the login screen and the boot menu
#   - `neofetch` / `fastfetch` and friends in the terminal
#   - Homebrew, installers and support tools
#
# Because we build on top of Bazzite, that file arrives already saying
# "Bazzite". This script rewrites the handful of lines that a human actually
# reads so the OS introduces itself as AquariusOS.
#
# ⚠️ ONE BIG EXCEPTION, LEARNED THE HARD WAY (2026-08-28)
#
# KDE's "Settings > About This System" page does NOT trust os-release. It first
# looks for a small override file at /etc/xdg/kcm-about-distrorc, and ANY field
# that file sets wins over os-release. Bazzite ships one, so on our first
# branded build the About page still proudly said "Bazzite 44 / NVIDIA Edition /
# https://bazzite.gg" even though os-release had said AquariusOS all along.
#
# So this script now writes BOTH files. If you only ever fix one of them, the
# About page is the one that will keep embarrassing you.
# Full story: docs/os-release-branding-research.md (addendum, 2026-08-28).
#
# IS THIS SAFE?
#
# Yes — because we do it HERE, at build time, inside the image. This is exactly
# how Bazzite itself rebrands Fedora, in its own build_files/image-info script:
#   https://github.com/ublue-os/bazzite/blob/main/build_files/image-info
# The "never edit os-release" warning you may have read applies to editing a
# system that is already running and booted. Editing the recipe is normal.
#
# WHAT WE DELIBERATELY DO **NOT** CHANGE  (this is the important part)
#
#   ID=bazzite        The machine-readable id. Bazzite's own tools (ujust, the
#                     updater, the rollback helper) check for this, and so does
#                     our Anaconda installer profile (installer/build.sh reads
#                     ID out of os-release). Changing it is what forced Bazzite
#                     to patch grub and /etc/system-release when they renamed
#                     Fedora. Nobody ever sees ID, so there is nothing to gain
#                     and a boot to lose. Leave it alone.
#   ID_LIKE, CPE_NAME Same reasoning — machine-readable, not user-visible.
#   DOCUMENTATION_URL, SUPPORT_URL
#                     These still point at Bazzite, on purpose. We do not have
#                     docs or a support forum, and Bazzite's documentation
#                     genuinely IS the documentation for most of this OS.
#                     Sending people there is the honest answer. Change these
#                     when aquariusos.com exists.
#   BOOTLOADER_NAME, IMAGE_ID, VERSION_CODENAME
#                     Left as Bazzite set them. IMAGE_ID in particular is used to
#                     decide whether a saved hibernation image is still valid, and
#                     changing it means the initramfs has to be rebuilt afterwards.
#                     Not worth it for something no one reads.
#
# WHEN THIS RUNS
#
# Last — the final line of build_files/build.sh, after packages and fonts are in.
# It is the last coat of paint, so nothing installed afterwards can overwrite it.
# That ordering was already correct and was NOT the cause of the 2026-08-28 bug;
# keep it that way anyway, and add new build steps ABOVE the call to this script.
# ==============================================================================

# Stop immediately if anything fails, and print each command as it runs so the
# GitHub Actions log shows exactly what happened. Same settings as build.sh.
set -euox pipefail

# ------------------------------------------------------------------------------
# The AquariusOS identity, in one place
# ------------------------------------------------------------------------------
# Change a value here and it changes everywhere below.

# The name shown to humans. Two fields use it: NAME (short) and PRETTY_NAME
# (the one Settings and neofetch print). Bazzite sets both to the plain product
# name with no version number attached, and we match that — the version has its
# own separate field in the file, so repeating it in the name is just noise.
IMAGE_PRETTY_NAME="AquariusOS"

# The hostname a fresh install gets if the user does not pick one, i.e. the
# computer will call itself "aquarius" on the network.
IMAGE_HOSTNAME="aquarius"

# A short, lowercase, no-spaces id for THIS flavour of the OS. Not the same as
# ID (which stays "bazzite" — see the note at the top). Both the normal and the
# NVIDIA image use the same value: they are the same OS, just built with
# different graphics drivers.
IMAGE_VARIANT_ID="aquarius-os"

# The logo. This is the *name* of an icon, without the folder and without the
# .svg on the end. The file itself ships with us, copied in by build.sh from:
#   system_files/usr/share/icons/hicolor/scalable/apps/aquarius-logo.svg
# If that file is ever renamed, rename it here too — there is a check further
# down that fails the build rather than let the About page show a blank square.
LOGO_ICON="aquarius-logo"

# The brand colour, for terminals. This looks cryptic but is simple: it is the
# escape code a terminal uses to colour the distro name that fastfetch/neofetch
# print next to the logo. Read it as:
#
#   0        normal text (not bold, not underlined)
#   38;2     "a full 24-bit colour follows, for the foreground"
#   138;180;255   red, green, blue — which is #8AB4FF, our Starlight accent
#                 (branding/tokens.md, the same blue as the KDE accent colour)
#
# The format matches Bazzite's exactly; only the three numbers differ.
LOGO_COLOR="0;38;2;138;180;255"

# Which image this is, and who publishes it. These come in from the build as
# arguments (see the Containerfile and the Justfile) because ONE recipe builds
# TWO images — aquarius-os and aquarius-os-nvidia — and each needs to record its
# own name. The ":-" bits are fallbacks so that a bare `podman build .` with no
# arguments still works and still produces something sensible.
IMAGE_NAME="${IMAGE_NAME:-aquarius-os}"
IMAGE_VENDOR="${IMAGE_VENDOR:-stoneharborent}"

# The "edition" line, printed under the name on KDE's About page. This is the
# one identity field that genuinely differs between our images, so it is worked
# out from the image name rather than typed three times. Bazzite words its own
# the same way ("NVIDIA Edition" / "Desktop Edition"), which is where the phrase
# Royce saw on the About screen came from in the first place.
#
# "Handheld Edition" is the deck image (aquarius-os-deck), which boots into Game
# Mode on a ROG Xbox Ally / Steam Deck class machine. The user only ever reads
# this on the About page in DESKTOP mode — Game Mode has no About page — so it
# says the thing that is useful there: this desktop belongs to a handheld.
#
# The deck line is listed FIRST on purpose. If a bazzite-deck-nvidia variant is
# ever added, its name would match both patterns, and "Handheld" is the more
# useful half of "handheld with an NVIDIA GPU" — a case order change, not a
# rewrite. `case` stops at the first match.
#
# ⚠️ If you add an edition here, add it to the matching allow-list in the
# "Verify OS identity" step of .github/workflows/build.yml too, or the build
# goes red on a name it has never heard of. That is deliberate: an unrecognised
# edition means somebody added an image and only half-wired it.
case "$IMAGE_NAME" in
*-deck*) IMAGE_VARIANT="Handheld Edition" ;;
*-nvidia*) IMAGE_VARIANT="NVIDIA Edition" ;;
*) IMAGE_VARIANT="Desktop Edition" ;;
esac

# Where AquariusOS lives on the internet. There is no website yet, so the GitHub
# repo is the honest answer — and it is definitely better than the old value,
# which pointed the About page at bazzite.gg.
#
# NOTE the repo name is hard-coded as "aquarius-os" and NOT taken from
# $IMAGE_NAME: both images are built out of the one repo, so the NVIDIA build
# would otherwise link to a github.com/…/aquarius-os-nvidia that doesn't exist.
# (The Justfile has the same trap and the same note.)
HOME_URL="https://github.com/${IMAGE_VENDOR}/aquarius-os"

# Where bugs go. This one MUST be ours: an AquariusOS bug filed on Bazzite's
# tracker is noise for them and a dead end for us.
BUG_REPORT_URL="https://github.com/${IMAGE_VENDOR}/aquarius-os/issues"

# ------------------------------------------------------------------------------
# Step 1 — the description file that ublue tools read
# ------------------------------------------------------------------------------
# Separately from os-release, Universal Blue images ship a small machine-readable
# file describing which image is installed. Bazzite's copy is already inside our
# base image and currently claims this machine is running Bazzite, which after
# this script is no longer true. We overwrite it with our own details, keeping
# exactly the same field names so anything that reads it still finds what it
# expects.

IMAGE_INFO="/usr/share/ublue-os/image-info.json"

# The Fedora release number this is built from, e.g. 43. `rpm -E %fedora` is the
# standard way to ask.
FEDORA_VERSION="$(rpm -E %fedora)"

# Today's date, as 20260825. Together with the Fedora version this gives every
# build a version string like "43.20260825".
BUILD_DATE="$(date -u +%Y%m%d)"

# ⚠️ base-image-name IS LOAD-BEARING. READ THIS BEFORE TOUCHING THE LINE THAT READS IT.
#
# This field is not a label. Bazzite's own first-boot scripts read it back out of
# this file at RUNTIME and change what they do based on it. The one that matters
# most is /usr/libexec/bazzite-autologin, which runs before the login screen on
# every boot of the handheld image and decides which session to log into:
#
#     if base-image-name =~ "kinoite"   -> KDE
#     elif base-image-name =~ "silverblue" -> GNOME
#     else  "Unknown base image ... leaving autologin alone"
#
# That last branch is the whole problem. Bazzite fills this field with the plain
# word "kinoite" (KDE) or "silverblue" (GNOME) — the FEDORA edition underneath,
# not the name of the Bazzite image. If we overwrite it with anything else, that
# `else` fires, autologin is skipped, and the handheld boots to a login screen
# instead of Game Mode. No error, no clue, just the wrong OS.
#
# And that is exactly what this script used to do. Until 2026-08-28 the line
# below read `"image-name"` with a leading `.*`, which matched the
# `"base-image-name"` line too and took the first hit — so it copied Bazzite's
# IMAGE name ("bazzite", "bazzite-deck") into a field that is supposed to hold
# the Fedora edition. Nothing on the desktop images reads it, so it sat there
# harmlessly and wrong for months. On the handheld base it would have broken the
# single feature the image exists for. Found by reading Bazzite's runtime scripts
# while adding the deck variant; written up in docs/deck-variant-research.md.
#
# So: read the field by its own name, anchored to the start of the line so it
# cannot be confused with any other key, and pass it through untouched.
BASE_IMAGE_NAME="$(sed -n 's/^[[:space:]]*"base-image-name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$IMAGE_INFO" 2>/dev/null | head -n1 || true)"

# If it is missing or is a word Bazzite's autologin does not recognise, stop the
# build. The alternative is shipping a handheld image that quietly refuses to
# start Game Mode, which is precisely the class of silent failure this repo keeps
# getting bitten by. If Bazzite ever adds a third Fedora edition, this line going
# red is how we find out — add the word here and move on.
case "$BASE_IMAGE_NAME" in
*kinoite* | *silverblue*) : ;;
*)
  echo "ERROR: ${IMAGE_INFO} has base-image-name='${BASE_IMAGE_NAME}'." >&2
  echo "       Bazzite's own boot-time scripts expect 'kinoite' or 'silverblue'" >&2
  echo "       there and skip autologin on anything else — which on the handheld" >&2
  echo "       image means it boots to a login screen instead of Game Mode." >&2
  echo "       The file as it stands:" >&2
  cat "$IMAGE_INFO" >&2
  exit 1
  ;;
esac

# Which Bazzite image we were actually built on top of — "bazzite",
# "bazzite-nvidia-open", "bazzite-deck". This is genuinely useful to have
# recorded, and it is what the old code was trying to capture; it just put it in
# the wrong field. It gets its own key, under a name nothing upstream will ever
# collide with. Extra keys in this file are ignored by everything that reads it.
UPSTREAM_IMAGE_NAME="$(sed -n 's/^[[:space:]]*"image-name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$IMAGE_INFO" 2>/dev/null | head -n1 || true)"
UPSTREAM_IMAGE_NAME="${UPSTREAM_IMAGE_NAME:-unknown}"

# Where this image can be downloaded from. "ostree-unverified-registry" means
# "pull it from a normal container registry, without checking a signature."
# That is the honest description today: we publish signatures, but AquariusOS
# does not yet install a policy telling machines to require them
# (see installer/README.md). Change this to "ostree-image-signed:docker://"
# on the day we do.
IMAGE_REF="ostree-unverified-registry:ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"

# Make sure the folder exists before writing into it (it does on Bazzite, but
# this costs nothing and means the script also works on a plainer base).
mkdir -p "$(dirname "$IMAGE_INFO")"

cat >"$IMAGE_INFO" <<EOF
{
  "image-name": "${IMAGE_NAME}",
  "image-vendor": "${IMAGE_VENDOR}",
  "image-ref": "${IMAGE_REF}",
  "image-tag": "latest",
  "image-branch": "stable",
  "base-image-name": "${BASE_IMAGE_NAME}",
  "aquarius-upstream-image": "${UPSTREAM_IMAGE_NAME}",
  "fedora-version": "${FEDORA_VERSION}",
  "version": "${FEDORA_VERSION}.${BUILD_DATE}",
  "version-pretty": "${IMAGE_PRETTY_NAME} ${FEDORA_VERSION} (${BUILD_DATE})"
}
EOF

# ------------------------------------------------------------------------------
# Step 1b — the OTHER thing Bazzite's boot scripts read out of that file
# ------------------------------------------------------------------------------
# Several of Bazzite's first-boot and session scripts ask "am I a handheld?" and
# they all answer it the same way: by checking whether image-name in the file we
# just rewrote CONTAINS the word "deck". For example, in bazzite-hardware-setup:
#
#     if [[ "$IMAGE_NAME" != *deck* && "$IMAGE_NAME" != *dx* ]]; then
#         rm -f /etc/sddm.conf.d/steamos.conf     # i.e. "you are not a handheld"
#
# We just replaced their image-name with ours. Ours is "aquarius-os-deck", which
# still contains "deck", so every one of those tests keeps giving the right
# answer — but only by virtue of the name we happened to choose. That is too
# important to leave as a happy accident, so it is asserted here.
#
# If the handheld image is ever renamed to something without "deck" in it, this
# fails the build with an explanation instead of shipping a handheld that has
# quietly stopped believing it is one.
case "$IMAGE_NAME" in
*deck*)
  echo "OK: image-name '${IMAGE_NAME}' contains 'deck', so Bazzite's handheld checks still match."
  ;;
*)
  # Not a deck build. Make sure we are not on a handheld BASE while claiming a
  # non-handheld name — that combination is the broken one.
  if [ "${UPSTREAM_IMAGE_NAME}" != "${UPSTREAM_IMAGE_NAME#*deck}" ]; then
    echo "ERROR: this image is built on the handheld base '${UPSTREAM_IMAGE_NAME}'," >&2
    echo "       but is named '${IMAGE_NAME}', which does not contain 'deck'." >&2
    echo "       Bazzite's own boot scripts decide 'am I a handheld?' by looking" >&2
    echo "       for that word in image-name, so this image would boot with its" >&2
    echo "       handheld setup switched off. Rename it, or build it on the" >&2
    echo "       desktop base." >&2
    exit 1
  fi
  ;;
esac

# ------------------------------------------------------------------------------
# Step 2 — the name everyone actually sees
# ------------------------------------------------------------------------------
# os-release is a plain list of NAME=value lines. We change some of them.
#
# Bazzite does this with one bare `sed -i` per field, which has a nasty failure
# mode: if the base image ever stops shipping a field, the matching `sed` finds
# nothing, changes nothing, and says nothing. So we use a small helper instead —
# it replaces the line if the field is there and adds the line if it isn't.

OS_RELEASE="/usr/lib/os-release"

# set_field FIELD VALUE  →  writes `FIELD=VALUE` into os-release.
# Pass VALUE with its quotes included where the file uses them, so that what you
# read here is exactly what ends up in the file.
set_field() {
  local field="$1"
  local value="$2"
  if grep -q "^${field}=" "$OS_RELEASE"; then
    # "|" is the find/replace separator instead of the usual "/", so values that
    # contain slashes (our URLs) don't need any escaping.
    sed -i "s|^${field}=.*|${field}=${value}|" "$OS_RELEASE"
  else
    echo "${field}=${value}" >>"$OS_RELEASE"
  fi
}

# The short name, and the long name — the latter is THE one that shows up on the
# login screen and in neofetch. Quoting matches Bazzite's file exactly.
set_field NAME "\"${IMAGE_PRETTY_NAME}\""
set_field PRETTY_NAME "\"${IMAGE_PRETTY_NAME}\""

# Which flavour of the OS this is. VARIANT is the human-readable one ("NVIDIA
# Edition"); VARIANT_ID is its machine-readable twin. Before 2026-08-28 we set
# only VARIANT_ID and left VARIANT saying "Kinoite", inherited from Fedora.
set_field VARIANT "\"${IMAGE_VARIANT}\""
set_field VARIANT_ID "${IMAGE_VARIANT_ID}"

# The default computer name for a fresh install.
set_field DEFAULT_HOSTNAME "\"${IMAGE_HOSTNAME}\""

# The logo and the brand colour.
set_field LOGO "${LOGO_ICON}"
set_field ANSI_COLOR "\"${LOGO_COLOR}\""

# Our home on the internet, and where to report bugs.
set_field HOME_URL "\"${HOME_URL}\""
set_field BUG_REPORT_URL "\"${BUG_REPORT_URL}\""

# ------------------------------------------------------------------------------
# Step 3 — make sure /etc/os-release and /usr/lib/os-release agree
# ------------------------------------------------------------------------------
# Some programs open /usr/lib/os-release, others open /etc/os-release. On Fedora
# the second is just a signpost pointing at the first (`ln -s ../usr/lib/os-release
# /etc/os-release`, in the fedora-release package), so editing one file is enough
# and everybody sees the same answer.
#
# We do not want to *rely* on that quietly staying true: if some future package
# ever replaced the signpost with a real file, half the system would go on
# calling itself Bazzite and it would take a day to work out why. So we check,
# and put the signpost back if it has gone.

ETC_OS_RELEASE="/etc/os-release"

if [ -L "$ETC_OS_RELEASE" ] && [ "$(readlink -f "$ETC_OS_RELEASE")" = "$OS_RELEASE" ]; then
  echo "OK: ${ETC_OS_RELEASE} is the standard link to ${OS_RELEASE}."
else
  echo "NOTE: ${ETC_OS_RELEASE} was not the standard link. Restoring it."
  ln -snf ../usr/lib/os-release "$ETC_OS_RELEASE"
fi

# ------------------------------------------------------------------------------
# Step 4 — KDE's "About This System" page
# ------------------------------------------------------------------------------
# THIS is the file that was making the About page say Bazzite. KDE reads it
# before os-release and every key in it overrides os-release:
#
#   https://invent.kde.org/plasma/kinfocenter/-/blob/master/kcms/about-distro/src/main.cpp
#     cg.readEntry("Name",     os.name())      ← rc file wins, os-release is only the fallback
#     cg.readEntry("Variant",  os.variant())
#     cg.readEntry("Website",  os.homeUrl())
#     cg.readEntry("LogoPath", os.logo())
#
# Bazzite ships its own copy of this file (system_files/nvidia/kinoite/etc/xdg/
# kcm-about-distrorc), which is why the About page kept saying "Bazzite /
# NVIDIA Edition / https://bazzite.gg" no matter what we did to os-release.
# We overwrite it with ours.
#
# We deliberately do NOT set LogoPath. Leaving it out means KDE falls back to
# os-release's LOGO — which we set a few lines above — so the logo has exactly
# one home in this script instead of two that can drift apart.

KCM_RC="/etc/xdg/kcm-about-distrorc"

# The logo has to actually exist, or the About page shows a blank square and
# nobody notices for a month. Fail the build instead.
LOGO_FILE="/usr/share/icons/hicolor/scalable/apps/${LOGO_ICON}.svg"
if [ ! -f "$LOGO_FILE" ]; then
  echo "ERROR: LOGO is set to '${LOGO_ICON}' but ${LOGO_FILE} does not exist." >&2
  echo "       Either ship that file in system_files/ or change LOGO_ICON here." >&2
  exit 1
fi

mkdir -p "$(dirname "$KCM_RC")"
cat >"$KCM_RC" <<EOF
# Written at build time by build_files/image-info.sh — do not edit by hand.
# KDE's About This System page reads this file BEFORE /etc/os-release, and
# anything set here wins. LogoPath is left out on purpose so the logo comes from
# os-release's LOGO field instead.
[General]
Name=${IMAGE_PRETTY_NAME}
Variant=${IMAGE_VARIANT}
Website=${HOME_URL}
EOF

# ------------------------------------------------------------------------------
# Step 5 — the last hard-coded "bazzite" hostname
# ------------------------------------------------------------------------------
# Bazzite ships a first-boot script, /usr/libexec/bazzite-hardware-setup, with
# this in it:
#
#     if (( $(hostname | wc -m) > 20 )); then
#       hostnamectl set-hostname bazzite
#     fi
#
# In plain English: "if this computer ended up with a silly long name (which can
# happen when the router hands one out before the machine has picked its own),
# rename it to something short." Sensible — except the short name it picks is
# hard-coded, it runs on OUR image, and `hostnamectl set-hostname` writes the
# name to disk permanently. One trip through that branch and the machine calls
# itself "bazzite" forever, no matter what DEFAULT_HOSTNAME says.
#
# So we swap the name it falls back to. The `if [ -f ]` means a future Bazzite
# that renames or drops this script doesn't break our build; the grep afterwards
# means a future Bazzite that *rewords* the line can't silently slip past us.

HW_SETUP="/usr/libexec/bazzite-hardware-setup"

if [ -f "$HW_SETUP" ]; then
  sed -i "s/set-hostname bazzite/set-hostname ${IMAGE_HOSTNAME}/g" "$HW_SETUP"
  if grep -q "set-hostname bazzite" "$HW_SETUP"; then
    echo "ERROR: ${HW_SETUP} still hard-codes the hostname 'bazzite'." >&2
    grep -n "set-hostname" "$HW_SETUP" >&2
    exit 1
  fi
else
  echo "NOTE: ${HW_SETUP} not found — nothing to rebrand. (Did Bazzite rename it?)"
fi

# ------------------------------------------------------------------------------
# Step 6 — prove it worked
# ------------------------------------------------------------------------------
# If a field we meant to rewrite went missing, or KDE's override file did not get
# written, the OS would still say Bazzite — a silent failure, the worst kind. So
# we check every single thing we just claimed to do, and fail the whole build if
# any of it did not take. A red X in the Actions tab is far better than shipping
# an image that calls itself the wrong thing.

# must_contain FILE PATTERN DESCRIPTION — fail loudly if PATTERN isn't in FILE.
BRANDING_OK=1
must_contain() {
  local file="$1" pattern="$2" description="$3"
  if grep -Eq "$pattern" "$file"; then
    echo "  OK   ${description}"
  else
    echo "  FAIL ${description}  (looked for /${pattern}/ in ${file})" >&2
    BRANDING_OK=0
  fi
}

echo "=== Checking the AquariusOS identity ==="

# The two os-release files. /etc/os-release is checked separately from
# /usr/lib/os-release on purpose: they are supposed to be the same file, and
# reading both is how we find out if they ever stop being.
for f in "$OS_RELEASE" "$ETC_OS_RELEASE"; do
  must_contain "$f" '^NAME="AquariusOS"$' "${f}: NAME"
  must_contain "$f" '^PRETTY_NAME="AquariusOS"$' "${f}: PRETTY_NAME"
  must_contain "$f" "^VARIANT=\"${IMAGE_VARIANT}\"$" "${f}: VARIANT"
  must_contain "$f" "^DEFAULT_HOSTNAME=\"${IMAGE_HOSTNAME}\"$" "${f}: DEFAULT_HOSTNAME"
  must_contain "$f" "^LOGO=${LOGO_ICON}$" "${f}: LOGO"
  must_contain "$f" '^HOME_URL="https://github\.com/' "${f}: HOME_URL is ours"
  must_contain "$f" '^ID=bazzite$' "${f}: ID left as bazzite (deliberate)"
done

# KDE's About page.
must_contain "$KCM_RC" '^Name=AquariusOS$' "${KCM_RC}: Name"
must_contain "$KCM_RC" "^Variant=${IMAGE_VARIANT}$" "${KCM_RC}: Variant"
must_contain "$KCM_RC" '^Website=https://github\.com/' "${KCM_RC}: Website"

if [ "$BRANDING_OK" -ne 1 ]; then
  echo "ERROR: the AquariusOS identity did not fully apply. Files as they stand:" >&2
  echo "--- ${OS_RELEASE} ---" >&2
  cat "$OS_RELEASE" >&2
  echo "--- ${KCM_RC} ---" >&2
  cat "$KCM_RC" >&2
  exit 1
fi

# Print the finished files into the build log so the result is visible in the
# Actions output without anyone having to boot the image to check.
echo "=== AquariusOS identity applied. ${OS_RELEASE} is now: ==="
cat "$OS_RELEASE"
echo "=== ${ETC_OS_RELEASE} points at: ==="
ls -l "$ETC_OS_RELEASE"
echo "=== ${KCM_RC} is now: ==="
cat "$KCM_RC"
