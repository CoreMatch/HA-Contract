#!/usr/bin/env bash
# check-knowledge-anchors.sh — mechanical drift check for knowledge/ ADR entries.
#
# Canonical location: HA-Contract/scripts/check-knowledge-anchors.sh
# Run from the root of any repository that has a knowledge/ directory:
#
#   bash /home/lnb/Desktop/HA/HA-Contract/scripts/check-knowledge-anchors.sh
#
# With --stamp, the checker does not report: it rewrites knowledge/*.md and
# adds/refreshes the fp= fingerprint on every non-time-point line anchor
# (lines containing [xref] are skipped). Re-run --stamp after intentionally
# editing anchored code so the fingerprints follow the code.
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
#        Optional content fingerprint suffix:  path:L123-L145 fp=abcd1234
#        -> additionally, the sha256 (first 8 hex) of the anchored lines
#        (trailing whitespace stripped) must match. This catches "file is
#        still long enough but the content moved" drift that the bare
#        line-count check cannot see. Add/refresh fingerprints with
#        `--stamp` (see below); time-point anchors are never stamped.
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
#   6. Continuation symbols  `path::A`, `B`, `C`  (backticked chain,
#      separators: + / , and full-width ，、)
#        -> B, C inherit the path of A and are checked as symbol anchors in
#        that file. Only adjacent chains are recognized; symbols continued
#        across other prose are not — rewrite those in full `path::Sym` form.
#
# knowledge/ is scanned recursively (knowledge/**/*.md), so entries in
# subdirectories (e.g. knowledge/archive/) are checked too.
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
STAMP=0
case "${1:-}" in
  --self-test) SELFTEST=1 ;;
  --stamp) STAMP=1 ;;
esac

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

line_fp() { # $1=path $2=start $3=end -> first 8 hex of sha256 of the
            # anchored lines with trailing whitespace stripped.
  sed -n "$2,$3p" "$1" 2>/dev/null | sed -E 's/[[:space:]]+$//' | sha256sum | cut -c1-8
}

if [ "$STAMP" -eq 1 ]; then
  command -v python3 >/dev/null 2>&1 || { echo "--stamp requires python3" >&2; exit 2; }
  python3 - "$ROOT" <<'PYEOF'
import hashlib, os, re, sys
root = sys.argv[1]
RE_COLON = re.compile(r'([A-Za-z0-9_./~-]+):L?(\d+)(?:-L?(\d+))?( @ [0-9a-fA-F]{7,40})?( fp=[0-9a-f]{8})?')
RE_HASH  = re.compile(r'([A-Za-z0-9_./~-]+)#L(\d+)(?:-L?(\d+))?( @ [0-9a-fA-F]{7,40})?( fp=[0-9a-f]{8})?')

def fp_of(path, a, b):
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        return None
    if a < 1 or b > len(lines) or a > b:
        return None
    body = "\n".join(l.rstrip() for l in lines[a-1:b]) + "\n"
    return hashlib.sha256(body.encode()).hexdigest()[:8]

def stamp_line(line):
    n = 0
    def repl(m):
        nonlocal n
        if m.group(4):  # time-point anchor: pinned, never stamped
            return m.group(0)
        path, a, b = m.group(1), int(m.group(2)), int(m.group(3) or m.group(2))
        h = fp_of(os.path.join(root, path), a, b)
        if not h:
            return m.group(0)
        base = m.group(0)
        if m.group(5):
            if m.group(5) == " fp=" + h:
                return m.group(0)
            base = base[:-len(m.group(5))]
        n += 1
        return base + " fp=" + h
    line = RE_COLON.sub(repl, line)
    line = RE_HASH.sub(repl, line)
    return line, n

total = 0
kdir = os.path.join(root, "knowledge")
md_files = []
for dirpath, dirnames, filenames in os.walk(kdir):
    dirnames.sort()
    for fn in sorted(filenames):
        if fn.endswith(".md"):
            md_files.append(os.path.join(dirpath, fn))
for p in md_files:
    with open(p, encoding="utf-8") as f:
        lines = f.readlines()
    out, changed = [], False
    for line in lines:
        if "[xref]" in line:
            out.append(line)
            continue
        new, n = stamp_line(line)
        if n:
            changed = True
            total += n
        out.append(new)
    if changed:
        with open(p, "w", encoding="utf-8") as f:
            f.writelines(out)
print(f"stamped {total} line anchor(s)")
PYEOF
  exit $?
fi

