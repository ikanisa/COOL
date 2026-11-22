#!/usr/bin/env bash
# Keep the existing manual command available.
exec "$(dirname "$0")/release/native_mobile_accessibility_signoff_gate.sh" "$@"
