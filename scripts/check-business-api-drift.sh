#!/usr/bin/env bash
set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"

normalize_route() {
  sed -E 's/:([A-Za-z_][A-Za-z0-9_]*)/{\1}/g'
}

extract_hrpauth_routes() {
  {
    printf '/status\n'
    rg -o 'api\.(GET|POST)\("[^"]+"' "$ROOT/HRPAuth/main.go" | sed -E 's/.*\("([^"]+)"/\1/'
  } | sort -u
}

extract_haskinlib_routes() {
  rg -o 'r\.(GET|POST|PUT)\("[^"]+"' "$ROOT/HASkinLib/main.go" | sed -E 's/.*\("([^"]+)"/\1/' | sort -u
}

extract_openapi_paths() {
  local file="$1"
  rg '^  /' "$file" | sed -E 's/^  ([^:]+):$/\1/' | sort -u
}

check_set() {
  local name="$1"
  local expected_file="$2"
  local actual_file="$3"
  local missing

  missing="$(comm -23 "$expected_file" "$actual_file" || true)"
  if [[ -n "$missing" ]]; then
    echo "$name routes missing from OpenAPI:"
    echo "$missing"
    exit 1
  fi
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

extract_hrpauth_routes | normalize_route > "$tmpdir/hrpauth-routes.txt"
extract_haskinlib_routes | normalize_route > "$tmpdir/haskinlib-routes.txt"
extract_openapi_paths "$ROOT/docs/api/openapi/hrpauth-business.yaml" > "$tmpdir/hrpauth-openapi.txt"
extract_openapi_paths "$ROOT/docs/api/openapi/haskinlib-business.yaml" > "$tmpdir/haskinlib-openapi.txt"

check_set "HRPAuth" "$tmpdir/hrpauth-routes.txt" "$tmpdir/hrpauth-openapi.txt"
check_set "HASkinLib" "$tmpdir/haskinlib-routes.txt" "$tmpdir/haskinlib-openapi.txt"

echo "Business API drift check passed."
