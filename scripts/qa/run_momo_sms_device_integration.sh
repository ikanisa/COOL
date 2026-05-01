#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export SUITE="${SUITE:-momo-sms}"
export AUTO_GRANT_SMS_PERMISSION="${AUTO_GRANT_SMS_PERMISSION:-1}"

exec bash "$ROOT_DIR/scripts/qa/run_device_integration.sh" "$@"
