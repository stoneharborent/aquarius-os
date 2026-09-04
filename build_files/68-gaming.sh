#!/usr/bin/bash
# ==============================================================================
# STEP 7e — the gaming layer
# ==============================================================================
# WHAT THIS STEP IS FOR, IN PLAIN ENGLISH
#
# AquariusOS is a creator's machine first. It is also meant to be a very good
# gaming PC, because the person who edits video on this computer in the
# afternoon plays games on it in the evening, and having to reboot into Windows
# for that would make the whole project pointless.
#
# This step is what makes that true out of the box: Steam, the pieces Steam
# needs to run Windows games through Proton, a performance overlay, and drivers
# for Xbox controllers. Everything here is a system package, baked into BOTH
# images — the AMD/Intel one and the NVIDIA one — because a gaming machine that
# needs a setup guide before it can run a game is not a gaming machine.
#
# ------------------------------------------------------------------------------
# WHAT IS DELIBERATELY NOT HERE
# ------------------------------------------------------------------------------
#   * No "Game Mode" session at the login screen, and no boot-to-Steam.
#   * No handheld support — no Steam Deck / ROG Ally / Legion Go device
#     drivers, no gyro, no TDP sliders, no fan curves.
#
# Both are Royce's standing decision 6 of 2026-09-02, and they are not an
# oversight. Valve's SteamOS and Bazzite already do handhelds properly, and
# doing it properly means testing thirty devices we do not own. The reasoning
# is written out in docs/base-distro-reassessment-2026-09.md, section 4.
#
# ------------------------------------------------------------------------------
# WHERE THE SOFTWARE COMES FROM, AND THE ONE RULE ABOUT IT
# ------------------------------------------------------------------------------
# Three sources, in order of preference:
#
#   Fedora        gamescope, gamemode, MangoHud, vkBasalt, protontricks,
#                 winetricks, steam-devices, and the 32-bit graphics libraries.
#                 Everything that can come from Fedora does.
#
#   Terra         umu-launcher, and Steam. Terra (repos.fyralabs.com) is Fyra
#                 Labs' Fedora add-on repository and it is where Bazzite gets
#                 its Steam. (RPM Fusion, already enabled here for the codecs,
#                 turns out to carry the very same Steam release — see the note
#                 further down. umu is Terra's alone, so Terra is not optional.)
#
#   Universal     The Xbox controller kernel modules (xone and xpadneo),
#   Blue          already compiled and already signed — exactly the same
#                 arrangement, and the same box, as the virtual camera in
#                 step 6c.
#
# ⚠️ THE RULE ABOUT TERRA, AND IT MATTERS MORE THAN IT LOOKS.
#
# Terra ships newer versions of some packages than Fedora does. If we left it
# switched on, a future `dnf install` — ours or a user's — could silently take
# a Terra build of something instead of Fedora's, and the machine would drift
# away from the base we test on. For a gaming distribution that is a feature.
# For a machine somebody's paid video work lives on it is a liability.
#
# So Terra is added, then SWITCHED OFF, and switched on again only for the
# length of the one command that installs Steam and umu. That is what Bazzite
# does for the same reason, and it means Terra can never replace a Fedora
# package behind our backs.
#
# ⚠️ AND WE DO NOT TAKE TERRA'S MESA. Terra publishes `terra-release-mesa`,
# which points the machine at a Valve-patched Mesa graphics driver. Bazzite
# uses it, and for pure gaming it is the better choice — it lands Valve's game
# fixes months early. We keep Fedora's Mesa anyway, because this machine's job
# is colour-accurate video work and a graphics driver that changes on a gaming
# schedule is the wrong risk to take with it. A game that needs the newest Mesa
# is a bad afternoon; a graphics driver regression in the middle of a client
# grade is a bad week. The check at the bottom of this file proves we still
# have Fedora's.
#
# ------------------------------------------------------------------------------
# ⚠️ THIS STEP MUST RUN AFTER 60-nvidia.sh
# ------------------------------------------------------------------------------
# Two reasons, both the same reason really:
#   1. Step 6 sometimes REPLACES this image's kernel. The controller modules
#      belong to one exact kernel, so the question has to be asked after the
#      swap, not before.
#   2. The 32-bit NVIDIA libraries come out of the same box step 6 uses, and
#      whether we want them at all depends on which image this is.
# ==============================================================================

# shellcheck source=build_files/aq-lib.sh
source "$(dirname "$0")/aq-lib.sh"

NVIDIA="${NVIDIA:-0}"
AKMODS="/ctx-akmods"
NVIDIA_BOX="/ctx-nvidia"
GAMING_DIR="/usr/share/aquarius/gaming"
CONTROLLER_STAMP="${GAMING_DIR}/controllers.txt"

