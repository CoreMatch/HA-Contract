# Anchor-checker self-test fixture

This fixture is consumed by `check-knowledge-anchors.sh --self-test`.
Expected outcome: exactly 10 problems, 0 URL false positives.

## URLs must never parse as anchors

The dev server runs at http://127.0.0.1:2778 and production at
https://arena.mcnb.dev:443/api/matches — see also
https://example.org:8443/docs#L5 for the protocol notes. None of these
may be reported.

## Valid anchors (8, no problems)

- Symbol anchor: sample.txt::MARKER
- Field anchor: sample.txt (field: second)
- Line anchors: sample.txt:L2 and sample.txt:2 and sample.txt:L1-L3
- Markdown-link line anchors: sample.txt#L1-L2 and sample.txt#L3
- Line anchor with correct content fingerprint: sample.txt:L1-L2 fp=2bcc721a

## Deliberately broken anchors (exactly 6 problems)

- File that does not exist: docs/missing.go:10
- Line beyond EOF: sample.txt:L99
- Symbol that does not exist: sample.txt::NOSUCHSYMBOL
- Field that does not exist: sample.txt (field: nosuchkey)
- Time point in a nonexistent commit: sample.txt:L1 @ deadbeef0
- Wrong content fingerprint: sample.txt:L3 fp=deadbeef

## Continuation symbol chains (1 valid, 1 problem)

- Valid chain, continuations inherit the path: `sample.txt::MARKER`, `first`
- Broken chain, second symbol does not exist: `sample.txt::MARKER` + `NOSUCHCONT`

## Subdirectory coverage (1 problem, in knowledge/sub/nested.md)

knowledge/ must be scanned recursively; `sub/nested.md` carries one valid
line anchor and one broken symbol anchor (problem 8).

## Archival declaration (2 problems, in knowledge/archived-*.md)

`archived-declared.md` carries the archival-policy HTML comment marker
(`anchor-policy: archival`) and no rotting anchors — it must pass clean.
`archived-violation.md` carries the same marker plus a symbol anchor and a
bare line anchor — the inverse check must report both (problems 9 and 10).

## Skipped lines

- [xref] nonexistent/foo.go:123 — cross-repo marker, must be skipped entirely.

## Non-anchor tokens that must never be reported

- Docker image tags: the builder uses golang:1.26-alpine and ships alpine:3.
- Host-port pairs without scheme: dev API at localhost:8080 today.
- PHP class constants in prose: the mock sets PDO::ERRMODE_EXCEPTION.
- Convention examples in prose: write `file.ext::Symbol` or `file.ext (field: key)`.
- Times and ratios in prose: the match ended 12:00 with a 1:1 tie — even
  though a file named `1` exists in the fixture root, these must never parse.
