#!/usr/bin/env bash
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "${ROOT}"

TALOS_VERSION=${TALOS_VERSION:-v1.14.2}
PKGS=${PKGS:-v1.14.0-37-g6c312e4}
TOOLS=${TOOLS:-v1.14.0-8-g9776960}
REGISTRY=${REGISTRY:-ghcr.io}
USERNAME=${USERNAME:-}
IMAGE_TAG=${IMAGE_TAG:-v0.3.0}
OUTPUT_DIR=${OUTPUT_DIR:-"${ROOT}/_out"}
# Package names in ${REGISTRY}/${USERNAME}. CI uses names it created
# itself: a GITHUB_TOKEN cannot write to packages pushed from elsewhere.
OVERLAY_NAME=${OVERLAY_NAME:-sbc-mixtile-blade3}
OPENMIOP_NAME=${OPENMIOP_NAME:-openmiop}
# If set, the installer image is pushed there (for talosctl upgrade).
INSTALLER_IMAGE=${INSTALLER_IMAGE:-}

DRBD_EXTENSION=${DRBD_EXTENSION:-ghcr.io/siderolabs/drbd:9.3.4-${TALOS_VERSION}}
ZFS_EXTENSION=${ZFS_EXTENSION:-ghcr.io/siderolabs/zfs:2.4.4-${TALOS_VERSION}}
ISCSI_EXTENSION=${ISCSI_EXTENSION:-ghcr.io/siderolabs/iscsi-tools:v0.2.0}
PANFROST_EXTENSION=${PANFROST_EXTENSION:-ghcr.io/siderolabs/panfrost:20260916-${TALOS_VERSION}}
RKNN_EXTENSION=${RKNN_EXTENSION:-ghcr.io/siderolabs/rockchip-rknn:${TALOS_VERSION}}

# openmiop: Ethernet over the Cluster Box PCIe fabric (pcie-ep-net). The
# version must match openmiop_version in Pkgfile. Set OPENMIOP=0 to build
# an image without it.
OPENMIOP=${OPENMIOP:-1}
OPENMIOP_VERSION=${OPENMIOP_VERSION:-$(awk '/^  openmiop_version:/{print $2}' "${ROOT}/Pkgfile")}

usage() {
    cat <<EOF
Usage: USERNAME=<registry namespace> $0 [overlay|extension|image|all]

Environment:
  TALOS_VERSION=${TALOS_VERSION}
  PKGS=${PKGS}
  TOOLS=${TOOLS}
  REGISTRY=${REGISTRY}
  IMAGE_TAG=${IMAGE_TAG}
  OUTPUT_DIR=${OUTPUT_DIR}
  OPENMIOP=${OPENMIOP} (OPENMIOP_VERSION=${OPENMIOP_VERSION})

The overlay and the openmiop extension are pushed because the Talos
imager resolves them as OCI images.

With OPENMIOP=1 the image drops the module.sig_enforce kernel argument:
openmiop-ep.ko is built against the exact Talos kernel tree but cannot
be signed with the Talos build key, which is discarded after each
official kernel build.
EOF
}

require_tools() {
    command -v docker >/dev/null
    command -v make >/dev/null
    command -v xz >/dev/null

    if [[ -z "${USERNAME}" ]]; then
        echo "USERNAME must name a writable namespace in ${REGISTRY}" >&2
        exit 2
    fi

    docker info >/dev/null
    docker buildx version >/dev/null
}

build_overlay() {
    make target-sbc-mixtile-blade3 \
        PLATFORM=linux/arm64 \
        PKGS="${PKGS}" \
        TOOLS="${TOOLS}" \
        TARGET_ARGS="--tag=${REGISTRY}/${USERNAME}/${OVERLAY_NAME}:${IMAGE_TAG} --push"
}

build_extension() {
    make target-openmiop \
        PLATFORM=linux/arm64 \
        PKGS="${PKGS}" \
        TOOLS="${TOOLS}" \
        TARGET_ARGS="--tag=${REGISTRY}/${USERNAME}/${OPENMIOP_NAME}:${OPENMIOP_VERSION} --push"
}

