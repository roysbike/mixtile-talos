#!/usr/bin/env bash
# Publish a GitHub release from a finished tag build.
#
#   scripts/publish-release.sh TAG [OUTPUT_DIR]
#
# Takes the release notes from docs/release-notes/TAG.md and fills in the
# image references and digests recorded in BUILD-INFO.txt, so the notes
# always name what this build pushed. Refuses to publish when the build is
# not from the tagged commit, the tree was dirty or CHANGELOG.md does not
# have the version.
set -Eeuo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TAG=${1:?tag}
OUT=${2:-"${ROOT}/_out"}
NOTES_TEMPLATE=${ROOT}/docs/release-notes/${TAG}.md
ASSETS=(metal-arm64.raw.xz rk3588-mixtile-blade3.dtb u-boot-rockchip.bin
        openmiop-ep.ko openmiop-extension-manifest.yaml BUILD-INFO.txt)

fail() { echo "publish-release: $*" >&2; exit 1; }
info() { sed -n "s/^$1: //p" "${OUT}/BUILD-INFO.txt" | head -n1; }

[[ -s "${NOTES_TEMPLATE}" ]] || fail "missing ${NOTES_TEMPLATE}"
grep -q "^## \[${TAG#v}\] - " "${ROOT}/CHANGELOG.md" || fail "CHANGELOG.md has no [${TAG#v}] section"

commit=$(git -C "${ROOT}" rev-parse HEAD)
tag_commit=$(git -C "${ROOT}" rev-parse "${TAG}^{commit}")
[[ "${commit}" == "${tag_commit}" ]] || fail "HEAD ${commit} is not ${TAG} (${tag_commit})"
[[ "$(info commit)" == "${commit}" ]] || fail "BUILD-INFO commit $(info commit) != ${commit}"
[[ "$(info commit-dirty)" == no ]] || fail "build tree was dirty"

installer=$(info installer)
overlay=$(info overlay)
extension=$(info openmiop-extension)
[[ "${installer}" == *@sha256:* && "${overlay}" == *@sha256:* && "${extension}" == *@sha256:* ]] ||
    fail "BUILD-INFO lacks image digests"

# Every published file must match the checksum the build recorded.
(cd "${OUT}" && for a in "${ASSETS[@]}"; do grep -E "  ${a}\$" SHA256SUMS; done) > "${OUT}/SHA256SUMS.release"
[[ $(wc -l < "${OUT}/SHA256SUMS.release") -eq ${#ASSETS[@]} ]] || fail "SHA256SUMS does not cover every asset"
(cd "${OUT}" && sha256sum -c SHA256SUMS.release)

run_url="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-roysbike/mixtile-talos}/actions/runs/${GITHUB_RUN_ID:-local}"
sed -e "s|@INSTALLER@|${installer}|g" \
    -e "s|@INSTALLER_DIGEST@|${installer#*@}|g" \
    -e "s|@OVERLAY@|${overlay}|g" \
    -e "s|@EXTENSION@|${extension}|g" \
    -e "s|@COMMIT@|${commit}|g" \
    -e "s|@RUN_URL@|${run_url}|g" \
    -e "s|@VERMAGIC@|$(info openmiop-ko-vermagic)|g" \
    -e "s|@OPENMIOP_REF@|$(info openmiop-ref)|g" \
    "${NOTES_TEMPLATE}" > "${OUT}/release-notes.md"
! grep -n '@[A-Z_]*@' "${OUT}/release-notes.md" || fail "unfilled placeholder in the notes"

mkdir -p "${OUT}/release"
# _out is written by root-owned containers; copy (hard links are refused).
for a in "${ASSETS[@]}"; do cp "${OUT}/${a}" "${OUT}/release/${a}"; done
cp "${OUT}/SHA256SUMS.release" "${OUT}/release/SHA256SUMS"
(cd "${OUT}/release" && sha256sum -c SHA256SUMS)

prerelease=()
[[ "${TAG}" == *-* ]] && prerelease=(--prerelease)
gh release create "${TAG}" --verify-tag "${prerelease[@]}" \
    --title "mixtile-talos ${TAG}: Talos v1.14.2 for Mixtile Blade 3 with openmiop" \
    --notes-file "${OUT}/release-notes.md" \
    "${OUT}"/release/*
