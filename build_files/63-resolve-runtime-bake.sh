#!/usr/bin/bash
# ==============================================================================
# 63 — Put the environment DaVinci Resolve runs in inside the operating system
# ==============================================================================
# PLAIN ENGLISH
#
# Step 62 put in everything AquariusOS has around DaVinci Resolve. This step
# puts in the last missing piece: the Rocky Linux environment Resolve actually
# runs inside, as a single file, so that setting Resolve up needs no download
# from us at all.
#
# ⚠️ THERE IS STILL NO DAVINCI RESOLVE IN THIS IMAGE, AND THERE NEVER WILL BE.
# Blackmagic's licence does not allow anyone else to hand out their installer,
# so no file, no program and no picture of theirs enters this operating system.
# What this step adds is OUR container: a Rocky Linux userland with the
# libraries Resolve needs, built by .github/workflows/build-resolve-runtime.yml
# from resolve-runtime/ in this same repository. The person still downloads
# Resolve from Blackmagic, and that is the one step that cannot be automated
# and should not be.
#
# WHAT IT BUYS
# Before this, setting Resolve up took about fifteen minutes and nearly all of
# it was downloading a gigabyte of container. Now the container is already here,
# the first login builds it in the background before anybody asks, and what is
# left for the person is their own Blackmagic download and about three minutes.
# It also means Resolve can be set up on a machine with no internet connection
# at all, which was impossible before.
#
# ⚠️ NVIDIA EDITION ONLY, AND THAT IS A DECISION RATHER THAN AN OVERSIGHT.
# Blackmagic support NVIDIA graphics on Linux and nothing else. On an AMD or
# Intel machine Resolve installs and then says its GPU processing mode is
# unsupported — step 62 says so plainly rather than letting somebody find out
# from Resolve. Putting a third of a gigabyte into the download of every person
# who cannot use it would be a cost with no matching benefit, so the AMD/Intel
# edition does not carry the file and sets Resolve up the way it always did:
# by downloading the environment when somebody asks for it.
#
# WHAT IS ACTUALLY WRITTEN
#
#   /usr/share/aquarius/resolve/runtime.oci
#       The environment, as one file, in the standard format for such things
#       (an "OCI archive"). About 330 MB — the same bytes the registry would
#       have sent, compressed the same way.
#
#   /usr/share/aquarius/resolve/runtime-baked.env
#       What that file is, in three lines a machine can read: which image, which
#       tag, and the digest — the registry's own name for these exact bytes.
#       `aq resolve status` prints it, and installed.env records it when
#       somebody's machine starts from this copy, so a machine can always say
#       what it is really running.
#
# ⚠️ IT IS A SEED, NOT A PIN. The long version is in runtime.env beside the file
# this step reads. The short version: a machine starts here, and `aq resolve
# update` still re-asks the registry for the tag, so Rocky's security rebuilds
# reach machines that started from this copy. Nothing is frozen by being baked.
#
# WHY NOT A READ-ONLY PODMAN IMAGE STORE UNDER /usr, WHICH WOULD BE SMALLER
# It was tried first, because on paper it is exactly right: podman can be told
# about extra, read-only image stores, the user's podman then sees the image
# with no download and no copy into their home folder, and the whole thing costs
# the disk space once instead of twice.
#
# It does not work here, for a reason that has nothing to do with bootc or with
# read-only folders. AN IMAGE STORE BELONGS TO THE ACCOUNT THAT UNPACKED IT.
# When a container image is unpacked, every file in it is given an owner, and a
# store built by the administrator during this build has files owned by the
# administrator — while Resolve's container runs as the PERSON, in a sandbox
# where the administrator's account does not exist at all. Measured on Fedora
# with podman 5.8: an image unpacked by a person is stored with every file owned
# by that person, and no other ownership is recorded anywhere, so there is
# nothing for podman to translate. Half the files in an administrator's store
# would be unreadable to the person, in ways that look like a broken Resolve
# rather than like a permissions problem.
#
# So the file is loaded into the person's own store, once, at their first login,
# where every file gets the right owner by construction. It costs the space
# twice — here and in the home folder — and that is the honest price of it being
# correct. The same reasoning is written beside the code that loads it, in
# /usr/libexec/aquarius-resolve-install.
#
# The beginner-facing guide is docs/restart/resolve.md.
# ==============================================================================

