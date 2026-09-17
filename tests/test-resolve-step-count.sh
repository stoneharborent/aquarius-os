#!/usr/bin/bash
# =============================================================================
# test-resolve-step-count.sh — the setup only promises steps it is going to do
# =============================================================================
# WHAT THIS PROVES, AND WHY IT EXISTS
#
# Since 16 September 2026 the NVIDIA edition of AquariusOS carries the
# environment DaVinci Resolve runs in inside the operating system, and the first
# login builds the container out of it in the background. By the time anybody
# clicks DaVinci Resolve, two of the seven setup steps — "Downloading the
# environment" and "Setting that environment up" — have nothing left to do.
#
# ⚠️ THE FAULT THIS GUARDS AGAINST IS A PROGRESS BAR THAT LIES. The old flow
# announced both steps anyway and completed each in well under a second. A
# window that draws seven rows and flashes past two of them teaches people that
# the window is not telling them the truth — and "Downloading…" appearing and
# vanishing on a machine with no internet reads as a failure that was hidden.
#
# So a step with no work is not announced at all, and the total shrinks to
# match. That arithmetic is the thing that can silently rot: it lives in one
# `step` function that renumbers canonical steps 1-7 into "the third of five",
# and a mistake in it produces a bar that stops at four fifths for ever, or one
# that announces "STEP 6/5".
#
# HOW IT IS TESTED WITHOUT A CONTAINER, A GRAPHICS CARD OR A DOWNLOAD
# A folder of small stand-in programs is put at the FRONT of the path, so that
# the script asks our `podman` and our `distrobox` instead of the real ones and
# is told whatever this test wants it to be told. Nothing is installed, nothing
# is downloaded and nothing on this computer is touched.
#
#     tests/test-resolve-step-count.sh [path-to-aquarius-resolve-install]
#
# With no argument it tests the copy in this repository, which is what a
# developer wants. The build passes the copy in the finished image, which is
# what actually ships.
# =============================================================================

set -uo pipefail

INSTALL="${1:-}"
if [ -z "${INSTALL}" ]; then
    INSTALL="$(dirname "$0")/../system_files/usr/libexec/aquarius-resolve-install"
fi

if [ ! -r "${INSTALL}" ]; then
    echo "FAIL: no aquarius-resolve-install at ${INSTALL}" >&2
    exit 1
fi

FAILED=0
note() { printf '  %s\n' "$*"; }
ok() { printf '  ok   %s\n' "$*"; }
bad() {
    printf '  FAIL %s\n' "$*" >&2
    FAILED=1
}

WORK="$(mktemp -d -t aq-resolve-steps-XXXXXX)"
trap 'rm -rf "${WORK}"' EXIT

mkdir -p "${WORK}/bin" "${WORK}/home/Downloads"

# The download the person is pretending to have made. Nothing reads its
# contents — the name is what carries the edition and the version — and it never
# reaches anything of Blackmagic's, because the stand-in `distrobox` below is
# what would "install" it.
printf 'not a real installer\n' \
    > "${WORK}/home/Downloads/DaVinci_Resolve_Studio_21.1_Linux.run"

# -----------------------------------------------------------------------------
# The stand-ins
# -----------------------------------------------------------------------------
# `podman` answers two questions and nothing else: is the image here, and is the
# container here. Both answers are read out of files this test writes, so one
# stand-in covers every case below.
cat > "${WORK}/bin/podman" << 'STANDIN'
#!/bin/sh
STATE="${AQ_TEST_STATE}"
case "$1 $2" in
    "image exists")     [ -e "${STATE}/have-image" ] && exit 0 ; exit 1 ;;
    "container exists") [ -e "${STATE}/have-container" ] && exit 0 ; exit 1 ;;
esac
case "$1" in
    pull)
        # Pretend a download happened, and say so in podman's own words so that
        # the PERCENT-reading awk in the real script has something to chew on.
        echo "Copying blob abcdef: 512.0MiB / 1024.0MiB"
        echo "Copying blob abcdef: 1024.0MiB / 1024.0MiB"
        touch "${STATE}/have-image"
        exit 0
        ;;
    load)
        touch "${STATE}/have-image"
        exit 0
        ;;
    image | images | tag | inspect) exit 0 ;;
esac
exit 0
STANDIN

# `distrobox` creates nothing and enters nothing. `create` records that the
# container now exists, so a second run of the script sees a built machine.
cat > "${WORK}/bin/distrobox" << 'STANDIN'
#!/bin/sh
STATE="${AQ_TEST_STATE}"
case "$1" in
    create) touch "${STATE}/have-container" ; exit 0 ;;
    enter)  exit 0 ;;
esac
exit 0
STANDIN

