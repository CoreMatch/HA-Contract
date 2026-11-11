#!/usr/bin/env bash
#
# Consumer URL drift check: verifies that every backend URL called by the
# ecosystem's consumers (frontends, launcher, proxy plugins, game-side
# reporters) exists in the HA-Contract OpenAPI surface — the caller side of
# the contract, complementing check-business-api-drift.sh (the server side).
#
# Consumers checked (all read-only):
#   - MatchCoreArena-Client      (Go services -> matchcorearena-business.yaml)
#   - MatchCoreArena-VelocityGate (Java -> matchcorearena-business.yaml)
#   - BedwarsRel-MCA             (Java + config.yml -> matchcorearena-business.yaml)
#   - HRPAuth-Spigot             (Java -> hrpauth/yggdrasil business yamls)
#   - SamuelClient               (Go -> Yggdrasil protocol surface)
#   - HASkinProxy upstream client (Go -> hrpauth/yggdrasil business yamls)
#   - HRPAuth-Web                (TS -> hrpauth/yggdrasil/haskinlib yamls)
#   - HRPAuth-Yggdrasil-API core client (Go -> hrpauth-business.yaml /internal/*)
#   - Cascade backend client     (Go -> cascade-backend-v1.yaml control plane)
#   - MCA-Cascade                (Go library -> matchcorearena-business.yaml)
#   - MatchCoreArena-MaintenanceView (Go ops console -> matchcorearena-business.yaml)
#   - HA-Services-MaintenanceView (Go ops panel -> ha-services-deployer.yaml)
#   - Grail CLI + mirror client  (Go -> grail.yaml)
#   - RW-Mod-Injector            (Java -> cascade-backend-v1.yaml mod surface)
#   - Cascade plugin hub         (Go -> cascade-plugin-v1.yaml plugin endpoints)
#   - Avalon plugin hub          (Go -> avalon-plugin-v1.yaml plugin endpoints)
#
# The Yggdrasil PROTOCOL surface (/authserver/*, /sessionserver/*, ...) is
# specified in HRPAuth-Yggdrasil-API knowledge/0010, not in a business yaml;
# it is carried here as an explicit allowlist (same list as
# check-business-api-drift.sh).
#
# Path parameters are compared wildcard-agnostic: `{anything}` matches
# `{anything}`. A consumer literal ending in `/` followed by runtime
# concatenation is normalized to `.../{param}`.
#
# Discipline: extraction yielding 0 URLs for a consumer is a HARD ERROR
# (silent false greens are forbidden). There are NO known-broken exceptions:
# any consumer URL that resolves to no contract path is a HARD FAILURE. A
# previously broken link that was fixed must stay fixed — if it regresses,
# this check turns red rather than downgrading to a warning.
#
# Exit codes: 0 = all consumer URLs resolve; 1 = unresolved URL(s);
# 2 = environment/read error.

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
  for candidate in "$ROOT/../$name" "$HOME/Desktop/HA/$name" "$ROOT/../hrpauth/$name" "$ROOT/../matchcore/$name" "$ROOT/../rw/$name" "$ROOT/../maintanance/$name" "$@"; do
    if [[ -d "$candidate" ]]; then
      echo "$(readlink -f "$candidate")"
      return
    fi
  done
  fail "$name repository not found (set $env_name or place it next to HA-Contract)"
}

