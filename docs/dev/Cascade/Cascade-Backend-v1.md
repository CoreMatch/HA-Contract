> **Provenance** (migration header; contract content below is unchanged)
>
> - Source repository: [CoreMatch/Cascade](https://github.com/CoreMatch/Cascade)
> - Source path: `HA-Contract/Cascade-Backend-v1.md`
> - Source commit: `f94f511`
> - Migrated on: 2026-11-04
> - Authority: from this migration on, **HA-Contract is the single source of
>   truth** for the Cascade backend contract (this document and
>   [`../../api/openapi/cascade-backend-v1.yaml`](../../api/openapi/cascade-backend-v1.yaml)).
>   The copy left in the Cascade repository is historical and must not diverge.
> - Revised on: 2026-11-04 as **v1.1** (backend trust strategies, health
>   readiness criterion, `FORBIDDEN` error code) and **v1.1.1** (deployment
>   content moved out per repository scope), 2026-11-05 as **v1.2** (proxy
>   transport selection from the declared trust strategy) and **v1.2.1**
>   (coverage-matrix clarifications: reserved `UNSUPPORTED_VERSION`, retry
>   scope), 2026-11-08 as **v1.3** (read-only room mod manifest and mod
>   file endpoints) by HA-Contract; see [Changelog](#changelog).

---

# Cascade Backend Contract v1.3.0

This contract defines the boundary between the Cascade edge proxy and an
independently developed Rusted Warfare backend. The backend owns rooms, lobby
state, game state, and all game protocol behavior. The proxy owns client
ingress, HRPAuth identity, route selection, and byte forwarding.

## Transport and trust

Since v1.1, transport and trust are **separate decisions** on the backend:

- Transport: the backend may serve TLS or plaintext on the game endpoint and
  the control plane; which one applies is a property of the backend
  deployment, outside this contract. The proxy selects the transport it
  speaks per backend as specified under
  [Proxy transport selection](#proxy-transport-selection), and validates the
  backend certificate whenever it establishes TLS.
- Trust: how the backend authenticates the proxy is chosen from the
  [backend trust strategies](#backend-trust-strategies) below. The v1
  requirement of mutual TLS plus Ed25519 JWT signature verification is no
  longer mandatory; it is replaced by the three trust strategies.
- The backend must not trust client-supplied identity fields as HA identity.
  The game UUID for a pending session comes from the proxy-issued JWT claims
  delivered through the identity endpoint, trusted at the level the selected
  trust strategy provides.
- Direct client access is a backend deployment decision and is outside this
  contract.

## Proxy transport selection

Since v1.2, the proxy derives the transport toward each backend from the
trust strategy declared for that backend:

- `open` or `ip` — the proxy connects in **plaintext** (no TLS) to both the
  `/v1` control plane and the game endpoint. The 24-byte `CASC` preamble is
  still written first on the game connection (it applies after the transport
  is established, whether or not TLS applies), and the identity JWT flow is
  unchanged.
- `pinned` — the proxy establishes **TLS with a client certificate**
  (mutual TLS) and expects the backend to check the certificate fingerprint
  as described above.
- Missing or unparseable declaration — the proxy defaults to the **safest
  available transport**: TLS with a client certificate. The proxy fails
  closed; it never falls back to plaintext silently.

A proxy-local override may force TLS or plaintext for a specific backend
regardless of the declared strategy. The override changes only the transport
the proxy speaks, never the trust strategy the backend runs; a deployment
whose backend serves TLS while declaring `open` or `ip` must force TLS on
the proxy side explicitly.

Plaintext transport provides no transport confidentiality and no peer
authentication; under `open` trust nothing on the path authenticates either
side. It is therefore a deliberate choice for `open`/`ip` deployments, never
a silent fallback. The structural JWT claim checks and the one-time `jti`
ledger remain in force on both transports.

## Backend trust strategies

An implementation chooses one of three trust strategies for authenticating the
proxy. The chosen strategy applies to both the game endpoint and the `/v1`
control plane. Which strategy runs is a deployment property of the backend;
the strategies are defined here so that proxy implementations know what
behavior to expect. Regardless of strategy, the one-time `jti` semantics must
hold.

- `open`: the backend accepts connections from any source and performs no
  proxy authentication: no client-certificate checks and no JWT signature
  verification. JWTs still receive the structural claim checks listed under
  [Identity JWT](#identity-jwt), and the one-time `jti` ledger still rejects
  replayed tokens. This strategy provides no peer authentication.
- `ip`: the backend accepts only connections whose source address is within
  an allowlist of exact IPs and/or CIDR ranges; JWT signatures are not
  verified.
- `pinned`: on top of a source allowlist where one applies, the backend
  requires TLS and a proxy client certificate whose SHA-256 fingerprint over
  the certificate DER matches one of the fingerprints the backend accepts.
  The accepted set may contain multiple fingerprints, so old and new proxy
  certificates can both be accepted at the same time. A mismatched
  fingerprint is rejected: game connections are closed before the preamble
  is read, and control-plane requests receive `403` with code `FORBIDDEN`.

Trust-strategy rejections on the control plane always use HTTP `403` with the
stable error code `FORBIDDEN`. Because the trust check wraps the whole `/v1`
surface, any control endpoint may return `403 FORBIDDEN` under strategies
that perform source or fingerprint checks.

## Game TCP preamble

After the transport is established (TLS handshake where TLS applies), the
proxy writes exactly 24 bytes before any Rusted Warfare bytes:

| Offset | Size | Encoding | Meaning |
| --- | ---: | --- | --- |
| 0 | 4 | ASCII | Magic `CASC` |
| 4 | 2 | unsigned big-endian | Protocol version, `1` |
| 6 | 2 | unsigned big-endian | Header size, `24` |
| 8 | 16 | bytes | Cryptographically random UUIDv4 session ID |

The backend rejects unknown magic, version, or header length and closes the
connection. Once accepted, the backend creates a pending session keyed by
session ID and starts the 5-second identity-binding deadline. Bytes following
the preamble are an unmodified native Rusted Warfare TCP stream.

The proxy selects a backend using only a room code present in the client's
initial `Preregister` packet. If no code is present, it uses the configured
default backend. A room code submitted later in a prompt is handled by that
selected backend; an established stream is never moved between backends.

## Session state machine

1. `PENDING`: backend accepted the preamble and waits for identity binding.
2. `BOUND`: backend verified and atomically consumed a valid JWT for the
   pending session. The backend may now accept the player's native game
   protocol traffic.
3. `CLOSED`: the connection ended, binding timed out, or a fatal protocol
   error occurred.

The backend may answer the initial `Preregister` while the session is pending,
but it must not accept registration, add the player to a room, or process game
commands before entering `BOUND`. The proxy binds identity after inspecting
`RegisterPlayer` and forwards that packet only after the identity API succeeds.
Pending sessions expire 5 seconds after preamble acceptance. Closing the TCP
connection at any point closes the associated pending or bound session.

## Identity JWT

The proxy signs a compact JWS JWT using EdDSA (Ed25519). Required protected
header:

```json
{"alg":"EdDSA","kid":"proxy-key-2026-01","typ":"JWT"}
```

Required claims:

| Claim | Type | Meaning |
| --- | --- | --- |
| `iss` | string | Configured proxy issuer |
| `aud` | string | Exact backend ID receiving this session |
| `sid` | string | Session ID from the TCP preamble |
| `sub` | string | Game UUID from the RW `RegisterPlayer` packet |
| `iat` | integer | Unix issue time |
| `exp` | integer | Expiry, no more than 30 seconds after issue |
| `jti` | string | Unique cryptographically random token ID |

The JWT must not contain HA UUID, HA login state, credentials, or authorization
policy. Since v1.1, the backend **does not verify the JWT signature, `kid`, or
`iss`** — proxy authenticity is carried by the selected
[trust strategy](#backend-trust-strategies). The backend still performs the
structural claim checks: well-formed compact JWS with `alg` `EdDSA`, audience
equal to its own backend ID, non-empty `sid`/`sub`/`jti`, `exp` within
30 seconds of `iat`, and not expired. A token ID can only be consumed once;
the one-time `jti` ledger is independent of trust strategy and of signature
verification. The proxy still signs tokens as specified above; backends simply
do not check the signature.

## HTTP API

Base path: `/v1`. Bodies and responses use `application/json`. The OpenAPI
document `openapi/cascade-backend-v1.yaml` is the machine-readable companion.

- `GET /health`: readiness of the backend control and game services.
  Readiness criterion (v1.1): the game listener is established; if a game-core
  helper process is configured on the backend, the helper must additionally be
  ready (checked via a non-blocking probe; health checks must not start the
  helper). If the helper is configured but failed to load, the backend stays
  `not_ready` — it must not silently degrade to ready without its game core.
  Backends without a configured helper report ready as soon as the listener is
  up (unchanged from v1).
- `GET /rooms`: complete room ownership snapshot for this backend.
- `PUT /sessions/{sessionID}/identity`: bind the signed JWT to a pending
  session.
- Room management endpoints support the proxy's existing room API facade:
  retrieve room list/detail, create/delete room, update settings, kick/ban a
  player, and retrieve room players.
- `GET /rooms/{code}/mods` (v1.3): mod manifest of the backend's game-core
  mod set for this room. Read-only; see [Room mod manifest](#room-mod-manifest).
- `GET /rooms/{code}/mods/{file}` (v1.3): mod file bytes, exactly as declared
  in the manifest. Read-only; see [Room mod manifest](#room-mod-manifest).

The backend must make `PUT .../identity` idempotent for the exact same
sessionID and jti. A retry with a different identity or jti for an already
bound session fails with `SESSION_IDENTITY_CONFLICT`.

## Room snapshot

`GET /rooms` returns all rooms currently owned by this backend:

```json
{
  "backendId": "rw-backend-a",
  "generatedAt": "2026-10-24T00:00:00Z",
  "rooms": [
    {
      "code": "NA1234",
      "title": "Lobby",
      "mapName": "maps/standard.tmx",
      "maxPlayers": 8,
      "players": 2,
      "inGame": false,
      "ownerId": "game-player-uuid",
      "ownerName": "Host",
      "adminCount": 1,
      "createdAt": "2026-10-24T00:00:00Z"
    }
  ]
}
```

The `rooms` property is always an array, including when the backend owns no
rooms. Each room snapshot item includes the legacy room-summary fields shown
above; room detail responses also include a `members` array.

The proxy polls every 5 seconds and uses the latest successful snapshot for
routing and list aggregation. Snapshots are authoritative per backend; a room
code claimed by multiple backends is a conflict and must not be routed.
After proxy restart, the directory is rebuilt from backend snapshots.

## Room mod manifest

Since v1.3 the backend exposes the mod set of its game core so that
client-side mod assemblers (RW-Mod-Injector) can prepare the exact mods a
room requires before connecting. Both endpoints are **read-only** and are
at the same public level as the room list itself: they carry no player data
and no server-internal fields.

- `GET /rooms/{code}/mods` returns the manifest:
  `{"mods":[{"name","file","sha256","size"}...], "sig":null, "sigAlg":null}`.
  - `name` is a human-readable mod name (display only; assemblers must not
    use it as an identity key).
  - `file` is a safe file name restricted to `[A-Za-z0-9._-]+` (never `.` or
    `..`); it is the only name valid on the content endpoint. Directory-style
    mods are packaged by the backend; the served artifact is always a single
    file.
  - `sha256` is the lowercase hex SHA-256 of the exact bytes served by the
    content endpoint; `size` is their size in bytes. **Content hashes are the
    sole trust basis**: assemblers match installed mods against the manifest
    by content hash only, never by name.
  - `sig` / `sigAlg` are reserved for a future publisher signature; v1.3
    backends emit `null` for both. Assemblers must accept and ignore them.
  - The manifest reflects the backend's mod set as loaded from its game-core
    mod directory. An empty `mods` array is valid (zero-mod room).
  - Unknown room code: `404` with code `ROOM_NOT_FOUND`.
- `GET /rooms/{code}/mods/{file}` returns the mod file bytes
  (`application/octet-stream`). The body must be exactly the bytes whose
  `sha256`/`size` the manifest declares for `file`; the backend must not
  transform the stored file. A `file` value outside the whitelist character
  set (including `.` and `..`) is `400 INVALID_REQUEST`; a well-formed value
  absent from the manifest is `404 ROOM_NOT_FOUND`.

Backends without a mod set or without mod-serving capability still answer
`GET /rooms/{code}/mods` with an empty manifest for rooms they own; the
content endpoint then only produces `404`. Trust-strategy behavior (`403
FORBIDDEN`) applies to both endpoints like any other `/v1` operation.

## Errors and retries

Errors use this shape:

```json
{"code":"SESSION_NOT_FOUND","message":"session is not pending"}
```

Stable error codes:

- `INVALID_REQUEST`
- `UNSUPPORTED_VERSION` (reserved; the reference backend has no version gate
  on the control plane as of v1.2.1 and does not emit this code — it stays
  registered for future protocol-version checks)
- `FORBIDDEN` (v1.1): the request was rejected by the backend trust strategy
  (source not in the accepted allowlist, or client-certificate fingerprint
  not accepted). Returned with HTTP `403`; possible on any `/v1` endpoint.
- `SESSION_NOT_FOUND`
- `SESSION_EXPIRED`
- `SESSION_IDENTITY_INVALID`
- `SESSION_IDENTITY_REPLAYED`
- `SESSION_IDENTITY_CONFLICT`
- `ROOM_NOT_FOUND`
- `ROOM_CONFLICT`
- `BACKEND_NOT_READY`
- `INTERNAL_ERROR`

The proxy retries only idempotent control requests, at most twice after the
initial attempt, with bounded backoff, and only for transport-level
failures; an HTTP error response from the backend is surfaced to the caller
immediately, without retry. It does not retry room creation unless the
backend supports an idempotency key. If identity binding cannot be
confirmed within the 5-second pending deadline, the proxy closes the game
connection and must not forward the client's pending PoW response. Client
errors must not expose tokens, certificates, or internal backend details.

## Health and directory behavior

- The proxy probes each backend every 5 seconds.
- Three consecutive failures mark a backend unhealthy; two consecutive
  successes restore health.
- A backend health failure closes its active client streams. Existing room
  ownership is retained and is not reassigned automatically.
- The proxy routes an exact known room to its snapshot owner. An unknown room
  uses the longest matching configured static prefix; otherwise it uses the
  default backend.
- Configured prefixes for different backends must not overlap.
- Duplicate room ownership is reported as a conflict and rejected for
  routing.

## Changelog

### v1.2.1 → v1.3 (2026-11-08)

Additive revision for client-side mod assembly (RW-Mod-Injector):

1. **`GET /rooms/{code}/mods`**: read-only mod manifest of the backend's
   game-core mod set for a room (`name` / `file` / `sha256` / `size` per
   entry, plus reserved `sig` / `sigAlg` emitted as `null`). Content hashes
   are defined as the sole trust basis for assembly; matching by name is
   contractually excluded.
2. **`GET /rooms/{code}/mods/{file}`**: read-only mod file bytes, exactly
   the bytes the manifest declares. `file` is whitelist-restricted
   (`[A-Za-z0-9._-]+`, never `.`/`..`); malformed values are
   `INVALID_REQUEST`, unknown files `ROOM_NOT_FOUND`.

No existing endpoint, field, or response semantics changed; v1.3 is not a
breaking revision for proxy implementations (the proxy is not a consumer of
these endpoints in v1.3 — they serve client-side assemblers, whether the
client reaches the backend directly or through a future proxy-side content
surface).

### v1.2 → v1.2.1 (2026-11-05)

Clarifying revision from the route/error-code coverage audit; **no
interface semantics changed**:

1. **`UNSUPPORTED_VERSION` marked reserved**: the reference backend has no
   version gate on the control plane and does not emit the code; it remains
   registered for future protocol-version checks.
2. **Retry scope clarified**: the proxy's bounded retries apply to
   transport-level failures of idempotent requests only; an HTTP error
   response from the backend is surfaced immediately without retry (this
   documents the implemented behavior).

Route coverage was audited at the same revision: the ten `/v1` routes
registered by the reference backend implementation and the ten paths in the
OpenAPI companion match one-to-one, and every route the proxy consumes
(`/health`, `/rooms`, `/sessions/{sessionID}/identity`, `/rooms/create`,
`/rooms/{code}` with its settings/kick/ban/players subresources) is present
in both.

### v1.1.1 → v1.2 (2026-11-05)

1. **Proxy transport selection**: the proxy derives its transport toward each
   backend from the trust strategy declared for that backend: plaintext for
   `open` and `ip`, TLS with a client certificate for `pinned`, and — when
   the declaration is missing or unparseable — the safest available transport
   (TLS with a client certificate; the proxy fails closed rather than falling
   back to plaintext). A proxy-local override may force either transport per
   backend. The `CASC` preamble and the identity JWT flow apply unchanged on
   both transports.

No endpoint paths, fields, or response semantics changed; v1.2 is not a
breaking revision for backend implementations.

### v1.1 → v1.1.1 (2026-11-04)

Corrective revision per the repository scope rule (`agents.md`: this
repository serves secondary development; deployment and operations material
is out of scope). Moved deployment/operations content out of the contract:
configuration item names and default values, allowlist authoring and
startup-failure conditions, fingerprint computation and rotation periods, and
network-exposure advice. **No interface semantics changed**: paths, fields,
response codes, trust-strategy behavior, `jti` one-time semantics, and the
`/health` readiness definition are exactly as in v1.1. Deployment guidance for
the reference backend lives in the Avalon README (CoreMatch/Avalon).

### v1 → v1.1 (2026-11-04)

1. **Backend trust strategies**: replaced the mandatory mutual-TLS + Ed25519
   signature verification with three backend-selected trust strategies
   (`open` / `ip` / `pinned`), and separated transport from trust. JWTs are
   no longer signature-verified by the backend; structural claim checks and
   the one-time `jti` ledger remain in force.
2. **`/v1/health` readiness**: when a game-core helper is part of the
   backend, `ready` additionally requires the helper to be ready
   (non-blocking probe); a helper that failed to load keeps the backend
   `not_ready` (no silent degradation). Unchanged for backends without a
   helper.
3. **`FORBIDDEN` error code**: added `403` with stable code `FORBIDDEN` for
   trust-strategy rejections (source allowlist / certificate fingerprint),
   possible on any `/v1` endpoint.

No endpoint paths or existing field semantics changed; v1.1 is not a breaking
revision for proxy implementations (the proxy still signs JWTs and may still
present client certificates — backends without fingerprint checks simply do
not require them).