# Everything else the script reaches for on its way through. None of it may
# touch this computer, so each one succeeds and does nothing.
for quiet in distrobox-create distrobox-enter xdg-open update-desktop-database \
    notify-send nvidia-smi nvidia-ctk aquarius-resolve-entry; do
    printf '#!/bin/sh\nexit 0\n' > "${WORK}/bin/${quiet}"
done
chmod 0755 "${WORK}"/bin/*

# -----------------------------------------------------------------------------
# One run of the setup, with this machine's state made up
# -----------------------------------------------------------------------------
# Prints the STEP lines it sent, and nothing else. Everything the script says to
# a person goes to a file, so a failure can be read afterwards.
run_setup() { # run_setup <have-image 0|1> <have-container 0|1> [extra args...]
    local have_image="$1" have_container="$2"
    shift 2
    local state="${WORK}/state"
    rm -rf "${state}"
    mkdir -p "${state}"
    [ "${have_image}" = "1" ] && touch "${state}/have-image"
    [ "${have_container}" = "1" ] && touch "${state}/have-container"

    AQ_TEST_STATE="${state}" \
        PATH="${WORK}/bin:${PATH}" \
        HOME="${WORK}/home" \
        AQ_RESOLVE_RUNTIME_IMAGE="example.invalid/runtime" \
        AQ_RESOLVE_RUNTIME_TAG="9" \
        bash "${INSTALL}" --progress-fd 3 "$@" \
        3> "${WORK}/progress.txt" > "${WORK}/said.txt" 2>&1
    grep '^STEP ' "${WORK}/progress.txt" || true
}

# The total every STEP line claims, and the numbers in order. A disagreement
# between two STEP lines about how many steps there are is the exact fault this
# file exists to catch.
totals_of() { sed -n 's#^STEP [0-9]*/\([0-9]*\) .*#\1#p' | sort -u | tr '\n' ' '; }
numbers_of() { sed -n 's#^STEP \([0-9]*\)/[0-9]* .*#\1#p' | tr '\n' ' '; }

check_run() { # check_run <title> <have-image> <have-container> <expected total>
    local title="$1" image="$2" container="$3" want="$4"
    local steps totals numbers expect i
    steps="$(run_setup "${image}" "${container}")"
    note ""
    note "${title}"
    printf '%s\n' "${steps}" | sed 's/^/    /'

    totals="$(printf '%s\n' "${steps}" | totals_of)"
    if [ "${totals}" = "${want} " ]; then
        ok "every step says there are ${want} of them"
    else
        bad "the steps disagree about the total: '${totals}' (wanted '${want}')"
    fi

    # 1, 2, 3 … with no gaps and no repeats-out-of-order. A step may be
    # announced twice in a row (step 4 is, once before the container is made and
    # once as it starts), so a repeat of the number just seen is allowed.
    numbers="$(printf '%s\n' "${steps}" | numbers_of)"
    expect=1
    for i in ${numbers}; do
        if [ "${i}" = "${expect}" ]; then
            continue
        elif [ "${i}" = "$((expect + 1))" ]; then
            expect="${i}"
        else
            bad "the step numbers jump: ${numbers}"
            return
        fi
    done
    if [ "${expect}" = "${want}" ]; then
        ok "they run 1 to ${want} with no gaps: ${numbers}"
    else
        bad "the last step was ${expect} of ${want}: ${numbers}"
    fi
}

echo "Testing ${INSTALL}"

# -----------------------------------------------------------------------------
# A machine with nothing: all seven steps, exactly as before 2026-09-16
# -----------------------------------------------------------------------------
check_run "Nothing on the machine yet — the full seven steps" 0 0 7

# ⚠️ AND THAT STATE IS NOT A CORNER CASE, IT IS A WHOLE EDITION. Since
# 2026-09-17 the DaVinci Resolve icon is on the AMD/Intel image too, but the
# 330 MB environment is not — so every AMD or Intel machine clicking that icon
# walks this path, downloads the environment, and takes about fifteen minutes.
# It is the old flow, unchanged, and it has to STAY unchanged: an optimisation
# aimed at prepared machines that quietly dropped the download step here would
# leave those machines building a container out of nothing.
STEPS_BARE="$(run_setup 0 0)"
if printf '%s\n' "${STEPS_BARE}" | grep -q 'Downloading the environment'; then
    ok "a machine with no environment (every AMD/Intel one) is still told it is downloading"
else
    bad "a machine with nothing on it no longer announces the download — the AMD/Intel flow would lie"
fi
if printf '%s\n' "${STEPS_BARE}" | grep -q 'Setting that environment up'; then
    ok "and that it is building the environment afterwards"
else
    bad "a machine with nothing on it no longer announces building the environment"
fi

