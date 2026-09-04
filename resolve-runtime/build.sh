#!/usr/bin/bash
# ==============================================================================
# Build the AquariusOS DaVinci Resolve runtime
# ==============================================================================
# PLAIN ENGLISH
#
# This runs INSIDE a Rocky Linux container while that container is being built.
# It installs everything DaVinci Resolve needs, and nothing else. Resolve itself
# is NOT installed here — Blackmagic's licence does not allow anybody but them
# to hand out the installer, so the user downloads it and we install it into a
# copy of this container on their own machine.
#
# WHY THIS EXISTS AT ALL — the one paragraph worth reading
#
# Resolve ships its own copy of a library called GLib, version 2.68, inside
# /opt/resolve/libs. On a modern Linux the system's text-drawing library
# (pango) is built against GLib 2.80 or newer, asks the bundled 2.68 for
# something that did not exist in 2021, and Resolve dies before its window ever
# appears. That is the single most common "Resolve does not work on Linux"
# story, and it recurs every time a distribution moves GLib forward.
#
# Enterprise Linux 9 — Rocky, RHEL, Alma — is still on GLib 2.68, the same
# series Resolve bundles. So on this userland the mismatch is not worked around.
# It cannot happen. That is the whole reason AquariusOS runs Resolve in a
# container instead of on the desktop it ships.
#
# HOW FAILURE IS HANDLED, AND WHY IT IS SPLIT IN TWO
#
#   packages-required.txt   Resolve does not start without these. If one is
#                           missing at the end, this script stops the build.
#   packages-optional.txt   Everything else. A missing one prints a NOTE.
#
# Rocky moves packages between its four repositories between point releases, and
# a name that vanishes from CRB should not take the flagship feature of the
# operating system down with it. The build log lists exactly what landed and
# what did not, every time, so this is a report and not a hope.
# ==============================================================================

set -euo pipefail

ROCKY="${ROCKY:-9}"

FAILS=0
say() {
    echo
    echo "=== $* ==="
}
ok() { echo "  OK   $*"; }
bad() {
    echo "  FAIL $*" >&2
    FAILS=$((FAILS + 1))
}
note() { echo "  NOTE $*"; }

# Read a package list file: strip comments and blank lines.
read_list() {
    sed -e 's/#.*$//' -e 's/[[:space:]]*$//' "$1" | grep -v '^$' || true
}

# ------------------------------------------------------------------------------
# Software sources
# ------------------------------------------------------------------------------
# Rocky splits its software across four places and only two are switched on by
# default:
#
#   BaseOS      the operating system itself                      (on)
#   AppStream   applications and libraries                       (on)
#   CRB         "CodeReady Builder" — the development half,      (off)
#               where several X11 helper libraries live
#   EPEL        Extra Packages for Enterprise Linux, the         (not installed)
#               community's additions
#
# Both of the off ones are needed, so both go on. This is the standard, and
# documented, way to get a full library set on Enterprise Linux — not a hack.
say "Software sources"
dnf -y install dnf-plugins-core
if dnf config-manager --set-enabled crb 2> /dev/null; then
    ok "CRB is switched on"
elif dnf config-manager --set-enabled powertools 2> /dev/null; then
    # Rocky 8 called the same repository PowerTools. Kept so that ROCKY=8 still
    # builds if anybody ever needs Blackmagic's exact stated target.
    ok "PowerTools is switched on (this is Rocky 8's name for CRB)"
else
    bad "neither CRB nor PowerTools could be switched on — half the X11 libraries below will be missing"
fi

if dnf -y install "https://dl.fedoraproject.org/pub/epel/epel-release-latest-${ROCKY}.noarch.rpm"; then
    ok "EPEL is installed"
else
    note "EPEL would not install — anything from it will show up as a missing optional package below"
fi

dnf -y makecache

# ------------------------------------------------------------------------------
# The packages Resolve cannot start without
# ------------------------------------------------------------------------------
say "Installing what Resolve needs"
mapfile -t REQUIRED < <(read_list /ctx/packages-required.txt)
echo "${#REQUIRED[@]} required packages."

# One `dnf install` for the whole list is far faster than one per package,
# because dnf resolves the dependency graph once. If it fails, we do NOT give
# up: we fall back to one at a time so the log names the package that is
# actually the problem, instead of a single wall of red that names none of them.
if dnf -y install "${REQUIRED[@]}"; then
    ok "all required packages installed in one go"