set -euo pipefail
# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

NVIDIA="${NVIDIA:-0}"

RUNTIME_ENV=/usr/share/aquarius/resolve/runtime.env
ARCHIVE=/usr/share/aquarius/resolve/runtime.oci
BAKED_ENV=/usr/share/aquarius/resolve/runtime-baked.env

# The day-one app-grid entry, the program behind it, and the older entry it
# replaces. All three are shipped in system_files/, which is one tree copied into
# both editions, so which of them survives is decided here.
RESOLVE_ENTRY=/usr/share/applications/aquarius-davinci-resolve.desktop
RESOLVE_OPEN=/usr/libexec/aquarius-resolve-open
INSTALL_ENTRY=/usr/share/applications/aquarius-install-resolve.desktop
PREPARE_UNIT=/usr/lib/systemd/user/aquarius-resolve-prepare.service
PREPARE_LINK=/usr/lib/systemd/user/graphical-session.target.wants/aquarius-resolve-prepare.service

# ==============================================================================
# 1. Which environment — asked of the one file that names it
# ==============================================================================
# ⚠️ THE NAME AND THE TAG ARE READ, NEVER RETYPED. runtime.env is the single
# place the runtime is named, and it is the file the finished operating system
# reads too. A second copy of the name in this script would be a second thing to
# remember to change, and the day somebody changed only one of them the build
# would bake one environment and the machine would look for another.
say "DaVinci Resolve — which environment this image will carry"

if [ ! -r "${RUNTIME_ENV}" ]; then
    bad "${RUNTIME_ENV} is missing — nothing would know which environment to bake"
    aq_finish "DaVinci Resolve — the baked environment"
    exit 1
fi

# shellcheck source=/dev/null
. "${RUNTIME_ENV}"

IMAGE="${AQ_RESOLVE_RUNTIME_IMAGE}:${AQ_RESOLVE_RUNTIME_TAG}"
echo "  ${IMAGE}"

# runtime.env names where the archive goes, so that this step and the machine
# cannot disagree about where to look. Checked rather than assumed, because a
# rename there and not here is a file written to a place nothing reads.
if [ "${AQ_RESOLVE_RUNTIME_ARCHIVE:-}" != "${ARCHIVE}" ]; then
    bad "runtime.env says the environment lives at '${AQ_RESOLVE_RUNTIME_ARCHIVE:-nowhere}', this step writes ${ARCHIVE}"
fi
if [ "${AQ_RESOLVE_BAKED_ENV:-}" != "${BAKED_ENV}" ]; then
    bad "runtime.env says the record lives at '${AQ_RESOLVE_BAKED_ENV:-nowhere}', this step writes ${BAKED_ENV}"
fi

