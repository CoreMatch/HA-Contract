#!/usr/bin/env bash
#
# Plugin event drift check (avalon-plugin-v1): compares the THREE sources of
# truth for the plugin event catalog and reports every per-side discrepancy:
#
#   1. Avalon hub code       — `go run ./scripts/plugin-events` in the Avalon
#                              checkout (internal/plugin/eventv2.go::EventNames)
#   2. this repo's openapi   — /events/* paths in
#                              docs/api/openapi/avalon-plugin-v1.yaml
#   3. Avalon developer docs — the machine-readable ```plugin-events block in
#                              docs/plugins/EVENT-CATALOG.md
#   4. Avalon template plugin — the p.Handle("<event>") subscription points in
#                              docs/plugins/template (the reference plugin must
#                              only subscribe to events the hub/contract/catalog
#                              all know; a stale subscription is drift)
#
# Discipline (Cascade contract-test false-green lesson, same spirit as
# knowledge/0005's "loud failure, never silent false green"):
#   - a source that cannot be read, fails to parse, or yields 0 entries is a
#     HARD ERROR — never "unreadable, therefore skipped";
#   - drift is reported per event per side ("missing from X, present in Y"),
#     never as a bare count mismatch.
#
# Usage:
#   bash scripts/check-avalon-plugin-event-drift.sh
#
# The Avalon checkout is resolved via $AVALON_REPO_DIR, falling back to a
# sibling of this repository, then ~/Desktop/HA/Avalon. A missing Avalon
# checkout, missing contract file, or missing tooling (go / python3+yaml) is
# a hard error.
#
# Exit codes: 0 = in sync; 1 = drift detected; 2 = environment/read error.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"

fail() {
	echo "ERROR: $*" >&2
	exit 2
}

resolve_avalon() {
	local env_value="$1" candidate
	if [[ -n "$env_value" ]]; then
		[[ -d "$env_value" ]] || fail "Avalon repository not found at \$AVALON_REPO_DIR='$env_value'"
		echo "$env_value"
		return
	fi
	for candidate in "$ROOT/../Avalon" "$HOME/Desktop/HA/Avalon"; do
		if [[ -d "$candidate" ]]; then
			echo "$(readlink -f "$candidate")"
			return
		fi
	done
	fail "Avalon repository not found (set AVALON_REPO_DIR or place it next to HA-Contract)"
}

AVALON_DIR="$(resolve_avalon "${AVALON_REPO_DIR:-}")"
CONTRACT_YAML="$ROOT/docs/api/openapi/avalon-plugin-v1.yaml"
CATALOG_MD="$AVALON_DIR/docs/plugins/EVENT-CATALOG.md"

[[ -f "$CONTRACT_YAML" ]] || fail "contract file missing: $CONTRACT_YAML"
[[ -f "$CATALOG_MD" ]] || fail "developer docs missing: $CATALOG_MD"
command -v go >/dev/null 2>&1 || fail "go toolchain required (Avalon module build)"
command -v python3 >/dev/null 2>&1 || fail "python3 required (openapi parse)"

# ---------------------------------------------------------------------------
# --self-test: proves this checker actually FAILS on event drift. A fixture
# copy of this contract tree is mutated (one /events/* path renamed) and
# re-checked against the real Avalon checkout: the clean fixture must pass,
# the mutated fixture must fail and name the event.
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then
	FIX="$(mktemp -d)"
	trap 'rm -rf "$FIX"' EXIT
	mkdir -p "$FIX/scripts" "$FIX/docs/api/openapi"
	cp "$CONTRACT_YAML" "$FIX/docs/api/openapi/"
	cp "$0" "$FIX/scripts/"
	SCRIPT_NAME="$(basename "$0")"
	FIX_ENV=(AVALON_REPO_DIR="${AVALON_REPO_DIR:-$ROOT/../Avalon}")

	echo "self-test[1/2]: clean fixture must pass"
	if ! env "${FIX_ENV[@]}" bash "$FIX/scripts/$SCRIPT_NAME" >"$FIX/clean.log" 2>&1; then
		cat "$FIX/clean.log" >&2
		echo "SELF-TEST FAILED: clean fixture reported drift" >&2
		exit 1
	fi

	echo "self-test[2/2]: renaming /events/player.kicked must fail"
	sed -i 's#^  /events/player.kicked:#  /events/player.kicked-renamed:#' "$FIX/docs/api/openapi/avalon-plugin-v1.yaml"
	grep -q "player.kicked-renamed" "$FIX/docs/api/openapi/avalon-plugin-v1.yaml" || {
		echo "SELF-TEST FAILED: could not inject the mutation" >&2
		exit 1
	}
	if env "${FIX_ENV[@]}" bash "$FIX/scripts/$SCRIPT_NAME" >"$FIX/mutated.log" 2>&1; then
		cat "$FIX/mutated.log" >&2
		echo "SELF-TEST FAILED: mutated contract did NOT trigger drift" >&2
		exit 1
	fi
	grep -q "player.kicked" "$FIX/mutated.log" || {
		cat "$FIX/mutated.log" >&2
		echo "SELF-TEST FAILED: drift report does not name the missing event" >&2
		exit 1
	}

	echo "self-test passed: clean fixture green, mutated fixture red."
	exit 0