# -----------------------------------------------------------------------------
# The environment is here but the container is not: six steps
# -----------------------------------------------------------------------------
# This is the state of an NVIDIA machine whose first-login preparation unpacked
# the environment and was then interrupted before it built the container.
check_run "The environment is unpacked but not built — six steps" 1 0 6

# -----------------------------------------------------------------------------
# Both already done: five steps. THE ORDINARY NVIDIA MACHINE.
# -----------------------------------------------------------------------------
check_run "Everything already prepared — five steps" 1 1 5

# ⚠️ AND THE ONE THAT MATTERS MOST: no "Downloading…" step on a machine that has
# nothing to download. It is the step somebody watching a five-minute install
# will remember, and announcing it falsely is what this whole change is about.
STEPS_READY="$(run_setup 1 1)"
if printf '%s\n' "${STEPS_READY}" | grep -q 'Downloading the environment'; then
    bad "a machine with the environment already here still announces a download"
else
    ok "a prepared machine never says it is downloading anything"
fi
if printf '%s\n' "${STEPS_READY}" | grep -q 'Matching Resolve to your screen'; then
    ok "and it still ends with the step that checks Resolve against your screen"
else
    bad "the last step is missing on a prepared machine"
fi

# -----------------------------------------------------------------------------
# Removing still walks its own three steps
# -----------------------------------------------------------------------------
# Removing shares this script and this channel, and its three steps have nothing
# to do with the environment. A change to the arithmetic above that reached them
# would be a window drawing three rows against a script sending five.
REMOVE_STEPS="$(run_setup 1 1 --remove --yes)"
note ""
note "Removing — its own three steps, untouched by any of the above"
printf '%s\n' "${REMOVE_STEPS}" | sed 's/^/    /'
if [ "$(printf '%s\n' "${REMOVE_STEPS}" | totals_of)" = "3 " ]; then
    ok "removing still says there are three steps"
else
    bad "removing no longer walks three steps"
fi

# -----------------------------------------------------------------------------
# Updating always re-asks about the environment, even though it is already here
# -----------------------------------------------------------------------------
# ⚠️ THE POLICY THIS PROTECTS, written up in runtime.env: the copy baked into
# AquariusOS is a SEED, not a pin. Skipping the download step on an update
# because "the image is obviously already here" would quietly freeze every
# NVIDIA machine on whatever environment its installer happened to carry, and
# Rocky's security rebuilds would never reach anybody.
UPDATE_STEPS="$(run_setup 1 1 --update)"
note ""
note "Updating — the environment is re-asked for on purpose"
printf '%s\n' "${UPDATE_STEPS}" | sed 's/^/    /'
if printf '%s\n' "${UPDATE_STEPS}" | grep -q 'Downloading the environment'; then
    ok "an update still asks the registry whether the environment is newer"
else
    bad "an update no longer refreshes the environment — security rebuilds would never arrive"
fi

# -----------------------------------------------------------------------------
# Preparing: quiet, and it does nothing twice
# -----------------------------------------------------------------------------
# This is what the first login runs. It must say nothing on the progress channel
# — nobody is watching one — and it must be safe to run on a machine that is
# already prepared, because every single login runs it again.
note ""
note "Preparing at first login"
PREPARE_STEPS="$(run_setup 1 1 --prepare)"
if [ -z "${PREPARE_STEPS}" ]; then
    ok "preparing an already-prepared machine announces nothing at all"
else
    bad "preparing sent progress lines nobody is reading: ${PREPARE_STEPS}"
fi
if grep -q 'already set up' "${WORK}/said.txt"; then
    ok "and says plainly that there was nothing to do"
else
    bad "preparing an already-prepared machine did not say so:"
    sed 's/^/       /' "${WORK}/said.txt" >&2
fi

# A machine with no NVIDIA graphics card must do nothing and must not fail.
# Resolve on Linux is supported on NVIDIA and nothing else, so building a
# gigabyte of container on an AMD laptop would spend somebody's disk for nothing.
if [ ! -e /proc/driver/nvidia/version ] && [ ! -c /dev/nvidiactl ]; then
    run_setup 0 0 --prepare > /dev/null
    if grep -q 'No NVIDIA graphics card' "${WORK}/said.txt"; then
        ok "on a machine with no NVIDIA card it does nothing, and says why"
    else
        bad "preparing on a machine with no NVIDIA card did not stand down:"
        sed 's/^/       /' "${WORK}/said.txt" >&2
    fi
else
    note "(this machine has an NVIDIA card, so the stand-down case is not tested here)"
fi

echo ""
if [ "${FAILED}" = "0" ]; then
    echo "test-resolve-step-count.sh: everything passed"
    exit 0
fi
echo "test-resolve-step-count.sh: FAILED" >&2
exit 1
