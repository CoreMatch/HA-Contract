# HRPAuth-Yggdrasil-API Interaction Contract

This document defines the **External Interaction Contract** for the `HRPAuth-Yggdrasil-API` service. It focuses exclusively on how this service interacts with Minecraft clients, HRPAuth Core, and other ecosystem components.

---

## 1. API Surface & Protocols

### 1.1 Yggdrasil Protocol (Minecraft Standard)
This service is the authoritative provider for Yggdrasil-compatible endpoints.
- **Surface**: `/authserver/*`, `/sessionserver/*`, `/api/profiles/*`, `/textures/*`.
- **Reference**: Full endpoint details are in [yggdrasil-api.md](file:///home/lnb/Desktop/HA/HRPAuth-Yggdrasil-API/HA-Contract/docs/dev/HRPAuth/yggdrasil-api.md).
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
- **Presence**: Registers via `POST /services/presence` with `frontend_areas: ["skin", "user"]`.
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
Allows external proxies (like `WinnerProxy`) to create game accounts for users who do not yet have a core identity:
- **Endpoint**: `POST /internal/proxy-register`.
- **Auth**: `X-Internal-Key` (Internal Auth).
- **Marker**: Accounts created this way are flagged as `cbh=0` (Created By Human = false) and are subject to the ecosystem's bot cleanup policy (30-day claim window).

### 3.2 Texture Standards
- **Validation**: Skins (64x32/64x64 PNG), Capes (64x32/22x17 PNG).
- **Warning Header**: Non-standard dimensions trigger a `X-Texture-Warnings` response header.
- **Business Scope**: `/texture/get`, `/texture/upload/:uuid`, `DELETE /texture/delete/:uuid/:type`, and `GET /previews/:fileName` belong to **current profile texture management**. They are not a texture discovery or per-account texture-library surface.

---

## 4. Anti-Drift Compliance
To prevent documentation drift, any change to API routes or response structures MUST be verified by running:
```bash
./scripts/check-business-api-drift.sh
```
The implementation in `main.go` MUST remain strictly aligned with `hrpauth-yggdrasil-business.yaml`.
