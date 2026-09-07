#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

require_m2_environment
require_private_env

pwsh -NoProfile -File "${AGENTOS_ROOT}/scripts/Secret-Scan-AgentOS.ps1"
pwsh -NoProfile -File "${AGENTOS_ROOT}/scripts/Health-AgentOS.ps1"
pwsh -NoProfile -File "${AGENTOS_ROOT}/scripts/Test-AgentOSV032Static.ps1"
pwsh -NoProfile -File "${AGENTOS_ROOT}/scripts/Test-AgentOSV032Gate.ps1"
