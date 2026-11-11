#!/usr/bin/env bash
#
# Plugin event drift check (cascade-plugin-v1): compares the sources of truth
# for the Cascade out-of-process plugin event catalog and reports every
# per-side discrepancy:
#
#   1. Cascade hub code       — scripts/eventnames (go/ast) over
#                               internal/plugin/plugin.go::allEventNames in the
#                               Cascade checkout. Cascade has no in-repo
#                               scripts/ dir and HA-Contract may not add one,
#                               so the extractor lives here and parses the
#                               negotiation slice directly (not a grep).
#   2. this repo's openapi    — /events/* paths in
#                               docs/api/openapi/cascade-plugin-v1.yaml
#   3. Cascade template plugin — the p.Handle("<event>") subscription points in
#                               docs/plugins/template (the reference plugin must
#                               only subscribe to events the hub/contract know;
#                               a stale subscription is drift)
#
# Cascade's docs/plugins/EVENT-CATALOG.md carries human tables but no
# machine-readable event block (unlike Avalon's ```plugin-events fence), so it
# is not a comparison source here; the three sources above are authoritative.
#
# Discipline (same as the Avalon check / knowledge/0005): an unreadable source,
# a parse failure, or 0 entries is a HARD ERROR — never "unreadable, therefore
# skipped"; drift is reported per event per side, never as a bare count.
#
# Usage:
#   bash scripts/check-cascade-plugin-event-drift.sh [--self-test]
#
# The Cascade checkout is resolved via $CASCADE_REPO_DIR, then flat sibling,
# then the nested workspace grouping dirs; the resolved checkout MUST contain
# the plugin code (internal/plugin/plugin.go). Missing checkout / contract /
# tooling is a hard error.
#
# Exit codes: 0 = in sync; 1 = drift detected; 2 = environment/read error.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"

fail() {
	echo "ERROR: $*" >&2
	exit 2
}

resolve_cascade() {
	local env_value="$1" candidate
	if [[ -n "$env_value" ]]; then
		[[ -d "$env_value" ]] || fail "Cascade repository not found at \$CASCADE_REPO_DIR='$env_value'"
		echo "$env_value"
		return
	fi
	for candidate in "$ROOT/../Cascade" "$HOME/Desktop/HA/Cascade" "$HOME/Desktop/avalon/Cascade" "$ROOT/../rw/Cascade"; do
		if [[ -d "$candidate" ]]; then
			echo "$(readlink -f "$candidate")"
			return
		fi
	done
	fail "Cascade repository not found (set CASCADE_REPO_DIR or place it next to HA-Contract)"
}

CASCADE_DIR="$(resolve_cascade "${CASCADE_REPO_DIR:-}")"
CONTRACT_YAML="$ROOT/docs/api/openapi/cascade-plugin-v1.yaml"
PLUGIN_GO="$CASCADE_DIR/internal/plugin/plugin.go"
TEMPLATE_DIR="$CASCADE_DIR/docs/plugins/template"

[[ -f "$CONTRACT_YAML" ]] || fail "contract file missing: $CONTRACT_YAML"
[[ -f "$PLUGIN_GO" ]] || fail "Cascade plugin code missing: $PLUGIN_GO (need a checkout with the plugin system)"
[[ -d "$TEMPLATE_DIR" ]] || fail "Cascade template plugin missing: $TEMPLATE_DIR"
command -v go >/dev/null 2>&1 || fail "go toolchain required (eventnames build)"
command -v python3 >/dev/null 2>&1 || fail "python3 required (openapi parse)"

