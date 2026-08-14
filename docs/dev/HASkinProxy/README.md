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
| `upstream` | `base_url` | The URL of the Yggdrasil-compliant service. |
| `cache` | `profile_ttl` | Cache duration for profile data in seconds. |
| `cache` | `texture_ttl` | Cache duration for texture metadata in seconds. |

## Implementation Details

- **Language**: Go (1.20+)
- **Framework**: Gin Gonic
- **Caching**: freecache
- **Compliance**: 
  - Upstream: [Yggdrasil API](https://github.com/yushijinhun/authlib-injector/wiki/Yggdrasil-API-Reference)
  - Downstream: [CustomSkinAPI](file:///home/lnb/HASkinProxy/HA-Contract/docs/references/CustomSkinAPI.md)

## Integration with HA System

While generic in nature, `HASkinProxy` is a key component in the HA ecosystem, serving as the primary skin delivery mechanism for clients that do not support Yggdrasil-based skin loading directly.
