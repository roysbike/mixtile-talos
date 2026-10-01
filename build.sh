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

DRBD_EXTENSION=${DRBD_EXTENSION:-ghcr.io/siderolabs/drbd:9.3.4-${TALOS_VERSION}}
ZFS_EXTENSION=${ZFS_EXTENSION:-ghcr.io/siderolabs/zfs:2.4.4-${TALOS_VERSION}}
ISCSI_EXTENSION=${ISCSI_EXTENSION:-ghcr.io/siderolabs/iscsi-tools:v0.2.0}

usage() {
    cat <<EOF
Usage: USERNAME=<registry namespace> $0 [overlay|image|all]

Environment:
  TALOS_VERSION=${TALOS_VERSION}
  PKGS=${PKGS}
  TOOLS=${TOOLS}
  REGISTRY=${REGISTRY}
  IMAGE_TAG=${IMAGE_TAG}
  OUTPUT_DIR=${OUTPUT_DIR}

The overlay is pushed because the Talos imager resolves overlays as OCI images.
EOF
}

require_tools() {
    command -v docker >/dev/null
    command -v make >/dev/null

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
        TARGET_ARGS="--tag=${REGISTRY}/${USERNAME}/sbc-mixtile-blade3:${IMAGE_TAG} --push"
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
        trap 'rm -f "${temporary_registry_config}"' EXIT

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
        --overlay-image "${REGISTRY}/${USERNAME}/sbc-mixtile-blade3:${IMAGE_TAG}"
        --system-extension-image "${DRBD_EXTENSION}"
        --system-extension-image "${ZFS_EXTENSION}"
        --system-extension-image "${ISCSI_EXTENSION}"
    )

    for kind in installer metal; do
        docker run "${docker_args[@]}" \
            "ghcr.io/siderolabs/imager:${TALOS_VERSION}" \
            "${kind}" "${common_args[@]}"
    done

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
        overlay|image|all) ;;
        *)
            usage >&2
            exit 2
            ;;
    esac

    require_tools

    case "${action}" in
        overlay) build_overlay ;;
        image) build_images ;;
        all)
            build_overlay
            build_images
            ;;
    esac
}

main "$@"
