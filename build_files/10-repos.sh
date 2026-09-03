#!/usr/bin/bash
# ==============================================================================
# STEP 1 — Where AquariusOS gets its software from
# ==============================================================================
# WHAT A "REPOSITORY" IS
#
# Linux does not install programs by downloading them from websites. Every
# program comes from a repository: a signed, versioned catalogue that the
# package manager knows how to search. Fedora ships with its own repositories
# already configured. This step adds one more family.
#
# WHY WE NEED RPM FUSION
#
# Fedora is made by Red Hat, an American company, and it will not ship software
# that is patent-encumbered in the United States. In practice that means Fedora
# ships a version of ffmpeg with the H.264, H.265 and AAC parts removed, and a
# graphics driver that cannot hardware-decode those formats either.
#
# For a general-purpose computer that is a mild annoyance. For a video editing
# machine it is fatal: H.264 and H.265 are what every camera and every phone on
# earth records, and AAC is the audio inside all of it. An AquariusOS that
# cannot open an MP4 is not an operating system for creators.
#
# RPM Fusion is the long-established community repository that packages those
# pieces for Fedora. It is not a fringe thing — it is what Fedora's own
# documentation points people at, and it is what every creator-oriented Fedora
# spin uses. Two halves:
#
#   free      open-source software Fedora will not ship for patent reasons
#             (the full ffmpeg, the freeworld graphics drivers, x264, x265)
#   nonfree   software that is not open source at all
#             (the Fraunhofer AAC encoder, the NVIDIA driver)
#
# We enable both. The actual installing happens in the next step.
#
# ⚠️ LEGAL NOTE, STATED PLAINLY: shipping these codecs in an image we publish is
# what Fedora itself declines to do. It is what Bazzite, Nobara, Ultramarine and
# every other Fedora-derived creator distribution also do, and RPM Fusion is
# hosted for exactly this purpose. It is a decision, not an oversight.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

FEDORA="$(rpm -E %fedora)"

say "Building AquariusOS on Fedora ${FEDORA}"
cat /usr/lib/os-release
echo "Kernel in this image: $(rpm -q --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}\n' kernel-core 2> /dev/null || echo '(none — that would be very wrong)')"

# ------------------------------------------------------------------------------
# Add RPM Fusion
# ------------------------------------------------------------------------------
# These two packages contain nothing but the repository definition and the key
# used to verify everything that comes from it. Installing them is what makes
# the catalogue searchable; it installs no actual software.
say "Adding the RPM Fusion repositories"
aq_dnf install \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${FEDORA}.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${FEDORA}.noarch.rpm"

# ------------------------------------------------------------------------------
# Check they are actually there and switched on
# ------------------------------------------------------------------------------
# `dnf install` of a URL can succeed and still leave a repository disabled if
# the package changes shape upstream. The whole media layer depends on these
# four being enabled, and a disabled repository does not produce an error — it
# produces a "no match for argument" three steps later, which is a much less
# obvious message.
say "Checking the repositories are enabled"
aq_installed rpmfusion-free-release rpmfusion-nonfree-release

echo "Every repository this image can now see:"
aq_dnf repolist --all || true

# The first column of `repolist` is the repository's id. Pulling just that
# column out means the check does not depend on how wide dnf decides to print
# the other ones.
aq_dnf repolist --enabled | awk 'NR > 1 { print $1 }' > /tmp/aq-enabled-repos.txt

for repo in rpmfusion-free rpmfusion-free-updates rpmfusion-nonfree rpmfusion-nonfree-updates; do
    if grep -qFx "${repo}" /tmp/aq-enabled-repos.txt; then
        ok "${repo} is enabled"
    else
        bad "${repo} is not enabled — the codec step will fail with 'no match for argument'"
    fi
done
rm -f /tmp/aq-enabled-repos.txt

# ------------------------------------------------------------------------------
# Refresh the catalogue once, here
# ------------------------------------------------------------------------------
# Doing it now means every later step works from the same downloaded catalogue
# instead of each one fetching it again.
say "Downloading the package catalogues"
aq_dnf makecache

aq_finish "Software sources"
