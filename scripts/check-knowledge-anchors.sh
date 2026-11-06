#!/usr/bin/env bash
# check-knowledge-anchors.sh — mechanical drift check for knowledge/ ADR entries.
#
# Canonical location: HA-Contract/scripts/check-knowledge-anchors.sh
# Run from the root of any repository that has a knowledge/ directory:
#
#   bash /home/lnb/Desktop/HA/HA-Contract/scripts/check-knowledge-anchors.sh
#
# Recognized anchor formats in knowledge/*.md:
#
#   1. Symbol anchor      path/to/file.ext::SymbolName
#        -> the file must exist; the symbol must be greppable in it (fixed string).
#   2. Line anchor        path:L123 / path:L123-L145 (bare numbers also accepted),
#                         and the markdown-link spelling path#L123 / path#L123-L145
#        -> the file must exist and have at least <end> lines.
#        Colons inside URLs (http://host:port) are NOT line anchors; URLs are
#        stripped before extraction.
#   3. Time-point anchor  path:L123-L145 @ <commit>
#        -> the file must exist in <commit> with at least <end> lines (git-verified).
#        Use this for historical citations that must keep exact line numbers.
#   4. Field anchor       path/to/file.ext (field: key_name)
#        -> the file must exist; the key name must be greppable in it.
#        Use this for config templates / YAML sections / generated files that
#        have no stable code symbol.
#   5. Cross-repo marker  [xref]
#        -> any line containing [xref] is skipped entirely. Mark citations of
#        other repositories' files with [xref] so they are not checked here.
#
# Absolute paths (e.g. /home/lnb/Desktop/HA/Avalon/...) are checked directly.
# Relative paths are resolved against the repository root.
#
# Environment:
#   ANCHOR_ALLOW_MISSING_ABS_PATHS=1
#       Skip absolute-path anchors whose target does not exist instead of
#       reporting them. For single-repository environments (CI) where the
#       sibling checkouts referenced by cross-repo absolute paths are absent.
#       In a full workspace checkout, leave it unset so everything is checked.
#
# Self test:
#   bash check-knowledge-anchors.sh --self-test
#   runs the checker against scripts/tests/anchor-fixture and asserts the exact
#   expected outcome (5 problems, no URL false positives).
#
# Output: one line per problem; a summary at the end.
# Exit code: 0 = all anchors verified; 1 = problems found; 2 = no knowledge/ dir.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELFTEST=0
[ "${1:-}" = "--self-test" ] && SELFTEST=1

if [ "$SELFTEST" -eq 1 ]; then
  ROOT="$SCRIPT_DIR/tests/anchor-fixture"
else
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
cd "$ROOT" || exit 2

if [ ! -d knowledge ]; then
  echo "no knowledge/ directory under $ROOT — nothing to check" >&2
  exit 2
fi

problems=0
checked=0
skipped_abs=0
report_lines=""

missing_abs_skippable() { # $1=path; true when a missing absolute path may be skipped
  case "$1" in
    /*) [ "${ANCHOR_ALLOW_MISSING_ABS_PATHS:-0}" = "1" ] && return 0 ;;
  esac
  return 1
}

report() { # $1 = anchor description, $2 = problem
  report_lines+="PROBLEM: $2"$'\n'
  report_lines+="    anchor: $1"$'\n'
  problems=$((problems + 1))
}

path_plausible() { # a candidate path must contain '/' or exist as a root file.
                    # Slash-less tokens that are not existing files (docker
                    # image tags like alpine:3, host:port like localhost:8080,
                    # PHP class constants like PDO::X, convention examples
                    # like file.ext) are skipped. Known limitation: a
                    # mistyped root-level file name is not flagged.
  case "$1" in
    /*) return 0 ;;
    */*) return 0 ;;
    *) [ -f "$1" ] && return 0; return 1 ;;
  esac
}

file_ok() { [ -f "$1" ]; }

line_count() { wc -l < "$1" 2>/dev/null || echo 0; }

check_line_anchor() { # $1=path $2=end-line $3=commit(or empty) $4=raw-anchor
  local p="$1" end="$2" commit="$3" raw="$4" n
  if [ -n "$commit" ]; then
    if ! git cat-file -e "$commit:$p" >/dev/null 2>&1; then
      if [ ! -e "$p" ] && missing_abs_skippable "$p"; then
        skipped_abs=$((skipped_abs + 1)); return
      fi
      report "$raw" "time-point anchor: $p not found in commit $commit"
      return
    fi
    n=$(git show "$commit:$p" 2>/dev/null | wc -l)
    if [ "$n" -lt "$end" ]; then
      report "$raw" "time-point anchor: $p @ $commit has $n lines, anchor needs line $end"
    fi
    return
  fi
  if ! file_ok "$p"; then
    if missing_abs_skippable "$p"; then skipped_abs=$((skipped_abs + 1)); return; fi
    report "$raw" "file not found: $p"
    return
  fi
  n=$(line_count "$p")
  if [ "$n" -lt "$end" ]; then
    report "$raw" "$p has only $n lines, anchor needs line $end"
  fi
}

check_symbol_anchor() { # $1=path $2=symbol $3=raw
  local p="$1" sym="$2" raw="$3"
  if ! file_ok "$p"; then
    if missing_abs_skippable "$p"; then skipped_abs=$((skipped_abs + 1)); return; fi
    report "$raw" "file not found: $p"
    return
  fi
  if ! grep -qF -- "$sym" "$p"; then
    report "$raw" "symbol '$sym' not found in $p"
  fi
}

