#!/usr/bin/bash
# ==============================================================================
# Stamp a fresh version number onto the Aquarius Plasma Style
# ==============================================================================
# WHAT PROBLEM THIS SOLVES
#
# The glass look of the desktop — the top bar, the dock, every popup — is drawn
# in a handful of SVG files under
#     /usr/share/plasma/desktoptheme/aquarius/
#
# Turning drawings into actual pixels is slow, so Plasma does it once and saves
# the result in a cache file inside each person's home folder. That cache has to
# be thrown away whenever we ship redrawn artwork, or people install an update
# and keep seeing the OLD panels — with nothing on screen to explain why.
#
# Plasma throws the cache away by putting the theme's version number into the
# cache file's NAME:
#
#     ~/.cache/plasma_theme_aquarius_v<version>.kcache
#
# A different version number means a different filename, so Plasma builds a
# fresh cache and deletes every older one it finds. That is the whole mechanism,
# and it is reliable — as long as the version number actually changes.
#
# WHY WE CANNOT JUST TYPE A VERSION NUMBER IN BY HAND
#
# Somebody would forget. Every single time.
#
# And the usual safety net does not work here. Plasma's fallback check is "is the
# theme's file newer than the cache?" — but AquariusOS is built as an image, and
# this style of OS deliberately flattens file timestamps to zero so that two
# builds of the same content are byte-for-byte identical. So the timestamps
# cannot be trusted to tell anybody anything, and the version number is the only
# signal left. Hence: stamp it automatically, on every build, from something that
# is guaranteed to be different every build — the clock.
#
# WHAT IT WRITES
#
# A version like  1.20260830.174231  — the date and the time, in UTC, of the
# moment the image was built. Same shape as the version string image-info.sh
# builds for the OS itself, and it sorts correctly.
#
# WHERE THIS IS CALLED FROM
#
#   build_files/build.sh   (one line, near the end)
#
# It is a separate script rather than lines inside build.sh purely to keep
# build.sh small and to keep this explanation next to the thing it explains.
#
# Background, including the KDE source this was checked against:
#   docs/plasma-style.md
# ==============================================================================

set -euo pipefail

THEME_DIR="/usr/share/plasma/desktoptheme/aquarius"

JSON="${THEME_DIR}/metadata.json"
DESKTOP="${THEME_DIR}/metadata.desktop"

# The placeholder that sits in the repo. If you change it here, change it in both
# files too — the whole point of the check further down is that these agree.
PLACEHOLDER="0.0.0-unstamped"

# ------------------------------------------------------------------------------
# 1. Is the theme actually there?
# ------------------------------------------------------------------------------
# If somebody moves or renames the theme folder, this script would otherwise do
# nothing at all and the build would go green with a broken cache story. Fail
# loudly instead.
test -d "${THEME_DIR}"
test -f "${JSON}"
test -f "${DESKTOP}"

# ------------------------------------------------------------------------------
# 2. Work out the new version number
# ------------------------------------------------------------------------------
# UTC, so the number does not jump around when GitHub's build machines sit in
# different time zones. Seconds are included because two builds can easily happen
# on the same day, and two builds on the same day MUST get different numbers.
AQ_THEME_VERSION="1.$(date -u +%Y%m%d.%H%M%S)"

echo "Plasma style: stamping version ${AQ_THEME_VERSION}"

# ------------------------------------------------------------------------------
# 3. Write it into both files
# ------------------------------------------------------------------------------
# metadata.json is the one KDE reads for the theme's details. metadata.desktop is
# the small old-style file whose mere existence switches the version mechanism on
# — the comment at the top of that file explains why it is not redundant.
#
# `sed -i` edits the file in place. The patterns match the whole line, so a
# hand-edited file with different spacing is a mismatch that the check in step 4
# will catch rather than silently skip.
sed -i "s|\"Version\": \"${PLACEHOLDER}\"|\"Version\": \"${AQ_THEME_VERSION}\"|" "${JSON}"
sed -i "s|^X-KDE-PluginInfo-Version=${PLACEHOLDER}$|X-KDE-PluginInfo-Version=${AQ_THEME_VERSION}|" "${DESKTOP}"

# ------------------------------------------------------------------------------
# 4. Prove it worked
# ------------------------------------------------------------------------------
# A `sed` that matches nothing exits successfully and changes nothing, which is
# exactly the kind of failure that ships. So check the result rather than trust
# the command: the new number must be present, and the placeholder must be gone.
grep -q "\"Version\": \"${AQ_THEME_VERSION}\"" "${JSON}"
grep -q "^X-KDE-PluginInfo-Version=${AQ_THEME_VERSION}$" "${DESKTOP}"

if grep -q "${PLACEHOLDER}" "${JSON}" "${DESKTOP}" ; then
  echo "FAIL: the placeholder '${PLACEHOLDER}' is still in the theme metadata."
  echo "      The version stamp did not fully apply, so people would keep seeing"
  echo "      stale panel artwork after updating. Check the sed patterns above"
  echo "      against the two files."
  exit 1
fi

# And the JSON has to still be valid JSON afterwards — a broken metadata.json
# means Plasma cannot read the theme at all and the desktop falls back to Breeze.
# `python3` is present in the build image; if it ever is not, this check is
# skipped rather than failing the build for the wrong reason.
if command -v python3 >/dev/null 2>&1 ; then
  python3 -c "import json,sys; json.load(open(sys.argv[1]))" "${JSON}"
  echo "Plasma style: metadata.json is still valid JSON."
fi

echo "OK: Plasma style stamped as version ${AQ_THEME_VERSION}."