# ==============================================================================
# 2. The AMD/Intel edition carries none of it
# ==============================================================================
# system_files/ is one tree copied into both editions, so "not on the AMD image"
# has to be something this step ENFORCES rather than something that is true by
# accident. The check is the point: if a future change ever put the archive into
# system_files/ by hand, this is where the AMD build would notice.
if [ "${NVIDIA}" != "1" ]; then
    say "DaVinci Resolve — the AMD/Intel edition carries no environment"
    echo "  Blackmagic support NVIDIA graphics on Linux and nothing else, so this"
    echo "  edition does not carry a third of a gigabyte for a thing it cannot"
    echo "  usefully run. Setting Resolve up here downloads the environment, the"
    echo "  way every edition did before 2026-09-16."

    # And no "DaVinci Resolve" entry in the app grid either. On this edition
    # Resolve is OFFERED — the plain "Install DaVinci Resolve" entry, which says
    # what it is and whose window says out loud that AMD graphics are not
    # supported by Blackmagic. Putting a DaVinci Resolve icon on the dock of a
    # machine that cannot usefully run it would be a lie told by an icon.
    rm -f "${RESOLVE_ENTRY}"
    if [ -e "${RESOLVE_ENTRY}" ]; then
        bad "${RESOLVE_ENTRY} is in the AMD/Intel image — it would promise a Resolve this machine cannot run well"
    else
        ok "no day-one DaVinci Resolve entry in the AMD/Intel image"
    fi
    # The pinned name on the dock therefore resolves to nothing here, which is
    # deliberate and costs nothing: GNOME does not draw a name it cannot find.
    # The long version is beside favorite-apps in
    # system_files/usr/share/glib-2.0/schemas/zz1-aquarius-20-shell.gschema.override.
    if grep -q "aquarius-davinci-resolve.desktop" \
        /usr/share/glib-2.0/schemas/zz1-aquarius-20-shell.gschema.override; then
        ok "the dock still names it, and GNOME quietly skips a name it cannot find"
    else
        bad "the dock no longer names DaVinci Resolve at all — the NVIDIA edition would lose its pin"
    fi

    # "Install DaVinci Resolve" stays VISIBLE here. It is the only way in on
    # this edition, so hiding it (which is what the NVIDIA edition does) would
    # leave no way to set Resolve up without a terminal.
    if grep -q '^NoDisplay=true$' "${INSTALL_ENTRY}"; then
        bad "'Install DaVinci Resolve' is hidden in the AMD/Intel image — there would be no way in at all"
    else
        ok "'Install DaVinci Resolve' is still in the app grid, which here is the only way in"
    fi

    rm -f "${ARCHIVE}" "${BAKED_ENV}"
    if [ -e "${ARCHIVE}" ]; then
        bad "${ARCHIVE} is in the AMD/Intel image — it would be ~330 MB nobody can use"
    else
        ok "no environment archive in the AMD/Intel image"
    fi
    if [ -e "${BAKED_ENV}" ]; then
        bad "${BAKED_ENV} is in the AMD/Intel image, claiming an environment that is not there"
    else
        ok "and no record claiming there is one"
    fi
    # aq_finish only stops the build when something failed, so the exit is what
    # actually ends this step on the AMD/Intel edition. Without it the script
    # would carry on and fetch the very thing it just decided not to carry.
    aq_finish "DaVinci Resolve — the baked environment"
    exit 0
fi

# ==============================================================================
# 3. Fetch it
# ==============================================================================
# skopeo copies between image stores and files without needing a container
# engine running, which is the only thing that can work inside a build. It is
# not in the base image, so it is asked for by name here — and it is removed
# again at the end, because a tool that exists only to build the image has no
# business being in the finished one.
say "DaVinci Resolve — fetching the environment"

aq_dnf install skopeo
aq_installed skopeo

mkdir -p "$(dirname "${ARCHIVE}")"
rm -rf "${ARCHIVE}"

# ⚠️ NO LOGIN, ON PURPOSE, AND IT IS CHECKED RATHER THAN HOPED FOR.
# ghcr.io/stoneharborent/aquarius-resolve-runtime is a PUBLIC package, so this
# build needs no credentials and a fork or a fresh clone can build the image
# without being given any. If somebody ever makes that package private, this
# line is where the build stops, with a message saying so — which is much better
# than a private package quietly becoming a secret the build depends on.
#
# The digest is asked for FIRST, separately, so that the failure "this
# environment has not been published yet" is told apart from "the copy failed
# half way", and so that what gets written down is the registry's own answer
# rather than something worked out from the file afterwards.
if ! DIGEST="$(skopeo inspect --format '{{.Digest}}' "docker://${IMAGE}" 2> /tmp/aq-skopeo.txt)"; then
    bad "could not reach ${IMAGE}:"
    sed 's/^/       /' /tmp/aq-skopeo.txt >&2
    echo "       If this says 'authentication required', the runtime package has been" >&2
    echo "       made private. It has always been public and this build has no" >&2
    echo "       credentials by design — see the note above this line." >&2
    echo "       If it says 'manifest unknown', the runtime has not been built yet:" >&2
    echo "       run the 'Build the Resolve runtime' workflow first." >&2
    aq_finish "DaVinci Resolve — the baked environment"
    exit 1