MATCHCOREARENA_CLIENT_DIR="$(resolve_repo "${MCA_CLIENT_REPO_DIR:-}" MatchCoreArena-Client MCA_CLIENT_REPO_DIR)"
VELOCITYGATE_DIR="$(resolve_repo "${VELOCITYGATE_REPO_DIR:-}" MatchCoreArena-VelocityGate VELOCITYGATE_REPO_DIR)"
BEDWARSREL_MCA_DIR="$(resolve_repo "${BEDWARSREL_MCA_REPO_DIR:-}" BedwarsRel-MCA BEDWARSREL_MCA_REPO_DIR)"
HRPAUTH_SPIGOT_DIR="$(resolve_repo "${HRPAUTH_SPIGOT_REPO_DIR:-}" HRPAuth-Spigot HRPAUTH_SPIGOT_REPO_DIR)"
SAMUELCLIENT_DIR="$(resolve_repo "${SAMUELCLIENT_REPO_DIR:-}" SamuelClient SAMUELCLIENT_REPO_DIR)"
HASKINPROXY_DIR="$(resolve_repo "${HASKINPROXY_REPO_DIR:-}" HASkinProxy HASKINPROXY_REPO_DIR)"
HRPAUTH_WEB_DIR="$(resolve_repo "${HRPAUTH_WEB_REPO_DIR:-}" HRPAuth-Web HRPAUTH_WEB_REPO_DIR)"
YGGDRASIL_DIR="$(resolve_repo "${YGGDRASIL_REPO_DIR:-}" HRPAuth-Yggdrasil-API YGGDRASIL_REPO_DIR)"
CASCADE_DIR="$(resolve_repo "${CASCADE_REPO_DIR:-}" Cascade CASCADE_REPO_DIR "$HOME/Cascade")"
AVALON_DIR="$(resolve_repo "${AVALON_REPO_DIR:-}" Avalon AVALON_REPO_DIR)"
GRAIL_DIR="$(resolve_repo "${GRAIL_REPO_DIR:-}" Grail GRAIL_REPO_DIR)"
MCA_CASCADE_DIR="$(resolve_repo "${MCA_CASCADE_REPO_DIR:-}" MCA-Cascade MCA_CASCADE_REPO_DIR)"
MCA_MAINTVIEW_DIR="$(resolve_repo "${MCA_MAINTVIEW_REPO_DIR:-}" MatchCoreArena-MaintenanceView MCA_MAINTVIEW_REPO_DIR)"
HA_MAINTVIEW_DIR="$(resolve_repo "${HA_MAINTVIEW_REPO_DIR:-}" HA-Services-MaintenanceView HA_MAINTVIEW_REPO_DIR)"
RWMI_DIR="$(resolve_repo "${RWMI_REPO_DIR:-}" RW-Mod-Injector RWMI_REPO_DIR)"

command -v gawk >/dev/null 2>&1 || fail "gawk is required"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
python3 -c 'import yaml' 2>/dev/null || fail "PyYAML required"

