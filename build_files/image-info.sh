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
#   - KDE's Settings > About This System page
#   - the login screen and the boot menu
#   - `neofetch` / `fastfetch` and friends in the terminal
#   - installers and support tools
#
# Because we build on top of Bazzite, that file arrives already saying
# "Bazzite". This script rewrites the handful of lines that a human actually
# reads so the OS introduces itself as AquariusOS.
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
#                     updater, the rollback helper) check for this. Changing it
#                     is what forced Bazzite to patch grub and /etc/system-release
#                     when they renamed Fedora. Nobody ever sees ID, so there is
#                     nothing to gain and a boot to lose. Leave it alone.
#   ID_LIKE, CPE_NAME Same reasoning — machine-readable, not user-visible.
#   HOME_URL, SUPPORT_URL, DOCUMENTATION_URL, BUG_REPORT_URL
#                     These still point at Bazzite, on purpose. We do not have a
#                     website yet, and Bazzite's documentation genuinely IS the
#                     documentation for most of this OS. Sending people there is
#                     the honest answer. Change these when aquariusos.com exists.
#   BOOTLOADER_NAME, IMAGE_ID, VERSION_CODENAME
#                     Left as Bazzite set them. IMAGE_ID in particular is used to
#                     decide whether a saved hibernation image is still valid, and
#                     changing it means the initramfs has to be rebuilt afterwards.
#                     Not worth it for something no one reads.
#
# The full reasoning is written up in docs/os-release-branding-research.md.
#
# WHEN THIS RUNS
#
# Late — near the end of build_files/build.sh, after packages and fonts are in.
# It is the last coat of paint, so nothing installed afterwards can overwrite it.
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
# If that file is ever renamed, rename it here too or the About page shows a
# blank square.
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

# What we were built on top of — "bazzite" or "bazzite-nvidia-open". We read it
# out of the existing file rather than guessing, so this stays correct for both
# of our images without either of them having to be told which one it is.
# The `|| true` and the fallback mean a missing or surprising file cannot fail
# the whole build over a label.
BASE_IMAGE_NAME="$(sed -n 's/.*"image-name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$IMAGE_INFO" 2>/dev/null | head -n1 || true)"
BASE_IMAGE_NAME="${BASE_IMAGE_NAME:-bazzite}"

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
  "fedora-version": "${FEDORA_VERSION}",
  "version": "${FEDORA_VERSION}.${BUILD_DATE}",
  "version-pretty": "${IMAGE_PRETTY_NAME} ${FEDORA_VERSION} (${BUILD_DATE})"
}
EOF

# ------------------------------------------------------------------------------
# Step 2 — the name everyone actually sees
# ------------------------------------------------------------------------------
# `sed -i` means "edit this file in place". Each line below reads as:
#
#   sed -i "s/^FIELD=.*/FIELD=new value/" /usr/lib/os-release
#          └─ find a line that starts with FIELD= …
#                       └─ … and replace the whole line with this
#
# One line per field, in the same order and style as Bazzite's script, so the
# two can be compared side by side when Bazzite changes something.

OS_RELEASE="/usr/lib/os-release"

# The short name. "AquariusOS".
sed -i "s/^NAME=.*/NAME=\"${IMAGE_PRETTY_NAME}\"/" "$OS_RELEASE"

# The long name — THE one that shows up in KDE's About This System, on the login
# screen, and in neofetch. This is the whole point of the exercise.
sed -i "s/^PRETTY_NAME=.*/PRETTY_NAME=\"${IMAGE_PRETTY_NAME}\"/" "$OS_RELEASE"

# Which flavour of the OS this is.
sed -i "s/^VARIANT_ID=.*/VARIANT_ID=${IMAGE_VARIANT_ID}/" "$OS_RELEASE"

# The default computer name for a fresh install.
sed -i "s/^DEFAULT_HOSTNAME=.*/DEFAULT_HOSTNAME=\"${IMAGE_HOSTNAME}\"/" "$OS_RELEASE"

# The logo and the brand colour.
sed -i "s/^LOGO=.*/LOGO=${LOGO_ICON}/" "$OS_RELEASE"
sed -i "s/^ANSI_COLOR=.*/ANSI_COLOR=\"${LOGO_COLOR}\"/" "$OS_RELEASE"

# ------------------------------------------------------------------------------
# Step 3 — prove it worked
# ------------------------------------------------------------------------------
# If a field we meant to rewrite was missing from the base image, the matching
# `sed` above would have quietly done nothing and the OS would still say
# Bazzite — a silent failure, the worst kind. So we check, and we fail the whole
# build if the name did not take. A red X in the Actions tab is far better than
# shipping an image that calls itself the wrong thing.
grep -q "^PRETTY_NAME=\"${IMAGE_PRETTY_NAME}\"$" "$OS_RELEASE" || {
  echo "ERROR: PRETTY_NAME was not rewritten. Here is what ${OS_RELEASE} says:" >&2
  cat "$OS_RELEASE" >&2
  exit 1
}

# Print the finished file into the build log so the result is visible in the
# Actions output without anyone having to boot the image to check.
echo "=== AquariusOS identity applied. ${OS_RELEASE} is now: ==="
cat "$OS_RELEASE"
