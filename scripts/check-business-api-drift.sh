#!/usr/bin/env bash
#
# Business API drift check: verifies that the OpenAPI contracts and the
# service implementations agree on the registered business routes, at the
# METHOD + path level, in both directions.
#
# Checks performed:
#   - HRPAuth core            vs docs/api/openapi/hrpauth-business.yaml
#   - HASkinLib               vs docs/api/openapi/haskinlib-business.yaml
#   - HRPAuth-Yggdrasil-API   vs docs/api/openapi/hrpauth-yggdrasil-business.yaml
#     (protocol routes documented in docs/dev/HRPAuth/yggdrasil-api.md are
#      excluded from the implementation->contract direction)
#   - MatchCoreArena-Server   vs docs/api/openapi/matchcorearena-business.yaml
#   - WinnerProxy             vs docs/api/openapi/winnerproxy-business.yaml
#     (the /winnerproxy-prefixed alias registrations are excluded; the
#      contract documents the canonical prefix-less form)
#   - Cascade proxy           vs docs/api/openapi/cascade-proxy.yaml
#     (the backend control plane lives in cascade-backend-v1.yaml and is
#      implemented outside these repositories; see docs/dev/Cascade/README.md)
#
# Both directions are checked: METHOD+path present in code but missing from
# the contract, and contract METHOD+path with no registered route.
#
# Implementation repositories are located via environment variables, falling
# back to sibling directories of this repository, then to ~/Desktop/HA
# (~/Cascade for the Cascade proxy):
#   HRPAUTH_REPO_DIR, HASKINLIB_REPO_DIR, YGGDRASIL_REPO_DIR,
#   MATCHCOREARENA_REPO_DIR, WINNERPROXY_REPO_DIR, CASCADE_REPO_DIR
#
# Missing repositories or contract files are hard errors (no silent pass).

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"

fail() {
  echo "ERROR: $*" >&2
  exit 2
}

resolve_repo() {
  local env_value="$1" name="$2" env_name="$3"; shift 3
  if [[ -n "$env_value" ]]; then
    [[ -d "$env_value" ]] || fail "$name repository not found at \$$env_name='$env_value'"
    echo "$env_value"
    return
  fi
  local candidate
  for candidate in "$ROOT/../$name" "$HOME/Desktop/HA/$name" "$@"; do
    if [[ -d "$candidate" ]]; then
      echo "$(readlink -f "$candidate")"
      return
    fi
  done
  fail "$name repository not found (set $env_name or place it next to HA-Contract)"
}

HRPAUTH_DIR="$(resolve_repo "${HRPAUTH_REPO_DIR:-}" HRPAuth HRPAUTH_REPO_DIR)"
HASKINLIB_DIR="$(resolve_repo "${HASKINLIB_REPO_DIR:-}" HASkinLib HASKINLIB_REPO_DIR)"
YGGDRASIL_DIR="$(resolve_repo "${YGGDRASIL_REPO_DIR:-}" HRPAuth-Yggdrasil-API YGGDRASIL_REPO_DIR)"
MATCHCOREARENA_DIR="$(resolve_repo "${MATCHCOREARENA_REPO_DIR:-}" MatchCoreArena-Server MATCHCOREARENA_REPO_DIR)"
WINNERPROXY_DIR="$(resolve_repo "${WINNERPROXY_REPO_DIR:-}" WinnerProxy WINNERPROXY_REPO_DIR)"
CASCADE_DIR="$(resolve_repo "${CASCADE_REPO_DIR:-}" Cascade CASCADE_REPO_DIR "$HOME/Cascade")"

HRPAUTH_YAML="$ROOT/docs/api/openapi/hrpauth-business.yaml"
HASKINLIB_YAML="$ROOT/docs/api/openapi/haskinlib-business.yaml"
YGGDRASIL_YAML="$ROOT/docs/api/openapi/hrpauth-yggdrasil-business.yaml"
MATCHCOREARENA_YAML="$ROOT/docs/api/openapi/matchcorearena-business.yaml"
WINNERPROXY_YAML="$ROOT/docs/api/openapi/winnerproxy-business.yaml"
CASCADE_PROXY_YAML="$ROOT/docs/api/openapi/cascade-proxy.yaml"