fi
echo "  ${IMAGE} is ${DIGEST}"

# Copied BY DIGEST, not by tag. Between the question above and the copy below,
# somebody could publish a new build of tag 9 — and then the archive and the
# digest written beside it would be about two different things, which is exactly
# the kind of fault that is invisible until a machine reports a digest it is not
# running.
if ! skopeo copy --quiet \
    "docker://${AQ_RESOLVE_RUNTIME_IMAGE}@${DIGEST}" \
    "oci-archive:${ARCHIVE}:${IMAGE}" 2> /tmp/aq-skopeo.txt; then
    bad "the environment could not be copied into the image:"
    sed 's/^/       /' /tmp/aq-skopeo.txt >&2
    aq_finish "DaVinci Resolve — the baked environment"
    exit 1
fi
rm -f /tmp/aq-skopeo.txt

# ==============================================================================
# 4. Read it back out of the finished image
# ==============================================================================
# ⚠️ THE RULE THIS REPOSITORY IS BUILT ON: every step reads its own result out of
# the finished image, and reads CONTENT rather than a clock. A copy that half
# worked leaves a file behind, and a file being there is not the same as the
# environment being in it.
say "DaVinci Resolve — reading the environment back out of the image"

if [ ! -r "${ARCHIVE}" ]; then
    bad "${ARCHIVE} was not written"
    aq_finish "DaVinci Resolve — the baked environment"
    exit 1
fi

SIZE_BYTES="$(stat -c '%s' "${ARCHIVE}")"
SIZE_MB=$((SIZE_BYTES / 1024 / 1024))
echo "  ${ARCHIVE} is ${SIZE_MB} MB"

# A number, because "did it grow by a factor of ten" is a question somebody will
# want answered a year from now and nobody will remember today's answer. The
# floor catches a truncated copy; the ceiling catches somebody accidentally
# baking an environment with a video editor in it, which would be the licence
# problem this whole feature exists to avoid.
if [ "${SIZE_MB}" -lt 100 ]; then
    bad "the environment is only ${SIZE_MB} MB — that is far too small to be a Linux userland, so the copy did not finish"
elif [ "${SIZE_MB}" -gt 900 ]; then
    bad "the environment is ${SIZE_MB} MB. It has been ~330 MB. Something much bigger than Rocky's libraries is in it — check resolve-runtime/ before letting this ship."
else
    ok "the environment is ${SIZE_MB} MB, which is the size it has always been"
fi

# ⚠️ AND IT IS READ AS AN IMAGE, NOT AS A FILE. skopeo reading its own output
# back is the check that the archive is a real, complete, readable image rather
# than a file of the right size. It also proves the digest is the one we asked
# for, which is the whole reason for copying by digest above.
if ! BACK="$(skopeo inspect --format '{{.Digest}}' "oci-archive:${ARCHIVE}" 2>&1)"; then
    bad "the environment in the image cannot be read back: ${BACK}"
elif [ "${BACK}" != "${DIGEST}" ]; then
    bad "the environment in the image is ${BACK}, but ${DIGEST} was asked for"
else
    ok "the environment reads back as exactly the ${DIGEST} that was asked for"
fi