else
    note "the single install failed — retrying one package at a time to find out which"
    for pkg in "${REQUIRED[@]}"; do
        dnf -y install "${pkg}" || bad "cannot install ${pkg}"
    done
fi

# ------------------------------------------------------------------------------
# The packages that only make things better
# ------------------------------------------------------------------------------
say "Installing the optional extras"
mapfile -t OPTIONAL < <(read_list /ctx/packages-optional.txt)
echo "${#OPTIONAL[@]} optional packages."

# Deliberately one at a time. `dnf install a b c` fails as a whole if any one
# name is unknown, and the point of this list is that some names are expected to
# be unknown on some point releases.
OPTIONAL_MISSING=()
for pkg in "${OPTIONAL[@]}"; do
    if dnf -y install "${pkg}" > /dev/null 2>&1; then
        echo "  got  ${pkg}"
    else
        OPTIONAL_MISSING+=("${pkg}")
    fi
done
if [ "${#OPTIONAL_MISSING[@]}" -gt 0 ]; then
    note "not available on Rocky ${ROCKY}: ${OPTIONAL_MISSING[*]}"
    note "(that is allowed — nothing in the optional list stops Resolve starting)"
else
    ok "every optional package was available too"
fi

# ------------------------------------------------------------------------------
# Read the result back
# ------------------------------------------------------------------------------
# `dnf install` can report success having installed something that merely
# "provides" the name you asked for. The package database is the answer that
# counts, so every required name is asked about directly.
say "Checking every required package is really installed"
for pkg in "${REQUIRED[@]}"; do
    if rpm -q "${pkg}" > /dev/null 2>&1; then
        echo "  OK   ${pkg} $(rpm -q --queryformat '%{VERSION}-%{RELEASE}' "${pkg}")"
    else
        bad "${pkg} is NOT installed"
    fi
done

# ------------------------------------------------------------------------------
# THE CHECK THIS WHOLE IMAGE EXISTS FOR
# ------------------------------------------------------------------------------
# If GLib in this container is not the 2.68 series, the reason for building on
# Enterprise Linux has evaporated and Resolve will crash on launch in the
# familiar way. Better to fail here, in a build nobody is waiting on, than on a
# creator's machine at midnight.
#
# This is a warning rather than a failure on Rocky 10, because Rocky 10 is a
# deliberate opt-in (ROCKY=10) and the person choosing it is choosing to find
# out what happens.
say "The GLib version — the reason this image is built on Enterprise Linux"
GLIB_VERSION="$(rpm -q --queryformat '%{VERSION}' glib2)"
echo "  glib2 is ${GLIB_VERSION}"
echo "  Resolve bundles 2.68.x in /opt/resolve/libs."
case "${GLIB_VERSION}" in
    2.68.*)
        ok "the system GLib is the same series Resolve bundles — the launch crash cannot happen here"
        ;;
    *)
        if [ "${ROCKY}" = "9" ]; then
            bad "Rocky 9 is supposed to carry GLib 2.68 and this one carries ${GLIB_VERSION}. Something changed upstream; do not publish this until somebody has looked at it."
        else
            note "GLib is ${GLIB_VERSION}, NOT the 2.68 series Resolve bundles."
            note "Resolve may fail to start in this container with an 'undefined symbol' error."
            note "That is the known risk of ROCKY=${ROCKY} and it is why 9 is the default."
        fi
        ;;
esac

say "The C library version — the VFX Reference Platform floor"
GLIBC_VERSION="$(rpm -q --queryformat '%{VERSION}' glibc)"
echo "  glibc is ${GLIBC_VERSION}"
echo "  The VFX Reference Platform's CY2027 floor is 2.34, which is Enterprise Linux 9."
echo "  Unreal Engine 5's stated floor is Rocky 8, which is older still."

# ------------------------------------------------------------------------------
# Tidy up
# ------------------------------------------------------------------------------
# The package manager's cache is several hundred megabytes of downloaded
# metadata that the finished image never reads. Removing it is the difference
# between a 1 GB image and a 1.5 GB one, on something every user downloads.
say "Cleaning up"
dnf -y clean all
rm -rf /var/cache/dnf /var/cache/yum /tmp/* 2> /dev/null || true

if [ "${FAILS}" -ne 0 ]; then
    echo "::error::The Resolve runtime is missing ${FAILS} thing(s) it cannot work without."
    exit 1
fi

say "The Resolve runtime built cleanly."
