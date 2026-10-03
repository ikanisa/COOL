#!/usr/bin/env bash

# Populate script arrays from the versioned contract, after validating local
# entrypoints, JWT settings and auth wiring. Names only; never credential values.
collect_load_edge_inventory() {
  local collect_inventory_helper collect_inventory_values collect_inventory_name
  collect_inventory_helper="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/edge_function_inventory.rb"
  ruby "$collect_inventory_helper" auth-check || return 1
  EXPECTED_FUNCTIONS=()
  NO_VERIFY_JWT_FUNCTIONS=()
  RETIRED_FUNCTIONS=()
  REQUIRED_SECRETS=()
  collect_inventory_values="$(ruby "$collect_inventory_helper" expected)" || return 1
  while IFS= read -r collect_inventory_name; do
    [[ -z "$collect_inventory_name" ]] || EXPECTED_FUNCTIONS+=("$collect_inventory_name")
  done <<< "$collect_inventory_values"
  collect_inventory_values="$(ruby "$collect_inventory_helper" no-verify-jwt)" || return 1
  while IFS= read -r collect_inventory_name; do
    [[ -z "$collect_inventory_name" ]] || NO_VERIFY_JWT_FUNCTIONS+=("$collect_inventory_name")
  done <<< "$collect_inventory_values"
  collect_inventory_values="$(ruby "$collect_inventory_helper" retired)" || return 1
  while IFS= read -r collect_inventory_name; do
    [[ -z "$collect_inventory_name" ]] || RETIRED_FUNCTIONS+=("$collect_inventory_name")
  done <<< "$collect_inventory_values"
  collect_inventory_values="$(ruby "$collect_inventory_helper" secrets)" || return 1
  while IFS= read -r collect_inventory_name; do
    [[ -z "$collect_inventory_name" ]] || REQUIRED_SECRETS+=("$collect_inventory_name")
  done <<< "$collect_inventory_values"
}