for f in "$HRPAUTH_YAML" "$HASKINLIB_YAML" "$YGGDRASIL_YAML" "$MATCHCOREARENA_YAML" "$WINNERPROXY_YAML" "$CASCADE_PROXY_YAML"; do
  [[ -f "$f" ]] || fail "contract file missing: $f"
done

command -v rg >/dev/null 2>&1 || fail "ripgrep (rg) is required"

normalize_route() {
  sed -E 's/:([A-Za-z_][A-Za-z0-9_]*)/{\1}/g'
}

extract_gin_routes() {
  # $1 = route file; emits "METHOD /path" lines. Captures GET/POST/PUT/DELETE
  # registrations and resolves router group prefixes
  # (e.g. auth := r.Group("/authserver")). Group variables that are function
  # parameters (not assigned via :=) resolve to an empty prefix, which is the
  # canonical form for alias-registered routes.
  awk '
    match($0, /([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*:=[[:space:]][^=].*\.Group\("([^"]*)"\)/, g) {
      groups[g[1]] = g[2]
    }
    match($0, /([A-Za-z_][A-Za-z0-9_]*)\.(GET|POST|PUT|DELETE)\("([^"]*)"/, m) {
      prefix = (m[1] in groups) ? groups[m[1]] : ""
      path = prefix m[3]
      if (path == "") path = "/"
      print m[2] " " path
    }
  ' "$1" | normalize_route | sort -u
}

