# Cascade Backend Contract

This directory holds the **authoritative** contract between the
[Cascade](https://github.com/CoreMatch/Cascade) edge proxy and an
independently developed Rusted Warfare backend.

## Files

- [`Cascade-Backend-v1.md`](./Cascade-Backend-v1.md): the contract document,
  currently at **v1.1.1** (transport and trust separation, backend trust
  strategies `open`/`ip`/`pinned`, `/v1/health` helper readiness, `FORBIDDEN`
  error code; v1.1.1 moved deployment content out per repository scope — see
  its Changelog). Migrated from `CoreMatch/Cascade@f94f511` on 2026-11-04
  and revised here as the authoritative copy; the copy left in the Cascade
  repository is historical.
- [`../../api/openapi/cascade-backend-v1.yaml`](../../api/openapi/cascade-backend-v1.yaml):
  OpenAPI 3.1 definition of the backend `/v1` control plane (`info.version`
  tracks the contract version, currently `1.1.1`).

## Counterpart implementations

- Proxy side: `CoreMatch/Cascade` (edge proxy; client ingress, HRPAuth
  identity, route selection, byte forwarding).
- Backend side: `CoreMatch/Avalon`, `internal/net/gateway`
  (mTLS + `CASC` preamble + JWT session gating + `/v1` control plane).

## Anti-drift status

`scripts/check-business-api-drift.sh` does **not** cover this contract. The
script extracts gin route registrations from `main.go` of the HA sibling
service repositories (HRPAuth / HASkinLib / HRPAuth-Yggdrasil-API), while the
backend routes of this contract are registered with Go `net/http` ServeMux
patterns (`mux.HandleFunc("GET /v1/health", ...)`) inside
`internal/net/gateway/control.go` of Avalon, which is outside
the script's repository resolution. Until the script grows a non-gin,
cross-repository extractor, conformance is enforced by Avalon's own
contract tests (`internal/net/gateway`) plus the Cascade-side contract test
(`internal/backend/contract_test.go`, which parses the OpenAPI file).
