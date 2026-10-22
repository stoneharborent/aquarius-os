#!/usr/bin/bash
# ==============================================================================
# BUILDER STAGE — the X20's two speaker drivers, for the HANDHELD image only
# ==============================================================================
# ⚠️ THIS SCRIPT DOES NOT RUN INSIDE AQUARIUSOS. It runs in a throwaway Fedora
# container (the `x20-audio-src-1` stage in the Containerfile) whose only job is
# to compile two small sound drivers and leave them in /out. Step 7g
# (build_files/78-handheld.sh) then copies those two files into the handheld
# image. The compiler, the kernel source code and everything else in this
# container are thrown away. The two desktop images never run this at all —
# they take an empty stage instead, the same trick the NVIDIA image's gamescope
# builder uses.
#
# ------------------------------------------------------------------------------
# WHY THIS EXISTS, IN PLAIN ENGLISH
# ------------------------------------------------------------------------------
# Royce's handheld is the ROG Xbox Ally X20 (its motherboard calls itself
# `RC74XA`, made by `ASUSTeK COMPUTER INC.`). With Fedora's kernel exactly as
# Fedora ships it, its built-in speakers make no sound at all and the sound
# menu shows "Dummy Output". Two things are wrong, and neither is our doing:
#
#   1. The machine's own firmware (a table called SSDT8) tells Linux "this
#      machine only has digital microphones" (the setting
#      `acp-audio-config-flag=0x10`). That is not true — the speakers and the
#      headphone socket sit on a newer kind of wiring called SoundWire. Linux
#      believes the firmware and picks the wrong sound driver. Linux already
#      keeps a short list of laptops whose firmware says this wrongly; RC74XA
#      is not on it yet. Patch 1 adds it. (Driver: `snd-acp-config`.)
#
#   2. Even on the right driver, Linux's list of "which SoundWire parts sit on
#      which wire" does not describe this machine: here the two speaker
#      amplifiers (TI TAS2783, addresses 8 and B) are on wire 0 and the
#      headphone chip (Realtek RT721) is on wire 1. Patch 2 adds that exact
#      layout. (Driver: `snd-soc-acpi-amd-match`.)
#
# Both patches were proven on the real handheld on 2026-10-16: with them, and
# with the right speaker firmware selected, the owner heard the left and right
# speakers separately. The full history, and the tests that must NOT be
# repeated (unloading a sound driver while the machine is running froze it), is
# in docs/restart/handheld.md under "The built-in speakers".
#
# ------------------------------------------------------------------------------
# WHY WE COMPILE THEM HERE, EVERY BUILD
# ------------------------------------------------------------------------------
# A kernel driver only loads on the EXACT kernel it was compiled for. The bench
# test used drivers compiled for kernel 7.2.10; the next image moved to 7.2.11
# and the speakers went silent again. So instead of keeping a compiled file
# anywhere, this stage compiles both drivers from scratch, every build, for
# whatever kernel this build's image is going to ship.
#
# HOW IT KNOWS WHICH KERNEL THAT IS: AquariusOS's kernel is decided by step 5.8
# (build_files/58-kernel-pin.sh) — it is the kernel inside Universal Blue's
# module box. This stage is handed THE SAME BOX (the `akmods-src` stage), reads
# the kernel version out of the same package files, and step 7g checks the
# finished image's kernel matches what was compiled here. Two different answers
# stop the build.
#
# ------------------------------------------------------------------------------
# WHERE THE SOURCE CODE COMES FROM
# ------------------------------------------------------------------------------
# From FEDORA'S OWN SOURCE PACKAGE for that exact kernel — for 7.2.11 that is
# `kernel-7.2.11-200.fc44.src.rpm`. That is the code Fedora's kernel was really
# compiled from: the upstream Linux 7.2.11 tarball plus Fedora's own patch file
# (`patch-7.2-redhat.patch`). We unpack both and apply Fedora's patch exactly
# the way Fedora's kernel.spec does, so the two files we change start out
# identical to the ones inside Fedora's real driver. We do not guess an
# upstream git tag.
#
# The source package is downloaded with dnf from Fedora's "source" repositories.
# If Fedora has already moved on and that version is no longer listed there,
# it is fetched from Fedora's build system (Koji), from the folder of copies
# signed with Fedora's release key. Either way the package's signature is
# checked against Fedora's key before anything is unpacked. An unsigned or
# wrongly signed package stops the build.
#
# ------------------------------------------------------------------------------
# ⚠️ WHAT MAKES THIS STEP FAIL, ON PURPOSE
# ------------------------------------------------------------------------------
#   * a patch that no longer applies EXACTLY (no "fuzz" allowed). If Linux
#     changes those lines, a human has to look; quietly shipping Fedora's stock
#     drivers would bring "Dummy Output" back with every check green;
#   * a compiled driver whose "vermagic" (the kernel version written inside
#     it) is not exactly the image's kernel;
#   * a compiled driver that does not carry the RC74XA change.
#
# ⚠️ THESE TWO DRIVERS ARE NOT SIGNED. Every other kernel module in AquariusOS
# comes signed from Fedora or Universal Blue. These do not, so a machine with
# Secure Boot switched ON refuses to load them — and the loader then falls back
# to Fedora's own drivers (no speakers, everything else normal). The X20 runs
# with Secure Boot OFF. docs/restart/handheld.md says this in plain words.
# ==============================================================================

