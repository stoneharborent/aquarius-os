#!/usr/bin/bash
# ==============================================================================
# STEP 7 — Identity: teaching the OS to call itself AquariusOS
# ==============================================================================
# WHAT THIS IS FOR
#
# Every Linux system keeps a small text file that says what it is called. It
# lives at /usr/lib/os-release, and /etc/os-release is a shortcut pointing at
# it. Almost everything that displays the name of the operating system reads
# that one file: the boot menu, the login screen, `neofetch`, installers,
# support tools, bug reporters.
#
# Because we build on top of Fedora, that file arrives saying "Fedora Linux".
# This script rewrites the handful of lines a human actually reads.
#
# IS THIS SAFE? Yes — because we do it HERE, at build time, inside the image.
# The "never edit os-release" advice you may have read applies to editing a
# running, booted system. Editing the recipe is how every Fedora derivative in
# existence is made, Bazzite included.
#
# ------------------------------------------------------------------------------
# ⚠️ ID STAYS `fedora`, AND THAT IS DELIBERATE
# ------------------------------------------------------------------------------
# os-release has two kinds of field. NAME and PRETTY_NAME are for people.
# ID and VERSION_ID are for programs — and a great many programs use them to
# build a URL: which repository to add, which package to download, which driver
# to install. RPM Fusion's own instructions, NVIDIA's, and every "install this
# on Fedora" script on the internet read ID.
#
# AquariusOS *is* Fedora underneath, exactly and completely. Changing ID to
# something else would break every one of those and gain nothing.
#
# (On the old Bazzite line this line said `ID=bazzite`, because that is what we
# inherited and changing it would have broken Bazzite's own scripts. Same
# reasoning, different answer, because the base changed.)
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

IMAGE_PRETTY_NAME="AquariusOS"
IMAGE_HOSTNAME="aquarius"
IMAGE_VARIANT_ID="aquarius-os"
LOGO_ICON="aquarius-logo"
# The Aquarius blue, written the way a terminal wants it. This is what colours
# the logo in `neofetch` and friends.
LOGO_COLOR="0;38;2;138;180;255"

IMAGE_NAME="${IMAGE_NAME:-aquarius-os-next}"
IMAGE_VENDOR="${IMAGE_VENDOR:-stoneharborent}"
NVIDIA="${NVIDIA:-0}"

# Which edition this is, in words, for the About page.
if [ "${NVIDIA}" = "1" ]; then
    IMAGE_VARIANT="NVIDIA Edition"
else
    IMAGE_VARIANT="Desktop Edition"
fi

HOME_URL="https://github.com/${IMAGE_VENDOR}/aquarius-os"
BUG_REPORT_URL="https://github.com/${IMAGE_VENDOR}/aquarius-os/issues"

FEDORA_VERSION="$(rpm -E %fedora)"
BUILD_DATE="$(date -u +%Y%m%d)"
KERNEL_VERSION="$(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' kernel-core)"

say "Giving this image its name: ${IMAGE_PRETTY_NAME} — ${IMAGE_VARIANT}"

# ------------------------------------------------------------------------------
# A machine-readable note about this image
# ------------------------------------------------------------------------------
# Not part of any standard — it is ours, and it is what our own tools (and a
# person running `cat` on it) read to answer "what exactly am I running?".
# `bootc upgrade` uses the image reference to know where updates come from.
IMAGE_INFO="/usr/share/aquarius/image-info.json"
IMAGE_REF="ostree-unverified-registry:ghcr.io/${IMAGE_VENDOR}/${IMAGE_NAME}"

install -d -m 0755 "$(dirname "${IMAGE_INFO}")"
cat > "${IMAGE_INFO}" << EOF
{
  "image-name": "${IMAGE_NAME}",
  "image-vendor": "${IMAGE_VENDOR}",
  "image-ref": "${IMAGE_REF}",
  "image-tag": "latest",
  "base-image-name": "quay.io/fedora/fedora-bootc:${FEDORA_VERSION}",
  "desktop": "gnome",
  "nvidia": ${NVIDIA},
  "fedora-version": "${FEDORA_VERSION}",
  "kernel-version": "${KERNEL_VERSION}",
  "version": "${FEDORA_VERSION}.${BUILD_DATE}",
  "version-pretty": "${IMAGE_PRETTY_NAME} ${FEDORA_VERSION} (${BUILD_DATE})"
}
EOF
echo "${IMAGE_INFO} is now:"
cat "${IMAGE_INFO}"
python3 -c "import json; json.load(open('${IMAGE_INFO}'))" \
    && ok "image-info.json is valid JSON"

