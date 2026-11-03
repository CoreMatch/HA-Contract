# HRPAuth-Yggdrasil-API Interaction Contract

This document defines the **External Interaction Contract** for the `HRPAuth-Yggdrasil-API` service. It focuses exclusively on how this service interacts with Minecraft clients, HRPAuth Core, and other ecosystem components.

---

## 1. API Surface & Protocols

### 1.1 Yggdrasil Protocol (Minecraft Standard)
This service is the authoritative provider for Yggdrasil-compatible endpoints.
- **Surface**: `/authserver/*`, `/sessionserver/*`, `/api/profiles/*`, `/textures/*`.
- **Reference**: Full endpoint details are in [yggdrasil-api.md](../HRPAuth/yggdrasil-api.md).
- **UUID Constraint**: All UUIDs in paths and JSON bodies MUST be **32-character, unhyphenated, lowercase hex**.

### 1.2 HA Business API (Unified Standard)
All non-Yggdrasil endpoints (e.g., `/texture/get`, `/texture/upload/:uuid`, `/register`, `/internal/*`) MUST follow the **HA Unified Response Format**:
```json
{
  "success": true,
  "message": "...",
  "data": { ... },
  "code": "error_code",
  "meta": { "request_id": "..." }
}
```
- **Error Codes**: Use stable `lower_snake_case` codes registered in `docs/api/error-codes.md`.
- **Tracing**: Every response MUST include a `request_id` in the `meta` field.

---

## 2. HRPAuth Core Integration

### 2.1 Microservice Handshake
The service integrates with HRPAuth Core via the **Microservice Extension Layer**:
- **Presence**: Registers via `POST /services/presence` with `security_level: 0`, scope name `yggdrasil-api`, `frontend_areas: ["webui-dash"]`, and a `root_metadata.yggdrasil` block that the core merges into its `GET /` response.
- **SDK Aggregation**: Delivers its frontend integration (Texture Management, Mojang Binding) as a source package via `POST /services/sdk-packages`.
- **Relay**: Declares relay rules via `POST /services/relay` to expose business endpoints through the HRPAuth Core gateway.

### 2.2 Authentication & Security
- **Inbound Auth (from Core)**: Internal callbacks (e.g., `GET /internal/heartbeat`) are authenticated via the `X-Internal-Key` header.
- **Outbound Auth (to Core)**: Calls to Core APIs require an OAuth2 Bearer token (Ops level 2) obtained via `POST /services/auth-key`.
- **Internal Heartbeat**: The service MUST respond `200 OK` to `GET /internal/heartbeat` from Core to maintain its active status and internal key.

### 2.3 Data Consistency (Lazy Loading)
The service maintains game-account consistency by pulling data from HRPAuth Core:
1. **Trigger**: When a profile name or user metadata is needed.
2. **Action**: Calls HRPAuth Core's `GET /services/users/:uuid`.
3. **Semantics**: If Core returns `404`, the local game account is considered deleted and must be purged.

---

## 3. Cross-Project Conventions

### 3.1 Proxy Registration Protocol
Creates a game account without an HRPAuth core identity:
- **Endpoint**: `POST /internal/proxy-register`.
- **Auth**: `X-Internal-Key` (Internal Auth).
- **Marker**: Accounts created this way are flagged as `cbh=0` (Created By Human = false) and are subject to the ecosystem's bot cleanup policy (30-day claim window).
- **Current caller status**: WinnerProxy does not use this endpoint; its registration client calls `POST /register` instead (see `docs/dev/HRPAuth/yggdrasil-api.md`, Account Registration and Sync).

### 3.2 Texture Standards
- **Validation**: Standard skin PNG sizes are 64x32 and 64x64; standard cape PNG sizes are 64x32 and 22x17. Non-standard dimensions can be accepted with warnings in the upload response, but a skin must be large enough to extract its face and head overlay.
- **Business Scope**: `/texture/get`, `/texture/upload/:uuid`, `DELETE /texture/delete/:uuid/:type`, `GET /texture/avatar/:uuid`, and `GET /previews/:fileName` belong to **current profile texture management**. They are not a texture discovery or per-account texture-library surface.
- **Skin Avatar**: `GET /texture/avatar/:uuid` is public and returns `image/png`, not a JSON success envelope. It renders the current local skin's front face with the head overlay; the UUID may contain hyphens. It returns `400` for an invalid UUID, `404` when no local skin is bound, and `500` on storage or rendering failure. It does not change the account avatar.
- **Lifecycle**: Skin upload generates the avatar; an existing skin's avatar is generated on first access if needed. Deleting or replacing a skin removes the active binding immediately; the old texture and avatar become eligible for background cleanup after seven days, provided no active or unexpired binding references the same texture.

---

## 4. Configuration

The service reads `config.yaml` from its working directory (auto-generated on
first start). Current schema version: **3** (`ConfigVersion`, migration chain
1→3). Top-level sections:

| Section | Keys | Notes |
|---|---|---|
| `version` | | Schema version string |
| `site` | `name`, `implementation`, `version` | Service identity |
| `server` | `port`, `cors_origin` | HTTP listener |
| `callback` | `url` | Backend callback URL |
| `database` | `host`, `db_name`, `user`, `password`, `charset`, `table_prefix` | Own MySQL database |
| `redis` | `host`, `port`, `password`, `db`, `prefix` | |
| `core_api` | `base_url`, `client_id`, `client_secret` | HRPAuth core connection (OAuth2 service credentials) |
| `security` | `rate_limit_max_attempts`, `rate_limit_window_sec` | Login rate limiting |
| `microservice` | `name`, `ttl_seconds`, `relay_url`, `relay_path_prefix`, `profile_cards` | Presence/relay registration; `relay_path_prefix` defaults to `/yggdrasil-api`; `profile_cards` maps card names to priorities |
| `yggdrasil.server` | `name`, `implementation`, `version`, `links.homepage`, `links.register`, `skin_domains`, `signature_public_key_path`, `signature_private_key_path`, `textures_storage` | Signature keys are read from PEM **files** (path keys) |
| `yggdrasil.security` | `token_expiry_days`, `session_expiry_seconds`, `max_texture_width`, `max_texture_height`, `max_texture_file_size`, `max_tokens_per_user` | `max_texture_file_size` is parsed but not written into the generated default config (value 0 disables the check) |
| `yggdrasil.feature_flags` | `non_email_login`, `legacy_skin_api`, `no_mojang_namespace`, `enable_mojang_anti_features`, `enable_profile_key`, `username_check`, `enable_ip_check` | See `docs/dev/HRPAuth/feature-flags.md` |

Runtime values pulled from HRPAuth core at startup (`Runtime.SiteURL`,
`Runtime.FrontendURL`, `Runtime.InternalKey`) are not configuration keys.

---

## 5. Anti-Drift Compliance
To prevent documentation drift, any change to API routes or response structures MUST be verified by running:
```bash
./scripts/check-business-api-drift.sh
```
The implementation in `main.go` MUST remain strictly aligned with `hrpauth-yggdrasil-business.yaml`.
