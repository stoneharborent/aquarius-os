# ==============================================================================
# AquariusOS — the commands that build it
# ==============================================================================
# `just` is a small task runner: `just build` runs the build recipe below. It is
# how GitHub Actions builds the image, and it is how you would build one on a
# Linux machine, so the two cannot drift apart.
#
# Run `just` with no arguments to see everything this file can do.
#
# All the names and versions come from aquarius-os.env — that is the one place
# to change them.
# ==============================================================================

set dotenv-filename := "aquarius-os.env"
set dotenv-load

export image_name := env_var("IMAGE_NAME")
export nvidia_image_name := env_var("NVIDIA_IMAGE_NAME")
export handheld_image_name := env_var("HANDHELD_IMAGE_NAME")
export handheld_claw_image_name := env_var("HANDHELD_CLAW_IMAGE_NAME")
export base_image := env_var("BASE_IMAGE")
export fedora_version := env_var("FEDORA_VERSION")
export akmods_nvidia_image := env_var("AKMODS_NVIDIA_IMAGE")
export akmods_image := env_var("AKMODS_IMAGE")
export repo_name := env_var("REPO_NAME")
export repo_organization := env_var("REPO_ORGANIZATION")
export image_desc := env_var("IMAGE_DESC")
export image_keywords := env_var("IMAGE_KEYWORDS")
export image_logo_url := env_var("IMAGE_LOGO_URL")
export default_tag := env_var("DEFAULT_TAG")
export bib_image := env_var("BIB_IMAGE")

[private]
default:
    @just --list

# ------------------------------------------------------------------------------
# Housekeeping
# ------------------------------------------------------------------------------

# Check this file is written correctly (the build runs this first).
[group('Just')]
check:
    echo "Checking syntax: Justfile"
    just --unstable --fmt --check -f Justfile

# Reformat this file.
[group('Just')]
fix:
    just --unstable --fmt -f Justfile

