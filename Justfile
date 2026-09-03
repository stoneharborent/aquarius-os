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
export base_image := env_var("BASE_IMAGE")
export fedora_version := env_var("FEDORA_VERSION")
export akmods_nvidia_image := env_var("AKMODS_NVIDIA_IMAGE")
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
# GitHub Actions builds the two images from one matrix, and asks these two
# recipes what each one is called and whether it wants the NVIDIA driver. Adding
# a variant means adding a line to each — and nowhere else.

# The published name of a variant. `just variant-image-name nvidia`
[group('Utility')]
variant-image-name variant="base":
    #!/usr/bin/env bash

    set -euo pipefail
    case "{{ variant }}" in
        base) echo "${IMAGE_NAME}" ;;
        nvidia) echo "${NVIDIA_IMAGE_NAME}" ;;
        *)
            echo "Unknown variant '{{ variant }}' — expected 'base' or 'nvidia'." >&2
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
        *)
            echo "Unknown variant '{{ variant }}' — expected 'base' or 'nvidia'." >&2
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

# Build an AquariusOS image. `just build aquarius-os-next-nvidia latest 1`
build $target_image=image_name $tag=default_tag $nvidia="0":
    #!/usr/bin/env bash

    set -euox pipefail
    case "${nvidia}" in
        0 | 1) : ;;
        *)
            echo "just build: nvidia must be 0 or 1, not '${nvidia}'." >&2
            exit 1
            ;;
    esac
    BUILD_ARGS=()
    BUILD_ARGS+=("--build-arg" "FEDORA_VERSION={{ fedora_version }}")
    BUILD_ARGS+=("--build-arg" "NVIDIA=${nvidia}")
    BUILD_ARGS+=("--build-arg" "AKMODS_NVIDIA_IMAGE={{ akmods_nvidia_image }}")
    BUILD_ARGS+=("--build-arg" "IMAGE_NAME=${target_image}")
    BUILD_ARGS+=("--build-arg" "IMAGE_VENDOR={{ repo_organization }}")
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