install -d -m 0755 "${GAMING_DIR}"

# ==============================================================================
# 1. Terra — added, then switched off
# ==============================================================================
# The bootstrap is a chicken-and-egg: Terra's repository description and its
# signing key both live INSIDE a package that comes from Terra. So the very
# first install has to reach the repository by hand (`--repofrompath`) and
# without a key check (`--nogpgcheck`), because at that instant the key is not
# on the machine yet. Every install after this one is signature-checked
# normally. This is Terra's own documented instruction:
# https://developer.fyralabs.com/terra/installing
say "Adding Terra (the repository Steam comes from)"

FEDORA="$(rpm -E %fedora)"
echo "Fedora release in this image: ${FEDORA}"

# The single quotes below are deliberate and shellcheck's SC2016 is wrong here:
# $releasever is dnf's own variable, not the shell's, and dnf has to receive it
# unexpanded so that it fills in the Fedora version itself.
# shellcheck disable=SC2016
aq_dnf install --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release

aq_installed terra-release

# The key really has to be on disk now, or every later install from Terra fails
# with a signature error that reads like a network problem.
AQ_TERRA_KEY="/etc/pki/rpm-gpg/RPM-GPG-KEY-terra${FEDORA}"
if [ -r "${AQ_TERRA_KEY}" ]; then
    ok "Terra's signing key is installed (${AQ_TERRA_KEY})"
else
    echo "Keys that ARE in /etc/pki/rpm-gpg:"
    ls -1 /etc/pki/rpm-gpg/ | sed 's/^/       /'
    bad "Terra's signing key for Fedora ${FEDORA} is not there — installs from Terra would fail their signature check"
fi

# ⚠️ THE PART THAT MAKES TERRA SAFE. Off by default, on for one command at a
# time. This setting travels with the image, so it is also how the finished
# operating system behaves on a user's machine.
say "Switching Terra off again, so it can only ever be used on purpose"
aq_dnf config-manager setopt terra.enabled=0 terra-source.enabled=0

aq_dnf repolist --enabled | awk 'NR > 1 { print $1 }' > /tmp/aq-enabled.txt
if grep -qFx 'terra' /tmp/aq-enabled.txt; then
    bad "Terra is still enabled — it could replace Fedora packages without anybody asking"
else
    ok "Terra is present but switched off"
fi
rm -f /tmp/aq-enabled.txt

# And the Mesa half of Terra must never have arrived. `terra-release-mesa` is a
# separate package; nothing above asks for it, and this check is here so that a
# future edit which quietly adds it cannot go unnoticed.
if rpm -q terra-release-mesa > /dev/null 2>&1; then
    bad "terra-release-mesa is installed — this image would take Valve-patched Mesa instead of Fedora's, which is not the trade we chose"
else
    ok "terra-release-mesa is NOT installed — the graphics driver stays Fedora's"
fi

# Prove the per-command switch works BEFORE relying on it, so that a change in
# dnf's option name fails here with an explanation rather than three commands
# later with "no match for argument: steam".
#
# dnf5 spells it `--enable-repo`; dnf4 spelled it `--enablerepo` and dnf5 still
# understands that too. Rather than betting on which, the two are tried in
# order and the one that answers is the one used from here on.
say "Checking Terra can be switched on for one command"
AQ_TERRA_FLAG=""
for flag in --enable-repo=terra --enablerepo=terra; do
    if aq_dnf repoquery "${flag}" \
        --queryformat '%{name}-%{evr} from %{reponame}\n' steam umu-launcher \
        > /tmp/aq-terra-probe.txt 2>&1; then
        AQ_TERRA_FLAG="${flag}"
        break
    fi
    echo "  ${flag} did not work:"
    sed 's/^/       /' /tmp/aq-terra-probe.txt
done
if [ -n "${AQ_TERRA_FLAG}" ]; then
    sed 's/^/       /' /tmp/aq-terra-probe.txt
    ok "Terra answers when it is switched on for one command (${AQ_TERRA_FLAG})"
else
    echo "AQUARIUS ERROR: Terra could not be switched on for a single command." >&2
    echo "                Neither --enable-repo nor --enablerepo worked, which" >&2
    echo "                means either dnf has renamed the option again or Terra" >&2
    echo "                is unreachable from this build. The output above says" >&2
    echo "                which of the two it is." >&2
    exit 1
fi
rm -f /tmp/aq-terra-probe.txt

