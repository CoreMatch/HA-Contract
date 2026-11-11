#!/usr/bin/env bash
#
# Field-level drift check: verifies that curated OpenAPI schemas and the Go
# struct json tags that implement them agree on field NAMES and (where the
# ecosystem convention applies) REQUIRED-ness, in both directions.
#
# The ecosystem convention: a Go json field without `omitempty` is always
# serialized and must be listed in the schema's `required`; a field with
# `omitempty` is optional. Entries marked names-only are request structs
# whose zero values are meaningful inputs — for those only the field name
# sets are compared.
#
# Extraction uses mature parsers, not regex source scraping:
#   - contract side: python3 + PyYAML over the OpenAPI schema components;
#   - code side:     scripts/structjson (Go go/ast parser).
#
# Discipline (same as the route/event drift checks): a source that cannot be
# read, fails to parse, or yields 0 fields is a HARD ERROR — never
# "unreadable, therefore skipped".
#
# Usage:
#   bash scripts/check-business-api-fields.sh
#
# Implementation repositories are located like in
# check-business-api-drift.sh (env vars, then sibling dirs, then
# ~/Desktop/HA).
#
# Exit codes: 0 = in sync; 1 = drift detected; 2 = environment/read error.

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

HRPAUTH_DIR="$(resolve_repo "${HRPAUTH_REPO_DIR:-}" HRPAuth HRPAUTH_REPO_DIR)"
HASKINLIB_DIR="$(resolve_repo "${HASKINLIB_REPO_DIR:-}" HASkinLib HASKINLIB_REPO_DIR)"
YGGDRASIL_DIR="$(resolve_repo "${YGGDRASIL_REPO_DIR:-}" HRPAuth-Yggdrasil-API YGGDRASIL_REPO_DIR)"
MATCHCOREARENA_DIR="$(resolve_repo "${MATCHCOREARENA_REPO_DIR:-}" MatchCoreArena-Server MATCHCOREARENA_REPO_DIR)"
AVALON_DIR="$(resolve_repo "${AVALON_REPO_DIR:-}" Avalon AVALON_REPO_DIR)"

# Cascade for the plugin payload pairs: needs a checkout that carries the
# plugin system (internal/plugin). The flat CI checkout and the avalon
# workspace do; a lagging grouping-dir checkout may not, so fall back to a
# checkout that has internal/plugin/event.go.
CASCADE_DIR="$(resolve_repo "${CASCADE_REPO_DIR:-}" Cascade CASCADE_REPO_DIR "$HOME/Cascade")"
if [[ ! -f "$CASCADE_DIR/internal/plugin/event.go" ]]; then
  for _cand in "$HOME/Desktop/avalon/Cascade" "$ROOT/../avalon/Cascade"; do
    if [[ -f "$_cand/internal/plugin/event.go" ]]; then
      CASCADE_DIR="$(readlink -f "$_cand")"
      break
    fi
  done
fi
[[ -f "$CASCADE_DIR/internal/plugin/event.go" ]] || fail "Cascade plugin code not found (internal/plugin/event.go); set CASCADE_REPO_DIR to a checkout with the plugin system"

command -v go >/dev/null 2>&1 || fail "go toolchain required (structjson build)"
command -v python3 >/dev/null 2>&1 || fail "python3 required (openapi parse)"
python3 -c 'import yaml' 2>/dev/null || fail "PyYAML required (python3 -c 'import yaml' failed)"

