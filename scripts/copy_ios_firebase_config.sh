#!/bin/sh
set -eu

case "${CONFIGURATION:-}" in
  *staging*)
    source_path="${PROJECT_DIR}/Runner/GoogleService-Info-staging.plist"
    ;;
  *)
    source_path="${PROJECT_DIR}/Runner/GoogleService-Info.plist"
    ;;
esac

destination_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
destination_path="${destination_dir}/GoogleService-Info.plist"

if [ ! -f "$source_path" ]; then
  echo "error: Missing Firebase config plist at $source_path" >&2
  exit 1
fi

mkdir -p "$destination_dir"
cp "$source_path" "$destination_path"
echo "Copied $(basename "$source_path") to ${destination_path}"
