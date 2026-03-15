#!/usr/bin/env bash

readonly IOS_MAPS_KEYS_XCCONFIG="$ROOT_DIR/ios/Flutter/MapsKeys.xcconfig"

ios_value_is_placeholder() {
  local normalized lowered
  normalized="$(printf '%s' "${1:-}" | tr -d '\r')"
  if [[ -z "${normalized//[[:space:]]/}" ]]; then
    return 0
  fi

  case "$normalized" in
    REPLACE_WITH*|TEAMID.*|0000000000)
      return 0
      ;;
  esac

  lowered="$(printf '%s' "$normalized" | tr '[:upper:]' '[:lower:]')"
  [[ "$lowered" == "your_google_maps_ios_api_key" || "$lowered" == *placeholder* ]]
}

resolve_ios_maps_key() {
  if [[ -n "${GOOGLE_MAPS_IOS_API_KEY:-}" ]]; then
    printf '%s\n' "$(printf '%s' "$GOOGLE_MAPS_IOS_API_KEY" | tr -d '\r')"
    return 0
  fi

  if [[ ! -f "$IOS_MAPS_KEYS_XCCONFIG" ]]; then
    return 1
  fi

  awk -F= '/^GOOGLE_MAPS_IOS_API_KEY=/{sub(/\r$/, "", $2); print $2}' \
    "$IOS_MAPS_KEYS_XCCONFIG" | tail -n 1
}

has_ios_maps_key() {
  local maps_key
  maps_key="$(resolve_ios_maps_key || true)"
  if ios_value_is_placeholder "$maps_key"; then
    return 1
  fi
  return 0
}