# ==============================================================================
# 2. The gaming software Fedora already packages
# ==============================================================================
# WHAT EACH ONE IS, because none of these names explain themselves:
#
#   gamescope     A tiny window manager that a game runs INSIDE. It gives the
#                 game its own private screen, so the game can think it is at
#                 1920x1080 while your monitor stays at its real resolution,
#                 and it can limit frame rate and upscale cleanly. It is what
#                 the Steam Deck runs everything in.
#   gamemode      A small service a game can ask for a temporary performance
#                 boost from — the processor stops power-saving while the game
#                 is running, and goes back to normal the moment it quits.
#   mangohud      The overlay that shows frame rate, temperatures and load in
#                 the corner of a game. Off unless asked for; see below.
#   vkBasalt      Optional picture sharpening and colour effects for games.
#   protontricks  Fixes for individual Windows games running under Proton.
#   winetricks    The same idea, one layer down. protontricks needs it.
#   steam-devices The USB rules that let a controller, a Steam Controller or a
#                 VR headset be used without administrator rights. Steam pulls
#                 this in anyway; it is named here so it is ours on purpose.
#
# The 32-bit ones are not a mistake. A great many Windows games — and Steam's
# own runtime — are still 32-bit programs, and a 64-bit Linux cannot run them
# without a parallel set of 32-bit graphics libraries. Missing these is the
# classic "the game launches and immediately closes" on Linux.
say "The gaming software Fedora packages"

aq_dnf install \
    gamescope \
    gamemode \
    mangohud \
    mangohud.i686 \
    vkBasalt \
    vkBasalt.i686 \
    protontricks \
    winetricks \
    steam-devices

say "The 32-bit graphics libraries old and Windows games need"
aq_dnf install \
    mesa-dri-drivers.i686 \
    mesa-vulkan-drivers.i686 \
    mesa-libGL.i686 \
    libglvnd-glx.i686 \
    vulkan-loader.i686

# ==============================================================================
# 3. Steam and umu, from Terra, with Terra on for exactly this command
# ==============================================================================
# WHY STEAM IS A SYSTEM PACKAGE AND NOT A FLATPAK, since every other app on
# this machine is a Flatpak:
#
#   * A Flatpak Steam is sandboxed, and the sandbox is where Linux gaming goes
#     wrong: controllers it cannot see, drives it cannot reach, NVIDIA driver
#     versions it has to shadow separately, and Proton prefixes in a place
#     nothing else can get at.
#   * Steam is the piece that has to reach the graphics card, the controller
#     and the filesystem most directly. Bazzite ships it as an RPM for exactly
#     these reasons and so do we.
#
# umu-launcher is Valve's and the community's shared way of running a Windows
# game through Proton from OUTSIDE Steam — it is what Lutris and Heroic use
# under the hood, so having it here means those two work properly the moment
# somebody installs them.
say "Steam and umu-launcher, with Terra switched on for this one command"
aq_dnf install "${AQ_TERRA_FLAG}" steam umu-launcher

# ⚠️ WHICH REPOSITORY STEAM ACTUALLY CAME FROM, and why we stopped caring.
#
# RPM Fusion — which this image has had enabled since step 1, for the codecs —
# packages Steam as well, and on 2026-09-04 the first build of this step showed
# both repositories offering THE SAME RELEASE, steam-1.0.0.87-1.fc44, with dnf
# taking RPM Fusion's copy on the tie.
#
# That is a fine outcome and not worth engineering around. Both are the same
# upstream Steam, both are already trusted sources in this image, and pinning
# one would mean fighting dnf every time the other happened to be a day ahead.
# Terra is still switched on for this command because umu-launcher is only
# there, and umu is what Lutris and Heroic run Windows games through.
#
# So the source is printed rather than judged: worth being able to read in a
# build log, not worth failing a build over.
say "Where Steam and umu came from"
rpm -q --queryformat '       %{NAME}-%{VERSION}-%{RELEASE}  (packaged by: %{VENDOR})\n' \
    steam umu-launcher 2>&1 || true

aq_installed steam umu-launcher gamescope gamemode mangohud vkBasalt protontricks winetricks steam-devices

# ==============================================================================
# 4. THE MESA CHECK — the one that proves the Terra rule held
# ==============================================================================
# If Terra ever did replace Fedora's graphics driver, everything above would
# still install perfectly and nothing would look wrong until a colour grade
# came out different. So the question is asked directly, of the package
# database, in the only way that cannot be fooled: who made it.
say "The graphics driver is still Fedora's"
for pkg in mesa-dri-drivers mesa-vulkan-drivers mesa-libGL; do
    AQ_VENDOR="$(rpm -q --queryformat '%{VENDOR}' "${pkg}" 2> /dev/null || echo '(missing)')"
    echo "  ${pkg}: ${AQ_VENDOR}"
    case "${AQ_VENDOR}" in
        *Fedora*) ok "${pkg} is Fedora's" ;;
        *) bad "${pkg} says its vendor is '${AQ_VENDOR}' — something replaced Fedora's Mesa" ;;
    esac
done

