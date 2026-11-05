# 0006. MCA Calls `POST /user/lookup-uuid` — Endpoint Never Existed

## Status
Drift record — RESOLVED 2026-11-05 via option C (see Resolution).

## Date
2026-11-05

## Context
MatchCoreArena-Server resolves match participants from Mojang UUIDs to HRPAuth
UIDs during match settlement. The call it makes targets an auth-core endpoint
that was never implemented or contracted anywhere.

## Facts (verified 2026-11-05)

- [xref] MCA-Server `internal/auth/client.go:332-363` — `LookupUserByUUID`
  posts `{"uuid": ...}` to `POST /user/lookup-uuid` (comment: public,
  unauthenticated) and expects `200 {"uid": ...}` / `404`.
- [xref] Introduced by MCA-Server commit
  `5161b1ba5a1fc867ab175d6ec0604520cc0df0ec` "feat: add UUID-to-UID
  resolution for match service" (2026-09-18); the design is recorded in
  [xref] MCA-Server `knowledge/0003-player-identity-is-hrpauth-uid-with-minecraft-uuid-resolution.md`.
- [xref] HRPAuth registers only `POST /user/lookup`
  (`/home/lnb/Desktop/HA/HRPAuth/main.go:L214` →
  `/home/lnb/Desktop/HA/HRPAuth/controllers/user_info_controller.go::LookupUser`);
  its request
  accepts exactly one of `uid` (numeric) or `username` — there is no uuid
  dimension.
- [xref] HRPAuth git history contains no occurrence of `lookup-uuid`
  (`git log -S "lookup-uuid"` is empty); the legacy PHP backend
  (`HRPAuth-Backend-PHP`) had no lookup endpoint at all. The endpoint never
  existed on any auth backend — this is not a server-side rename.
- Contract `docs/api/openapi/hrpauth-business.yaml:411` documents
  `/user/lookup` with `oneOf [uid, username]`; no `lookup-uuid` path exists
  in any contract file.
- [xref] Impact: MCA-Server `internal/service/match.go:114-126` aborts the
  whole match report when any participant's UUID cannot be resolved;
  `resolveUID` (`/home/lnb/Desktop/HA/MatchCoreArena-Server/internal/service/match.go::resolveUID`) receives 404 →
  `ErrUserNotFound`. The Redis cache (`mca:uuid_to_uid:`, 24 h) is only
  written by `resolveUID` itself after a successful lookup, so it can never
  warm up: settlement of real match reports fails end-to-end.

## Root cause
The client side invented the path: MCA-Server's 2026-09-18 UUID-to-UID
feature was designed against a public uuid→uid endpoint that the auth core
never implemented and the contract never registered. The client's design
memo (MCA knowledge 0003) was never matched by a server-side counterpart.

## Options (none applied)

- **A — extend `POST /user/lookup` with a `uuid` input dimension** (HRPAuth:
  third `oneOf` branch; MCA: repoint `LookupUserByUUID` to `/user/lookup`).
  Smallest combined diff, but makes uuid→uid+username correlation available
  on a public, unauthenticated endpoint — a privacy policy decision.
- **B — add `POST /user/lookup-uuid` on HRPAuth** as a new public endpoint
  (MCA client unchanged). Same privacy decision as A; contract registers the
  new path.
- **C — client switches to `GET /services/users/{uuid}`** (already
  contracted at `docs/api/openapi/hrpauth-business.yaml:1037`, requires ops
  level 2; OAuth2 service tokens satisfy it per
  [xref] HRPAuth `controllers/auth_level.go:33-48`). Avoids any new public
  surface, but MCA's auth client currently holds only a public client ID
  ([xref] MCA-Server `internal/auth/client.go:21-42`), so this needs service
  credentials issued to MCA plus a service-token flow — auth wiring and
  deployment config, not a rename.

All three options change either protocol semantics (new public lookup
dimension) or deployment credentials, so per the minimal-change rule none was
applied; the author picks A/B/C.

## Resolution (2026-11-05)

The author chose **option C**. MatchCoreArena-Server no longer calls
`/user/lookup-uuid` (the path never existed; nothing is registered under it):
`LookupUserByUUID` now calls the contracted ops-level
`GET /services/users/{uuid}` with a `client_credentials` service token
(MCA-Server `feat/service-identity-lookup`, merged as `3d1cbaa` + wiring
follow-up `e0e6f00`, config 1.5.0 `auth.hrpauth.service_client_id/secret`).
The service credentials are the HRPAuth built-in super-client pair, injected
by deployment (same source as HRPAuth-Yggdrasil-API's `core_api`
credentials); no new public endpoint was added and `/user/lookup` is
unchanged. Resolution failures are typed: unknown UUID →
`404 mca_user_not_found`, service-credential/upstream failure →
`502 oauth_hrpauth_down` (settlement aborts atomically either way).