# ---------------------------------------------------------------------------
# --self-test: proves this checker actually FAILS when a consumer URL loses
# its contract target. The fixture contract renames /api/matchmaking/leave,
# which the MatchCoreArena-Client calls — the mutated fixture must fail and
# name the URL; the clean fixture must pass.
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then
  FIX="$(mktemp -d)"
  trap 'rm -rf "$FIX"' EXIT
  mkdir -p "$FIX/scripts" "$FIX/docs/api/openapi"
  cp "$ROOT/docs/api/openapi/"*.yaml "$FIX/docs/api/openapi/"
  cp "$0" "$FIX/scripts/"
  SCRIPT_NAME="$(basename "$0")"

  REPO_ENV=(
    MCA_CLIENT_REPO_DIR="$MATCHCOREARENA_CLIENT_DIR"
    VELOCITYGATE_REPO_DIR="$VELOCITYGATE_DIR"
    BEDWARSREL_MCA_REPO_DIR="$BEDWARSREL_MCA_DIR"
    HRPAUTH_SPIGOT_REPO_DIR="$HRPAUTH_SPIGOT_DIR"
    SAMUELCLIENT_REPO_DIR="$SAMUELCLIENT_DIR"
    HASKINPROXY_REPO_DIR="$HASKINPROXY_DIR"
    HRPAUTH_WEB_REPO_DIR="$HRPAUTH_WEB_DIR"
    YGGDRASIL_REPO_DIR="$YGGDRASIL_DIR"
    CASCADE_REPO_DIR="$CASCADE_DIR"
    AVALON_REPO_DIR="$AVALON_DIR"
    GRAIL_REPO_DIR="$GRAIL_DIR"
    MCA_CASCADE_REPO_DIR="$MCA_CASCADE_DIR"
    MCA_MAINTVIEW_REPO_DIR="$MCA_MAINTVIEW_DIR"
    HA_MAINTVIEW_REPO_DIR="$HA_MAINTVIEW_DIR"
    RWMI_REPO_DIR="$RWMI_DIR"
  )

  echo "self-test[1/4]: clean fixture must pass"
  if ! env "${REPO_ENV[@]}" bash "$FIX/scripts/$SCRIPT_NAME" >"$FIX/clean.log" 2>&1; then
    cat "$FIX/clean.log" >&2
    echo "SELF-TEST FAILED: clean fixture reported drift" >&2
    exit 1
  fi
  if grep -q "WARNING" "$FIX/clean.log"; then
    cat "$FIX/clean.log" >&2
    echo "SELF-TEST FAILED: clean fixture emitted a warning (no known-broken exceptions should remain)" >&2
    exit 1
  fi

  echo "self-test[2/4]: renaming /api/matchmaking/leave must fail"
  sed -i 's#^  /api/matchmaking/leave:#  /api/matchmaking/leave-renamed:#' \
    "$FIX/docs/api/openapi/matchcorearena-business.yaml"
  grep -q "leave-renamed" "$FIX/docs/api/openapi/matchcorearena-business.yaml" || {
    echo "SELF-TEST FAILED: could not inject the mutation" >&2
    exit 1
  }
  if env "${REPO_ENV[@]}" bash "$FIX/scripts/$SCRIPT_NAME" >"$FIX/mutated.log" 2>&1; then
    cat "$FIX/mutated.log" >&2
    echo "SELF-TEST FAILED: orphaned consumer URL did NOT trigger drift" >&2
    exit 1
  fi
  grep -q "/api/matchmaking/leave" "$FIX/mutated.log" || {
    cat "$FIX/mutated.log" >&2
    echo "SELF-TEST FAILED: drift report does not name the orphaned URL" >&2
    exit 1
  }

  echo "self-test[3/4]: re-breaking the two fixed texture links must fail hard (no warning backdoor)"
  # Restore clean contracts, then drop the two texture targets that the fixed
  # consumers now call (HASkinProxy -> DELETE /texture/delete/{uuid}/{type},
  # HRPAuth-Web -> POST /texture/upload/{uuid}). With the known-broken
  # exceptions removed, these unresolved URLs must be HARD failures.
  cp "$ROOT/docs/api/openapi/"*.yaml "$FIX/docs/api/openapi/"
  sed -i 's#^  /texture/delete/{uuid}/{type}:#  /texture/delete-removed:#' \
    "$FIX/docs/api/openapi/hrpauth-yggdrasil-business.yaml"
  sed -i 's#^  /texture/upload/{uuid}:#  /texture/upload-removed:#' \
    "$FIX/docs/api/openapi/hrpauth-yggdrasil-business.yaml"
  grep -q "texture/delete-removed" "$FIX/docs/api/openapi/hrpauth-yggdrasil-business.yaml" || {
    echo "SELF-TEST FAILED: could not inject the texture/delete mutation" >&2
    exit 1
  }
  grep -q "texture/upload-removed" "$FIX/docs/api/openapi/hrpauth-yggdrasil-business.yaml" || {
    echo "SELF-TEST FAILED: could not inject the texture/upload mutation" >&2
    exit 1
  }
  if env "${REPO_ENV[@]}" bash "$FIX/scripts/$SCRIPT_NAME" >"$FIX/mutated2.log" 2>&1; then
    cat "$FIX/mutated2.log" >&2
    echo "SELF-TEST FAILED: re-broken texture links did NOT trigger drift" >&2
    exit 1
  fi
  grep -q "texture/delete" "$FIX/mutated2.log" || {
    cat "$FIX/mutated2.log" >&2
    echo "SELF-TEST FAILED: drift report does not name texture/delete" >&2
    exit 1
  }
  grep -q "texture/upload" "$FIX/mutated2.log" || {
    cat "$FIX/mutated2.log" >&2
    echo "SELF-TEST FAILED: drift report does not name texture/upload" >&2
    exit 1
  }
  if grep -q "WARNING" "$FIX/mutated2.log"; then
    cat "$FIX/mutated2.log" >&2
    echo "SELF-TEST FAILED: re-broken links were downgraded to WARNING (backdoor still present)" >&2
    exit 1
  fi

  echo "self-test[4/4]: dropping the Grail sync endpoint must fail (new consumer)"
  # Restore clean contracts, then remove /v1/sync/changes which the Grail
  # mirror client calls — the expanded consumer surface must turn red.
  cp "$ROOT/docs/api/openapi/"*.yaml "$FIX/docs/api/openapi/"
  sed -i 's#^  /v1/sync/changes:#  /v1/sync/changes-removed:#' "$FIX/docs/api/openapi/grail.yaml"
  grep -q "sync/changes-removed" "$FIX/docs/api/openapi/grail.yaml" || {
    echo "SELF-TEST FAILED: could not inject the Grail sync mutation" >&2
    exit 1
  }
  if env "${REPO_ENV[@]}" bash "$FIX/scripts/$SCRIPT_NAME" >"$FIX/mutated3.log" 2>&1; then
    cat "$FIX/mutated3.log" >&2
    echo "SELF-TEST FAILED: orphaned Grail sync URL did NOT trigger drift" >&2
    exit 1
  fi
  grep -q "/v1/sync/changes" "$FIX/mutated3.log" || {
    cat "$FIX/mutated3.log" >&2
    echo "SELF-TEST FAILED: drift report does not name /v1/sync/changes" >&2
    exit 1
  }

  echo "self-test passed: clean green; all breakage mutations red with no warning backdoor."
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# --- contract path sets (method-agnostic) ---
openapi_paths() {
  python3 - "$1" <<'PY'
import sys, yaml
with open(sys.argv[1], encoding="utf-8") as f:
    doc = yaml.safe_load(f)
for p in sorted((doc or {}).get("paths") or {}):
    print(p)
PY
}

