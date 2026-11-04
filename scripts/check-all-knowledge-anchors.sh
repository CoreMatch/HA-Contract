#!/usr/bin/env bash
# check-all-knowledge-anchors.sh — run the knowledge anchor checker across all
# workspace repositories in one pass.
#
# Canonical location: HA-Contract/scripts/check-all-knowledge-anchors.sh
#
# Usage:
#   bash check-all-knowledge-anchors.sh [root ...]
#   default roots: /home/lnb/Desktop/HA /home/lnb
#
# Scans each root's top-level directories for main git checkouts that carry a
# knowledge/ directory (a directory counts as a main checkout when .git is a
# directory; linked worktrees have a .git file and are skipped), runs
# check-knowledge-anchors.sh in each, and prints one summary line per repo:
#
#   repo | anchors | problems | exit
#
# Exit code: 0 when every repo is clean; 1 when any repo reports problems;
# 2 when no repo with knowledge/ was found at all.
#
# This script only orchestrates; the checker's interface is unchanged.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check-knowledge-anchors.sh"

roots=("$@")
[ ${#roots[@]} -eq 0 ] && roots=(/home/lnb/Desktop/HA /home/lnb)

if [ ! -x "$CHECKER" ] && [ ! -f "$CHECKER" ]; then
  echo "checker not found: $CHECKER" >&2
  exit 2
fi

printf '%-38s %8s %9s %5s\n' "repo" "anchors" "problems" "exit"
printf '%-38s %8s %9s %5s\n' "----" "-------" "--------" "----"

found=0
failed=0

for root in "${roots[@]}"; do
  [ -d "$root" ] || continue
  for d in "$root"/*/; do
    d="${d%/}"
    [ -d "$d/knowledge" ] || continue
    [ -d "$d/.git" ] || continue   # skip linked worktrees (.git is a file)
    found=$((found + 1))
    out=$(cd "$d" && bash "$CHECKER" 2>&1)
    rc=$?
    summary=$(printf '%s\n' "$out" | tail -1)
    anchors=$(printf '%s' "$summary" | sed -nE 's/.*anchors checked: ([0-9]+).*/\1/p')
    problems=$(printf '%s' "$summary" | sed -nE 's/.*problems: ([0-9]+).*/\1/p')
    [ -z "$anchors" ] && anchors="-"
    [ -z "$problems" ] && problems="-"
    printf '%-38s %8s %9s %5s\n' "$(basename "$d")" "$anchors" "$problems" "$rc"
    if [ "$rc" -ne 0 ]; then
      failed=$((failed + 1))
    fi
  done
done

echo "----------------------------------------"
echo "repos with knowledge/: $found, failing: $failed"

if [ "$found" -eq 0 ]; then
  exit 2
fi
if [ "$failed" -gt 0 ]; then
  exit 1
fi
exit 0
