#!/usr/bin/env bash
#
# Business API drift check: verifies that the OpenAPI contracts and the
# service implementations agree on the set of business routes.
#
# Checks performed:
#   - HRPAuth core            vs docs/api/openapi/hrpauth-business.yaml
#   - HASkinLib               vs docs/api/openapi/haskinlib-business.yaml
#   - HRPAuth-Yggdrasil-API   vs docs/api/openapi/hrpauth-yggdrasil-business.yaml
#     (protocol routes documented in docs/dev/HRPAuth/yggdrasil-api.md are
#      excluded from the implementation->contract direction)
#
# Both directions are checked: routes present in code but missing from the
# contract, and contract paths with no registered route.
#
# Implementation repositories are located via environment variables, falling
# back to sibling directories of this repository, then to ~/Desktop/HA:
#   HRPAUTH_REPO_DIR, HASKINLIB_REPO_DIR, YGGDRASIL_REPO_DIR
#
# Missing repositories or contract files are hard errors (no silent pass).

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"

fail() {
  echo "ERROR: $*" >&2
  exit 2
}

resolve_repo() {
  local env_value="$1" name="$2"
  if [[ -n "$env_value" ]]; then
    [[ -d "$env_value" ]] || fail "$name repository not found at \$$3='$env_value'"
    echo "$env_value"
    return
  fi
  local candidate
  for candidate in "$ROOT/../$name" "$HOME/Desktop/HA/$name"; do
    if [[ -f "$candidate/main.go" ]]; then
      echo "$(readlink -f "$candidate")"
      return
    fi
  done
  fail "$name repository not found (set $3 or place it next to HA-Contract)"
}

HRPAUTH_DIR="$(resolve_repo "${HRPAUTH_REPO_DIR:-}" HRPAuth HRPAUTH_REPO_DIR)"
HASKINLIB_DIR="$(resolve_repo "${HASKINLIB_REPO_DIR:-}" HASkinLib HASKINLIB_REPO_DIR)"
YGGDRASIL_DIR="$(resolve_repo "${YGGDRASIL_REPO_DIR:-}" HRPAuth-Yggdrasil-API YGGDRASIL_REPO_DIR)"

HRPAUTH_YAML="$ROOT/docs/api/openapi/hrpauth-business.yaml"
HASKINLIB_YAML="$ROOT/docs/api/openapi/haskinlib-business.yaml"
YGGDRASIL_YAML="$ROOT/docs/api/openapi/hrpauth-yggdrasil-business.yaml"

for f in "$HRPAUTH_YAML" "$HASKINLIB_YAML" "$YGGDRASIL_YAML"; do
  [[ -f "$f" ]] || fail "contract file missing: $f"
done

command -v rg >/dev/null 2>&1 || fail "ripgrep (rg) is required"

normalize_route() {
  sed -E 's/:([A-Za-z_][A-Za-z0-9_]*)/{\1}/g'
}

extract_gin_routes() {
  # $1 = main.go path; captures GET/POST/PUT/DELETE registrations and resolves
  # router group prefixes (e.g. auth := r.Group("/authserver")).
  awk '
    match($0, /([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:=[[:space:]][^=].*\.Group\("([^"]*)"\)/, g) {
      groups[g[1]] = g[2]
    }
    match($0, /([A-Za-z_][A-Za-z0-9_]*)\.(GET|POST|PUT|DELETE)\("([^"]*)"/, m) {
      prefix = (m[1] in groups) ? groups[m[1]] : ""
      path = prefix m[3]
      if (path == "") path = "/"
      print path
    }
  ' "$1" | normalize_route | sort -u
}

extract_openapi_paths() {
  rg '^  /' "$1" | sed -E 's/^  ([^:]+):$/\1/' | sort -u
}

DRIFT_FOUND=0

