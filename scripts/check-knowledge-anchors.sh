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
#   2. Line anchor        path/to/file.ext:L12  or  path:L12-L34  (bare numbers also accepted)
#        -> the file must exist and have at least <end> lines.
#   3. Time-point anchor  path:L12-L34 @ <commit>
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
# Absolute paths (e.g. /home/lnb/RW-HPS/Go-Server/...) are checked directly.
# Relative paths are resolved against the repository root.
#
# Output: one line per problem; a summary at the end.
# Exit code: 0 = all anchors verified; 1 = problems found; 2 = no knowledge/ dir.

set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT" || exit 2

if [ ! -d knowledge ]; then
  echo "no knowledge/ directory under $ROOT — nothing to check" >&2
  exit 2
fi

problems=0
checked=0

report() { # $1 = anchor description, $2 = problem
  echo "PROBLEM: $2"
  echo "    anchor: $1"
  problems=$((problems + 1))
}

path_plausible() { # a candidate path must contain '/' or exist as a root file
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
    report "$raw" "file not found: $p"
    return
  fi
  if ! grep -qF -- "$key" "$p"; then
    report "$raw" "field/key '$key' not found in $p"
  fi
}

# Collect content once, dropping [xref] lines and fenced URL noise.
content=$(cat knowledge/*.md 2>/dev/null | grep -vF '[xref]')

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

# 3) line anchors (optionally time-point): path:L12-L34 [@ commit]
while IFS= read -r m; do
  [ -z "$m" ] && continue
  case "$m" in *://*) continue ;; esac
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

echo "----------------------------------------"
echo "anchors checked: $checked, problems: $problems"
if [ "$problems" -gt 0 ]; then
  exit 1
fi
exit 0