# ---------------------------------------------------------------------------
# --self-test: proves this checker actually FAILS on field drift. A fixture
# copy of the contract tree is mutated (one required entry dropped from
# QueueStats) and re-checked against the real implementation repos: the
# clean fixture must pass, the mutated fixture must fail and name the field.
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then
  FIX="$(mktemp -d)"
  trap 'rm -rf "$FIX"' EXIT
  mkdir -p "$FIX/scripts" "$FIX/docs/api/openapi"
  cp -r "$ROOT/docs/api/openapi/"*.yaml "$FIX/docs/api/openapi/"
  cp -r "$ROOT/scripts/structjson" "$FIX/scripts/"
  cp "$0" "$FIX/scripts/"
  SCRIPT_NAME="$(basename "$0")"

  REPO_ENV=(
    HRPAUTH_REPO_DIR="$HRPAUTH_DIR"
    HASKINLIB_REPO_DIR="$HASKINLIB_DIR"
    YGGDRASIL_REPO_DIR="$YGGDRASIL_DIR"
    MATCHCOREARENA_REPO_DIR="$MATCHCOREARENA_DIR"
    AVALON_REPO_DIR="$AVALON_DIR"
    CASCADE_REPO_DIR="$CASCADE_DIR"
  )

  echo "self-test[1/3]: clean fixture must pass"
  if ! env "${REPO_ENV[@]}" bash "$FIX/scripts/$SCRIPT_NAME" >"$FIX/clean.log" 2>&1; then
    cat "$FIX/clean.log" >&2
    echo "SELF-TEST FAILED: clean fixture reported drift" >&2
    exit 1
  fi

  echo "self-test[2/3]: dropping a required field from QueueStats must fail"
  sed -i 's#required: \[players, parties, average_wait_seconds\]#required: [players, parties]#' \
    "$FIX/docs/api/openapi/matchcorearena-business.yaml"
  grep -q 'required: \[players, parties\]$' "$FIX/docs/api/openapi/matchcorearena-business.yaml" || {
    echo "SELF-TEST FAILED: could not inject the mutation" >&2
    exit 1
  }
  if env "${REPO_ENV[@]}" bash "$FIX/scripts/$SCRIPT_NAME" >"$FIX/mutated.log" 2>&1; then
    cat "$FIX/mutated.log" >&2
    echo "SELF-TEST FAILED: mutated schema did NOT trigger drift" >&2
    exit 1
  fi
  grep -q "average_wait_seconds" "$FIX/mutated.log" || {
    cat "$FIX/mutated.log" >&2
    echo "SELF-TEST FAILED: drift report does not name the drifted field" >&2
    exit 1
  }

  echo "self-test[3/3]: dropping playerId from the Cascade plugin PlayerInfo schema must fail"
  # Restore clean contracts, then drop playerId from the PlayerInfo required
  # list (the code field is non-omitempty, so the required sets diverge).
  cp -r "$ROOT/docs/api/openapi/"*.yaml "$FIX/docs/api/openapi/"
  sed -i 's#required: \[playerId, name, authenticated\]#required: [name, authenticated]#' \
    "$FIX/docs/api/openapi/cascade-plugin-v1.yaml"
  grep -q 'required: \[name, authenticated\]' "$FIX/docs/api/openapi/cascade-plugin-v1.yaml" || {
    echo "SELF-TEST FAILED: could not inject the PlayerInfo mutation" >&2
    exit 1
  }
  if env "${REPO_ENV[@]}" bash "$FIX/scripts/$SCRIPT_NAME" >"$FIX/mutated2.log" 2>&1; then
    cat "$FIX/mutated2.log" >&2
    echo "SELF-TEST FAILED: mutated Cascade plugin schema did NOT trigger drift" >&2
    exit 1
  fi
  grep -q "playerId" "$FIX/mutated2.log" || {
    cat "$FIX/mutated2.log" >&2
    echo "SELF-TEST FAILED: drift report does not name playerId" >&2
    exit 1
  }

  echo "self-test passed: clean green; QueueStats and Cascade PlayerInfo mutations red."
  exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

if ! (cd "$ROOT/scripts/structjson" && go build -o "$tmpdir/structjson" .); then
  fail "structjson build failed"
fi

# schema_fields <yaml> <schema-name> -> "name<TAB>required|optional" lines
schema_fields() {
  python3 - "$1" "$2" <<'PY'
import sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML not available")
path, name = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    doc = yaml.safe_load(f)
schemas = ((doc or {}).get("components") or {}).get("schemas") or {}
schema = schemas.get(name)
if not isinstance(schema, dict):
    sys.exit(f"schema {name} not found in {path}")
props = schema.get("properties") or {}
if not props:
    sys.exit(f"schema {name} has 0 properties — refusing to compare against nothing")
required = set(schema.get("required") or [])
for pname in sorted(props):
    print(f"{pname}\t{'required' if pname in required else 'optional'}")
PY
}