# ==============================================================================
# 5. The 32-bit NVIDIA libraries (NVIDIA image only)
# ==============================================================================
# A 32-bit Windows game running under Proton on an NVIDIA card needs a 32-bit
# copy of NVIDIA's OpenGL and Vulkan libraries. Step 6 installs only the 64-bit
# ones, because until now nothing needed the others.
#
# They are already in the box step 6 downloaded — Universal Blue put them there
# for this exact purpose — so this costs no extra download, only the install.
# Nothing here touches the driver itself or the kernel module.
case "${NVIDIA}" in
    1)
        say "The 32-bit NVIDIA libraries, so 32-bit games can use the card"
        AQ_I686_RPMS="$(find "${NVIDIA_BOX}/rpms/nvidia" -name '*.i686.rpm' 2> /dev/null | sort || true)"
        if [ -z "${AQ_I686_RPMS}" ]; then
            echo "There are no 32-bit NVIDIA packages in the box. Everything in it:"
            find "${NVIDIA_BOX}/rpms/nvidia" -name '*.rpm' -printf '  %f\n' 2> /dev/null | head -40 || true
            bad "no 32-bit NVIDIA libraries — 32-bit Windows games would fail to start on this image"
        else
            echo "Installing:"
            printf '%s\n' "${AQ_I686_RPMS}" | sed 's|.*/|       |'
            # shellcheck disable=SC2086
            aq_dnf install ${AQ_I686_RPMS}
            aq_installed nvidia-driver-libs
            if rpm -q --queryformat '%{ARCH}\n' nvidia-driver-libs | grep -qx 'i686'; then
                ok "the 32-bit NVIDIA libraries are installed"
            else
                bad "nvidia-driver-libs is installed but not in its 32-bit form"
            fi
            echo "Both architectures of nvidia-driver-libs now present:"
            rpm -q --queryformat '       %{NAME}-%{VERSION}.%{ARCH}\n' nvidia-driver-libs
        fi
        ;;
    0)
        say "The AMD / Intel image — no NVIDIA libraries to add"
        echo "Mesa's own 32-bit drivers went in above and are all this image needs."
        ;;
esac

# ==============================================================================
# 6. Xbox controller support (both images)
# ==============================================================================
# WHAT LINUX ALREADY DOES BY ITSELF, so it is clear what is being added:
#
#   * PlayStation controllers — DualShock 4 and DualSense — work over USB and
#     Bluetooth with no help at all. The driver is in the kernel.
#   * An Xbox controller plugged in with a USB cable works with the kernel's
#     own `xpad` driver.
#
# WHAT IT DOES NOT DO:
#
#   * The Xbox Wireless Adapter — the little USB dongle that comes with, or is
#     sold for, Xbox controllers — is not supported by the kernel at all.
#     `xone` is the driver for it.
#   * Xbox controllers over Bluetooth work, badly: wrong button mapping on some
#     models, no rumble, and a battery level nothing can read. `xpadneo` is the
#     driver that fixes all three.
#
# Both are kernel modules, and a kernel module is built against ONE EXACT
# kernel. This is the same problem as the NVIDIA driver and the virtual camera,
# and it gets the same answer: Universal Blue's box of already-compiled,
# already-signed modules (ghcr.io/ublue-os/akmods), which is the same box step
# 6c takes the virtual camera from and is signed with the key this image
# already trusts.
#
# AND THE SAME HONESTY RULE. If the box was built for a different kernel than
# this image runs — which happens for a day or two after a Fedora kernel update
# — we do NOT install it and we do NOT change which kernel AquariusOS ships for
# the sake of a controller. The feature is left out, written down in
# /usr/share/aquarius/gaming/controllers.txt, and the next day's build has it.
# Every other controller keeps working either way.
say "Xbox controller drivers"

AQ_KVER="$(find /usr/lib/modules -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort | head -1)"
echo "  this image runs kernel: ${AQ_KVER}"

# Written from every path out of this section, so the file always exists and
# always says something true.
XONE_STATUS="unavailable"
XPADNEO_STATUS="unavailable"
CONTROLLER_NOTE="not attempted"

