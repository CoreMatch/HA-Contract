# Yggdrasil API Reference

This document is the single source of truth for the **Yggdrasil-compatible** HTTP surface exposed by the **HRPAuth-Yggdrasil-API** service. This service is decoupled from the HRPAuth core and focuses entirely on Minecraft-related logic.

> Reference target: [authlib-injector Yggdrasil Server Technical Specification](https://yushijinhun.github.io/authlib-injector/) and [wiki.vg Authentication](https://wiki.vg/Authentication).

## Contents

1. [Conventions](#1-conventions)
2. [Errors](#2-errors)
3. [Meta — `GET /`](#3-meta--get-)
4. [Authserver](#4-authserver)
5. [Sessionserver](#5-sessionserver)
6. [Profile and Texture](#6-profile-and-texture)
7. [Legacy Skin API](#7-legacy-skin-api)
8. [Minecraft Services (Profile Keys)](#8-minecraft-services-profile-keys)
9. [Account Registration and Sync](#9-account-registration-and-sync)

---

## 1. Conventions

- All requests and responses are JSON, `Content-Type: application/json; charset=utf-8`. The two texture download endpoints (`GET /textures/:hash`, `GET /skins/MinecraftSkins/:username`) return `image/png` instead.
- UUIDs in paths and responses are **unhyphenated lowercase hex** (32 chars).
- All endpoints should be served over HTTPS in production.

## 2. Errors

Standard Yggdrasil error envelope:

```json
{
  "error":        "<machine-readable type>",
  "errorMessage": "<human-readable detail>",
  "cause":        null
}
```

| HTTP | `error` | Meaning |
|------|---------|---------|
| 400 | `BadRequestException` | Malformed request (missing fields, bad query params, etc.). |
| 400 | `IllegalArgumentException` | Generic argument rejection. |
| 400 | `ProfileNotFoundException` | `GET /sessionserver/session/minecraft/profile/:uuid` could not find the UUID. |
| 401 | `UnauthorizedOperationException` | Texture upload/delete with no/invalid `Authorization: Bearer <accessToken>`. |
| 403 | `ForbiddenOperationException` | Wrong credentials, invalid token, rate limited, or feature disabled. |
| 404 | `NotFoundException` | `GET /textures/:hash` hash not on disk. |
| 404 | `MethodNotAllowedException` | Wrong HTTP method for a known path. |

The `/minecraftservices/player/certificates` endpoint additionally emits a **Mojang-style** error envelope (`path` + `errorType` + `error` + `errorMessage`) for the `401 Unauthorized` case to match what the Minecraft client expects.

## 3. Meta — `GET /`

| Status | Headers | Body |
|--------|---------|------|
| `200` | `X-Authlib-Injector-API-Location: /` | See below |

```json
{
  "meta": {
    "serverName":            "<yggdrasil.server.name || site.name>",
    "implementationName":    "<yggdrasil.server.implementation || site.implementation>",
    "implementationVersion": "<yggdrasil.server.version || site.version>",
    "links": {
      "homepage": "<from yggdrasil.server.links.homepage || frontend.url>",
      "register": "<from yggdrasil.server.links.register || frontend.url + '/register'>"
    },
    "feature.non_email_login":             true,
    "feature.legacy_skin_api":             true,
    "feature.no_mojang_namespace":         false,
    "feature.enable_mojang_anti_features": false,
    "feature.enable_profile_key":          false,
    "feature.username_check":              true
  },
  "skinDomains":        ["<domain>", ".<domain>"],
  "signaturePublickey": "<PEM public key from yggdrasil.server.signature_public_key>"
}
```

`skinDomains` defaults to `[callback.url domain, .callback.url domain]` when `yggdrasil.server.skin_domains` is empty.

The response also carries `X-Authlib-Injector-API-Location: /` so that authlib-injector ALI resolution points back at the same root.

## 4. Authserver

| Endpoint | Auth | Notes |
|----------|------|-------|
| `POST /authserver/authenticate` | none | Username/password + `agent`. Body: `{username, password, agent:{name,version}, clientToken?, requestUser?}`. Rate-limited by `security.rate_limit_*`. |
| `POST /authserver/refresh` | none | Body: `{accessToken, clientToken, selectedProfile?, requestUser?}`. **Response no longer includes `availableProfiles`** — only `accessToken`, `clientToken`, `selectedProfile` and (when `requestUser=true`) `user`. This matches the authlib-injector wiki response schema. |
| `POST /authserver/validate` | none | Body: `{accessToken, clientToken?}`. Returns `204 No Content` on success, `403` otherwise. |
| `POST /authserver/invalidate` | none | Body: `{accessToken, clientToken?}`. Always returns `204`. |
| `POST /authserver/signout` | none | Body: `{username, password}`. **Rate-limited** with the same Redis counter as `/authenticate` to prevent password enumeration via this endpoint. Always returns `204`. |

### Successful `/authenticate` Response

```json
{
  "accessToken": "<new or reused>",
  "clientToken": "<echoed or generated>",
  "availableProfiles": [
    { "id": "<uuid>", "name": "<profile name>" }
  ],
  "selectedProfile": { "id": "<uuid>", "name": "<profile name>" }
}
```

`user` is appended when `requestUser: true`.

## 5. Sessionserver

| Endpoint | Notes |
|----------|-------|
| `POST /sessionserver/session/minecraft/join` | Body: `{accessToken, selectedProfile, serverId}`. Records a session keyed by `(profile_id, server_id)` with TTL = `yggdrasil.security.session_expiry_seconds`. |
| `GET /sessionserver/session/minecraft/hasJoined?username=&serverId=&ip=` | Returns `204` on miss; otherwise a profile object including `textures` and (when applicable) the `textures` property signature. `ip` is only enforced when `yggdrasil.feature_flags.enable_ip_check = true`. |
| `GET /sessionserver/session/minecraft/profile/:uuid?unsigned=true` | Returns the profile plus properties; `signature` is included only when `unsigned=false`. `204` on miss. |

`hasJoined` response:

```json
{
  "id":   "<uuid>",
  "name": "<profile name>",
  "properties": [
    {
      "name":  "textures",
      "value": "<base64 JSON>",
      "signature": "<base64>"
    }
  ]
}
```

## 6. Profile and Texture

| Endpoint | Auth | Notes |
|----------|------|-------|
| `POST /api/profiles/minecraft` | none | Body: 纯 JSON 数组 `["name1","name2",...]`（authlib-injector / wiki.vg 标准）。响应为纯数组 `[{"id","name"}]`，仅返回命中的档案；未命中任何档案时返回 `[]`。非法请求体返回 `IllegalArgumentException`。 |
| `PUT /api/user/profile/:uuid/:textureType` | `Authorization: Bearer <accessToken>` | `textureType ∈ {skin, cape}`. Multipart with `file` (PNG, validated to be 64x32/64x64 for skin or 64x32/22x17 for cape) and optional `model` (`slim` or empty). PNG is re-encoded to strip metadata. `textures` property is re-signed with the Yggdrasil private key. Non-standard dimensions or oversized textures are allowed with a `X-Texture-Warnings` response header when warnings are generated. |
| `DELETE /api/user/profile/:uuid/:textureType` | `Authorization: Bearer <accessToken>` | Clears the texture. The property is dropped when the payload becomes empty; otherwise only the requested texture type is removed and the payload is re-signed. |
| `GET /textures/:hash` | none | Streams `<storage>/textures/<hash>` as `image/png`. `404 NotFoundException` if the file is missing. |
| `GET /previews/:fileName` | none | Streams generated WebP preview file. |

## 7. Legacy Skin API

`GET /skins/MinecraftSkins/:username` — see [`legacy-skin-api.md`](./legacy-skin-api.md) for full details.

- Gate: `yggdrasil.feature_flags.legacy_skin_api == true`.
- Trailing `.png` is stripped from `:username` before lookup.
- Returns the on-disk SKIN PNG or `204 No Content`.

## 8. Minecraft Services (Profile Keys)

`POST /minecraftservices/player/certificates` and `GET /minecraftservices/publickeys` — see [`profile-keys.md`](./profile-keys.md) for full details.

- Gate: `yggdrasil.feature_flags.enable_profile_key == true`.
- `/player/certificates` auth: `Authorization: Bearer <yggdrasil accessToken>`.
- 2048-bit RSA key pair, persisted per user, valid 48h with refresh window at +40h.
- Public key signed by the Yggdrasil signature private key (SHA1withRSA), so the existing `signaturePublickey` from `GET /` doubles as the trust root.

## 9. Account Registration and Sync

### Game Account Registration (`POST /register`)

Creates a game-specific account and default profile for an existing core user.

- **Auth**: None (requires core credentials in body).
- **Body**: `{ "identifier": "<email or username>", "password": "<password>", "mojang_uuid": "<optional>" }`.
- **Logic**:
    1. Verifies credentials against the HRPAuth core service.
    2. Checks if a game account already exists for the user (1:1 mapping).
    3. Inherits the `username` from the core service for the default profile.
    4. Binds `mojang_uuid` if provided and valid.

### Data Consistency (Lazy Loading)

The Yggdrasil service no longer receives push events for username changes or account deletions. Instead, it follows a **lazy loading** pattern:

1.  **Cache Check**: When a profile name is needed (e.g., during `/authenticate` or `/sessionserver` calls), the service checks Redis for a cached `username` associated with the `core_user_id`.
2.  **Pull from Core**: If not cached, the service calls HRPAuth Core's `GET /services/users/:uuid` internal API.
3.  **Update & Cache**: The retrieved name is stored in Redis (TTL: 10 minutes) and the local database is updated to reflect the change.
4.  **Auto-Cleanup**: If HRPAuth Core returns a `404 Not Found`, the Yggdrasil service assumes the core account has been deleted and triggers local account deletion.

### Internal Heartbeat (`GET /internal/heartbeat`)

Used by HRPAuth core to verify service health and internal key validity.

- **Auth**: `X-Internal-Key` header.
- **Response**: `204 No Content` or `200 OK` on success; `401 Unauthorized` if the key is invalid.

### Proxy Registration (`POST /internal/proxy-register`)

Used by WinnerProxy to create a game account without an HRPAuth core identity.

- **Auth**: `X-Internal-Key` header.
- **Body**: `{ "username": "<string>", "password": "<string>", "mojang_uuid": "<string>" }`.
- **Logic**:
    1. Creates an account with `cbh = 0` (Created By Human = false).
    2. Stores the provided `password` (hashed) for local Yggdrasil auth.
    3. Account is subject to bot cleanup if not claimed within 30 days.