DRIFT_FOUND=0

# check_fields <label> <yaml> <schema> <go-file> <struct> <mode> <exclude,csv>
check_fields() {
  local label="$1" yaml="$2" schema="$3" gofile="$4" struct="$5" mode="$6" exclude="${7:-}"

  [[ -f "$yaml" ]] || fail "contract file missing: $yaml"
  [[ -f "$gofile" ]] || fail "Go source missing for $label: $gofile"

  local contract_f="$tmpdir/${label//\//_}.contract" code_f="$tmpdir/${label//\//_}.code"
  if ! schema_fields "$yaml" "$schema" | sort > "$contract_f"; then
    fail "openapi schema extraction failed for $label ($schema in $(basename "$yaml"))"
  fi
  if ! "$tmpdir/structjson" "$struct" "$gofile" | sort > "$code_f"; then
    fail "structjson extraction failed for $label ($struct in $gofile)"
  fi

  if [[ -n "$exclude" ]]; then
    local ex
    for ex in ${exclude//,/ }; do
      awk -F'\t' -v ex="$ex" '$1 != ex' "$contract_f" > "$contract_f.tmp"
      mv "$contract_f.tmp" "$contract_f"
      awk -F'\t' -v ex="$ex" '$1 != ex' "$code_f" > "$code_f.tmp"
      mv "$code_f.tmp" "$code_f"
    done
  fi

  local missing_in_contract missing_in_code
  missing_in_contract="$(comm -23 <(cut -f1 "$code_f") <(cut -f1 "$contract_f") || true)"
  missing_in_code="$(comm -13 <(cut -f1 "$code_f") <(cut -f1 "$contract_f") || true)"

  if [[ -n "$missing_in_contract" ]]; then
    echo "[$label] struct fields present in code but missing from schema $schema:"
    echo "$missing_in_contract" | sed 's/^/  - /'
    DRIFT_FOUND=1
  fi
  if [[ -n "$missing_in_code" ]]; then
    echo "[$label] schema $schema fields with no struct field in $struct:"
    echo "$missing_in_code" | sed 's/^/  - /'
    DRIFT_FOUND=1
  fi

  if [[ "$mode" == "omitempty" ]]; then
    local req_contract req_code req_diff
    req_contract="$(awk -F'\t' '$2 == "required" { print $1 }' "$contract_f" | sort)"
    req_code="$(awk -F'\t' '$2 == "required" { print $1 }' "$code_f" | sort)"
    req_diff="$(comm -3 <(printf '%s\n' "$req_code") <(printf '%s\n' "$req_contract") || true)"
    if [[ -n "$req_diff" ]]; then
      echo "[$label] required/optional mismatch between schema $schema and struct $struct (field required on exactly one side):"
      echo "$req_diff" | sed 's/^/  - /'
      DRIFT_FOUND=1
    fi
  fi
}

MCA_MM="$MATCHCOREARENA_DIR/internal/service/matchmaking.go"
MCA_YAML="$ROOT/docs/api/openapi/matchcorearena-business.yaml"
AVALON_BACKEND_YAML="$ROOT/docs/api/openapi/cascade-backend-v1.yaml"
YGG_YAML="$ROOT/docs/api/openapi/hrpauth-yggdrasil-business.yaml"
HRPAUTH_YAML="$ROOT/docs/api/openapi/hrpauth-business.yaml"

# MatchCoreArena matchmaking surface (omitempty convention verified).
check_fields "MCA/MatchAssignment"   "$MCA_YAML" MatchAssignment   "$MCA_MM" MatchAssignment   omitempty
check_fields "MCA/JoinTarget"        "$MCA_YAML" JoinTarget        "$MCA_MM" JoinTarget        omitempty
check_fields "MCA/QueueEntry"        "$MCA_YAML" QueueEntry        "$MCA_MM" QueueEntry        omitempty
check_fields "MCA/FormedGroup"       "$MCA_YAML" FormedGroup       "$MCA_MM" FormedGroup       omitempty
check_fields "MCA/GroupMember"       "$MCA_YAML" GroupMember       "$MCA_MM" GroupMember       omitempty
check_fields "MCA/MatchmakingStatus" "$MCA_YAML" MatchmakingStatus "$MCA_MM" MatchmakingStatus omitempty
check_fields "MCA/QueueStats"        "$MCA_YAML" QueueStats        "$MCA_MM" QueueStats        omitempty

# Avalon cascade backend control plane. RoomSummary.Members is excluded:
# the contract models it on RoomDetail (allOf), not on RoomSummary.
check_fields "Avalon/RoomSummary"     "$AVALON_BACKEND_YAML" RoomSummary     "$AVALON_DIR/internal/net/gateway/rooms.go"      RoomSummary      omitempty members
check_fields "Avalon/RoomModManifest" "$AVALON_BACKEND_YAML" RoomModManifest "$AVALON_DIR/internal/game/manage/modmanifest.go" ModManifest     omitempty
check_fields "Avalon/RoomModEntry"    "$AVALON_BACKEND_YAML" RoomModEntry    "$AVALON_DIR/internal/game/manage/modmanifest.go" ModManifestEntry omitempty

# HRPAuth-Yggdrasil-API player summary.
check_fields "Yggdrasil/PlayerSummary" "$YGG_YAML" PlayerSummary "$YGGDRASIL_DIR/services/player_service.go" PlayerInfo omitempty

# HRPAuth core. SdkPackageMeta follows the omitempty convention;
# PresenceRequest is a request struct whose zero values are meaningful
# inputs, so only its field name set is compared.
check_fields "HRPAuth/SdkPackageMeta" "$HRPAUTH_YAML" SdkPackageMeta "$HRPAUTH_DIR/controllers/sdk_package_store.go"    SdkPackageMeta  omitempty
check_fields "HRPAuth/PresenceRequest" "$HRPAUTH_YAML" PresenceRequest "$HRPAUTH_DIR/controllers/presence_controller.go" PresenceRequest names-only

# HASkinLib texture record (two controllers share the shape; both are
# checked against the single TextureRecord schema).
SKINLIB_YAML="$ROOT/docs/api/openapi/haskinlib-business.yaml"
check_fields "HASkinLib/TextureRecord(listpreview)" "$SKINLIB_YAML" TextureRecord "$HASKINLIB_DIR/controllers/list_preview_controller.go" listPreviewItem    omitempty
check_fields "HASkinLib/TextureRecord(profile)"     "$SKINLIB_YAML" TextureRecord "$HASKINLIB_DIR/controllers/profile_controller.go"      profileTextureItem omitempty

# Cascade out-of-process plugin event payloads (cascade-plugin/v1). These are
# the downstream-visible payload structs; the /api/plugins management response
# is contract-first (PluginStatus has no json tags yet) and is therefore not
# field-wired until the endpoint lands.
CASCADE_PLUGIN_YAML="$ROOT/docs/api/openapi/cascade-plugin-v1.yaml"
CASCADE_EVENT_GO="$CASCADE_DIR/internal/plugin/event.go"
check_fields "Cascade/PlayerInfo"    "$CASCADE_PLUGIN_YAML" PlayerInfo    "$CASCADE_EVENT_GO" PlayerInfo    omitempty
check_fields "Cascade/RouteDecision" "$CASCADE_PLUGIN_YAML" RouteDecision "$CASCADE_EVENT_GO" RouteDecision omitempty
check_fields "Cascade/ProxyInfo"     "$CASCADE_PLUGIN_YAML" ProxyInfo     "$CASCADE_EVENT_GO" ProxyInfo     omitempty

if [[ "$DRIFT_FOUND" -eq 1 ]]; then
  echo "Field-level API drift detected."
  exit 1
fi

echo "Field-level API drift check passed."