install_controller_kmod() { # install_controller_kmod <name> <module file pattern> <what it is for>
    local name="$1" modpat="$2" purpose="$3"
    local kmod common requires

    echo
    echo "--- ${name} — ${purpose} ---"

    kmod="$(find "${AKMODS}" -name "kmod-${name}-*.rpm" 2> /dev/null | sort | head -1)"
    if [ -z "${kmod}" ]; then
        echo "  There is no kmod-${name} package in Universal Blue's box."
        echo "  Everything that IS in it:"
        find "${AKMODS}" -name 'kmod-*.rpm' -printf '    %f\n' 2> /dev/null | head -40 || true
        return 1
    fi
    echo "  found: $(basename "${kmod}")"

    # The package's own metadata is the honest answer to "which kernel is this
    # for" — a file name is a guess, a Requires line is a fact written by the
    # tool that built it.
    requires="$(rpm -qp --requires "${kmod}" 2> /dev/null || true)"
    if ! printf '%s\n' "${requires}" | grep -qF "${AQ_KVER}"; then
        echo "  It was built for a different kernel than this image runs."
        echo "  It says it needs:"
        printf '%s\n' "${requires}" | sed 's/^/    /'
        echo "  Leaving it out rather than shipping a module that cannot load."
        return 1
    fi
    echo "  it was built for ${AQ_KVER} — the kernel this image runs"

    # The -kmod-common package carries the parts that are not the module
    # itself: the firmware the Xbox dongle needs, and the settings files. The
    # module alone is not a working driver.
    common="$(find "${AKMODS}" -name "${name}-kmod-common-*.rpm" 2> /dev/null | sort | head -1)"
    if [ -n "${common}" ]; then
        echo "  and its settings/firmware package: $(basename "${common}")"
        aq_dnf install "${common}" "${kmod}"
    else
        echo "  NOTE no ${name}-kmod-common package in the box — installing the module alone."
        aq_dnf install "${kmod}"
    fi

    # An RPM can install perfectly and file its module under a kernel that is
    # not in this image. The only question that matters is whether the module
    # is where THIS kernel will look for it.
    #
    # Written to a file first rather than piped into grep, for the reason
    # spelled out at aq_output_has() in aq-lib.sh: `find | grep -q` reports
    # FAILURE when it succeeds, because grep exits early and find dies of a
    # broken pipe. That trap cost us the first build of the restart.
    find "/usr/lib/modules/${AQ_KVER}" -name "${modpat}" > /tmp/aq-kmod-files.txt 2> /dev/null || true
    if [ -s /tmp/aq-kmod-files.txt ]; then
        echo "  the module is on disk where the kernel looks:"
        sed 's/^/    /' /tmp/aq-kmod-files.txt
    else
        echo "  AQUARIUS NOTE: the package installed but no ${modpat} is under"
        echo "                 /usr/lib/modules/${AQ_KVER}. Not usable."
        rm -f /tmp/aq-kmod-files.txt
        return 1
    fi
    rm -f /tmp/aq-kmod-files.txt

    # What the settings package actually dropped on the system. Printed rather
    # than judged: these files decide whether the driver co-operates with the
    # kernel's own xpad driver or replaces it, and that is worth being able to
    # read in a build log a year from now.
    if [ -n "${common}" ]; then
        echo "  what the settings package installed:"
        rpm -ql "$(rpm -qp --queryformat '%{NAME}' "${common}" 2> /dev/null)" 2> /dev/null \
            | grep -E 'modprobe.d|udev|firmware' | sed 's/^/    /' || true
    fi
    return 0
}

if [ ! -d "${AKMODS}" ] || [ -z "$(ls -A "${AKMODS}" 2> /dev/null || true)" ]; then
    echo "Universal Blue's module box is empty or was not mounted."
    CONTROLLER_NOTE="The pre-built module box was not available to this build."
else
    if install_controller_kmod xone 'xone_*.ko*' "the Xbox Wireless Adapter (the USB dongle)"; then
        XONE_STATUS="installed"
    fi
    if install_controller_kmod xpadneo 'hid-xpadneo.ko*' "Xbox controllers over Bluetooth"; then
        XPADNEO_STATUS="installed"
    fi

    if [ "${XONE_STATUS}" = "installed" ] || [ "${XPADNEO_STATUS}" = "installed" ]; then
        # A module added after the kernel's index was built is invisible until
        # the index is rebuilt. Skip this and the file is on disk and the
        # machine still says "module not found".
        say "Rebuilding the kernel's module index"
        depmod -a "${AQ_KVER}"
        for m in xone_dongle hid-xpadneo; do
            if grep -q "${m}" "/usr/lib/modules/${AQ_KVER}/modules.dep" 2> /dev/null; then
                ok "the kernel's index knows about ${m}"
            fi
        done
        CONTROLLER_NOTE="Taken from Universal Blue's signed module box, built for kernel ${AQ_KVER}."
    else
        echo
        echo "  ---------------------------------------------------------------"
        echo "  THE XBOX DRIVERS ARE NOT IN THIS IMAGE, AND THAT IS NOT A BUG."
        echo "  ---------------------------------------------------------------"
        echo "  This image runs kernel ${AQ_KVER} and the ready-made modules"
        echo "  were built for a different one, so they would not load."
        echo ""
        echo "  This happens for a day or two after a Fedora kernel update."
        echo "  Building again tomorrow fixes it; nothing needs changing."
        echo ""
        echo "  Everything else still works: PlayStation controllers over USB"
        echo "  and Bluetooth, Xbox controllers over a USB cable, and every"
        echo "  generic gamepad. Only the Xbox wireless dongle and the nicer"
        echo "  Xbox Bluetooth behaviour are missing."
        echo "  ---------------------------------------------------------------"
        CONTROLLER_NOTE="Kernel skew: this image runs ${AQ_KVER} and the pre-built modules were made for another kernel. Rebuild in a day or two."
    fi
