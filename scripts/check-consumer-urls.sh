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
# (silent false greens are forbidden). Known-broken consumer paths are
# listed explicitly below and reported as LOUD WARNINGS on every run —
# they are exceptions with owners, not silent skips.
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
  for candidate in "$ROOT/../$name" "$HOME/Desktop/HA/$name" "$@"; do
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
    MCA_CLIENT_REPO_DIR="${MCA_CLIENT_REPO_DIR:-$ROOT/../MatchCoreArena-Client}"
    VELOCITYGATE_REPO_DIR="${VELOCITYGATE_REPO_DIR:-$ROOT/../MatchCoreArena-VelocityGate}"
    BEDWARSREL_MCA_REPO_DIR="${BEDWARSREL_MCA_REPO_DIR:-$ROOT/../BedwarsRel-MCA}"
    HRPAUTH_SPIGOT_REPO_DIR="${HRPAUTH_SPIGOT_REPO_DIR:-$ROOT/../HRPAuth-Spigot}"
    SAMUELCLIENT_REPO_DIR="${SAMUELCLIENT_REPO_DIR:-$ROOT/../SamuelClient}"
    HASKINPROXY_REPO_DIR="${HASKINPROXY_REPO_DIR:-$ROOT/../HASkinProxy}"
    HRPAUTH_WEB_REPO_DIR="${HRPAUTH_WEB_REPO_DIR:-$ROOT/../HRPAuth-Web}"
  )

  echo "self-test[1/2]: clean fixture must pass"
  if ! env "${REPO_ENV[@]}" bash "$FIX/scripts/$SCRIPT_NAME" >"$FIX/clean.log" 2>&1; then
    cat "$FIX/clean.log" >&2
    echo "SELF-TEST FAILED: clean fixture reported drift" >&2
    exit 1
  fi

  echo "self-test[2/2]: renaming /api/matchmaking/leave must fail"
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

  echo "self-test passed: clean fixture green, mutated fixture red."
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
for f in "$MCA_YAML" "$HRPAUTH_YAML" "$YGG_YAML" "$SKINLIB_YAML"; do
  [[ -f "$f" ]] || fail "contract file missing: $f"
done

openapi_paths "$MCA_YAML" > "$tmpdir/mca-paths.txt"
openapi_paths "$HRPAUTH_YAML" > "$tmpdir/hrpauth-paths.txt"
openapi_paths "$YGG_YAML" > "$tmpdir/ygg-paths.txt"
openapi_paths "$SKINLIB_YAML" > "$tmpdir/skinlib-paths.txt"

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

# Known-broken consumer paths: reported as loud warnings on every run.
# POST /texture/delete: HASkinProxy forwards to a route the Yggdrasil-API
#   does not register (it registers DELETE /texture/delete/{uuid}/{type}).
# - /texture/upload: HRPAuth-Web's generated yggdrasil SDK calls
#   POST /yggdrasil-api/texture/upload (legacy HASkinLib-style form), but
#   Yggdrasil-API registers only POST /texture/upload/{uuid}.
# Tracked for the owning repos; removing an entry without fixing the code
# makes the check fail, which is intentional.
cat > "$tmpdir/known-broken.txt" <<'EOF'
POST /texture/delete
- /texture/upload
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
WARNED=0