MCA_YAML="$ROOT/docs/api/openapi/matchcorearena-business.yaml"
HRPAUTH_YAML="$ROOT/docs/api/openapi/hrpauth-business.yaml"
YGG_YAML="$ROOT/docs/api/openapi/hrpauth-yggdrasil-business.yaml"
SKINLIB_YAML="$ROOT/docs/api/openapi/haskinlib-business.yaml"
CASCADE_PROXY_YAML="$ROOT/docs/api/openapi/cascade-proxy.yaml"
CASCADE_BACKEND_YAML="$ROOT/docs/api/openapi/cascade-backend-v1.yaml"
DEPLOYER_YAML="$ROOT/docs/api/openapi/ha-services-deployer.yaml"
GRAIL_YAML="$ROOT/docs/api/openapi/grail.yaml"
CASCADE_PLUGIN_YAML="$ROOT/docs/api/openapi/cascade-plugin-v1.yaml"
AVALON_PLUGIN_YAML="$ROOT/docs/api/openapi/avalon-plugin-v1.yaml"
for f in "$MCA_YAML" "$HRPAUTH_YAML" "$YGG_YAML" "$SKINLIB_YAML" "$CASCADE_PROXY_YAML" "$CASCADE_BACKEND_YAML" "$DEPLOYER_YAML" "$GRAIL_YAML" "$CASCADE_PLUGIN_YAML" "$AVALON_PLUGIN_YAML"; do
  [[ -f "$f" ]] || fail "contract file missing: $f"
done

openapi_paths "$MCA_YAML" > "$tmpdir/mca-paths.txt"
openapi_paths "$HRPAUTH_YAML" > "$tmpdir/hrpauth-paths.txt"
openapi_paths "$YGG_YAML" > "$tmpdir/ygg-paths.txt"
openapi_paths "$SKINLIB_YAML" > "$tmpdir/skinlib-paths.txt"
# Cascade management surface (cascade-proxy.yaml) is a valid contract target
# too — e.g. the contract-first GET /api/plugins plugin-status endpoint.
openapi_paths "$CASCADE_PROXY_YAML" > "$tmpdir/cascade-paths.txt"
# Control-plane, delivery/orchestration, artifact and plugin surfaces.
openapi_paths "$CASCADE_BACKEND_YAML" > "$tmpdir/backend-paths.txt"
openapi_paths "$DEPLOYER_YAML" > "$tmpdir/deployer-paths.txt"
openapi_paths "$GRAIL_YAML" > "$tmpdir/grail-paths.txt"
openapi_paths "$CASCADE_PLUGIN_YAML" > "$tmpdir/cascade-plugin-paths.txt"
openapi_paths "$AVALON_PLUGIN_YAML" > "$tmpdir/avalon-plugin-paths.txt"

# Yggdrasil protocol surface (knowledge/0010; same list as the route drift
# script's exclusion set).
cat > "$tmpdir/ygg-protocol-paths.txt" <<'EOF'
/
/api/profiles/minecraft
/authserver/authenticate
/authserver/invalidate
/authserver/refresh
/authserver/signout
/authserver/validate
/minecraftservices/player/certificates
/minecraftservices/publickeys
/sessionserver/session/minecraft/hasJoined
/sessionserver/session/minecraft/hasjoined
/sessionserver/session/minecraft/join
/sessionserver/session/minecraft/profile/{uuid}
/skins/MinecraftSkins/{username}
/textures/{hash}
EOF

# normalize_path: :param and trailing-slash-concatenation -> {param}
normalize_path() {
  sed -E 's/:([A-Za-z_][A-Za-z0-9_]*)/{\1}/g; s#/$#/{param}#; s#\{[A-Za-z_][A-Za-z0-9_]*\}#{param}#g'
}

# path_in <normalized-path> <paths-file...>: wildcard-agnostic {param} match
path_in() {
  local p="$1"; shift
  local f norm
  for f in "$@"; do
    while IFS= read -r cand; do
      [[ -n "$cand" ]] || continue
      norm="$(printf '%s\n' "$cand" | sed -E 's#\{[A-Za-z_][A-Za-z0-9_]*\}#{param}#g')"
      [[ "$p" == "$norm" ]] && return 0
    done < "$f"
  done
  return 1
}

DRIFT_FOUND=0

