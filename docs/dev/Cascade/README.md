# Cascade Backend Contract

This directory holds the **authoritative** contract between the
[Cascade](https://github.com/CoreMatch/Cascade) edge proxy and an
independently developed Rusted Warfare backend.

## Files

- [`Cascade-Backend-v1.md`](./Cascade-Backend-v1.md): the contract document,
  currently at **v1.3.0** (read-only room mod manifest and mod file
  endpoints; earlier revisions: v1.2.1 coverage clarifications, v1.2 proxy
  transport selection, v1.1.x trust strategies and `FORBIDDEN` — see its
  Changelog). Migrated from `CoreMatch/Cascade@f94f511` on 2026-11-04
  and revised here as the authoritative copy; the copy left in the Cascade
  repository is historical.
- [`../../api/openapi/cascade-backend-v1.yaml`](../../api/openapi/cascade-backend-v1.yaml):
  OpenAPI 3.1 definition of the backend `/v1` control plane (`info.version`
  tracks the contract version, currently `1.3.0`).

## Counterpart implementations

- Proxy side: `CoreMatch/Cascade` (edge proxy; client ingress, HRPAuth
  identity, route selection, byte forwarding).
- Backend side: `CoreMatch/Avalon`, `internal/net/gateway`
  (mTLS + `CASC` preamble + JWT session gating + `/v1` control plane).

## Anti-drift status

Since 2026-11-08 `scripts/check-business-api-drift.sh` covers this contract.
It extracts the Go 1.22 `net/http` ServeMux patterns
(`mux.HandleFunc("GET /v1/health", ...)`) from
`internal/net/gateway/control.go` of the Avalon checkout (resolved via
`AVALON_REPO_DIR`, a sibling directory, or `~/Desktop/HA/Avalon`), strips the
`/v1` prefix, and compares METHOD+path against this file in both directions.
Field-level conformance for the `/v1` schemas (`RoomSummary`,
`RoomModManifest`, `RoomModEntry`) is additionally enforced by
`scripts/check-business-api-fields.sh` against the Avalon Go structs. This is
complemented by Avalon's own contract tests (`internal/net/gateway`) and the
Cascade-side contract test (`internal/backend/contract_test.go`, which parses
the OpenAPI file).
