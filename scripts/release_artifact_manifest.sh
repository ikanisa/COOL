#!/usr/bin/env bash
# Keep the existing manual command available.
exec "$(dirname "$0")/release/release_artifact_manifest.sh" "$@"
