#!/usr/bin/env bash

# Parse a dotenv file as data. Never source or evaluate it as shell code.
collect_load_dotenv_strict() {
  local dotenv_file="${1:-}"
  local metadata owner_id mode line key value first last
  local current_id

  [[ -n "$dotenv_file" ]] || {
    printf '[dotenv][FAIL] dotenv path is required\n' >&2
    return 1
  }
  [[ -f "$dotenv_file" && ! -L "$dotenv_file" ]] || {
    printf '[dotenv][FAIL] expected a regular, non-symlink file: %s\n' "$dotenv_file" >&2
    return 1
  }

  current_id="$(id -u)"
  if metadata="$(stat -f '%u %Lp' "$dotenv_file" 2>/dev/null)"; then
    :
  elif metadata="$(stat -c '%u %a' "$dotenv_file" 2>/dev/null)"; then
    :
  else
    printf '[dotenv][FAIL] cannot inspect ownership and mode: %s\n' "$dotenv_file" >&2
    return 1
  fi
  owner_id="${metadata%% *}"
  mode="${metadata##* }"
  [[ "$owner_id" == "$current_id" ]] || {
    printf '[dotenv][FAIL] dotenv must be owned by the current user: %s\n' "$dotenv_file" >&2
    return 1
  }
  [[ "$mode" =~ ^[0-7]?[0-7]00$ ]] || {
    printf '[dotenv][FAIL] dotenv must not be readable or writable by group/other (mode %s): %s\n' "$mode" "$dotenv_file" >&2
    return 1
  }

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]] || {
      printf '[dotenv][FAIL] unsupported dotenv line; use KEY=VALUE only: %s\n' "$dotenv_file" >&2
      return 1
    }
    key="${line%%=*}"
    value="${line#*=}"

    if [[ ${#value} -ge 2 ]]; then
      first="${value:0:1}"
      last="${value: -1}"
      if [[ "$first" == "'" || "$first" == '"' ]]; then
        [[ "$last" == "$first" ]] || {
          printf '[dotenv][FAIL] unterminated quoted value for %s\n' "$key" >&2
          return 1
        }
        value="${value:1:${#value}-2}"
      elif [[ "$last" == "'" || "$last" == '"' ]]; then
        printf '[dotenv][FAIL] unmatched quote in value for %s\n' "$key" >&2
        return 1
      fi
    fi

    [[ "$value" != *$'\n'* ]] || {
      printf '[dotenv][FAIL] multiline value rejected for %s\n' "$key" >&2
      return 1
    }
    if [[ "$value" == *'$('* ||
      "$value" == *'${'* ||
      "$value" == *'`'* ||
      "$value" == *'<('* ||
      "$value" == *'>('* ]]; then
      printf '[dotenv][FAIL] shell expansion syntax rejected for %s\n' "$key" >&2
      return 1
    fi
    export "$key=$value"
  done <"$dotenv_file"
}