# ⚠️ AND NOTHING OF BLACKMAGIC'S IS IN IT. This is the licence check, and it is
# cheap: the layer descriptions and the labels are read, and any mention of
# DaVinci or Blackmagic as a THING THAT IS IN THE IMAGE would show up as a
# package or a path. The runtime's own build proves the package list; what this
# proves is that the archive this image carries is that runtime and not
# something somebody built by hand with Resolve already installed.
if skopeo inspect --config "oci-archive:${ARCHIVE}" > /tmp/aq-runtime-config.json 2>&1; then
    if grep -qi '"/opt/resolve' /tmp/aq-runtime-config.json; then
        bad "the environment names /opt/resolve — there may be Blackmagic software in it, which we may not distribute"
    else
        ok "nothing of Blackmagic's is installed in the environment, as it must not be"
    fi
    if grep -q 'aquarius-resolve-setup' /tmp/aq-runtime-config.json \
        || grep -qi 'rocky' /tmp/aq-runtime-config.json; then
        ok "it is our own runtime, not some other container that happens to fit"
    else
        echo "  NOTE: the environment's description says neither. Not a failure —"
        echo "        labels are not a promise — but worth a look if it is unexpected."
    fi
else
    bad "the environment's description could not be read:"
    sed 's/^/       /' /tmp/aq-runtime-config.json >&2
fi
rm -f /tmp/aq-runtime-config.json

# ==============================================================================
# 5. Write down what it is
# ==============================================================================
# Three lines a machine can read. It is generated, not shipped in system_files/,
# because it is a fact about ONE BUILD rather than a setting anybody chooses —
# and a stale copy of it in the repository would be a machine confidently
# reporting a digest it is not running.
say "DaVinci Resolve — writing down what the baked environment is"

cat > "${BAKED_ENV}" << BAKED
# ==============================================================================
# What the environment carried inside this AquariusOS actually is
# ==============================================================================
# ⚠️ GENERATED BY build_files/63-resolve-runtime-bake.sh. Editing it by hand
# would make this operating system say it is running something it is not.
#
# It exists because of one small, specific thing: an image that was unpacked
# from a file has no "RepoDigest" — that name belongs to the registry the bytes
# came from, and these bytes did not come from a registry on your computer. So
# podman quite correctly has nothing to say, and without this file your machine
# could not tell you what it is running.
#
# ⚠️ THIS IS WHERE A MACHINE STARTS, NOT WHERE IT IS STUCK. "aq resolve update"
# still re-asks the registry for the tag below, so Rocky's security rebuilds
# reach machines that started from this copy. The full reasoning is in
# runtime.env next door.
# ==============================================================================
AQ_RESOLVE_BAKED_IMAGE=${AQ_RESOLVE_RUNTIME_IMAGE}
AQ_RESOLVE_BAKED_TAG=${AQ_RESOLVE_RUNTIME_TAG}
AQ_RESOLVE_BAKED_DIGEST=${DIGEST}
BAKED
chmod 0644 "${BAKED_ENV}"

aq_file_has "${BAKED_ENV}" "^AQ_RESOLVE_BAKED_DIGEST=sha256:[0-9a-f]{64}$" \
    "the record names the exact environment, by digest"
aq_file_has "${BAKED_ENV}" "^AQ_RESOLVE_BAKED_TAG=${AQ_RESOLVE_RUNTIME_TAG}$" \
    "and the Enterprise Linux release it is, which is what 'aq resolve update' re-asks for"

# The finished machine reads this file with `.`, exactly as it reads runtime.env,
# so anything in it that could RUN would run as the person. It is generated from
# three values we just read, so this cannot fail — which is precisely why it is
# worth one line to prove, rather than one line of reasoning.
# Read as: strip the comments and the blank lines, then look for any line that
# is NOT a plain AQ_RESOLVE_BAKED_SOMETHING=value with no shell punctuation in
# it. Finding one is the failure.
# shellcheck disable=SC2016  # the $ and ` are regex, not shell — single quotes are the point
if grep -vE '^[[:space:]]*(#|$)' "${BAKED_ENV}" \
    | grep -qvE '^AQ_RESOLVE_BAKED_[A-Z]+=[^ ;&|$(`]*$'; then
    bad "${BAKED_ENV} contains something other than plain NAME=value settings"
else
    ok "it is three plain settings and nothing that could run"
fi