# check_url <consumer> <method|-> <path> <paths-file...>
check_url() {
  local consumer="$1" method="$2" path="$3"; shift 3
  local norm
  norm="$(printf '%s\n' "$path" | normalize_path)"
  if path_in "$norm" "$@"; then
    return 0
  fi
  local key="$method $norm"
  if grep -qxF -e "$key" "$tmpdir/known-broken.txt" 2>/dev/null || grep -qxF -e "- $norm" "$tmpdir/known-broken.txt" 2>/dev/null; then
    echo "WARNING: [$consumer] $key is KNOWN-BROKEN (documented exception in $(basename "$0")); the upstream route is not registered"
    WARNED=1
    return 0
  fi
  echo "DRIFT: [$consumer] URL $key resolves to no contract path"
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
  check_url "MatchCoreArena-Client" "$method" "$path" "$tmpdir/mca-paths.txt"
done <<<"$mca_client_urls"

# --- 2. MatchCoreArena-VelocityGate (Java; GET assignment) ---
vg_urls="$(grep -rhoE '"/api/[^"]*"' "$VELOCITYGATE_DIR/src/main/java" | tr -d '"' | sort -u)"
[[ -n "$vg_urls" ]] || fail "VelocityGate: extracted 0 API URLs — refusing to pass silently"
while IFS= read -r path; do
  check_url "VelocityGate" GET "$path" "$tmpdir/mca-paths.txt"
done <<<"$vg_urls"

# --- 3. BedwarsRel-MCA (Java constants + config.yml) ---
bwr_urls="$(grep -rhoE '"/api/[^"]*"' "$BEDWARSREL_MCA_DIR" --include='*.java' | tr -d '"' | sort -u)"
bwr_cfg="$(grep -rhoE 'https?://[^ "]*/api/[a-z/]+' "$BEDWARSREL_MCA_DIR" --include='*.yml' | sed -E 's#^https?://[^/]+##' | sort -u || true)"
bwr_all="$(printf '%s\n%s\n' "$bwr_urls" "$bwr_cfg" | grep -v '^$' | sort -u || true)"
[[ -n "$bwr_all" ]] || fail "BedwarsRel-MCA: extracted 0 API URLs — refusing to pass silently"
while IFS= read -r path; do
  check_url "BedwarsRel-MCA" POST "$path" "$tmpdir/mca-paths.txt"
done <<<"$bwr_all"

# --- 4. HRPAuth-Spigot (Java; core + relayed yggdrasil business) ---
spigot_urls="$(grep -rhoE '"(/[a-z][^"]*)"' "$HRPAUTH_SPIGOT_DIR/src/main/java" --include='*.java' | tr -d '"' | grep -E '^/(oauth|yggdrasil-api)/' | sort -u)"
[[ -n "$spigot_urls" ]] || fail "HRPAuth-Spigot: extracted 0 API URLs — refusing to pass silently"
while IFS= read -r path; do
  if [[ "$path" == /yggdrasil-api/* ]]; then
    check_url "HRPAuth-Spigot" POST "${path#/yggdrasil-api}" "$tmpdir/ygg-paths.txt" "$tmpdir/ygg-protocol-paths.txt"
  else
    check_url "HRPAuth-Spigot" POST "$path" "$tmpdir/hrpauth-paths.txt"
  fi
done <<<"$spigot_urls"

# --- 5. SamuelClient (Go launcher; Yggdrasil protocol auth) ---
samuel_urls="$(grep -rhoE '"/authserver/[a-z]+"' "$SAMUELCLIENT_DIR" --include='*.go' | tr -d '"' | sort -u)"
[[ -n "$samuel_urls" ]] || fail "SamuelClient: extracted 0 authserver URLs — refusing to pass silently"
while IFS= read -r path; do
  check_url "SamuelClient" POST "$path" "$tmpdir/ygg-protocol-paths.txt" "$tmpdir/ygg-paths.txt"
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
  # /texture/delete is a POST forward; everything else here is GET-ish or
  # method-agnostic — check path existence across method-agnostic sets.
  method="-"
  [[ "$path" == /texture/delete ]] && method="POST"
  check_url "HASkinProxy" "$method" "$path" "$tmpdir/ygg-paths.txt" "$tmpdir/ygg-protocol-paths.txt"
done <<<"$hsp_ygg"
while IFS= read -r path; do
  check_url "HASkinProxy" "-" "$path" "$tmpdir/hrpauth-paths.txt"
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
    check_url "HRPAuth-Web" "-" "${path#/yggdrasil-api}" "$tmpdir/ygg-paths.txt" "$tmpdir/ygg-protocol-paths.txt"
  elif [[ "$path" == /skinlib-api/* ]]; then
    check_url "HRPAuth-Web" "-" "${path#/skinlib-api}" "$tmpdir/skinlib-paths.txt"
  else
    check_url "HRPAuth-Web" "-" "$path" "$tmpdir/hrpauth-paths.txt" "$tmpdir/ygg-paths.txt"
  fi
done <<<"$web_urls"

if [[ "$DRIFT_FOUND" -eq 1 ]]; then
  echo "Consumer URL drift detected."
  exit 1
fi

if [[ "$WARNED" -eq 1 ]]; then
  echo "Consumer URL check passed (with documented known-broken exceptions above)."
else
  echo "Consumer URL check passed."
fi