set -euo pipefail

# shellcheck source=build_files/aq-lib.sh
source /ctx/build_files/aq-lib.sh

AKMODS="/ctx-akmods"                   # Universal Blue's module box — the SAME one step 5.8 reads
KERNEL_RPMS="${AKMODS}/kernel-rpms"
PATCHES="/ctx/build_files/x20-audio"
OUT="/out"
WORK="/tmp/x20-audio"

# The folder the two drivers go into, inside /usr/lib/modules/<kernel>/. It is
# NOT one of the folders Linux searches by name (that would hide Fedora's own
# drivers, and the loader needs those as its fallback). A small depmod setting
# shipped by step 7g tells depmod to skip it. The loader loads these two files
# by their full path.
AQ_X20_DIR_NAME="aquarius-x20-audio"

# The two patches, in the order they are applied.
AQ_PATCHES=(rc74xa-acp-config.patch rc74xa-soundwire-links.patch)

# ------------------------------------------------------------------------------
# 1. Which kernel is this build's image going to ship?
# ------------------------------------------------------------------------------
# Asked of the package itself, exactly like step 5.8 does, never of a file name.
say "Which kernel the handheld image will ship"
if [ ! -d "${KERNEL_RPMS}" ]; then
    echo "AQUARIUS ERROR: ${KERNEL_RPMS} is missing. This stage must be given" >&2
    echo "                Universal Blue's module box (the akmods-src stage)," >&2
    echo "                because that box decides the image's kernel." >&2
    exit 1
fi
AQ_CORE_RPM=""
AQ_DEVEL_RPM=""
while IFS= read -r aq_rpm; do
    aq_name="$(rpm -qp --queryformat '%{NAME}' "${aq_rpm}" 2> /dev/null || true)"
    case "${aq_name}" in
        kernel-core) AQ_CORE_RPM="${aq_rpm}" ;;
        kernel-devel) AQ_DEVEL_RPM="${aq_rpm}" ;;
    esac
done < <(find "${KERNEL_RPMS}" -maxdepth 1 -name '*.rpm' | sort)
if [ -z "${AQ_CORE_RPM}" ] || [ -z "${AQ_DEVEL_RPM}" ]; then
    echo "AQUARIUS ERROR: the module box has no kernel-core or no kernel-devel package." >&2
    echo "                What IS there:" >&2
    ls -1 "${KERNEL_RPMS}" >&2 || true
    exit 1
fi
KVER="$(rpm -qp --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' "${AQ_CORE_RPM}")"
KVERSION="$(rpm -qp --queryformat '%{VERSION}' "${AQ_CORE_RPM}")"
KRELEASE="$(rpm -qp --queryformat '%{RELEASE}' "${AQ_CORE_RPM}")"
AQ_DEVEL_VER="$(rpm -qp --queryformat '%{VERSION}-%{RELEASE}.%{ARCH}' "${AQ_DEVEL_RPM}")"
echo "  kernel the image will ship : ${KVER}"
echo "  kernel-devel in the box    : ${AQ_DEVEL_VER}"
if [ "${AQ_DEVEL_VER}" != "${KVER}" ]; then
    echo "AQUARIUS ERROR: the box's kernel-devel (${AQ_DEVEL_VER}) is not the same" >&2
    echo "                version as its kernel (${KVER}). Drivers compiled against" >&2
    echo "                it would not load on the image's kernel." >&2
    exit 1
fi
ok "kernel and kernel-devel agree: ${KVER}"