check_set() {
  local name="$1" expected_file="$2" actual_file="$3" direction="$4" exclude_file="${5:-}"

  local filtered_expected="$expected_file"
  local filtered_actual="$actual_file"
  local tmp_filtered=""
  if [[ -n "$exclude_file" ]]; then
    tmp_filtered="$(mktemp)"
    if [[ "$direction" == "impl-vs-contract" ]]; then
      # Exclude documented protocol routes from the implementation side.
      grep -vxF -f "$exclude_file" "$expected_file" > "$tmp_filtered" || true
      filtered_expected="$tmp_filtered"
    else
      # Exclude tombstone/planned entries from the contract side.
      grep -vxF -f "$exclude_file" "$actual_file" > "$tmp_filtered" || true
      filtered_actual="$tmp_filtered"
    fi
  fi

  local missing
  if [[ "$direction" == "impl-vs-contract" ]]; then
    missing="$(comm -23 "$filtered_expected" "$filtered_actual" || true)"
    if [[ -n "$missing" ]]; then
      echo "[$name] routes present in code but missing from contract:"
      echo "$missing" | sed 's/^/  - /'
      DRIFT_FOUND=1
    fi
  else
    missing="$(comm -13 "$filtered_expected" "$filtered_actual" || true)"
    if [[ -n "$missing" ]]; then
      echo "[$name] contract paths with no registered route:"
      echo "$missing" | sed 's/^/  - /'
      DRIFT_FOUND=1
    fi
  fi

  if [[ -n "$tmp_filtered" ]]; then
    rm -f "$tmp_filtered"
  fi
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# --- HRPAuth core ---
extract_gin_routes "$HRPAUTH_DIR/main.go" > "$tmpdir/hrpauth-routes.txt"
extract_openapi_paths "$HRPAUTH_YAML" > "$tmpdir/hrpauth-openapi.txt"

# Tombstone entries kept in the contract as migration references (removed
# endpoints that no longer have a registered route).
cat > "$tmpdir/hrpauth-tombstones.txt" <<'EOF'
/user/declare-email
EOF

check_set "HRPAuth" "$tmpdir/hrpauth-routes.txt" "$tmpdir/hrpauth-openapi.txt" impl-vs-contract
check_set "HRPAuth" "$tmpdir/hrpauth-routes.txt" "$tmpdir/hrpauth-openapi.txt" contract-vs-impl "$tmpdir/hrpauth-tombstones.txt"

# --- HASkinLib ---
extract_gin_routes "$HASKINLIB_DIR/main.go" > "$tmpdir/haskinlib-routes.txt"
extract_openapi_paths "$HASKINLIB_YAML" > "$tmpdir/haskinlib-openapi.txt"

check_set "HASkinLib" "$tmpdir/haskinlib-routes.txt" "$tmpdir/haskinlib-openapi.txt" impl-vs-contract
check_set "HASkinLib" "$tmpdir/haskinlib-routes.txt" "$tmpdir/haskinlib-openapi.txt" contract-vs-impl

# --- HRPAuth-Yggdrasil-API ---
# Protocol routes are specified in docs/dev/HRPAuth/yggdrasil-api.md, not in
# the business yaml; they are excluded from the impl->contract direction.
cat > "$tmpdir/yggdrasil-protocol-paths.txt" <<'EOF'
/
/authserver/authenticate
/authserver/refresh
/authserver/validate
/authserver/invalidate
/authserver/signout
/sessionserver/session/minecraft/join
/sessionserver/session/minecraft/hasJoined
/sessionserver/session/minecraft/hasjoined
/sessionserver/session/minecraft/profile/{uuid}
/api/profiles/minecraft
/minecraftservices/player/certificates
/minecraftservices/publickeys
/textures/{hash}
/skins/MinecraftSkins/{username}
EOF

extract_gin_routes "$YGGDRASIL_DIR/main.go" > "$tmpdir/yggdrasil-routes.txt"
extract_openapi_paths "$YGGDRASIL_YAML" > "$tmpdir/yggdrasil-openapi.txt"

check_set "HRPAuth-Yggdrasil-API" "$tmpdir/yggdrasil-routes.txt" "$tmpdir/yggdrasil-openapi.txt" impl-vs-contract "$tmpdir/yggdrasil-protocol-paths.txt"
check_set "HRPAuth-Yggdrasil-API" "$tmpdir/yggdrasil-routes.txt" "$tmpdir/yggdrasil-openapi.txt" contract-vs-impl

if [[ "$DRIFT_FOUND" -eq 1 ]]; then
  echo "Business API drift detected."
  exit 1
fi

echo "Business API drift check passed."
