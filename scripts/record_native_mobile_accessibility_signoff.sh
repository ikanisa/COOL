#!/usr/bin/env bash
# Keep the existing manual command available.
exec "$(dirname "$0")/release/record_native_mobile_accessibility_signoff.sh" "$@"