# ------------------------------------------------------------------------------
# os-release
# ------------------------------------------------------------------------------
OS_RELEASE="/usr/lib/os-release"

set_field() {
    local field="$1" value="$2"
    if grep -q "^${field}=" "${OS_RELEASE}"; then
        sed -i "s|^${field}=.*|${field}=${value}|" "${OS_RELEASE}"
    else
        echo "${field}=${value}" >> "${OS_RELEASE}"
    fi
}

set_field NAME "\"${IMAGE_PRETTY_NAME}\""
set_field PRETTY_NAME "\"${IMAGE_PRETTY_NAME}\""
set_field VARIANT "\"${IMAGE_VARIANT}\""
set_field VARIANT_ID "${IMAGE_VARIANT_ID}"
set_field DEFAULT_HOSTNAME "\"${IMAGE_HOSTNAME}\""
set_field LOGO "${LOGO_ICON}"
set_field ANSI_COLOR "\"${LOGO_COLOR}\""
set_field HOME_URL "\"${HOME_URL}\""
set_field BUG_REPORT_URL "\"${BUG_REPORT_URL}\""
set_field DOCUMENTATION_URL "\"${HOME_URL}\""
set_field SUPPORT_URL "\"${HOME_URL}\""

# /etc/os-release must stay a link to the real file. If the two ever become
# separate copies they drift, and half the system reads the stale one.
ETC_OS_RELEASE="/etc/os-release"
if [ -L "${ETC_OS_RELEASE}" ] && [ "$(readlink -f "${ETC_OS_RELEASE}")" = "${OS_RELEASE}" ]; then
    ok "${ETC_OS_RELEASE} is the standard link to ${OS_RELEASE}"
else
    echo "NOTE: ${ETC_OS_RELEASE} was not the standard link. Restoring it."
    ln -snf ../usr/lib/os-release "${ETC_OS_RELEASE}"
fi

# ------------------------------------------------------------------------------
# The hostname
# ------------------------------------------------------------------------------
# DEFAULT_HOSTNAME above is what systemd falls back to when nothing else says
# otherwise. Writing /etc/hostname as well would override anything the person
# chose during installation, which is not ours to do — so we do not.
say "Hostname"
echo "  DEFAULT_HOSTNAME is '${IMAGE_HOSTNAME}' — a machine with no name of its"
echo "  own comes up as 'aquarius'. Anything set at install time still wins."
if [ -s /etc/hostname ]; then
    bad "/etc/hostname exists in the image — that would overrule the user's own choice"
    cat /etc/hostname
else
    ok "no /etc/hostname baked into the image (correct)"
fi

# ------------------------------------------------------------------------------
# Check the identity actually applied
# ------------------------------------------------------------------------------
say "Checking the AquariusOS identity"

echo "--- ${OS_RELEASE} ---"
cat "${OS_RELEASE}"
echo "---"

for f in "${OS_RELEASE}" "${ETC_OS_RELEASE}"; do
    aq_file_has "$f" '^NAME="AquariusOS"$' "${f}: NAME"
    aq_file_has "$f" '^PRETTY_NAME="AquariusOS"$' "${f}: PRETTY_NAME"
    aq_file_has "$f" "^VARIANT=\"${IMAGE_VARIANT}\"$" "${f}: VARIANT"
    aq_file_has "$f" "^VARIANT_ID=${IMAGE_VARIANT_ID}$" "${f}: VARIANT_ID"
    aq_file_has "$f" "^DEFAULT_HOSTNAME=\"${IMAGE_HOSTNAME}\"$" "${f}: DEFAULT_HOSTNAME"
    aq_file_has "$f" "^LOGO=${LOGO_ICON}$" "${f}: LOGO"
    aq_file_has "$f" '^HOME_URL="https://github\.com/' "${f}: HOME_URL is ours"
    aq_file_has "$f" '^ID=fedora$' "${f}: ID stays fedora (deliberate — see the header)"
    aq_file_has "$f" "^VERSION_ID=${FEDORA_VERSION}$" "${f}: VERSION_ID is the Fedora release"
done

# LOGO names an icon, and an icon that is not there makes the About page show a
# blank space with no error.
LOGO_FILE="/usr/share/icons/hicolor/scalable/apps/${LOGO_ICON}.svg"
if [ -s "${LOGO_FILE}" ]; then
    ok "LOGO=${LOGO_ICON} points at a file that exists"
else
    bad "LOGO is '${LOGO_ICON}' but ${LOGO_FILE} does not exist"
fi

aq_finish "AquariusOS identity"