check_field_anchor() { # $1=path $2=key $3=raw
  local p="$1" key="$2" raw="$3"
  if ! file_ok "$p"; then
    if missing_abs_skippable "$p"; then skipped_abs=$((skipped_abs + 1)); return; fi
    report "$raw" "file not found: $p"
    return
  fi
  if ! grep -qF -- "$key" "$p"; then
    report "$raw" "field/key '$key' not found in $p"
  fi
}

# Collect content once: drop [xref] lines, strip URLs so that
# http://host:port can never be parsed as a path:line anchor.
content=$(cat knowledge/*.md 2>/dev/null \
  | grep -vF '[xref]' \
  | sed -E 's@(https?|ftp)://[^[:space:]<>"]*@@g')

# 1) symbol anchors: path::Symbol
while IFS= read -r m; do
  [ -z "$m" ] && continue
  p="${m%%::*}"
  sym="${m##*::}"
  path_plausible "$p" || continue
  checked=$((checked + 1))
  check_symbol_anchor "$p" "$sym" "$m"
done <<< "$(printf '%s\n' "$content" | grep -oE '[A-Za-z0-9_./~-]+::[A-Za-z_][A-Za-z0-9_]*' || true)"

# 2) field anchors: path (field: key)
while IFS= read -r m; do
  [ -z "$m" ] && continue
  p="${m%% (field:*}"
  key=$(printf '%s' "$m" | sed -E 's/^[^(]*\(field: ([^)]+)\)$/\1/')
  path_plausible "$p" || continue
  checked=$((checked + 1))
  check_field_anchor "$p" "$key" "$m"
done <<< "$(printf '%s\n' "$content" | grep -oE '[A-Za-z0-9_./~-]+\.[A-Za-z0-9]+ \(field: [^)]+\)' || true)"

# 3a) line anchors with ':': path:L12-L34 [@ commit]  (bare numbers accepted)
while IFS= read -r m; do
  [ -z "$m" ] && continue
  commit=""
  rest="$m"
  case "$m" in
    *" @ "*)
      commit="${m##* @ }"
      rest="${m% @ *}"
      ;;
  esac
  p="${rest%%:*}"
  rng="${rest#*:}"
  rng="${rng#L}"
  end="${rng##*-L}"
  end="${end##*-}"
  case "$end" in *[!0-9]*|"") continue ;; esac
  path_plausible "$p" || continue
  checked=$((checked + 1))
  check_line_anchor "$p" "$end" "$commit" "$m"
done <<< "$(printf '%s\n' "$content" | grep -oE '[A-Za-z0-9_./~-]+:L?[0-9]+(-L?[0-9]+)?( @ [0-9a-fA-F]{7,40})?' || true)"

# 3b) line anchors with '#L' (markdown-link spelling): path#L12-L34 [@ commit]
while IFS= read -r m; do
  [ -z "$m" ] && continue
  commit=""
  rest="$m"
  case "$m" in
    *" @ "*)
      commit="${m##* @ }"
      rest="${m% @ *}"
      ;;
  esac
  p="${rest%%#*}"
  rng="${rest#*#L}"
  end="${rng##*-L}"
  end="${end##*-}"
  case "$end" in *[!0-9]*|"") continue ;; esac
  path_plausible "$p" || continue
  checked=$((checked + 1))
  check_line_anchor "$p" "$end" "$commit" "$m"
done <<< "$(printf '%s\n' "$content" | grep -oE '[A-Za-z0-9_./~-]+#L[0-9]+(-L?[0-9]+)?( @ [0-9a-fA-F]{7,40})?' || true)"

summary="anchors checked: $checked, problems: $problems"
[ "$skipped_abs" -gt 0 ] && summary+=", skipped missing absolute paths: $skipped_abs"

if [ "$SELFTEST" -eq 1 ]; then
  # Expected fixture outcome: exactly 5 problems (see tests/anchor-fixture),
  # and no false positives from the URL lines.
  fail=0
  if [ "$problems" -ne 5 ]; then
    echo "SELFTEST FAIL: expected 5 problems, got $problems"; fail=1
  fi
  if [ "$checked" -lt 11 ]; then
    echo "SELFTEST FAIL: expected at least 11 anchors checked (incl. #L forms), got $checked"; fail=1
  fi
  case "$report_lines" in
    *"127.0.0.1"*|*"arena.mcnb.dev"*|*"example.org"*|*"8443/docs"*)
      echo "SELFTEST FAIL: URL text was parsed as an anchor"; fail=1 ;;
  esac
  case "$report_lines" in
    *"docs/missing.go"*) : ;;
    *) echo "SELFTEST FAIL: docs/missing.go was not reported (missing-file check regressed)"; fail=1 ;;
  esac
  case "$report_lines" in
    *"PDO"*|*"alpine"*|*"golang"*|*"file.ext"*|*"localhost"*)
      echo "SELFTEST FAIL: non-path token was parsed as an anchor"; fail=1 ;;
  esac
  printf '%s' "$report_lines"
  echo "----------------------------------------"
  echo "$summary"
  if [ "$fail" -eq 0 ]; then
    echo "SELFTEST PASS"
    exit 0
  fi
  exit 1
fi

printf '%s' "$report_lines"
echo "----------------------------------------"
echo "$summary"
if [ "$problems" -gt 0 ]; then
  exit 1
fi
exit 0