# Check the build scripts for the mistakes shellcheck knows about.
[group('Just')]
lint:
    #!/usr/bin/env bash

    set -eoux pipefail
    if ! command -v shellcheck &> /dev/null; then
        echo "shellcheck is not installed. On Fedora: sudo dnf install ShellCheck"
        exit 1
    fi
    shellcheck build_files/*.sh

# Throw away build leftovers.
[group('Utility')]
clean:
    #!/usr/bin/env bash

    set -eoux pipefail
    rm -rf output/

# ------------------------------------------------------------------------------
# Which image is which
# ------------------------------------------------------------------------------
# GitHub Actions builds the four images from one matrix, and asks these recipes
# what each one is called, whether it wants the NVIDIA driver, whether it is a
# handheld, and — when it is — WHICH handheld. Adding a variant means adding a
# line to each of them and nowhere else.
#
# The four variants are:
#
#   base            aquarius-os                 an AMD or Intel desktop PC
#   nvidia          aquarius-os-nvidia          the same, plus NVIDIA's driver
#   handheld        aquarius-os-handheld        the ROG Xbox Ally X (phase G2)
#   handheld-claw   aquarius-os-handheld-claw   the MSI Claw 8 AI+ (phase G4)

# The published name of a variant. `just variant-image-name nvidia`
[group('Utility')]
variant-image-name variant="base":
    #!/usr/bin/env bash

    set -euo pipefail
    case "{{ variant }}" in
        base) echo "${IMAGE_NAME}" ;;
        nvidia) echo "${NVIDIA_IMAGE_NAME}" ;;
        handheld) echo "${HANDHELD_IMAGE_NAME}" ;;
        handheld-claw) echo "${HANDHELD_CLAW_IMAGE_NAME}" ;;
        *)
            echo "Unknown variant '{{ variant }}' — expected 'base', 'nvidia', 'handheld' or 'handheld-claw'." >&2
            exit 1
            ;;
    esac

# Whether a variant wants the NVIDIA driver: 0 or 1.
[group('Utility')]
variant-nvidia variant="base":
    #!/usr/bin/env bash

    set -euo pipefail
    case "{{ variant }}" in
        base) echo "0" ;;
        nvidia) echo "1" ;;
        handheld) echo "0" ;;
        handheld-claw) echo "0" ;;
        *)
            echo "Unknown variant '{{ variant }}' — expected 'base', 'nvidia', 'handheld' or 'handheld-claw'." >&2
            exit 1
            ;;
    esac

# Whether a variant is a handheld one: 0 or 1. (Phase G2 and phase G4.)
[group('Utility')]
variant-handheld variant="base":
    #!/usr/bin/env bash

    set -euo pipefail
    case "{{ variant }}" in
        base) echo "0" ;;
        nvidia) echo "0" ;;
        handheld) echo "1" ;;
        handheld-claw) echo "1" ;;
        *)
            echo "Unknown variant '{{ variant }}' — expected 'base', 'nvidia', 'handheld' or 'handheld-claw'." >&2
            exit 1
            ;;
    esac

# WHICH handheld a variant is for: 'ally' or 'claw'.
#
# The two desktop variants answer 'ally' as well. That is not a claim that a
# desktop PC is an Ally — the build only ever reads this when HANDHELD=1, and
# 'ally' is the default the build script itself uses. Answering with a real word
# rather than an empty string keeps the workflow's "the Justfile and the matrix
# must agree" check simple: it compares two strings and never has to reason
# about which of them is allowed to be blank.
[group('Utility')]
variant-handheld-target variant="base":
    #!/usr/bin/env bash

    set -euo pipefail
    case "{{ variant }}" in
        base) echo "ally" ;;
        nvidia) echo "ally" ;;
        handheld) echo "ally" ;;
        handheld-claw) echo "claw" ;;
        *)
            echo "Unknown variant '{{ variant }}' — expected 'base', 'nvidia', 'handheld' or 'handheld-claw'." >&2
            exit 1
            ;;
    esac

[group('Utility')]
generate-default-tag $tag=default_tag:
    #!/usr/bin/env bash

    set -eoux pipefail
    echo "${tag}"

# Every name the finished image gets pushed under. The dated ones are what makes
# it possible to go back to a specific day's build with `bootc switch`.
[group('Utility')]
generate-build-tags $target_image=image_name $tag=default_tag:
    #!/usr/bin/env bash

    set -eoux pipefail
    DATE=$(date +%Y%m%d)
    BUILD_TAGS=()
    if [[ -z "$(git status -s)" ]]; then
        GIT_SHA=$(git rev-parse --short HEAD)
        BUILD_TAGS+=("${tag}-${GIT_SHA}")
        BUILD_TAGS+=("${DATE}-${GIT_SHA}")
    fi
    BUILD_TAGS+=("${DATE}")
    BUILD_TAGS+=("${tag}")
    echo "${BUILD_TAGS[@]}"

[group('Utility')]
tag-images $target_image=image_name $tag=default_tag tags="":
    #!/usr/bin/env bash

    set -eoux pipefail
    IMAGE=$(podman inspect ${target_image}:${tag} | jq -r .[].Id)
    podman untag ${IMAGE}
    for tag in {{ tags }}; do
        podman tag $IMAGE "${target_image}:${tag}"
    done
    podman images

# ------------------------------------------------------------------------------
# The build
# ------------------------------------------------------------------------------

# Build an AquariusOS image.
#   just build aquarius-os-nvidia latest 1
#   just build aquarius-os-handheld latest 0 1 ally
#   just build aquarius-os-handheld-claw latest 0 1 claw
# The two numbers are the two switches: NVIDIA, then HANDHELD. They are never
# both 1 — neither handheld has an NVIDIA graphics card. The last word says
# WHICH handheld, and is only read when HANDHELD is 1.
build $target_image=image_name $tag=default_tag $nvidia="0" $handheld="0" $handheld_target="ally":
    #!/usr/bin/env bash

    set -euox pipefail
    case "${nvidia}" in
        0 | 1) : ;;
        *)
            echo "just build: nvidia must be 0 or 1, not '${nvidia}'." >&2
            exit 1
            ;;
    esac
    case "${handheld}" in
        0 | 1) : ;;
        *)
            echo "just build: handheld must be 0 or 1, not '${handheld}'." >&2
            exit 1
            ;;
    esac
    case "${handheld_target}" in
        ally | claw) : ;;
        *)
            echo "just build: handheld_target must be 'ally' (the ROG Xbox Ally X) or 'claw' (the MSI Claw 8 AI+), not '${handheld_target}'." >&2
            exit 1
            ;;
    esac
    if [ "${nvidia}" = "1" ] && [ "${handheld}" = "1" ]; then
        echo "just build: there is no NVIDIA handheld. Neither the ROG Xbox Ally X nor the MSI Claw 8 AI+ has an NVIDIA graphics card." >&2
        exit 1
    fi
    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "FEDORA_VERSION={{ fedora_version }}")
    BUILD_ARGS+=("--build-arg" "NVIDIA=${nvidia}")
    BUILD_ARGS+=("--build-arg" "HANDHELD=${handheld}")
    BUILD_ARGS+=("--build-arg" "HANDHELD_TARGET=${handheld_target}")
    BUILD_ARGS+=("--build-arg" "AKMODS_NVIDIA_IMAGE={{ akmods_nvidia_image }}")
    BUILD_ARGS+=("--build-arg" "AKMODS_IMAGE={{ akmods_image }}")
    BUILD_ARGS+=("--build-arg" "IMAGE_NAME=${target_image}")
    BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR={{ repo_organization }}")
    # (The Aquarius Desktop's three pinned pieces used to be passed here. That
    # desktop was retired on 2026-09-15 — both desktops now come from Fedora's
    # own packages, so FEDORA_VERSION is the only pin left.)
    LABELS=()
    if [[ -z "$(git status -s)" ]]; then
        GIT_SHA=$(git rev-parse --short HEAD)
        LABELS+=("--label" "org.opencontainers.image.revision=${GIT_SHA}")
        LABELS+=("--label" "org.opencontainers.image.source=https://github.com/{{ repo_organization }}/{{ repo_name }}/blob/${GIT_SHA}/Containerfile")
        LABELS+=("--label" "org.opencontainers.image.url=https://github.com/{{ repo_organization }}/{{ repo_name }}/tree/${GIT_SHA}")
        LABELS+=("--label" "org.opencontainers.image.version={{ default_tag }}.$(date +%Y%m%d)-${GIT_SHA}")
    fi
    LABELS+=("--label" "io.artifacthub.package.deprecated=false")
    LABELS+=("--label" "io.artifacthub.package.keywords={{ image_keywords }}")
    LABELS+=("--label" "io.artifacthub.package.license=Apache-2.0")
    LABELS+=("--label" "io.artifacthub.package.logo-url={{ image_logo_url }}")
    LABELS+=("--label" "io.artifacthub.package.prerelease=false")
    LABELS+=("--label" "org.opencontainers.image.created=$(date -u +%Y\-%m\-%d\T%H\:%M\:%S\Z)")
    LABELS+=("--label" "org.opencontainers.image.description={{ image_desc }}")
    LABELS+=("--label" "org.opencontainers.image.title=${target_image}")
    LABELS+=("--label" "org.opencontainers.image.vendor={{ repo_organization }}")
    podman build "${BUILD_ARGS[@]}" "${LABELS[@]}" \
        --pull=newer \
        --tag "${target_image}:${tag}" \
        --file Containerfile \
        .

# ------------------------------------------------------------------------------
# Installer ISOs and virtual machine disks
# ------------------------------------------------------------------------------
# These take a FINISHED image and turn it into something you can boot from a USB
# stick or run in a virtual machine. They need root and a Linux machine — the
# ISO build in GitHub Actions is the one that actually gets used.

[private]
_build-bib $target_image $tag $type $config:
    #!/usr/bin/env bash

    set -euo pipefail
    BUILDTMP=$(mktemp -p "${PWD}" -d -t _build-bib.XXXXXXXXXX)
    sudo podman run \
      --rm \
      -it \
      --privileged \
      --pull=newer \
      --net=host \
      --security-opt label=type:unconfined_t \
      -v $(pwd)/${config}:/config.toml:ro \
      -v $BUILDTMP:/output \
      -v /var/lib/containers/storage:/var/lib/containers/storage \
      "${bib_image}" \
      --type ${type} \
      --use-librepo=True \
      --rootfs=btrfs \
      "${target_image}:${tag}"
    mkdir -p output
    sudo mv -f $BUILDTMP/* output/
    sudo rmdir $BUILDTMP
    sudo chown -R $USER:$USER output/

# Build an installer ISO from an already-built image.
[group('Build installable media')]
build-iso $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "anaconda-iso" "disk_config/iso.toml")

# Build a virtual machine disk from an already-built image.
[group('Build installable media')]
build-qcow2 $target_image=("localhost/" + image_name) $tag=default_tag: && (_build-bib target_image tag "qcow2" "disk_config/disk.toml")
