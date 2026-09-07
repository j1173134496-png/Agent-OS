#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

require_m2_environment
require_private_env

if ! docker image inspect "${AGENTOS_API_IMAGE}" >/dev/null 2>&1; then
  echo "Building AgentOS API image for Apple Silicon: ${AGENTOS_API_IMAGE}"
  docker build \
    --platform "${AGENTOS_API_PLATFORM}" \
    --file "${AGENTOS_ROOT}/source/librechat-maintained/Dockerfile" \
    --tag "${AGENTOS_API_IMAGE}" \
    "${AGENTOS_ROOT}/source/librechat-maintained"
fi

pwsh -NoProfile -File "${AGENTOS_ROOT}/scripts/Start-AgentOSV032.ps1" -BootstrapOnly

echo
echo "Bootstrap phase completed."
echo "1. Open http://localhost:3080 and register the first administrator."
echo "2. Run ./scripts/macos/apply-system-config.sh"
