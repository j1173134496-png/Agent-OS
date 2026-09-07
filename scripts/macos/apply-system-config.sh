#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

require_m2_environment
require_private_env

pwsh -NoProfile -File "${AGENTOS_ROOT}/scripts/Sync-AgentOSV032Policy.ps1"
pwsh -NoProfile -File "${AGENTOS_ROOT}/scripts/Sync-AgentOSAgents.ps1"
pwsh -NoProfile -File "${AGENTOS_ROOT}/scripts/Health-AgentOS.ps1"

echo "System configuration applied. The managed Agent should now be visible in the marketplace."