fi

# The honest answer to "do the Xbox drivers work on this image?", in a file
# anybody can read. Same arrangement as the virtual camera's stamp, for the
# same reason: an image that is missing one optional piece and says so is far
# better than one that lies.
{
    echo "# How the AquariusOS Xbox controller drivers turned out on this image."
    echo "# Written by build_files/68-gaming.sh. Read by CI and by docs."
    echo "kernel=${AQ_KVER}"
    echo "xone=${XONE_STATUS}"
    echo "xpadneo=${XPADNEO_STATUS}"
    printf 'note=%s\n' "${CONTROLLER_NOTE}"
} > "${CONTROLLER_STAMP}"
chmod 0644 "${CONTROLLER_STAMP}"
echo
echo "Wrote ${CONTROLLER_STAMP}:"
sed 's/^/       /' "${CONTROLLER_STAMP}"

# The USB rules that let a controller be used without administrator rights.
# These come from steam-devices and they are the difference between "Steam sees
# my pad" and "Steam sees nothing and there is no error message".
say "The controller USB rules"
AQ_RULES="$(rpm -ql steam-devices 2> /dev/null | grep 'rules.d' | head -3 || true)"
if [ -n "${AQ_RULES}" ]; then
    printf '%s\n' "${AQ_RULES}" | sed 's/^/       /'
    ok "the controller USB rules are installed"
else
    bad "steam-devices installed no udev rules — controllers would need administrator rights"
fi

# ==============================================================================
# 7. Settings — and the two we deliberately do NOT change
# ==============================================================================

# ------------------------------------------------------------------------------
# vm.max_map_count — asked, not assumed
# ------------------------------------------------------------------------------
# A "memory map" is a region of memory a program has asked the kernel for, and
# Linux limits how many one program may have. Games running through Proton ask
# for a very large number of them, and the historic Linux limit (65530) is far
# too low: the game does not crash cleanly, it stutters and then dies, which is
# the hardest kind of fault to diagnose. Every gaming distribution raises it to
# 1048576.
#
# systemd has raised it to that value by default since version 255, so on
# Fedora 44 there is very likely nothing to do — but "very likely" is not a
# thing to leave a gaming machine resting on, so the answer is read out of the
# actual settings files rather than assumed.
say "The memory-map limit games need"
AQ_MMAP_MIN=1048576
AQ_MMAP_FOUND=0
grep -rhs '^[[:space:]]*vm\.max_map_count' \
    /usr/lib/sysctl.d /etc/sysctl.d /usr/local/lib/sysctl.d /etc/sysctl.conf \
    2> /dev/null > /tmp/aq-mmap.txt || true
grep -rls '^[[:space:]]*vm\.max_map_count' \
    /usr/lib/sysctl.d /etc/sysctl.d 2> /dev/null | sed 's/^/  set in: /' || true
if [ -s /tmp/aq-mmap.txt ]; then
    sed 's/^/       /' /tmp/aq-mmap.txt
    AQ_MMAP_FOUND="$(awk -F= '{gsub(/[^0-9]/,"",$2); if ($2+0 > m) m=$2+0} END {print m+0}' /tmp/aq-mmap.txt)"
fi
echo "  highest value anything already sets: ${AQ_MMAP_FOUND}"
if [ "${AQ_MMAP_FOUND}" -ge "${AQ_MMAP_MIN}" ]; then
    ok "already at least ${AQ_MMAP_MIN} — nothing for us to set"
else
    echo "  Too low for Proton. Setting it ourselves."
    install -d -m 0755 /usr/lib/sysctl.d
    cat > /usr/lib/sysctl.d/60-aquarius-gaming.conf << EOF
# AquariusOS — the memory-map limit Windows games need under Proton.
#
# Linux limits how many memory regions one program may hold. The old default
# (65530) is far below what games running through Proton ask for, and going
# over it does not fail cleanly: the game stutters and then dies.
#
# 1048576 is what every gaming distribution uses and what systemd itself sets
# by default from version 255 onward. This file only exists because, when
# AquariusOS was built, nothing on this image was setting it.
vm.max_map_count = ${AQ_MMAP_MIN}
EOF
    aq_file_has /usr/lib/sysctl.d/60-aquarius-gaming.conf \
        "vm.max_map_count = ${AQ_MMAP_MIN}" "the memory-map limit is raised for Proton"