extract_openapi_routes() {
  # Emits "METHOD /path" lines from an OpenAPI file: top-level path keys under
  # `paths:` (two-space indent) and operation keys (four-space indent) up to
  # the `components:` section.
  awk '
    /^components:/ { in_paths = 0 }
    /^paths:/ { in_paths = 1; next }
    in_paths && /^  \/[^ ]*:[[:space:]]*$/ {
      path = substr($1, 1, length($1) - 1)
      sub(/^  /, "", path)
      next
    }
    in_paths && /^    (get|post|put|delete|patch):[[:space:]]*$/ {
      method = toupper($1)
      sub(/:$/, "", method)
      if (path != "") print method " " path
    }
  ' "$1" | sort -u
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
      # Exclude documented protocol/alias routes from the implementation side.
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
      echo "[$name] contract routes with no registered implementation:"
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
extract_openapi_routes "$HRPAUTH_YAML" > "$tmpdir/hrpauth-openapi.txt"

# Tombstone entries kept in the contract as migration references (removed
# endpoints that no longer have a registered route).
cat > "$tmpdir/hrpauth-tombstones.txt" <<'EOF'
POST /user/declare-email
EOF

check_set "HRPAuth" "$tmpdir/hrpauth-routes.txt" "$tmpdir/hrpauth-openapi.txt" impl-vs-contract
check_set "HRPAuth" "$tmpdir/hrpauth-routes.txt" "$tmpdir/hrpauth-openapi.txt" contract-vs-impl "$tmpdir/hrpauth-tombstones.txt"

# --- HASkinLib ---
extract_gin_routes "$HASKINLIB_DIR/main.go" > "$tmpdir/haskinlib-routes.txt"
extract_openapi_routes "$HASKINLIB_YAML" > "$tmpdir/haskinlib-openapi.txt"

check_set "HASkinLib" "$tmpdir/haskinlib-routes.txt" "$tmpdir/haskinlib-openapi.txt" impl-vs-contract
check_set "HASkinLib" "$tmpdir/haskinlib-routes.txt" "$tmpdir/haskinlib-openapi.txt" contract-vs-impl

# --- HRPAuth-Yggdrasil-API ---
# Protocol routes are specified in docs/dev/HRPAuth/yggdrasil-api.md, not in
# the business yaml; they are excluded from the impl->contract direction.
cat > "$tmpdir/yggdrasil-protocol-paths.txt" <<'EOF'
GET /
POST /authserver/authenticate
POST /authserver/refresh
POST /authserver/validate
POST /authserver/invalidate
POST /authserver/signout
POST /sessionserver/session/minecraft/join
GET /sessionserver/session/minecraft/hasJoined
GET /sessionserver/session/minecraft/hasjoined
GET /sessionserver/session/minecraft/profile/{uuid}
POST /api/profiles/minecraft
POST /minecraftservices/player/certificates
GET /minecraftservices/publickeys
GET /textures/{hash}
GET /skins/MinecraftSkins/{username}
EOF

extract_gin_routes "$YGGDRASIL_DIR/main.go" > "$tmpdir/yggdrasil-routes.txt"
extract_openapi_routes "$YGGDRASIL_YAML" > "$tmpdir/yggdrasil-openapi.txt"

check_set "HRPAuth-Yggdrasil-API" "$tmpdir/yggdrasil-routes.txt" "$tmpdir/yggdrasil-openapi.txt" impl-vs-contract "$tmpdir/yggdrasil-protocol-paths.txt"
check_set "HRPAuth-Yggdrasil-API" "$tmpdir/yggdrasil-routes.txt" "$tmpdir/yggdrasil-openapi.txt" contract-vs-impl

# --- MatchCoreArena-Server ---
extract_gin_routes "$MATCHCOREARENA_DIR/api/router.go" > "$tmpdir/mca-routes.txt"
extract_openapi_routes "$MATCHCOREARENA_YAML" > "$tmpdir/mca-openapi.txt"

check_set "MatchCoreArena-Server" "$tmpdir/mca-routes.txt" "$tmpdir/mca-openapi.txt" impl-vs-contract
check_set "MatchCoreArena-Server" "$tmpdir/mca-routes.txt" "$tmpdir/mca-openapi.txt" contract-vs-impl

# --- WinnerProxy ---
# Every Yggdrasil route is also registered under the /winnerproxy prefix via
# a group argument (not a named group variable), so only the canonical
# prefix-less form and the /winnerproxy meta alias appear in the extraction;
# the alias itself is excluded here and documented in the contract.
cat > "$tmpdir/winnerproxy-aliases.txt" <<'EOF'
GET /winnerproxy
EOF

extract_gin_routes "$WINNERPROXY_DIR/internal/router/router.go" > "$tmpdir/winnerproxy-routes.txt"
extract_openapi_routes "$WINNERPROXY_YAML" > "$tmpdir/winnerproxy-openapi.txt"

check_set "WinnerProxy" "$tmpdir/winnerproxy-routes.txt" "$tmpdir/winnerproxy-openapi.txt" impl-vs-contract "$tmpdir/winnerproxy-aliases.txt"
check_set "WinnerProxy" "$tmpdir/winnerproxy-routes.txt" "$tmpdir/winnerproxy-openapi.txt" contract-vs-impl

# --- Cascade proxy ---
# The backend control plane (cascade-backend-v1.yaml) is implemented in the
# Avalon Go server (CoreMatch/Avalon) outside these repositories and is intentionally not
# checked here (see docs/dev/Cascade/README.md, "Anti-drift status").
extract_gin_routes "$CASCADE_DIR/internal/api/proxy_http.go" > "$tmpdir/cascade-routes.txt"
extract_openapi_routes "$CASCADE_PROXY_YAML" > "$tmpdir/cascade-openapi.txt"

check_set "Cascade-proxy" "$tmpdir/cascade-routes.txt" "$tmpdir/cascade-openapi.txt" impl-vs-contract
check_set "Cascade-proxy" "$tmpdir/cascade-routes.txt" "$tmpdir/cascade-openapi.txt" contract-vs-impl

if [[ "$DRIFT_FOUND" -eq 1 ]]; then
  echo "Business API drift detected."
  exit 1
fi

echo "Business API drift check passed."