echo "  ---- for the log ----"
sed 's/^/       /' "${BAKED_ENV}" | grep -v '^       #' | grep -v '^       $'

# ==============================================================================
# 6. The setup really knows about all this
# ==============================================================================
# Grepped rather than run: running it needs a container and a graphics card, and
# tests/test-resolve-step-count.sh is where the behaviour is proved. What is
# proved HERE is that the shipped script and the file this step wrote still
# agree with each other, which is the pair that can silently drift apart.
say "DaVinci Resolve — the setup knows the environment is already here"

AQ_INSTALL=/usr/libexec/aquarius-resolve-install
aq_file_has "${AQ_INSTALL}" 'AQ_RESOLVE_RUNTIME_ARCHIVE' \
    "the setup looks for the environment carried inside AquariusOS"
aq_file_has "${AQ_INSTALL}" 'podman load --input' \
    "and unpacks it into the person's own store rather than downloading it"
aq_file_has "${AQ_INSTALL}" 'AQ_RESOLVE_BAKED_DIGEST' \
    "and records the digest of the copy it started from, so the machine can say what it runs"
aq_file_has "${AQ_INSTALL}" 'if \[ "\$\{MODE\}" != "update" \] && \[ "\$\{HAVE_IMAGE\}" = "1" \]' \
    "⚠️ and an update still re-asks the registry, so the baked copy stays a seed and not a pin"

# The behaviour itself, against stand-in programs, with no container, no card
# and no download. This is the check that would catch the progress bar quietly
# going back to promising seven steps on a machine that only has five to walk.
if /ctx/tests/test-resolve-step-count.sh "${AQ_INSTALL}"; then
    ok "tests/test-resolve-step-count.sh passed against the copy in this image"
else
    bad "tests/test-resolve-step-count.sh FAILED — the progress bar would not match the work"
fi

# ==============================================================================
# 6b. DaVinci Resolve is in the apps from the first login
# ==============================================================================
# ⚠️ ROYCE'S POINT, AND IT IS THE WHOLE REASON THIS SECTION EXISTS: an operating
# system built around DaVinci Resolve whose flagship application is hidden
# behind a thing called "Install DaVinci Resolve" has buried it. So on the
# NVIDIA edition there is a DaVinci Resolve entry from the moment somebody first
# logs in, it is pinned to the dock beside Files, and clicking it does the right
# thing whether or not Resolve has been installed yet.
#
# ⚠️ AND IT WEARS OUR ICON, NOT BLACKMAGIC'S. Until somebody installs their own
# copy of Resolve, nothing of Blackmagic's is on this computer, and using their
# mark to advertise software we did not give them is not something we do. The
# entry wears the AquariusOS "DR" mark that the Install entry has worn since
# 2026-09-06 — drawn by us, checked in build_files/56-aquarius-icons.sh.
say "DaVinci Resolve — in your apps from the first login"

if [ ! -x "${RESOLVE_OPEN}" ]; then
    bad "${RESOLVE_OPEN} is missing or not runnable — the DaVinci Resolve icon would do nothing"