# ------------------------------------------------------------------------------
# 2. The tools, and kernel-devel for that exact kernel
# ------------------------------------------------------------------------------
# kernel-devel is the set of "how this kernel was configured" files an
# out-of-tree driver has to be compiled against. It comes from the box, so it
# is the exact build, not "a 7.2.11 from somewhere". Installing it also brings
# in the compiler and the tools it lists as needed.
say "Installing the compiler and kernel-devel ${KVER}"
aq_dnf install --setopt=install_weak_deps=False \
    "${AQ_DEVEL_RPM}" \
    gcc make bc bison flex perl elfutils-libelf-devel openssl-devel dwarves \
    patch cpio xz kmod binutils dnf5-plugins
aq_installed "kernel-devel-${KVERSION}-${KRELEASE}" gcc make patch kmod
KDIR="/usr/src/kernels/${KVER}"
if [ -r "${KDIR}/Makefile" ] && [ -r "${KDIR}/Module.symvers" ]; then
    ok "${KDIR} is there, with the kernel's own Module.symvers"
else
    bad "${KDIR} is incomplete — kernel-devel did not install where expected"
    aq_finish "Building the X20 speaker drivers"
fi

# ------------------------------------------------------------------------------
# 3. Fedora's own source package for that exact kernel, signature checked
# ------------------------------------------------------------------------------
say "Fetching Fedora's source package kernel-${KVERSION}-${KRELEASE}.src.rpm"
mkdir -p "${WORK}/srpm"
AQ_SRPM="${WORK}/srpm/kernel-${KVERSION}-${KRELEASE}.src.rpm"

# Fedora's public keys, so the signature check below has something to check
# against. Importing a key that is already there does nothing.
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-fedora-"$(rpm -E %fedora)"-primary 2> /dev/null || true

# First choice: Fedora's source repositories, through dnf.
if (cd "${WORK}/srpm" && "${AQ_DNF}" -y download --source \
    --enablerepo=fedora-source --enablerepo=updates-source \
    "kernel-${KVERSION}-${KRELEASE}") && [ -s "${AQ_SRPM}" ]; then
    echo "  got it from Fedora's source repositories"
else
    # Second choice: Fedora's build system, from the folder of copies signed with
    # the release key. The key's short id comes from the key Fedora ships in the
    # container, never typed in by hand, so a Fedora 45 build picks the right
    # folder by itself.
    echo "  not in the source repositories any more — trying Fedora's build system (Koji)"
    AQ_KEYID="$(rpm -q gpg-pubkey --queryformat '%{VERSION}\t%{SUMMARY}\n' \
        | awk -F'\t' -v f="Fedora ($(rpm -E %fedora))" 'index($2, f) == 1 { print $1; exit }')"
    AQ_KEYID="${AQ_KEYID: -8}"
    if [ -z "${AQ_KEYID}" ]; then
        echo "AQUARIUS ERROR: could not work out Fedora's release key id, so there is" >&2
        echo "                no signed copy to download." >&2
        exit 1
    fi
    AQ_KOJI="https://kojipkgs.fedoraproject.org/packages/kernel/${KVERSION}/${KRELEASE}/data/signed/${AQ_KEYID}/src/kernel-${KVERSION}-${KRELEASE}.src.rpm"
    echo "  ${AQ_KOJI}"
    curl --fail --location --silent --show-error --retry 3 --output "${AQ_SRPM}" "${AQ_KOJI}"
fi

# The signature check. `rpm -K` prints "digests signatures OK" only when the
# package is signed by a key this container trusts AND nothing in it changed.
# "digests OK" alone (no signature) is NOT good enough here.
AQ_SIGCHECK="$(rpm -K "${AQ_SRPM}" 2>&1 || true)"
echo "  ${AQ_SIGCHECK}"
case "${AQ_SIGCHECK}" in
    *"digests signatures OK"*) ok "the source package is signed by Fedora and unchanged" ;;
    *)
        echo "AQUARIUS ERROR: the kernel source package is not signed by Fedora's key," >&2
        echo "                or it was changed after signing. Not using it." >&2
        exit 1
        ;;
esac
AQ_SRPM_NVR="$(rpm -qp --queryformat '%{NAME}-%{VERSION}-%{RELEASE}' "${AQ_SRPM}")"
if [ "${AQ_SRPM_NVR}" = "kernel-${KVERSION}-${KRELEASE}" ]; then
    ok "it is the source of exactly this kernel: ${AQ_SRPM_NVR}"
else
    bad "the source package is ${AQ_SRPM_NVR}, not kernel-${KVERSION}-${KRELEASE}"
    aq_finish "Building the X20 speaker drivers"
fi
AQ_SRPM_SHA="$(sha256sum "${AQ_SRPM}" | cut -d' ' -f1)"