# ---------------------------------------------------------------------------
# --self-test: proves this checker actually FAILS on event drift. A fixture
# copy of this contract tree is mutated (one /events/* path renamed) and
# re-checked against the real Cascade checkout: the clean fixture must pass,
# the mutated fixture must fail and name the event.
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--self-test" ]]; then
	FIX="$(mktemp -d)"
	trap 'rm -rf "$FIX"' EXIT
	mkdir -p "$FIX/scripts" "$FIX/docs/api/openapi"
	cp "$CONTRACT_YAML" "$FIX/docs/api/openapi/"
	cp -r "$ROOT/scripts/eventnames" "$FIX/scripts/"
	cp "$0" "$FIX/scripts/"
	SCRIPT_NAME="$(basename "$0")"
	FIX_ENV=(CASCADE_REPO_DIR="$CASCADE_DIR")

	echo "self-test[1/2]: clean fixture must pass"
	if ! env "${FIX_ENV[@]}" bash "$FIX/scripts/$SCRIPT_NAME" >"$FIX/clean.log" 2>&1; then
		cat "$FIX/clean.log" >&2
		echo "SELF-TEST FAILED: clean fixture reported drift" >&2
		exit 1
	fi

	echo "self-test[2/2]: renaming /events/player.route must fail"
	sed -i 's#^  /events/player.route:#  /events/player.route-renamed:#' "$FIX/docs/api/openapi/cascade-plugin-v1.yaml"
	grep -q "player.route-renamed" "$FIX/docs/api/openapi/cascade-plugin-v1.yaml" || {
		echo "SELF-TEST FAILED: could not inject the mutation" >&2
		exit 1
	}
	if env "${FIX_ENV[@]}" bash "$FIX/scripts/$SCRIPT_NAME" >"$FIX/mutated.log" 2>&1; then
		cat "$FIX/mutated.log" >&2
		echo "SELF-TEST FAILED: mutated contract did NOT trigger drift" >&2
		exit 1
	fi
	grep -q "player.route" "$FIX/mutated.log" || {
		cat "$FIX/mutated.log" >&2
		echo "SELF-TEST FAILED: drift report does not name the missing event" >&2
		exit 1
	}

	echo "self-test passed: clean fixture green, mutated fixture red."
	exit 0
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

if ! (cd "$ROOT/scripts/eventnames" && go build -o "$tmpdir/eventnames" .); then
	fail "eventnames build failed"
fi

# --- source 1: Cascade hub code (parsed negotiation slice, not a grep) ---
if ! code_events="$("$tmpdir/eventnames" "$PLUGIN_GO")"; then
	fail "Cascade hub code: eventnames extraction failed on $PLUGIN_GO"
fi
[[ -n "$code_events" ]] || fail "Cascade hub code yielded 0 events — refusing to compare against nothing"

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

# --- source 3: template plugin subscription points (reference plugin) ---
template_events="$(gawk '
	match($0, /\.Handle\("([a-z][a-z0-9_.]*)"/, m) { print m[1] }
' "$TEMPLATE_DIR"/*.go | sort -u)"
[[ -n "$template_events" ]] || fail "template plugin subscribes to 0 events — refusing to compare against nothing"

code_events="$(printf '%s\n' "$code_events" | sort)"
contract_events="$(printf '%s\n' "$contract_events" | sort)"

drift=0
while IFS= read -r name; do
	[[ -n "$name" ]] || continue
	if ! grep -qxF "$name" <<<"$code_events"; then
		echo "DRIFT: template plugin subscribes to event '$name' which the Cascade hub code does not define"
		drift=1
	fi
	if ! grep -qxF "$name" <<<"$contract_events"; then
		echo "DRIFT: template plugin subscribes to event '$name' missing from the HA-Contract openapi /events/* paths"
		drift=1
	fi
done <<<"$template_events"

# --- two-way comparison (hub code x openapi): report presence per side ---
union="$(printf '%s\n%s\n' "$code_events" "$contract_events" | sort -u)"
while IFS= read -r name; do
	[[ -n "$name" ]] || continue
	in_code=0; in_contract=0
	grep -qxF "$name" <<<"$code_events" && in_code=1
	grep -qxF "$name" <<<"$contract_events" && in_contract=1
	if (( in_code == in_contract )); then
		continue
	fi
	drift=1
	present=(); missing=()
	(( in_code )) && present+=("Cascade hub code") || missing+=("Cascade hub code")
	(( in_contract )) && present+=("HA-Contract openapi") || missing+=("HA-Contract openapi")
	join() { local IFS=', '; echo "$*"; }
	echo "DRIFT: event '$name' missing from [$(join "${missing[@]}")] (present in: $(join "${present[@]}"))"
done <<<"$union"

if (( drift )); then
	echo "---" >&2
	echo "Fix: sync internal/plugin/plugin.go::allEventNames (Cascade), the /events/* paths of $CONTRACT_YAML, and the p.Handle subscriptions of docs/plugins/template (Cascade)." >&2
	exit 1
fi

echo "Cascade plugin event catalog in sync across hub code, openapi, and template ($(wc -l <<<"$union") events)."
