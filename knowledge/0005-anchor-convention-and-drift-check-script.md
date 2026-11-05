# 0005. Knowledge Anchor Convention and the Drift-Check Script

## Status
Accepted

## Date
2026-11-05

## Context
The ADR-style knowledge bases cite code with `path/to/file:Lx-Ly` line
references. Every code change shifts those line numbers, so citations
drift silently and the entries rot. Line numbers are the least stable
identifier available; symbol names and key names survive most edits.

## Decision
Knowledge entries anchor evidence in one of four formats, in order of
preference:

1. **Symbol anchor** — a file path, then `::`, then a symbol name, e.g.
   `scripts/check-knowledge-anchors.sh::check_symbol_anchor`. Used when the
   cited code has a stable function/type/constant name. Verified by grepping
   the symbol in the file.
2. **Field anchor** — a file path, then `(field: ...)` with a key name, e.g.
   `docs/api/openapi/cascade-backend-v1.yaml (field: /rooms)`. Used for config
   templates, YAML sections, and generated files that have no code symbol.
   Verified by grepping the key name in the file.
3. **Time-point anchor** — `path/to/file.ext:Lx-Ly @ <commit>`. Used only
   when line numbers must stay exact for a historical citation (frozen
   snapshots, quote verification, deleted code). Verified against that
   commit's tree, never the working tree.
4. **Line anchor** — `path/to/file.ext:Lx-Ly` (the markdown-link spelling
   `path/to/file.ext#Lx-Ly` is recognized as equivalent). Last resort for
   current-state citations that have neither a symbol nor a key name;
   expected to drift and to be repaired by the check below. Colons inside
   URLs (`http://host:port`) are never parsed as line anchors.

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
docker-tag/host-port/PHP-constant non-anchors, and each failure mode.
`scripts/check-all-knowledge-anchors.sh` runs the same checker across every
main checkout in the workspace that has a `knowledge/` directory and prints
a per-repo summary (repo / anchors / problems / exit), exiting non-zero if
any repository fails. CI (`.github/workflows/knowledge-anchors.yml`) runs
the self-test plus this repository's own check on every push/PR; because a
CI checkout has no sibling repositories, it sets
`ANCHOR_ALLOW_MISSING_ABS_PATHS=1`, which skips absolute-path anchors whose
target is absent (they stay fully enforced in a workspace checkout).

## Consequences
- Costs and limitations:
  - Symbol anchors break on renames; the checker then reports the symbol as
    missing, which is exactly the intended early warning.
  - Time-point anchors never drift but also never update; they are historical
    records, not current-state claims. Entries must say which they are.
  - The checker verifies existence (file/symbol/key/line count), not
    semantics; a citation can still be contextually wrong. Human review
    remains necessary.
  - Repositories without a local checkout of HA-Contract must copy the script
    or skip the check; the convention itself is repository-independent.
  - Slash-less path tokens are only checked when the file exists, so a
    mistyped root-level file name is not flagged (docker tags, host:port
    pairs and similar non-path tokens are skipped by the same rule).

## Evidence
- scripts/check-knowledge-anchors.sh (run from any repository root,
  exit 0 = clean, 1 = problems listed, 2 = no knowledge/)
