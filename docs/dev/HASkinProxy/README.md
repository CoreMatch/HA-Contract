# HASkinProxy Development Guide

`HASkinProxy` is a lightweight compatibility layer designed to bridge the gap between Yggdrasil-compliant authentication services and Minecraft clients using the CustomSkinLoader (CSL) protocol.

## Overview

The proxy translates standard Yggdrasil API responses into the CSL JSON format. This allows players to use custom skins and capes on servers that implement the Yggdrasil protocol without requiring the authentication server to natively support CSL.

### Architecture Flow

1. **Username to UUID Resolution**: 
   The proxy receives a request for `{username}.json`. It calls the upstream's `/api/profiles/minecraft` endpoint to resolve the username to a UUID.
2. **Profile Retrieval**:
   Using the UUID, the proxy fetches the full Yggdrasil profile from `/sessionserver/session/minecraft/profile/{uuid}`.
3. **Protocol Translation**:
   The base64-encoded `textures` property in the Yggdrasil profile is decoded. The proxy extracts the skin and cape URLs/hashes and re-packages them into the CSL JSON format.
4. **Texture Forwarding**:
   Requests for `/textures/{hash}` are proxied to the original texture storage (e.g., Mojang or the upstream's storage).
5. **Caching Layer**:
   To minimize upstream load, the proxy implements an in-memory cache using `freecache` for both profile data and texture metadata.

## Configuration

The service is configured via a `config.yaml` file. Default values are generated if the file is missing.

| Section | Key | Description |
|---------|-----|-------------|
| `server` | `listen_addr` | The address and port the proxy listens on (default `:2702`). |
| `server` | `public_url` | Externally reachable base URL, announced to HRPAuth as the relay source. |
| `upstream` | `base_url` | The URL of the Yggdrasil-compliant service. |
| `upstream` | `timeout` | Upstream request timeout in seconds. |
| `upstream` | `client_id`, `client_secret` | OAuth2 client id/token used to authenticate against HRPAuth. |
| `cache` | `profile_ttl` | Cache duration for profile data in seconds. |
| `cache` | `texture_ttl` | Cache duration for texture metadata in seconds. |
| `cache` | `max_size_mb` | Maximum in-memory cache size in MB. |
| `presence` | `enabled` | Toggle the presence (bonjour) handshake with HRPAuth (default `true`). |
| `presence` | `name` | Service name registered in HRPAuth (default `HASkinProxy`). |
| `presence` | `ttl_seconds` | Self-declared registration lifetime in seconds; `<=0` means never expire. |
| `sdk` | `enabled` | Toggle the automatic compile-time SDK package upload to HRPAuth (default `true`). |

## Implementation Details

- **Language**: Go (1.20+)
- **Framework**: Gin Gonic
- **Caching**: freecache
- **Compliance**:
  - Upstream: [Yggdrasil API](https://github.com/yushijinhun/authlib-injector/wiki/Yggdrasil-API-Reference)
  - Downstream: [CustomSkinAPI](file:///home/lnb/HASkinProxy/HA-Contract/docs/references/CustomSkinAPI.md)

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Liveness probe. |
| `GET` | `/{username}` | CSL profile (read-through cache). |
| `GET` | `/textures/{hash}` | Raw texture bytes (read-through cache). |
| `POST` | `/{username}/texture/delete` | Forward to upstream `POST /texture/delete`. |

The CustomSkinLoader setup page is not served as a runtime route anymore: it
is shipped as a compile-time SDK package (`sdk/` in this repo, embedded into
the binary and uploaded to HRPAuth on startup, see
[HRPAuth sdk-package.md](../HRPAuth/sdk-package.md)).

### Texture Management Passthrough

`POST /{username}/texture/delete` is a transparent forwarder to HRPAuth's `POST /texture/delete`. The proxy itself does **not** authenticate requests; the `Authorization` header and the request body (containing the bearer token, `profile_id`, `texture_type`, optional `auth_type` / `uid` / `email`) are forwarded verbatim. The upstream response (status code and JSON body) is returned to the client unchanged.

`:username` is used only to evict local cache entries on success:

- `profile:{username}` is removed unconditionally on upstream 2xx.
- `tex:{hash}` entries belonging to that profile (captured before the upstream call from the cached CSL profile) are also removed, so subsequent `GET /textures/{hash}` calls and CSL profile fetches reflect the deletion without waiting for TTL expiry.

On non-2xx upstream responses, no cache eviction occurs. On network errors to the upstream, the proxy responds `502 Bad Gateway` with `{"error": "..."}`.

## Integration with HA System

While generic in nature, `HASkinProxy` is a key component in the HA ecosystem, serving as the primary skin delivery mechanism for clients that do not support Yggdrasil-based skin loading directly.
