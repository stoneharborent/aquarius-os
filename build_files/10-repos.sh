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
# The tool for switching repositories on and off
# ------------------------------------------------------------------------------
# ⚠️ `dnf config-manager` IS NOT IN THE BARE FEDORA IMAGE. On a normal Fedora
# desktop it is always there, so nobody thinks of it as a separate thing; on the
# bootable base image it is a plugin that has to be installed, and without it
# every `dnf config-manager` call dies with:
#
#     Unknown argument "config-manager" for command "dnf5".
#
# The NVIDIA step needs it — it has to switch RPM Fusion off while it installs
# the NVIDIA driver, so that dnf cannot mix RPM Fusion's driver with Universal
# Blue's. Installing it here means every later step can rely on it. (Found the
# hard way on the second CI run of the restart, 2026-09-03.)
say "The repository-management plugin"
aq_dnf install dnf5-plugins

# ------------------------------------------------------------------------------
# Add RPM Fusion
# ------------------------------------------------------------------------------
# These two packages contain nothing but the repository definition and the key
# used to verify everything that comes from it. Installing them is what makes
# the catalogue searchable; it installs no actual software.
say "Adding the RPM Fusion repositories"
# The two small "release" packages are fetched by hand, with retries, before
# dnf sees them. mirrors.rpmfusion.org hands dnf ONE mirror and dnf gives up
# when that mirror is slow or down — which is how two builds in a row died on
# 2026-09-09 (mirror.fcix.net timing out, repos.eggycrew.com not resolving)
# with nothing wrong in this tree. download1.rpmfusion.org is the project's
# own primary server; the mirror list stays as the fallback. The files are
# read back (a real RPM starts with the bytes ED AB EE DB) before dnf is asked
# to install them, so a mirror's HTML error page can never be "installed".
# fedora-bootc ships curl-minimal; if a future base drops it, install it now.
command -v curl > /dev/null 2>&1 || aq_dnf install curl-minimal
install -d -m 0755 /tmp/aq-rpmfusion
for aq_flavour in free nonfree; do
    aq_rpm="rpmfusion-${aq_flavour}-release-${FEDORA}.noarch.rpm"
    aq_got=0
    for aq_url in \
        "https://download1.rpmfusion.org/${aq_flavour}/fedora/${aq_rpm}" \
        "https://mirrors.rpmfusion.org/${aq_flavour}/fedora/${aq_rpm}"; do
        if curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 --connect-timeout 20 --max-time 120 \
                -o "/tmp/aq-rpmfusion/${aq_rpm}" "${aq_url}" \
           && [ "$(head -c 4 "/tmp/aq-rpmfusion/${aq_rpm}" | od -An -tx1 | tr -d ' \n')" = "edabeedb" ]; then
            echo "  fetched ${aq_rpm} from ${aq_url}"
            aq_got=1
            break
        fi
        echo "  could not fetch ${aq_rpm} from ${aq_url}; trying the next source"
        rm -f "/tmp/aq-rpmfusion/${aq_rpm}"
    done
    if [ "${aq_got}" -ne 1 ]; then
        echo "FAIL: ${aq_rpm} could not be fetched from any source — RPM Fusion is unreachable right now"
        exit 1
    fi
done
aq_dnf install \
    "/tmp/aq-rpmfusion/rpmfusion-free-release-${FEDORA}.noarch.rpm" \
    "/tmp/aq-rpmfusion/rpmfusion-nonfree-release-${FEDORA}.noarch.rpm"
rm -rf /tmp/aq-rpmfusion

# ------------------------------------------------------------------------------
# Check they are actually there and switched on
# ------------------------------------------------------------------------------
# `dnf install` of a URL can succeed and still leave a repository disabled if
# the package changes shape upstream. The whole media layer depends on these
# four being enabled, and a disabled repository does not produce an error — it
# produces a "no match for argument" three steps later, which is a much less
# obvious message.
say "Checking the repositories are enabled"
aq_installed rpmfusion-free-release rpmfusion-nonfree-release dnf5-plugins

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
