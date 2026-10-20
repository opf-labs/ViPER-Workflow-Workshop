#!/usr/bin/env bash
#
# Builds the distributable tarball for ViPER VM users.
#
# The payload is taken from a BUILT workshop image, not from workshop-image/rootfs,
# because the flows, the notebooks, the Node-RED palette and the PUID reference CSV are
# all generated during the Docker build and do not exist in the source tree.
#
#     ./build-tarball.sh                                   uses the default image below
#     ./build-tarball.sh opf-cloud-viper:2.0.0-ipres2026-rc20
#
# Produces viper-workshop-extras.tar.gz in this directory, ready to attach to an email.

set -euo pipefail

IMAGE="${1:-opf-cloud-viper:2.0.0-ipres2026-rc20}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${HERE}/viper-workshop-extras.tar.gz"
STAGE="$(mktemp -d)"
trap 'rm -rf "${STAGE}"' EXIT

echo "==> Extracting /opt/workshop from ${IMAGE}"
docker image inspect "${IMAGE}" >/dev/null 2>&1 \
    || { echo "error: image ${IMAGE} not found locally. Build it first." >&2; exit 1; }

cid="$(docker create "${IMAGE}")"
mkdir -p "${STAGE}/viper-workshop-extras/payload/opt"
docker cp "${cid}:/opt/workshop" "${STAGE}/viper-workshop-extras/payload/opt/workshop"
docker rm -f "${cid}" >/dev/null

# The s6 service definition is Docker-only. The installer writes a systemd user unit
# instead, so shipping the s6 directory would only invite someone to try to use it.
rm -rf "${STAGE}/viper-workshop-extras/payload/opt/workshop/s6"

cp "${HERE}/install.sh" "${STAGE}/viper-workshop-extras/install.sh"
cp "${HERE}/README.md"  "${STAGE}/viper-workshop-extras/README.md"
chmod +x "${STAGE}/viper-workshop-extras/install.sh"

echo "==> Contents"
printf '    %-28s %s\n' "payload" "$(du -sh "${STAGE}/viper-workshop-extras/payload" | cut -f1)"
printf '    %-28s %s\n' "files"   "$(find "${STAGE}/viper-workshop-extras" -type f | wc -l)"

tar -czf "${OUT}" -C "${STAGE}" viper-workshop-extras

echo "==> Wrote ${OUT}"
printf '    %-28s %s\n' "size" "$(du -h "${OUT}" | cut -f1)"
echo
echo "    Test it before sending:"
echo "      tar -xzf $(basename "${OUT}") && cd viper-workshop-extras && ./install.sh --check"