build_images() {
    mkdir -p "${OUTPUT_DIR}"

    local docker_args=(
        --rm
        --privileged
        --platform=linux/arm64
        -v "${OUTPUT_DIR}:/out"
        -v /dev:/dev
    )

    # Docker Desktop stores credentials in a macOS-only helper which cannot
    # run inside the Linux imager container. Build a portable config from the
    # PAT when available so private GHCR overlays can be pulled.
    local registry_config=${DOCKER_CONFIG:-"${HOME}/.docker"}/config.json
    local temporary_registry_config=

    if [[ -n "${CR_PAT:-}" ]]; then
        temporary_registry_config=$(mktemp)
        local cleanup_command
        printf -v cleanup_command 'rm -f -- %q' "${temporary_registry_config}"
        trap "${cleanup_command}" EXIT

        local registry_auth
        registry_auth=$(printf '%s:%s' "${USERNAME}" "${CR_PAT}" | base64 | tr -d '\r\n')
        printf '{"auths":{"%s":{"auth":"%s"}}}\n' \
            "${REGISTRY}" "${registry_auth}" >"${temporary_registry_config}"
        chmod 600 "${temporary_registry_config}"

        registry_config=${temporary_registry_config}
    fi

    if [[ -f "${registry_config}" ]]; then
        docker_args+=(-v "${registry_config}:/root/.docker/config.json:ro")
    fi

    local common_args=(
        --arch arm64
        --base-installer-image "ghcr.io/siderolabs/installer-base:${TALOS_VERSION}"
        --overlay-name mixtile-blade3
        --overlay-image "${REGISTRY}/${USERNAME}/${OVERLAY_NAME}:${IMAGE_TAG}"
        --system-extension-image "${DRBD_EXTENSION}"
        --system-extension-image "${ZFS_EXTENSION}"
        --system-extension-image "${ISCSI_EXTENSION}"
        --system-extension-image "${PANFROST_EXTENSION}"
        --system-extension-image "${RKNN_EXTENSION}"
    )

    if [[ "${OPENMIOP}" == 1 ]]; then
        common_args+=(
            --system-extension-image "${REGISTRY}/${USERNAME}/${OPENMIOP_NAME}:${OPENMIOP_VERSION}"
            --extra-kernel-arg -module.sig_enforce
        )
    fi

    for kind in installer blade3; do
        docker run "${docker_args[@]}" \
            "ghcr.io/siderolabs/imager:${TALOS_VERSION}" \
            "${kind}" "${common_args[@]}"
    done

    local compressed_image="${OUTPUT_DIR}/metal-arm64.raw.xz"
    if [[ ! -f "${compressed_image}" ]]; then
        echo "expected compressed image not found: ${compressed_image}" >&2
        exit 1
    fi

    local sector_hex
    sector_hex=$(
        set +o pipefail
        xz -dc "${compressed_image}" 2>/dev/null |
            dd bs=512 skip=64 count=1 2>/dev/null |
            od -An -tx1 |
            tr -d '[:space:]'
    )

    if [[ -z "${sector_hex}" || "${sector_hex}" =~ ^0+$ ]]; then
        echo "U-Boot verification failed: sector 64 is empty in ${compressed_image}" >&2
        exit 1
    fi

    echo "verified U-Boot data at sector 64 in ${compressed_image}"

    if [[ -n "${INSTALLER_IMAGE}" ]]; then
        local loaded
        loaded=$(docker load -i "${OUTPUT_DIR}/installer-arm64.tar" | sed -n 's/^Loaded image: //p' | tail -1)
        docker tag "${loaded}" "${INSTALLER_IMAGE}"
        docker push "${INSTALLER_IMAGE}"
        docker inspect --format '{{index .RepoDigests 0}}' "${INSTALLER_IMAGE}" | tee "${OUTPUT_DIR}/installer-image.txt"
    fi

    if [[ -n "${temporary_registry_config}" ]]; then
        rm -f "${temporary_registry_config}"
        trap - EXIT
    fi
}

main() {
    local action=${1:-all}

    case "${action}" in
        -h|--help)
            usage
            return
            ;;
        overlay|extension|image|all) ;;
        *)
            usage >&2
            exit 2
            ;;
    esac

    require_tools

    case "${action}" in
        overlay) build_overlay ;;
        extension) build_extension ;;
        image) build_images ;;
        all)
            build_overlay
            [[ "${OPENMIOP}" == 1 ]] && build_extension
            build_images
            ;;
    esac
}

main "$@"
