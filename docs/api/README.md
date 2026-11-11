# HA Business API Standard

This is the single source of truth for the HA Business API, and it also records the internal implementation logic of this project for external protocols.

## Documentation Positioning

- **This Directory (`docs/api/`, `docs/dev/`)**: Shows **how this project internally implements** these APIs (including route mapping, internal processing logic, and business extensions).
- **Reference Directory ([`docs/references/`](../references/))**: Shows the **protocol standards themselves**. This project must comply with these standards.

## External Protocol Compliance (Implementation Layer)

This project implements the following external standards. For detailed protocol definitions, please refer to [docs/references/](../references/).

1. **Yggdrasil API / authlib-injector**: Implementation of the official Minecraft authentication protocol and its injector compatibility layer. The protocol-facing read surface (`/authserver/*`, `/sessionserver/*`, `/api/profiles/*`, `/textures/*`, `/skins/MinecraftSkins/*`, `/minecraftservices/*`, meta `GET /`) is documented in [`HRPAuth-Yggdrasil-API/knowledge/0010-yggdrasil-api-surface.md`](https://github.com/CoreMatch/HRPAuth-Yggdrasil-API/blob/main/knowledge/0010-yggdrasil-api-surface.md) (repatriated from this repository on 2026-11-07). The companion business wrapper surface exposed by `HRPAuth-Yggdrasil-API` (`/texture/get`, `/texture/upload/{uuid}`, `/texture/delete/{uuid}/{type}`, `/register`, `/internal/*`, Mojang proxy endpoints) is specified separately in [`openapi/hrpauth-yggdrasil-business.yaml`](./openapi/hrpauth-yggdrasil-business.yaml).
2. **CustomSkinAPI**: Implementation of the skin library standard interface.
3. **HASkinProxy (Protocol Translation)**: A dedicated service that bridges Yggdrasil API to CustomSkinAPI for CSL-compatible clients.

> Note: the Yggdrasil surface is intentionally **not** part of the core OpenAPI `hrpauth-business.yaml` file — that file covers only HRPAuth Core business endpoints. `HRPAuth-Yggdrasil-API` business wrappers live in `openapi/hrpauth-yggdrasil-business.yaml`, while the protocol surface remains documented separately in `HRPAuth-Yggdrasil-API/knowledge/0010-yggdrasil-api-surface.md` (repatriated 2026-11-07).

## Unified Constraints

1. OpenAPI is the source for paths and response structures.
2. Error codes use stable `lower_snake_case`.
3. Business errors return a unified format:

```json
{
  "success": false,
  "message": "Invalid email",
  "code": "invalid_email",
  "error": "invalid_email",
  "meta": {
    "request_id": "ab12cd34"
  }
}
```

Explanation:

- `code` is the standard field.
- `error` is a compatible alias, making it easier to maintain existing callers.
- `request_id` is used for troubleshooting logs and user feedback.

4. Business success responses return a unified format:

```json
{
  "success": true,
  "message": "Login successful",
  "data": {
    "token": "..."
  },
  "meta": {
    "request_id": "ab12cd34"
  }
}
```

During the transition period, some success fields will be mirrored at the top level to avoid immediate failure of old frontends; new callers should always read from `data`.

## File Descriptions

- `openapi/hrpauth-business.yaml`: HRPAuth Core Business API specification
- `openapi/hrpauth-yggdrasil-business.yaml`: HRPAuth-Yggdrasil-API business wrapper specification
- `openapi/haskinlib-business.yaml`: HASkinLib (texture library) specification
- `openapi/haskinproxy-business.yaml`: HASkinProxy (CSL protocol translation) specification
- `openapi/matchcorearena-business.yaml`: MatchCoreArena (matchmaking/settlement) specification
- `openapi/winnerproxy-business.yaml`: WinnerProxy (Yggdrasil edge proxy) specification
- `openapi/cascade-proxy.yaml`: Cascade proxy management API
- `openapi/cascade-backend-v1.yaml`: Cascade proxy↔backend control-plane contract (`/v1`, mutual TLS). Not an HA business API: it does not follow the unified business response format. Implemented by the Avalon gateway (`internal/net/gateway/control.go`) and covered by the anti-drift checks since 2026-11-08
- `openapi/ha-cupbearer.yaml`: HA-Cupbearer delivery + orchestration surface
- `openapi/grail.yaml`: Grail artifact distribution upstream (origin + tiered pull-only mirrors). Not an HA business API: raw-byte and metadata endpoints do not follow the unified business response format
- `openapi/webui-sdkhandler.yaml`: HA-WebUI-SDKHandler build/maintenance surface
- `openapi/avalon-plugin-v1.yaml`: Avalon out-of-process plugin contract (manifest + events)
- `openapi/cascade-plugin-v1.yaml`: Cascade out-of-process plugin contract (manifest + events; isomorphic to the Avalon one, `cascade-plugin/v1` namespace, `X-Cascade-*` signature headers)
- `error-codes.md`: Unified error code registry

## Anti-Drift

Run before submission:

```bash
./scripts/check-openapi-validity.sh        # every yaml is valid OpenAPI (mature validator)
./scripts/check-business-api-drift.sh      # METHOD+path, code <-> contract, both directions
./scripts/check-business-api-fields.sh     # schema fields <-> Go struct json tags (go/ast)
./scripts/check-consumer-urls.sh           # every consumer-called URL resolves to a contract path
./scripts/check-avalon-plugin-event-drift.sh  # hub code <-> openapi <-> EVENT-CATALOG <-> template subscriptions
./scripts/check-cascade-plugin-event-drift.sh # Cascade hub code <-> openapi <-> template subscriptions
```

Each script also supports `--self-test`, which re-runs the checker against a
fixture copy of the contract tree with ONE deliberate mutation injected and
asserts the checker turns red (clean fixture green, mutated fixture red).
The CI workflow `.github/workflows/business-api-drift.yml` runs every check
in self-test + real mode against all CoreMatch repositories.

Discipline: an unreadable source or an empty extraction is a hard error in
every checker — never "unreadable, therefore skipped". There are NO
known-broken consumer exceptions: any consumer URL that resolves to no
contract path is a hard failure (the two former texture exceptions were fixed
consumer-side on 2026-11-11 and the bypass removed). Contract-first endpoints
registered before implementation may be carried as "planned" in
`check-business-api-drift.sh` (exempt from contract-vs-impl while
unimplemented, but the contract MUST keep declaring them — removing one turns
the check red). The list is currently EMPTY: the last planned endpoint
(Cascade `GET /api/plugins`) was implemented in Cascade 4943d6f and its
exemption removed on 2026-11-12.
