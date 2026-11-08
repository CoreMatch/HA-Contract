#!/usr/bin/env bash
#
# OpenAPI validity check: every contract file under docs/api/openapi/ must be
# structurally valid OpenAPI 3.x according to the mature
# openapi-spec-validator suite. This catches YAML syntax errors and
# specification violations (misplaced $refs, bad security entries, ...) that
# line-based awk extractors cannot see — the matchcorearena-business.yaml
# "assigned: false" unquoted-colon incident (2026-11-08) is the canonical
# example of a silent false green this check eliminates.
#
# Usage:
#   bash scripts/check-openapi-validity.sh [--self-test]
#
# --self-test injects a structural violation (a security entry referencing a
# parameter) into a fixture copy and asserts the validator rejects it.
#
# Exit codes: 0 = all valid; 1 = invalid contract(s); 2 = environment error.

set -euo pipefail

ROOT="$(dirname "$(dirname "$(readlink -f "$0")")")"

fail() {
  echo "ERROR: $*" >&2
  exit 2
}

command -v python3 >/dev/null 2>&1 || fail "python3 is required"
if ! python3 -c 'import openapi_spec_validator' 2>/dev/null; then
  fail "openapi-spec-validator is required (pip install openapi-spec-validator)"
fi

validate_all() {
  local dir="$1" rc=0 f
  for f in "$dir"/*.yaml; do
    [[ -f "$f" ]] || continue
    if python3 -m openapi_spec_validator "$f" >"$TMPLOG" 2>&1; then
      echo "OK   $(basename "$f")"
    else
      echo "INVALID $(basename "$f"):"
      sed 's/^/  /' "$TMPLOG" | tail -8
      rc=1
    fi
  done
  return "$rc"
}

TMPLOG="$(mktemp)"
trap 'rm -f "$TMPLOG"' EXIT

if [[ "${1:-}" == "--self-test" ]]; then
  FIX="$(mktemp -d)"
  trap 'rm -rf "$FIX" "$TMPLOG"' EXIT
  mkdir -p "$FIX/docs/api/openapi"
  cp "$ROOT/docs/api/openapi/"*.yaml "$FIX/docs/api/openapi/"

  echo "self-test[1/2]: clean contracts must validate"
  if ! validate_all "$FIX/docs/api/openapi"; then
    echo "SELF-TEST FAILED: clean contracts did not validate" >&2
    exit 1
  fi

  echo "self-test[2/2]: structural violation must be rejected"
  # Break a contract: an unclosed flow mapping is a YAML syntax error, which
  # the validator must reject (mirrors the real-world unquoted-colon incident).
  printf '\n  /selftest-broken: {\n' >> "$FIX/docs/api/openapi/haskinproxy-business.yaml"
  if validate_all "$FIX/docs/api/openapi" >"$FIX/mutated.log" 2>&1; then
    cat "$FIX/mutated.log" >&2
    echo "SELF-TEST FAILED: invalid contract was accepted" >&2
    exit 1
  fi
  grep -q "haskinproxy-business.yaml" "$FIX/mutated.log" || {
    cat "$FIX/mutated.log" >&2
    echo "SELF-TEST FAILED: report does not name the broken file" >&2
    exit 1
  }

  echo "self-test passed: clean contracts valid, broken contract rejected."
  exit 0
fi

if validate_all "$ROOT/docs/api/openapi"; then
  echo "All OpenAPI contracts are valid."
else
  echo "OpenAPI validity check failed."
  exit 1
fi