fi
rm -f /tmp/aq-mmap.txt

# ------------------------------------------------------------------------------
# gamemode — nothing to switch on, and that is the correct answer
# ------------------------------------------------------------------------------
# gamemode is started ON DEMAND: a game (or MangoHud, or Lutris) asks for it
# over D-Bus, D-Bus starts the service, and it stops again afterwards. Enabling
# the service at login would be wrong — it would run all day doing nothing —
# and it is a very easy mistake to make, so this is written down.
say "gamemode (started on demand, never enabled)"
AQ_GM_DBUS="/usr/share/dbus-1/services/com.feralinteractive.GameMode.service"
if [ -r "${AQ_GM_DBUS}" ]; then
    ok "gamemode is wired to start on demand"
    sed 's/^/       /' "${AQ_GM_DBUS}"
else
    echo "  Files gamemode installed that look like services:"
    rpm -ql gamemode | grep -E 'systemd|dbus' | sed 's/^/       /' || true
    bad "gamemode has no D-Bus activation file — a game asking for it would get nothing"
fi

# ------------------------------------------------------------------------------
# MangoHud — installed, and OFF
# ------------------------------------------------------------------------------
# A performance overlay permanently stuck over every game (and every 3D
# application, including Blender) is not a default anybody wants. MangoHud is
# only visible when it is asked for — `mangohud %command%` in a game's Steam
# launch options — and this check makes sure nothing in the image has quietly
# switched it on globally.
say "MangoHud is installed but switched off"
AQ_MH_ON="$(grep -rls 'MANGOHUD=1\|^[[:space:]]*fps_limit\|^[[:space:]]*legacy_layout' \
    /usr/lib/environment.d /etc/environment.d /usr/share/MangoHud /etc/MangoHud.conf \
    2> /dev/null || true)"
if [ -z "${AQ_MH_ON}" ]; then
    ok "nothing turns MangoHud on by itself"
else
    echo "${AQ_MH_ON}" | sed 's/^/       /'
    bad "something switches MangoHud on for everything — it should only appear when asked for"
fi

# ------------------------------------------------------------------------------
# gamescope and CAP_SYS_NICE — Fedora's decision, not ours, and we leave it
# ------------------------------------------------------------------------------
# gamescope asks for a permission called CAP_SYS_NICE, which lets it raise its
# own scheduling priority. It is worth knowing that this permission has a
# history: on NVIDIA cards specifically it has been reported to make gamescope
# pick the wrong graphics card and refuse to start
# (ValveSoftware/gamescope #521, and #1370 for the general case), because a
# program holding an extra capability has part of its environment stripped by
# the loader for security — including some of the variables that tell a Vulkan
# program which card to use.
#
# ⚠️ AND FEDORA GRANTS IT ANYWAY, IN THE PACKAGE ITSELF. We found this out by
# checking, on 2026-09-04: `getcap /usr/bin/gamescope` reports
# `cap_sys_nice=ep` on a freshly built image, and it is there because the RPM
# declares it, not because anything in this build asked for it.
#
# So there is no decision for us to take here, only one not to fight. Stripping
# a capability that Fedora's own package ships would be us overriding the
# distribution on every build, for a fault we have not actually seen on our
# hardware. If gamescope ever does misbehave on the bench's 4090, this is the
# first thing to suspect and `sudo setcap -r /usr/bin/gamescope` is the
# one-line test — that is written up in docs/restart/gaming.md.
#
# What this check is for, then, is narrower and more useful: to notice if
# anything in OUR build ever starts granting capabilities of its own. So the
# question asked is not "does gamescope have capabilities" but "did they come
# from the package". Content, not assumption.
say "gamescope's permissions come from Fedora's package, not from us"
# `rpm -q --filecaps` is rpm's own listing of which files in a package carry
# POSIX capabilities. Asking rpm rather than assembling the answer out of two
# separate tags avoids the case where the two lists are different lengths and
# the query fails outright — which would look exactly like "the package
# declares nothing".
AQ_DECLARED_CAPS="$(rpm -q --filecaps gamescope 2> /dev/null \
    | awk '$1 == "/usr/bin/gamescope" { $1 = ""; sub(/^[[:space:]]+/, ""); print }' || true)"
echo "  the package declares: ${AQ_DECLARED_CAPS:-(none)}"
if aq_have getcap; then
    getcap /usr/bin/gamescope > /tmp/aq-caps.txt 2>&1 || true
    AQ_ACTUAL_CAPS="$(awk '{ $1 = ""; sub(/^ /, ""); print }' /tmp/aq-caps.txt)"
    echo "  the file actually has: ${AQ_ACTUAL_CAPS:-(none)}"
    rm -f /tmp/aq-caps.txt
    if [ -z "${AQ_ACTUAL_CAPS}" ]; then
        ok "gamescope carries no capabilities at all"
    elif [ -n "${AQ_DECLARED_CAPS}" ]; then
        ok "the capabilities on gamescope are the ones Fedora's package ships"
    else
        bad "gamescope has capabilities its package does not declare — something in THIS build granted them"
    fi