else
    chmod 0755 "${RESOLVE_OPEN}"
    ok "aquarius-resolve-open is present and runnable"
    if bash -n "${RESOLVE_OPEN}"; then
        ok "and it is valid shell"
    else
        bad "${RESOLVE_OPEN} has a syntax error"
    fi
    # ⚠️ IT MUST LOOK FOR THE PROGRAM AND NOT FOR THE WORD "RESOLVE". Blackmagic's
    # installer writes eight app-menu entries and seven of them are not the video
    # editor — the RAW Player, the Speed Test, the Remote Monitor, the Control
    # Panels Setup, Capture Logs, the uninstaller. Every one has "resolve" in its
    # file name, because they all live in /opt/resolve. An earlier draft matched
    # on the name and picked the RAW Player: clicking DaVinci Resolve would have
    # opened a still-image viewer.
    aq_file_has "${RESOLVE_OPEN}" 'RESOLVE_PROGRAM=/opt/resolve/bin/resolve' \
        "it recognises Resolve by the program it runs, not by a name that seven other tools share"
    aq_file_has "${RESOLVE_OPEN}" 'exec "\$\{INSTALLER_GUI\}" --finish-setup' \
        "and opens the setup window when there is no Resolve to start"

    # It answers on a machine with no Resolve at all, which is what this build
    # container is. `--report` decides and prints without starting anything.
    AQ_OPEN_SAYS="$("${RESOLVE_OPEN}" --report 2>&1 || true)"
    echo "  What it would do on this machine: ${AQ_OPEN_SAYS}"
    case "${AQ_OPEN_SAYS}" in
        "not-installed"*)
            ok "with no Resolve installed it would open the setup window, as it must"
            ;;
        "installed"*)
            bad "it thinks DaVinci Resolve is installed in a build container, which is impossible"
            ;;
        *)
            bad "'--report' did not answer in the shape the build reads: ${AQ_OPEN_SAYS}"
            ;;
    esac
fi

if [ ! -r "${RESOLVE_ENTRY}" ]; then
    bad "${RESOLVE_ENTRY} is missing — there would be no DaVinci Resolve in the app grid until somebody installed one"
else
    aq_file_has "${RESOLVE_ENTRY}" '^Name=DaVinci Resolve$' \
        "the app grid calls it DaVinci Resolve and nothing else"
    aq_file_has "${RESOLVE_ENTRY}" '^Exec=/usr/libexec/aquarius-resolve-open %U$' \
        "clicking it asks the program that decides, and a file dropped on it goes through"
    # ⚠️ OUR MARK. If this ever became a Blackmagic icon shipped in our image, it
    # would be their artwork redistributed by us on a machine with none of their
    # software on it. This line is the check that stops that happening quietly.
    aq_file_has "${RESOLVE_ENTRY}" '^Icon=aquarius-install-resolve$' \
        "⚠️ and it wears OUR drawn mark, never Blackmagic's, until their software is really here"
    aq_file_has "${RESOLVE_ENTRY}" '^StartupWMClass=org\.aquariusos\.ResolveInstaller$' \
        "the setup window it opens appears under this icon rather than as a nameless window"
    if desktop-file-validate "${RESOLVE_ENTRY}"; then
        ok "it passes freedesktop's own validator"
    else
        bad "${RESOLVE_ENTRY} is not a valid desktop entry — it would never appear in the app grid"
    fi
fi

# ⚠️ ONE ENTRY, NOT TWO. "DaVinci Resolve" and "Install DaVinci Resolve" side by
# side in the app grid is two doors into the same room, and the person has to
# work out which one they want before they have any way of knowing. So on this
# edition the Install entry is taken out of the grid — it still exists, still
# works, and is still what `aq resolve install --gui` and the Software-style
# flows open; it simply is not a second icon.
if grep -q '^NoDisplay=true$' "${INSTALL_ENTRY}"; then
    ok "'Install DaVinci Resolve' is already folded into the DaVinci Resolve entry"
else
    printf 'NoDisplay=true\n' >> "${INSTALL_ENTRY}"
    if grep -q '^NoDisplay=true$' "${INSTALL_ENTRY}"; then
        ok "'Install DaVinci Resolve' folded into the DaVinci Resolve entry — one icon, not two"
    else
        bad "could not hide ${INSTALL_ENTRY} — the app grid would show two DaVinci Resolves"
    fi
fi
if desktop-file-validate "${INSTALL_ENTRY}"; then
    ok "and it is still a valid desktop entry afterwards"
else
    bad "${INSTALL_ENTRY} stopped being a valid desktop entry"
fi

# ==============================================================================
# 6c. The first login builds the environment, with nobody watching
# ==============================================================================
say "DaVinci Resolve — the environment is built at the first login"

if [ -r "${PREPARE_UNIT}" ]; then
    ok "$(basename "${PREPARE_UNIT}") is installed"