check_line_anchor() { # $1=path $2=start $3=end $4=commit(or empty) $5=fp(or empty) $6=raw-anchor
  local p="$1" start="$2" end="$3" commit="$4" fp="$5" raw="$6" n actual
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
    return
  fi
  if [ -n "$fp" ]; then
    actual=$(line_fp "$p" "$start" "$end")
    if [ "$actual" != "$fp" ]; then
      report "$raw" "$p lines $start-$end content drifted (fingerprint $fp, current $actual) — re-anchor or re-stamp"
    fi
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

# Collect content once: knowledge/ recursively, drop [xref] lines, strip URLs
# so that http://host:port can never be parsed as a path:line anchor.
content=$(find knowledge -type f -name '*.md' | LC_ALL=C sort | while IFS= read -r f; do cat "$f"; done \
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

# 1b) continuation symbol anchors: `path::A`, `B`, `C` — B, C inherit the
# path of A. Only adjacent backticked chains are recognized (separators
# + / , plus full-width ，、, normalized below); anything less mechanical
# must be rewritten in full `path::Sym` form instead of loosening this rule.
while IFS= read -r chain; do
  [ -z "$chain" ] && continue
  path="${chain%%::*}"
  path_plausible "$path" || continue
  conts=$(printf '%s' "$chain" | grep -oE '[+/,] *`[A-Za-z_][A-Za-z0-9_]*' | sed -E 's/^[+/,] *`//' || true)
  while IFS= read -r sym; do
    [ -z "$sym" ] && continue
    checked=$((checked + 1))
    check_symbol_anchor "$path" "$sym" "$path::$sym (continuation)"
  done <<< "$conts"
done <<< "$(printf '%s\n' "$content" | sed 's/、/,/g; s/，/,/g' \
  | grep -oE '[A-Za-z0-9_./~-]+::[A-Za-z_][A-Za-z0-9_]*`( *[+/,] *`[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?`)+' || true)"

# 2) field anchors: path (field: key)
while IFS= read -r m; do
  [ -z "$m" ] && continue
  p="${m%% (field:*}"
  key=$(printf '%s' "$m" | sed -E 's/^[^(]*\(field: ([^)]+)\)$/\1/')
  path_plausible "$p" || continue
  checked=$((checked + 1))
  check_field_anchor "$p" "$key" "$m"
done <<< "$(printf '%s\n' "$content" | grep -oE '[A-Za-z0-9_./~-]+\.[A-Za-z0-9]+ \(field: [^)]+\)' || true)"

# 3a) line anchors with ':': path:L12-L34 [@ commit] [fp=abcd1234]  (bare numbers accepted)
while IFS= read -r m; do
  [ -z "$m" ] && continue
  commit=""
  fp=""
  rest="$m"
  case "$rest" in
    *" fp="*)
      fp="${rest##* fp=}"
      rest="${rest% fp=*}"
      ;;
  esac
  case "$rest" in
    *" @ "*)
      commit="${rest##* @ }"
      rest="${rest% @ *}"
      fp=""  # time-point anchors are pinned in history; no fingerprint
      ;;
  esac
  p="${rest%%:*}"
  rng="${rest#*:}"
  rng="${rng#L}"
  start="${rng%%-*}"
  case "$start" in *[!0-9]*|"") start="" ;; esac
  end="${rng##*-L}"
  end="${end##*-}"
  case "$end" in *[!0-9]*|"") continue ;; esac
  [ -n "$start" ] || start="$end"
  path_plausible "$p" || continue
  checked=$((checked + 1))
  check_line_anchor "$p" "$start" "$end" "$commit" "$fp" "$m"
done <<< "$(printf '%s\n' "$content" | grep -oE '[A-Za-z0-9_./~-]+:L?[0-9]+(-L?[0-9]+)?( @ [0-9a-fA-F]{7,40})?( fp=[0-9a-f]{8})?' || true)"

# 3b) line anchors with '#L' (markdown-link spelling): path#L12-L34 [@ commit] [fp=...]
while IFS= read -r m; do
  [ -z "$m" ] && continue
  commit=""
  fp=""
  rest="$m"
  case "$rest" in
    *" fp="*)
      fp="${rest##* fp=}"
      rest="${rest% fp=*}"
      ;;
  esac
  case "$rest" in
    *" @ "*)
      commit="${rest##* @ }"
      rest="${rest% @ *}"
      fp=""
      ;;
  esac
  p="${rest%%#*}"
  rng="${rest#*#L}"
  start="${rng%%-*}"
  case "$start" in *[!0-9]*|"") start="" ;; esac
  end="${rng##*-L}"
  end="${end##*-}"
  case "$end" in *[!0-9]*|"") continue ;; esac
  [ -n "$start" ] || start="$end"
  path_plausible "$p" || continue
  checked=$((checked + 1))
  check_line_anchor "$p" "$start" "$end" "$commit" "$fp" "$m"
done <<< "$(printf '%s\n' "$content" | grep -oE '[A-Za-z0-9_./~-]+#L[0-9]+(-L?[0-9]+)?( @ [0-9a-fA-F]{7,40})?( fp=[0-9a-f]{8})?' || true)"

summary="anchors checked: $checked, problems: $problems"
[ "$skipped_abs" -gt 0 ] && summary+=", skipped missing absolute paths: $skipped_abs"

if [ "$SELFTEST" -eq 1 ]; then
  # Expected fixture outcome: exactly 8 problems (see tests/anchor-fixture),
  # and no false positives from the URL lines.
  fail=0
  if [ "$problems" -ne 8 ]; then
    echo "SELFTEST FAIL: expected 8 problems, got $problems"; fail=1
  fi
  if [ "$checked" -lt 17 ]; then
    echo "SELFTEST FAIL: expected at least 17 anchors checked (incl. #L, fp, continuation and subdir forms), got $checked"; fail=1
  fi
  case "$report_lines" in
    *"content drifted"*) : ;;
    *) echo "SELFTEST FAIL: wrong-fingerprint anchor was not reported"; fail=1 ;;
  esac
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
