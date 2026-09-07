#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

require_m2_environment
require_private_env

if ! docker image inspect "${AGENTOS_API_IMAGE}" >/dev/null 2>&1; then
  echo "Missing ${AGENTOS_API_IMAGE}. Run ./scripts/macos/bootstrap-agentos.sh first." >&2
  exit 1
fi

pwsh -NoProfile -File "${AGENTOS_ROOT}/scripts/Start-AgentOSV032.ps1"