# check_url <consumer> <method|-> <path> <paths-file...>
check_url() {
  local consumer="$1" method="$2" path="$3"; shift 3
  local norm
  norm="$(printf '%s\n' "$path" | normalize_path)"
  if path_in "$norm" "$@"; then
    return 0
  fi
  echo "DRIFT: [$consumer] URL $method $norm resolves to no contract path"
  DRIFT_FOUND=1
}

# --- 1. MatchCoreArena-Client (Go; method known) ---
mca_client_urls="$(gawk '
  match($0, /\.(Get|Post|Put|Delete)\("(\/api\/[^"]+)"/, m) {
    print toupper(m[1]) " " m[2]
  }
' "$MATCHCOREARENA_CLIENT_DIR"/internal/services/*.go | sort -u)"
[[ -n "$mca_client_urls" ]] || fail "MatchCoreArena-Client: extracted 0 API URLs — refusing to pass silently"
while read -r method path; do
  method="$(echo "$method" | tr '[:lower:]' '[:upper:]')"
  check_url "MatchCoreArena-Client" "$method" "$path" "$tmpdir/mca-paths.txt" "$tmpdir/cascade-paths.txt"
done <<<"$mca_client_urls"

# --- 2. MatchCoreArena-VelocityGate (Java; GET assignment) ---
vg_urls="$(grep -rhoE '"/api/[^"]*"' "$VELOCITYGATE_DIR/src/main/java" | tr -d '"' | sort -u)"
[[ -n "$vg_urls" ]] || fail "VelocityGate: extracted 0 API URLs — refusing to pass silently"
while IFS= read -r path; do
  check_url "VelocityGate" GET "$path" "$tmpdir/mca-paths.txt" "$tmpdir/cascade-paths.txt"
done <<<"$vg_urls"

# --- 3. BedwarsRel-MCA (Java constants + config.yml) ---
bwr_urls="$(grep -rhoE '"/api/[^"]*"' "$BEDWARSREL_MCA_DIR" --include='*.java' | tr -d '"' | sort -u)"
bwr_cfg="$(grep -rhoE 'https?://[^ "]*/api/[a-z/]+' "$BEDWARSREL_MCA_DIR" --include='*.yml' | sed -E 's#^https?://[^/]+##' | sort -u || true)"
bwr_all="$(printf '%s\n%s\n' "$bwr_urls" "$bwr_cfg" | grep -v '^$' | sort -u || true)"
[[ -n "$bwr_all" ]] || fail "BedwarsRel-MCA: extracted 0 API URLs — refusing to pass silently"
while IFS= read -r path; do
  check_url "BedwarsRel-MCA" POST "$path" "$tmpdir/mca-paths.txt" "$tmpdir/cascade-paths.txt"
done <<<"$bwr_all"

# --- 4. HRPAuth-Spigot (Java; core + relayed yggdrasil business) ---
spigot_urls="$(grep -rhoE '"(/[a-z][^"]*)"' "$HRPAUTH_SPIGOT_DIR/src/main/java" --include='*.java' | tr -d '"' | grep -E '^/(oauth|yggdrasil-api)/' | sort -u)"
[[ -n "$spigot_urls" ]] || fail "HRPAuth-Spigot: extracted 0 API URLs — refusing to pass silently"
while IFS= read -r path; do
  if [[ "$path" == /yggdrasil-api/* ]]; then
    check_url "HRPAuth-Spigot" POST "${path#/yggdrasil-api}" "$tmpdir/ygg-paths.txt" "$tmpdir/ygg-protocol-paths.txt" "$tmpdir/cascade-paths.txt"
  else
    check_url "HRPAuth-Spigot" POST "$path" "$tmpdir/hrpauth-paths.txt" "$tmpdir/cascade-paths.txt"
  fi
done <<<"$spigot_urls"

# --- 5. SamuelClient (Go launcher; Yggdrasil protocol auth) ---
samuel_urls="$(grep -rhoE '"/authserver/[a-z]+"' "$SAMUELCLIENT_DIR" --include='*.go' | tr -d '"' | sort -u)"
[[ -n "$samuel_urls" ]] || fail "SamuelClient: extracted 0 authserver URLs — refusing to pass silently"
while IFS= read -r path; do
  check_url "SamuelClient" POST "$path" "$tmpdir/ygg-protocol-paths.txt" "$tmpdir/ygg-paths.txt" "$tmpdir/cascade-paths.txt"
done <<<"$samuel_urls"

# --- 6. HASkinProxy upstream client (Go) ---
# yggURL("/x") -> /yggdrasil-api relay; BaseURL + "/x" -> core paths.
hsp_ygg="$(grep -oE 'yggURL\("/[^"]+"' "$HASKINPROXY_DIR/internal/hrpauth/client.go" | sed -E 's/yggURL\("//; s/"$//' | sort -u)"
hsp_core="$(grep -oE 'BaseURL \+ "/[a-z/]+"' "$HASKINPROXY_DIR/internal/hrpauth/client.go" | sed -E 's/BaseURL \+ "//; s/"$//' | sort -u)"
hsp_token="$(grep -oE 'TokenURL:[[:space:]]*client.BaseURL \+ "/[^"]+"' "$HASKINPROXY_DIR/internal/hrpauth/client.go" | sed -E 's/.*"(\/[a-z/]+)"$/\1/' | sort -u || true)"
hsp_all="$(printf '%s\n%s\n' "$hsp_core" "$hsp_token" | grep -v '^$' | sort -u)"
[[ -n "$hsp_ygg" ]] || fail "HASkinProxy: extracted 0 yggdrasil upstream URLs — refusing to pass silently"
[[ -n "$hsp_all" ]] || fail "HASkinProxy: extracted 0 core upstream URLs — refusing to pass silently"
while IFS= read -r path; do
  # Method-agnostic: the contract path sets are compared by path only.
  check_url "HASkinProxy" "-" "$path" "$tmpdir/ygg-paths.txt" "$tmpdir/ygg-protocol-paths.txt" "$tmpdir/cascade-paths.txt"
done <<<"$hsp_ygg"
while IFS= read -r path; do
  check_url "HASkinProxy" "-" "$path" "$tmpdir/hrpauth-paths.txt" "$tmpdir/cascade-paths.txt"
done <<<"$hsp_all"

# --- 7. HRPAuth-Web (TS frontend) ---
web_files="$(find "$HRPAUTH_WEB_DIR/src/api" "$HRPAUTH_WEB_DIR/src/utils" "$HRPAUTH_WEB_DIR/src/generated" -name '*.ts' 2>/dev/null || true)"
[[ -n "$web_files" ]] || fail "HRPAuth-Web: no api/utils/generated TS files found"
web_urls="$(
  # ${BackendUrl}/path and buildServiceUrl(BackendUrl, '/path') literals
  {
    grep -rhoE '\$\{BackendUrl\}/[a-zA-Z0-9/_.-]+' $web_files | sed 's#\${BackendUrl}##' || true
    grep -rhoE 'buildServiceUrl\(BackendUrl, [`'"'"']/[a-zA-Z0-9/_.-]+' $web_files | sed -E 's#buildServiceUrl\(BackendUrl, [`'"'"']##' || true
    # PLAYER_BASE templates: const PLAYER_BASE = '/player'
    grep -rhoE '\$\{PLAYER_BASE\}/[a-zA-Z0-9/_.-]+' $web_files | sed 's#\${PLAYER_BASE}#/player#' || true
    # plain concatenation: base + '/path'
    grep -rhoE "\+ '/[a-zA-Z0-9/_.-]+'" $web_files | sed -E "s#\+ '##; s#'\$##" || true
  }
)"
web_urls="$(printf '%s\n' "$web_urls" | grep -v '^$' | sed -E 's#\$\{[a-zA-Z_][a-zA-Z0-9_]*\}#{param}#g' | sort -u)"
[[ -n "$web_urls" ]] || fail "HRPAuth-Web: extracted 0 backend URLs — refusing to pass silently"
while IFS= read -r path; do
  if [[ "$path" == /yggdrasil-api/* ]]; then
    check_url "HRPAuth-Web" "-" "${path#/yggdrasil-api}" "$tmpdir/ygg-paths.txt" "$tmpdir/ygg-protocol-paths.txt" "$tmpdir/cascade-paths.txt"
  elif [[ "$path" == /skinlib-api/* ]]; then
    check_url "HRPAuth-Web" "-" "${path#/skinlib-api}" "$tmpdir/skinlib-paths.txt" "$tmpdir/cascade-paths.txt"
  else
    check_url "HRPAuth-Web" "-" "$path" "$tmpdir/hrpauth-paths.txt" "$tmpdir/ygg-paths.txt" "$tmpdir/cascade-paths.txt"
  fi
done <<<"$web_urls"

# --- 8. HRPAuth-Yggdrasil-API core client (Go -> HRPAuth /internal/*) ---
ygg_core_urls="$(gawk '
  match($0, /doRequest(WithCode)?\("(GET|POST|PUT|DELETE)", "(\/[^"]+)"/, m) {
    print m[2] " " m[3]
  }
' "$YGGDRASIL_DIR/clients/core_client.go" | sort -u)"
[[ -n "$ygg_core_urls" ]] || fail "HRPAuth-Yggdrasil-API: extracted 0 core-client URLs — refusing to pass silently"
while read -r method path; do
  check_url "HRPAuth-Yggdrasil-API" "$method" "$path" "$tmpdir/hrpauth-paths.txt"
done <<<"$ygg_core_urls"

# --- 9. Cascade backend client (Go -> cascade-backend-v1 control plane) ---
# Direct literals in internal/backend/client.go and internal/proxy/server.go,
# the concatenated /sessions/{sessionID}/identity, and the room-scoped
# suffixes forwarded by the management API (proxy_http.go).
cascade_backend_urls="$(
  {
    # trailing-slash literals are concatenation prefixes (the full path is
    # assembled below), not standalone URLs
    gawk 'match($0, /http\.Method(Get|Post|Put|Delete), "(\/[^"]+)"/, m) { print m[2] }' "$CASCADE_DIR/internal/backend/client.go" | grep -v '/$'
    gawk 'match($0, /client\.Request\(ctx, "(GET|POST|PUT|DELETE)", "(\/[^"]+)"/, m) { print m[2] }' "$CASCADE_DIR/internal/proxy/server.go"
    grep -q '"/sessions/"+url.PathEscape(sessionID)+"/identity"' "$CASCADE_DIR/internal/backend/client.go" && echo "/sessions/{sessionID}/identity"
    gawk 'match($0, /(RoomRequest|forwardRoom)\([^;]*"(\/[a-z]+)"/, m) { print "/rooms/{code}" m[2] }' "$CASCADE_DIR/internal/api/proxy_http.go"
  } | sort -u)"
[[ -n "$cascade_backend_urls" ]] || fail "Cascade: extracted 0 backend control-plane URLs — refusing to pass silently"
while IFS= read -r path; do
  check_url "Cascade-backend-client" "-" "$path" "$tmpdir/backend-paths.txt"
done <<<"$cascade_backend_urls"

# --- 10. MCA-Cascade library (Go -> MCA matchmaking assignment) ---
grep -q '"/api/matchmaking/assignment/"' "$MCA_CASCADE_DIR/client.go" || fail "MCA-Cascade: assignment URL not found — refusing to pass silently"
check_url "MCA-Cascade" GET "/api/matchmaking/assignment/{uuid}" "$tmpdir/mca-paths.txt"

# --- 11. MatchCoreArena-MaintenanceView (Go ops console -> MCA business API) ---
mca_mv_urls="$(
  {
    gawk 'match($0, /doMCARequest\(ctx, http\.Method(Get|Post|Put|Delete), "(\/api\/[^"?]+)/, m) { print m[2] }' "$MCA_MAINTVIEW_DIR"/internal/logic/*.go
    gawk 'match($0, /doRequest\(ctx, "(GET|POST|PUT|DELETE)", "(\/api\/[^"?]+)/, m) { print m[2] }' "$MCA_MAINTVIEW_DIR"/internal/logic/*.go
    gawk 'match($0, /fmt\.Sprintf\("(\/api\/[^"?]+)"/, m) { print m[1] }' "$MCA_MAINTVIEW_DIR"/internal/logic/*.go | sed -E 's#%[sd]#{param}#g'
    grep -q '"/api/matches/by-game-id/" + url.PathEscape' "$MCA_MAINTVIEW_DIR"/internal/logic/mca.go && echo "/api/matches/by-game-id/{game_id}"
    grep -q '+ "/api/status"' "$MCA_MAINTVIEW_DIR"/internal/logic/*.go && echo "/api/status"
  } | sort -u)"
[[ -n "$mca_mv_urls" ]] || fail "MatchCoreArena-MaintenanceView: extracted 0 MCA URLs — refusing to pass silently"
while IFS= read -r path; do
  check_url "MatchCoreArena-MaintenanceView" "-" "$path" "$tmpdir/mca-paths.txt"
done <<<"$mca_mv_urls"

# --- 12. HA-Services-MaintenanceView (Go ops panel -> Deployer) ---
ha_mv_urls="$(gawk '
  match($0, /doRaw\(ctx, http\.Method(Get|Post|Put|Delete), "(\/api\/v1\/deploy[^"]*)"/, m) {
    print m[2]
  }
' "$HA_MAINTVIEW_DIR/internal/deployer/client.go" | sort -u)"
[[ -n "$ha_mv_urls" ]] || fail "HA-Services-MaintenanceView: extracted 0 Deployer URLs — refusing to pass silently"
while IFS= read -r path; do
  check_url "HA-Services-MaintenanceView" "-" "$path" "$tmpdir/deployer-paths.txt"
done <<<"$ha_mv_urls"

# --- 13. Grail CLI + mirror client (Go -> Grail node surface) ---
grail_urls="$(
  {
    grep -hoE '"/v1/[^"%]*"' "$GRAIL_DIR/main.go" "$GRAIL_DIR/internal/client/client.go" | tr -d '"'
    grep -hoE 'fmt\.Sprintf\("/v1/[^"]*"' "$GRAIL_DIR/main.go" | sed -E 's#fmt\.Sprintf\(##; s#"##g; s#%s#{param}#g' | grep -v '/$'
    grep -hoE 'base\+"(yank|deprecate)"' "$GRAIL_DIR/main.go" | sed -E 's#^base\+"#/v1/projects/{param}/channels/{param}/versions/{param}/#; s#"$##'
  } | sort -u)"
[[ -n "$grail_urls" ]] || fail "Grail: extracted 0 client URLs — refusing to pass silently"
while IFS= read -r path; do
  check_url "Grail-client" "-" "$path" "$tmpdir/grail-paths.txt"
done <<<"$grail_urls"

# --- 14. RW-Mod-Injector (Java -> cascade-backend-v1 mod surface) ---
rmi_urls="$(
  {
    grep -qE '\+ "/rooms/" \+ [^;]+ \+ "/mods"' "$RWMI_DIR/injector/src/main/java/com/corematch/rwmodinjector/Manifest.java" && echo "/rooms/{param}/mods"
    grep -qE '\+ "/rooms/" \+ [^;]+ \+ "/mods/" \+' "$RWMI_DIR/injector/src/main/java/com/corematch/rwmodinjector/Assembler.java" && echo "/rooms/{param}/mods/{param}"
  })"
[[ -n "$rmi_urls" ]] || fail "RW-Mod-Injector: extracted 0 control-plane URLs — refusing to pass silently"
while IFS= read -r path; do
  check_url "RW-Mod-Injector" GET "$path" "$tmpdir/backend-paths.txt"
done <<<"$rmi_urls"

# --- 15/16. Cascade and Avalon plugin hubs (Go -> plugin-served endpoints) ---
# The plugin contracts' paths are relative to the plugin base URL's /v1
# prefix, which the hubs prepend; the comparison strips it. The event URLs
# are /events/<name> with the event names taken from the hub's own event
# constants, so every emitted event must have a contract path.
grep -q '"/v1/manifest"' "$CASCADE_DIR/internal/plugin/manifest.go" || fail "Cascade: plugin manifest URL not found — refusing to pass silently"
grep -q '"/v1/events/" + eventName' "$CASCADE_DIR/internal/plugin/hub.go" || fail "Cascade: plugin event URL not found — refusing to pass silently"
check_url "Cascade-plugin-client" GET "/manifest" "$tmpdir/cascade-plugin-paths.txt"
cascade_plugin_events="$(gawk 'match($0, /Event[A-Za-z]+[[:space:]]*=[[:space:]]*"([a-z]+\.[a-z]+)"/, m) { print m[1] }' "$CASCADE_DIR/internal/plugin/plugin.go" | sort -u)"
[[ -n "$cascade_plugin_events" ]] || fail "Cascade: extracted 0 plugin event names — refusing to pass silently"
while IFS= read -r ev; do
  check_url "Cascade-plugin-client" POST "/events/$ev" "$tmpdir/cascade-plugin-paths.txt"
done <<<"$cascade_plugin_events"
grep -q '"/v1/manifest"' "$AVALON_DIR/internal/plugin/manifest.go" || fail "Avalon: plugin manifest URL not found — refusing to pass silently"
grep -q '"/v1/events/" + eventName' "$AVALON_DIR/internal/plugin/hub.go" || fail "Avalon: plugin event URL not found — refusing to pass silently"
check_url "Avalon-plugin-client" GET "/manifest" "$tmpdir/avalon-plugin-paths.txt"
avalon_plugin_events="$(gawk 'match($0, /Event[A-Za-z]+[[:space:]]*=[[:space:]]*"([a-z]+\.[a-z]+)"/, m) { print m[1] }' "$AVALON_DIR/internal/plugin/event.go" "$AVALON_DIR/internal/plugin/eventv2.go" | sort -u)"
[[ -n "$avalon_plugin_events" ]] || fail "Avalon: extracted 0 plugin event names — refusing to pass silently"
while IFS= read -r ev; do
  check_url "Avalon-plugin-client" POST "/events/$ev" "$tmpdir/avalon-plugin-paths.txt"
done <<<"$avalon_plugin_events"

if [[ "$DRIFT_FOUND" -eq 1 ]]; then
  echo "Consumer URL drift detected."
  exit 1
fi

echo "Consumer URL check passed."
