#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTOS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

export AGENTOS_API_IMAGE="${AGENTOS_API_IMAGE:-agentos/librechat:v0.3.2-m2}"
export AGENTOS_API_PLATFORM="${AGENTOS_API_PLATFORM:-linux/arm64}"
export AGENTOS_API_PULL_POLICY="${AGENTOS_API_PULL_POLICY:-never}"
export AGENTOS_MONGO_IMAGE="${AGENTOS_MONGO_IMAGE:-mongo:8.0.20}"
export AGENTOS_MONGO_PLATFORM="${AGENTOS_MONGO_PLATFORM:-linux/arm64}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_m2_environment() {
  require_command git
  require_command docker
  require_command pwsh

  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "This entry point is for macOS. Detected: $(uname -s)" >&2
    exit 1
  fi
  if [[ "$(uname -m)" != "arm64" ]]; then
    echo "This entry point expects Apple Silicon (arm64). Detected: $(uname -m)" >&2
    exit 1
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "Docker Desktop is not running." >&2
    exit 1
  fi
}

require_private_env() {
  if [[ ! -f "${AGENTOS_ROOT}/.env" ]]; then
    pwsh -NoProfile -File "${AGENTOS_ROOT}/scripts/New-AgentOSEnv.ps1"
    echo "Created ${AGENTOS_ROOT}/.env." >&2
    echo "Set AGENTOS_LLM_BASE_URL, AGENTOS_LLM_API_KEY and SUBMIT_MCP_TOKEN, then rerun this command." >&2
    exit 2
  fi

  local unresolved
  unresolved="$(grep -E '=(__REQUIRED__|__REQUIRED_PRIVATE_SERVICE_TOKEN__)$' "${AGENTOS_ROOT}/.env" | cut -d= -f1 || true)"
  if [[ -n "${unresolved}" ]]; then
    echo "Private .env still has unresolved values:" >&2
    echo "${unresolved}" >&2
    exit 2
  fi
}
