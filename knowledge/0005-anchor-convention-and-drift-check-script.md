# 0005. Knowledge Anchor Convention and the Drift-Check Script

## Status
Accepted

## Context
The ADR-style knowledge bases cite code with `path/to/file:Lx-Ly` line
references. Every code change shifts those line numbers, so citations
drift silently and the entries rot. Line numbers are the least stable
identifier available; symbol names and key names survive most edits.

## Decision
Knowledge entries anchor evidence in one of three formats, in order of
preference:

1. **Symbol anchor** — a file path, then `::`, then a symbol name, e.g.
   `scripts/check-knowledge-anchors.sh::check_symbol_anchor`. Used when the
   cited code has a stable function/type/constant name. Verified by grepping
   the symbol in the file.
2. **Field anchor** — a file path, then `(field: ...)` with a key name, e.g.
   `docs/api/openapi/cascade-backend-v1.yaml (field: /rooms)`. Used for config
   templates, YAML sections, and generated files that have no code symbol.
   Verified by grepping the key name in the file.
3. **Line anchor** — `path/to/file.ext:Lx-Ly` (the markdown-link spelling
   `path/to/file.ext#Lx-Ly` is recognized as equivalent). Last resort for
   current-state citations that have neither a symbol nor a key name;
   expected to drift and to be repaired by the check below. Colons inside
   URLs (`http://host:port`) are never parsed as line anchors.
   A line anchor may carry a **content fingerprint** suffix:
   `path/to/file.ext:Lx-Ly fp=abcd1234` — the first 8 hex of the sha256 of
   the anchored lines (trailing whitespace stripped). With a fingerprint
   the checker additionally verifies that the anchored lines still hash to
   the recorded value, closing the hole where a file is still long enough
   but the anchored content has moved elsewhere in it. Time-point anchors
   (`... @ <commit>`) never carry fingerprints — they are pinned in history.

Cross-repository citations are prefixed with `[xref]` on the same line and
are skipped by the checker (it cannot verify other repositories from here).
Absolute paths are checked directly.

The mechanical check lives at `scripts/check-knowledge-anchors.sh` in this
repository (canonical location). It scans `knowledge/*.md` of whatever
repository it is run from, verifies every anchor per the rules above, prints
a problem list, and exits non-zero on any failure:

```bash
bash /home/lnb/Desktop/HA/HA-Contract/scripts/check-knowledge-anchors.sh
```

The checker carries a self-test fixture (`scripts/tests/anchor-fixture/`,
run with `--self-test`) covering URL false positives, the `#L` spelling,
docker-tag/host-port/PHP-constant non-anchors, a wrong-fingerprint case,
and each failure mode.
`scripts/check-all-knowledge-anchors.sh` runs the same checker across every
main checkout in the workspace that has a `knowledge/` directory and prints
a per-repo summary (repo / anchors / problems / exit), exiting non-zero if
any repository fails.

**Fingerprint workflow (`--stamp`).** Fingerprints are written by the
checker itself, never by hand:

```bash
bash /home/lnb/Desktop/HA/HA-Contract/scripts/check-knowledge-anchors.sh --stamp
```

`--stamp` rewrites `knowledge/*.md`, adding/refreshing `fp=` on every
non-time-point line anchor (lines containing `[xref]` are skipped). Run it
**after every intentional edit of anchored content** — the fingerprint must
follow the code. If a fingerprint is stale, the checker reports
`content drifted (fingerprint <old>, current <new>) — re-anchor or
re-stamp`: that is a working alarm, not a false positive. The repair is to
re-read the cited code and either fix the anchor range (content moved) or
re-run `--stamp` (the citation was meant to follow the edit). Do not delete
the fingerprint or bypass the check to silence it.

**Manual defense line for checker changes.** HA-Contract main has no branch
protection (deliberate, 2026-11-08: many sessions push directly), so the
only gate on the checker script itself is this rule: **any change to
`scripts/check-knowledge-anchors.sh` must pass `--self-test` locally before
it is pushed.** Every consuming repo runs the fetched script's self-test
before checking, so a broken script pushed to main turns all consuming
repos red with a clear reason — loud batch failure by design, never a
silent false green.

CI (`.github/workflows/knowledge-anchors.yml`) runs
the self-test plus this repository's own check on every push/PR; because a
CI checkout has no sibling repositories, it sets
`ANCHOR_ALLOW_MISSING_ABS_PATHS=1`, which skips absolute-path anchors whose
target is absent (they stay fully enforced in a workspace checkout).
Every other repository with a `knowledge/` directory carries the same
`knowledge-anchors.yml` workflow; it fetches the checker from this
repository's `main` branch at run time (no local copies, no pinned forks),
so all repositories always enforce the current rules — including
fingerprints — and a checker improvement takes effect everywhere on the
next CI run.

## Consequences
- Costs and limitations:
  - Symbol anchors break on renames; the checker then reports the symbol as
    missing, which is exactly the intended early warning.
  - The checker verifies existence (file/symbol/key/line count) and — with
    `fp=` — content identity of the anchored lines, but not semantics; a
    citation can still be contextually wrong. Human review remains
    necessary.
  - The checker is fetched from this repository's main branch by each
    repository's CI; there are no local copies to keep in sync.
  - Slash-less path tokens are only checked when the file exists, so a
    mistyped root-level file name is not flagged (docker tags, host:port
    pairs and similar non-path tokens are skipped by the same rule).
  - Field record 2026-11-08: on the first day the per-repo CI ran, it
    caught 9 cross-repo anchors missing `[xref]` in HA-Cupbearer
    (knowledge/0009 + 0010 citing Avalon/Cascade/sibling-service files),
    which the workspace-anchored convention had not caught — the mechanism
    proved it is not decorative.

## Evidence
- scripts/check-knowledge-anchors.sh (run from any repository root,
  exit 0 = clean, 1 = problems listed, 2 = no knowledge/)