# ------------------------------------------------------------------------------
# 4. Unpack it and apply Fedora's own patch, the way kernel.spec does
# ------------------------------------------------------------------------------
say "Unpacking the kernel source and applying Fedora's patch"
mkdir -p "${WORK}/spec"
(cd "${WORK}/spec" && rpm2cpio "${AQ_SRPM}" | cpio -idm --quiet)
AQ_TARBALL="$(find "${WORK}/spec" -maxdepth 1 -name 'linux-*.tar.xz' | head -1)"
AQ_REDHAT_PATCH="$(find "${WORK}/spec" -maxdepth 1 -name 'patch-*-redhat.patch' | head -1)"
if [ -z "${AQ_TARBALL}" ]; then
    echo "AQUARIUS ERROR: the source package has no linux-*.tar.xz. Fedora changed" >&2
    echo "                how it packages the kernel; look at kernel.spec." >&2
    exit 1
fi
echo "  upstream source : ${AQ_TARBALL##*/}"
echo "  Fedora's patch  : ${AQ_REDHAT_PATCH##*/}"
tar -xf "${AQ_TARBALL}" -C "${WORK}"
TREE="$(find "${WORK}" -mindepth 1 -maxdepth 1 -type d -name 'linux-*' | head -1)"
# kernel.spec's ApplyOptionalPatch applies Fedora's patch only if it is longer
# than nine lines (a near-empty file means "no changes this release"), with
# plain `patch -p1`. Same rule here.
if [ -n "${AQ_REDHAT_PATCH}" ] && [ "$(wc -l < "${AQ_REDHAT_PATCH}")" -gt 9 ]; then
    patch -p1 -s -d "${TREE}" < "${AQ_REDHAT_PATCH}"
    ok "Fedora's patch applied — this is the code Fedora's ${KVER} was built from"
else
    ok "Fedora's patch is empty this release — the upstream source is Fedora's source"
fi

# ------------------------------------------------------------------------------
# 5. Our two patches — exactly, or not at all
# ------------------------------------------------------------------------------
# `--fuzz=0` means every line around each change has to match exactly. Lines
# that merely MOVED (an offset) are fine; lines that CHANGED are not. A patch
# that does not apply stops the build here, loudly, rather than shipping
# Fedora's unchanged drivers and a silent handheld with every check green.
say "Applying the two RC74XA patches (no fuzz allowed)"
for aq_p in "${AQ_PATCHES[@]}"; do
    echo "--- ${aq_p} ---"
    if patch -p1 --fuzz=0 --forward --batch --no-backup-if-mismatch \
        -d "${TREE}" < "${PATCHES}/${aq_p}"; then
        ok "${aq_p} applied exactly"
    else
        echo "::error::${aq_p} no longer applies to kernel ${KVER}." >&2
        echo "         Linux changed the lines this patch edits. Do NOT loosen the" >&2
        echo "         check. Read the new version of the file, rewrite the patch" >&2
        echo "         by hand, and bench-test the speakers again." >&2
        echo "         (Or: the fix has reached Linux itself — then delete the" >&2
        echo "         patch, see docs/restart/handheld.md.)" >&2
        exit 1
    fi
done

AQ_ACP_C="${TREE}/sound/soc/amd/acp-config.c"
AQ_MATCH_C="${TREE}/sound/soc/amd/acp/amd-acp70-acpi-match.c"
aq_file_has "${AQ_ACP_C}" 'DMI_EXACT_MATCH\(DMI_BOARD_NAME, "RC74XA"\)' \
    "acp-config.c now names board RC74XA"
aq_file_has "${AQ_MATCH_C}" 'acp70_rc74xa_links' \
    "amd-acp70-acpi-match.c now has the RC74XA wiring"

# A label inside each compiled driver, so anybody can ask a driver file
# "are you ours?" with `modinfo -F aquarius_x20 <file>`. It is metadata only —
# it changes nothing about what the driver does.
printf '\n/* AquariusOS: label only (build_files/78-handheld-audio-build.sh). */\n#include <linux/module.h>\nMODULE_INFO(aquarius_x20, "%s");\n' \
    "rc74xa-acp-config" >> "${AQ_ACP_C}"
printf '\n/* AquariusOS: label only (build_files/78-handheld-audio-build.sh). */\n#include <linux/module.h>\nMODULE_INFO(aquarius_x20, "%s");\n' \
    "rc74xa-soundwire-links" >> "${AQ_MATCH_C}"