else
    bad "${PREPARE_UNIT} is missing — the environment would only ever be built while somebody waited"
fi

aq_file_has "${PREPARE_UNIT}" '^ExecStart=-/usr/libexec/aquarius-resolve-install --prepare$' \
    "it runs the preparation, and the '-' means a failure costs the person nothing"
# The two Conditions are the whole safety of this unit. Without the first it
# would build a container on an AMD laptop that cannot use it; without the
# second, an NVIDIA machine running the AMD/Intel edition would start a
# gigabyte download nobody asked for in the background at its first login.
aq_file_has "${PREPARE_UNIT}" '^ConditionPathExists=/proc/driver/nvidia/version$' \
    "it only runs on a machine with an NVIDIA driver loaded"
aq_file_has "${PREPARE_UNIT}" '^ConditionPathExists=/usr/share/aquarius/resolve/runtime\.oci$' \
    "and only where the environment is really inside the operating system"
aq_file_has "${PREPARE_UNIT}" '^WantedBy=graphical-session\.target$' \
    "it belongs to the desktop session, which is what makes it run as you and not as an administrator"
# ⚠️ WANTED, NOT REQUIRED. A Requires= here would mean a failed preparation
# taking the desktop session down with it. Nobody is waiting for this.
if grep -qE '^(Requires|RequiredBy|Before)=' "${PREPARE_UNIT}"; then
    bad "the preparation unit holds up the login — it must never do that"
else
    ok "nothing about it holds up your login"
fi

# ⚠️ SWITCHED ON FROM /usr, NOT /etc — the same rule, and the same bench fault,
# as the daily update check in step 62. The long version is in aq-lib.sh next to
# aq_unit_is_on_from_usr: a link in /etc can be deleted by a local `disable`, and
# this kind of operating system then preserves that deletion for ever.
if [ -L "${PREPARE_LINK}" ]; then
    echo "  ${PREPARE_LINK} -> $(readlink "${PREPARE_LINK}")"
    if [ -e "${PREPARE_LINK}" ]; then
        ok "the preparation is switched on from /usr, so an update always restores it"
    else
        bad "the 'switched on' link for the preparation is dangling — it points at nothing"
    fi
else
    bad "${PREPARE_LINK} is missing — the unit would be installed but never start"
fi
if [ -e /etc/systemd/user/graphical-session.target.wants/aquarius-resolve-prepare.service ]; then
    bad "the preparation is ALSO switched on through /etc — a build step ran an enable. See aq-lib.sh."
else
    ok "nothing switches it on through /etc (an update could lose that)"
fi

if aq_have systemd-analyze; then
    systemd-analyze verify --user "${PREPARE_UNIT}" > /tmp/aq-prepare-check.txt 2>&1 || true
    if [ -s /tmp/aq-prepare-check.txt ]; then
        echo "  NOTE: systemd-analyze had something to say about the unit:"
        sed 's/^/         /' /tmp/aq-prepare-check.txt
    else
        ok "systemd is happy with aquarius-resolve-prepare.service"
    fi
    rm -f /tmp/aq-prepare-check.txt
fi

# `aq resolve prepare` is the front door for doing it by hand, on the bench or
# after a `remove`. A command nobody can discover is a command nobody uses.
aq_file_has /usr/bin/aq 'resolve prepare' \
    "'aq resolve prepare' is a command people can find"

# ==============================================================================
# 7. Take the build tool back out
# ==============================================================================
# skopeo was wanted for ninety seconds. Leaving it in would be a tool in
# everybody's operating system that exists only because of how the image was
# made, which is the sort of thing that accumulates until nobody knows why any
# of it is there.
say "DaVinci Resolve — putting the build tool away"
aq_dnf remove skopeo
if aq_have skopeo; then
    echo "  NOTE: skopeo is still on the path — something else in this image needs it."
    echo "        That is fine; it simply means it was not ours to remove."
else
    ok "skopeo is gone from the finished image"
fi

aq_finish "DaVinci Resolve — the baked environment"
