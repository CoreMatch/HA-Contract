# WinnerProxy Service Contract

WinnerProxy is the server-join proxy for the HA ecosystem. It answers
Yggdrasil `hasJoined` / profile queries for Minecraft servers, falling back
from the HA upstream to Mojang, and can proxy-register Mojang players.

## Inbound HTTP Surface

The last three routes are bound both at the root and under the `/winnerproxy`
prefix.

| Method | Path | Purpose |
|---|---|---|
| GET | `/health` | Liveness probe |
| GET | `/` | Service banner / status page |
| GET | `/winnerproxy` | Service banner / status page (alias) |
| GET | `/sessionserver/session/minecraft/hasJoined` | Three-step join verification: HA upstream first, then Mojang, then proxy registration |
| GET | `/sessionserver/session/minecraft/profile/{uuid}` | Profile query (HA upstream, Mojang fallback) |
| POST | `/api/profiles/minecraft` | Batch username → profile summary |

## Outbound Calls (current implementation)

Yggdrasil-plane calls go to the configured upstream base URL
(`upstreams.hrpauth.url`, default includes the `/yggdrasil-api` relay
prefix); management-plane calls go to the management base URL
(`hrpauth.url`, the core root). All calls carry an OAuth2 client-credentials
Bearer token; proxy registration additionally carries the `X-Internal-Key`.

| Call | Used by | Notes |
|---|---|---|
| `GET /sessionserver/session/minecraft/hasJoined` | hasJoined step 1 | HA skin path |
| `GET /sessionserver/session/minecraft/profile/{uuid}` | profile query | |
| `POST /api/profiles/minecraft` | batch query | The base URL carries the `/yggdrasil-api` relay prefix and the relay strips it. Upstream failures surface as 502 with an explicit `{"error": ...}` reason |
| `POST /internal/proxy-register` | proxy registration (hasJoined step 3) | Body `{username, password, mojang_uuid}`; authenticated with `X-Internal-Key` (contract `hrpauth-yggdrasil-business.yaml` `/internal/proxy-register`). Consumes `profile_id` from the envelope response |
| `POST /services/auth-key` | startup, and after any 401 from proxy registration | Fetches/re-fetches the service's `X-Internal-Key` (core re-issues the key on every call) |
| `GET /` | startup | Fetches Yggdrasil metadata published via presence `root_metadata` |
| `POST /services/presence` | startup | Registers with `security_level: 0` and `root_metadata.yggdrasil` |
| `POST /services/relay` | startup | Declares relay rules |
| `POST /services/sdk-packages` (and `DELETE /services/sdk-packages/{name}`) | startup | Compile-time SDK package upload for the WebUI |

## Configuration

Runtime configuration of the WinnerProxy service (configuration file, listen
address defaults, upstream credentials) is documented in the
[WinnerProxy repository README](https://github.com/CoreMatch/WinnerProxy).

## Behavior Notes

- Single-instance design: in-process freecache, no shared state, no leader
  election.
- hasJoined flow: HA 200 → return HA profile; else Mojang hasJoined → return
  Mojang profile (Mojang-signed textures); else optional proxy registration
  path.
- On startup the service registers presence on the core and contributes a
  `yggdrasil` metadata block to the core `GET /` response via `root_metadata`.