else
    echo "  note   getcap is not in this image; the package's own declaration above is the answer"
fi

# ==============================================================================
# 8. The two menu entries
# ==============================================================================
# Steam installs its own. Ours is the second one: Big Picture, Steam's
# full-screen controller-driven interface, straight from the app grid — which
# is as close to a "game mode" as a desktop machine needs, and it needs no
# separate session, no autologin and no handheld plumbing.
say "The Steam menu entries"
AQ_STEAM_DESKTOP="/usr/share/applications/steam.desktop"
if [ -r "${AQ_STEAM_DESKTOP}" ]; then
    ok "Steam's own menu entry is there (the app chooser shows it as Included)"
else
    echo "  Menu entries Steam installed:"
    rpm -ql steam | grep 'applications/' | sed 's/^/       /' || true
    bad "there is no ${AQ_STEAM_DESKTOP} — the app chooser's Included list expects it"
fi

AQ_BIGPICTURE="/usr/share/applications/aquarius-steam-bigpicture.desktop"
aq_file_has "${AQ_BIGPICTURE}" '^Exec=steam -bigpicture$' "the Big Picture entry starts Steam full screen"
aq_file_has "${AQ_BIGPICTURE}" '^TryExec=steam$' "it hides itself if Steam is ever not installed"

# The desktop database is what the app grid actually reads. A new .desktop file
# that is not in it does not appear.
if aq_have update-desktop-database; then
    update-desktop-database /usr/share/applications || true
    ok "the app grid's index was rebuilt"
fi

# ==============================================================================
# 9. The Gaming shelf in the app chooser
# ==============================================================================
# The window that opens at the first login now has a Gaming shelf. Steam is not
# on it — Steam is in this image already, so it appears in the "Included with
# AquariusOS" group at the top with an Open button. The shelf holds the three
# Flatpaks that make sense to OFFER rather than assume: Heroic (Epic and GOG),
# Lutris (everything else), and ProtonUp-Qt (newer Proton versions). All three
# are unticked, because plenty of people will only ever want Steam.
#
# The lists themselves live in system_files/ and are checked by step 7c against
# Flathub. What is checked here is the join: that the chooser knows how to draw
# a shelf called Gaming at all.
say "The Gaming shelf in the app chooser"
aq_file_has /usr/libexec/aquarius-creator-apps '"Gaming"' \
    "the chooser knows how to draw a Gaming shelf"
aq_file_has /usr/libexec/aquarius-creator-apps '"steam\.desktop"' \
    "the chooser lists Steam as already included"
aq_file_has /usr/share/aquarius/apps/catalog.ini '^Category=Gaming$' \
    "the catalogue has apps on the Gaming shelf"

AQ_GAMING_COUNT="$(/usr/libexec/aquarius-flatpak-preinstall --catalog 2> /dev/null \
    | awk -F'\t' '$4 == "Gaming"' | wc -l | tr -d ' ')"
echo "  apps on the Gaming shelf: ${AQ_GAMING_COUNT}"
/usr/libexec/aquarius-flatpak-preinstall --catalog 2> /dev/null \
    | awk -F'\t' '$4 == "Gaming" { print "       " $1 "  —  " $2 }' || true
if [ "${AQ_GAMING_COUNT}" -ge 3 ] 2> /dev/null; then
    ok "the Gaming shelf has ${AQ_GAMING_COUNT} apps on it"
else
    bad "the Gaming shelf has ${AQ_GAMING_COUNT} apps on it — expected at least three"
fi

# None of them may be ticked by default: somebody who only wants Steam should
# not be handed three game launchers they did not ask for.
AQ_GAMING_TICKED="$(/usr/libexec/aquarius-flatpak-preinstall --catalog 2> /dev/null \
    | awk -F'\t' '$4 == "Gaming" && $5 == "recommended:yes"' | wc -l | tr -d ' ')"
if [ "${AQ_GAMING_TICKED}" -eq 0 ] 2> /dev/null; then
    ok "none of them are ticked when the window opens"
else
    bad "${AQ_GAMING_TICKED} gaming app(s) are ticked by default — they should all be a choice"
fi

# ==============================================================================
# 10. The plain-language note that ships with the OS
# ==============================================================================
say "The note that ships in the image"
aq_file_has "${GAMING_DIR}/README.md" 'Steam' "the gaming note is in the image"

aq_finish "Gaming"