# ------------------------------------------------------------------------------
# 6. Compile, against kernel-devel for the exact kernel
# ------------------------------------------------------------------------------
# The whole AMD sound folder is compiled with its own, unchanged Makefile, using
# Fedora's configuration from kernel-devel. That way each driver is made of
# exactly the pieces Fedora's driver is made of — we do not write our own
# recipe for it. It takes a minute or two. Only our two drivers are kept.
say "Compiling the AMD sound drivers against ${KDIR}"
make -C "${KDIR}" M="${TREE}/sound/soc/amd" -j"$(nproc)" modules

AQ_DEST="${OUT}/usr/lib/modules/${KVER}/${AQ_X20_DIR_NAME}"
install -d -m 0755 "${AQ_DEST}"
install -m 0644 "${TREE}/sound/soc/amd/snd-acp-config.ko" "${AQ_DEST}/snd-acp-config.ko"
install -m 0644 "${TREE}/sound/soc/amd/acp/snd-soc-acpi-amd-match.ko" "${AQ_DEST}/snd-soc-acpi-amd-match.ko"

# ------------------------------------------------------------------------------
# 7. Read the result back
# ------------------------------------------------------------------------------
say "Checking the two compiled drivers"
for aq_m in snd-acp-config snd-soc-acpi-amd-match; do
    aq_ko="${AQ_DEST}/${aq_m}.ko"
    aq_vm="$(modinfo -F vermagic "${aq_ko}")"
    echo "  ${aq_m}: vermagic '${aq_vm}', needs '$(modinfo -F depends "${aq_ko}")'"
    if [ "${aq_vm%% *}" = "${KVER}" ]; then
        ok "${aq_m} was built for exactly ${KVER}"
    else
        bad "${aq_m} says it is for '${aq_vm%% *}', not ${KVER}"
    fi
    aq_name="$(modinfo -F name "${aq_ko}")"
    if [ "${aq_name}" = "${aq_m//-/_}" ]; then
        ok "${aq_m} calls itself ${aq_name}, the same name as Fedora's driver it stands in for"
    else
        bad "${aq_m} calls itself '${aq_name}'"
    fi
done
AQ_TAG="$(modinfo -F aquarius_x20 "${AQ_DEST}/snd-acp-config.ko")"
[ "${AQ_TAG}" = "rc74xa-acp-config" ] \
    && ok "snd-acp-config carries the RC74XA label" \
    || bad "snd-acp-config has no RC74XA label (got '${AQ_TAG}')"
AQ_TAG="$(modinfo -F aquarius_x20 "${AQ_DEST}/snd-soc-acpi-amd-match.ko")"
[ "${AQ_TAG}" = "rc74xa-soundwire-links" ] \
    && ok "snd-soc-acpi-amd-match carries the RC74XA label" \
    || bad "snd-soc-acpi-amd-match has no RC74XA label (got '${AQ_TAG}')"
# The board name has to be IN the compiled driver, not just in the source.
# (Written to a file first, then searched: piping `strings` straight into
# `grep -q` is the broken-pipe trap described in aq-lib.sh.)
strings "${AQ_DEST}/snd-acp-config.ko" > "${WORK}/strings.txt"
if grep -qx 'RC74XA' "${WORK}/strings.txt"; then
    ok "the compiled snd-acp-config contains the board name RC74XA"
else
    bad "the compiled snd-acp-config does not contain RC74XA — the patch did not make it in"
fi

# What was built, from what — read back by step 7g and kept in the image.
install -d -m 0755 "${OUT}/usr/share/aquarius/x20-audio"
{
    echo "# The X20 (board RC74XA) speaker drivers in this image, and where they came from."
    echo "# Written by build_files/78-handheld-audio-build.sh. See docs/restart/handheld.md."
    echo "kernel=${KVER}"
    echo "source=${AQ_SRPM_NVR}.src.rpm"
    echo "source_sha256=${AQ_SRPM_SHA}"
    for aq_p in "${AQ_PATCHES[@]}"; do
        echo "patch=${aq_p} $(sha256sum "${PATCHES}/${aq_p}" | cut -d' ' -f1)"
    done
    for aq_m in snd-acp-config snd-soc-acpi-amd-match; do
        echo "module=${AQ_X20_DIR_NAME}/${aq_m}.ko $(sha256sum "${AQ_DEST}/${aq_m}.ko" | cut -d' ' -f1)"
    done
} > "${OUT}/usr/share/aquarius/x20-audio/build.txt"
sed 's/^/       /' "${OUT}/usr/share/aquarius/x20-audio/build.txt"

aq_finish "Building the X20 speaker drivers"