fi

# --- source 1: Avalon hub code (compiled truth, not source grep) ---
if ! code_events="$(cd "$AVALON_DIR" && go run ./scripts/plugin-events)"; then
	fail "Avalon hub code: 'go run ./scripts/plugin-events' failed (build or empty event set)"
fi
[[ -n "$code_events" ]] || fail "Avalon hub code yielded 0 events — refusing to compare against nothing"

# --- source 2: HA-Contract openapi /events/* paths ---
if ! contract_events="$(python3 - "$CONTRACT_YAML" <<'PY'
import sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML not available")
with open(sys.argv[1], encoding="utf-8") as f:
    doc = yaml.safe_load(f)
paths = (doc or {}).get("paths") or {}
names = sorted(p.split("/", 2)[2] for p in paths if p.startswith("/events/"))
print("\n".join(names))
PY
)"; then
	fail "openapi parse failed for $CONTRACT_YAML (python3/PyYAML required)"
fi
[[ -n "$contract_events" ]] || fail "openapi yielded 0 /events/* paths — refusing to compare against nothing"

# --- source 3: EVENT-CATALOG.md machine-readable block ---
if ! grep -q '^```plugin-events$' "$CATALOG_MD"; then
	fail "EVENT-CATALOG machine block missing: no '\`\`\`plugin-events' fence in $CATALOG_MD"
fi
catalog_events="$(awk '
	/^```plugin-events$/ { inblock = 1; next }
	inblock && /^```$/   { inblock = 0; next }
	inblock && NF        { print $1 }
' "$CATALOG_MD" | sort)"
[[ -n "$catalog_events" ]] || fail "EVENT-CATALOG machine block parsed to 0 events — refusing to compare against nothing"

code_events="$(printf '%s\n' "$code_events" | sort)"
contract_events="$(printf '%s\n' "$contract_events" | sort)"

# --- source 4: template plugin subscription points (reference plugin) ---
drift=0
TEMPLATE_DIR="$AVALON_DIR/docs/plugins/template"
[[ -d "$TEMPLATE_DIR" ]] || fail "template plugin directory missing: $TEMPLATE_DIR"
template_events="$(gawk '
	match($0, /\.Handle\("([a-z][a-z0-9_.]*)"/, m) { print m[1] }
' "$TEMPLATE_DIR"/*.go | sort -u)"
[[ -n "$template_events" ]] || fail "template plugin subscribes to 0 events — refusing to compare against nothing"
while IFS= read -r name; do
	[[ -n "$name" ]] || continue
	if ! grep -qxF "$name" <<<"$code_events"; then
		echo "DRIFT: template plugin subscribes to event '$name' which the Avalon hub code does not define"
		drift=1
	fi
	if ! grep -qxF "$name" <<<"$contract_events"; then
		echo "DRIFT: template plugin subscribes to event '$name' missing from the HA-Contract openapi /events/* paths"
		drift=1
	fi
done <<<"$template_events"

# --- three-way comparison: report every event with its presence vector ---
union="$(printf '%s\n%s\n%s\n' "$code_events" "$contract_events" "$catalog_events" | sort -u)"
while IFS= read -r name; do
	[[ -n "$name" ]] || continue
	in_code=0; in_contract=0; in_catalog=0
	grep -qxF "$name" <<<"$code_events" && in_code=1
	grep -qxF "$name" <<<"$contract_events" && in_contract=1
	grep -qxF "$name" <<<"$catalog_events" && in_catalog=1
	if (( in_code == in_contract && in_contract == in_catalog )); then
		continue
	fi
	drift=1
	present=(); missing=()
	(( in_code )) && present+=("Avalon hub code") || missing+=("Avalon hub code")
	(( in_contract )) && present+=("HA-Contract openapi") || missing+=("HA-Contract openapi")
	(( in_catalog )) && present+=("Avalon EVENT-CATALOG") || missing+=("Avalon EVENT-CATALOG")
	join() { local IFS=', '; echo "$*"; }
	echo "DRIFT: event '$name' missing from [$(join "${missing[@]}")] (present in: $(join "${present[@]}"))"
done <<<"$union"

if (( drift )); then
	echo "---" >&2
	echo "Fix: sync internal/plugin/eventv2.go::allEventNames (Avalon), the /events/* paths of $CONTRACT_YAML, and the plugin-events block of docs/plugins/EVENT-CATALOG.md (Avalon)." >&2
	exit 1
fi

echo "plugin event catalog in sync across hub code, openapi, and EVENT-CATALOG ($(wc -l <<<"$union") events)."
