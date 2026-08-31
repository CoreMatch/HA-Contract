# Microservice Extension Layer

This document describes the microservice extension mechanism of HRPAuth. It covers service registration, frontend service discovery, SDK relaying, route rules, relay rules, request orchestration, and the three-level auth model.

## Design Positioning

HRPAuth is the **core standard service**: its request parameters, response structures, status codes, and semantics strictly follow external standards and **cannot be extended in the core flow**.

Therefore, all microservice extensions happen **outside the main service flow**:

- **Pre-flow routing**: decides, for each incoming request, whether it should be forwarded to a microservice before (or instead of) reaching the main service.
- **Post-flow routing**: after the main service produces a response, dispatches the result to designated microservices for side processing.

The extension layer is an **edge orchestrator / router**, not a plugin system. It never changes HRPAuth's internal business decisions. The standard response is passed through unchanged by default; post-processing is executed out-of-band.

```
Frontend
  -> Extension Layer (relay / orchestration middlewares)
       -> HRPAuth core (standard, unmodified)
       -> Microservices (pre routing / post routing)
```

## Service Registration (`POST /services/presence`)

Every participant — including the frontend SPA itself — is a microservice. It announces its existence with a "bonjour" handshake; HRPAuth replies "ca va très bien, merci".

### Request

```json
{
  "name": "texture-service",
  "ttl_seconds": 120,
  "scope": {
    "name": "texture-processing",
    "frontend_areas": ["skin", "user"]
  },
  "sdk_url": "http://127.0.0.1:2703/sdk/texture-sdk.js",
  "security_level": 1,
  "interacts_with": ["audit-service"]
}
```

| Field | Description |
| --- | --- |
| `name` | Unique service name. |
| `ttl_seconds` | Optional self-declared lifetime in seconds. `<= 0` or omitted means **never expires**; the record is kept until the HRPAuth process exits. |
| `scope` | Optional scope declaration. |
| `scope.name` | Scope name of this service. |
| `scope.frontend_areas` | Frontend areas this service covers. **Non-empty means the service is visible to frontends**; omitted/empty means frontend-invisible (internal only). The frontend SPA uses this field to declare itself as a frontend. |
| `sdk_url` | Optional URL of a JS file that tells the target frontend area how to use this service. The file content is negotiated between the microservice and the frontend; HRPAuth does not interpret it and only relays it. |
| `security_level` | Auth level of this service: `0` none / `1` user / `2` ops. Default `0`, clamped to `0..2`. |
| `interacts_with` | Optional list of other services this service interacts with. By default a service is implicitly treated as interacting with the main service only. |

### Response

```json
{
  "success": true,
  "message": "ca va très bien, merci",
  "data": {
    "service": "texture-service",
    "first_seen": "...",
    "last_seen": "...",
    "expires_at": null
  }
}
```

Repeated heartbeats keep `first_seen`, refresh `last_seen`, and may update all optional fields. Expired records are cleaned lazily on access.

## Frontend Service Discovery (`GET /services/list`)

The frontend SPA pulls the list of microservices relevant to itself. Public endpoint, no authentication; the caller must be a registered service and pass its own name.

```
GET /services/list?name=hrpauth-webui
```

HRPAuth looks up the frontend's registered `scope.frontend_areas`, then returns only services whose `frontend_areas` **overlap** with it. The frontend itself is excluded.

```json
{
  "success": true,
  "message": "services fetched",
  "data": [
    {
      "name": "texture-service",
      "scope_name": "texture-processing",
      "sdk_url": "http://127.0.0.1:2703/sdk/texture-sdk.js"
    }
  ]
}
```

`name` is required; missing or unregistered (or not declared as frontend) yields `service_not_registered`.

## SDK Relaying (`GET /services/sdk/:name`)

Loads the JS usage file of a service through HRPAuth as relay. HRPAuth fetches the service's `sdk_url` and passes the response through unchanged (Content-Type follows the microservice, typically `application/javascript`).

```html
<script src="http://localhost:PORT/services/sdk/texture-service"></script>
```

- Requires the service to be registered **and** to have declared `sdk_url`; otherwise `404 sdk_not_found`.
- Relay failure returns `502 relay_failed`.
- The frontend should always load the SDK through this endpoint; `sdk_url` itself points to the microservice's internal address and must not be reached directly.

### Frontend SDK Exposure Convention (HRPAuth-Web)

This section describes the **current HRPAuth-Web implementation** — it is not an HRPAuth requirement. HRPAuth still does not interpret SDK contents and only relays them unchanged.

The reference frontend (HRPAuth-Web) expects an injected SDK to expose a **global object**:

```html
<script src="http://localhost:PORT/services/sdk/texture-service"></script>
```

The global key is derived from the service name: `window['<service-name>-sdk']` (e.g. `window['texture-service-sdk']`). The minimum shape recognized by the frontend:

```javascript
window['texture-service-sdk'] = {
  name: 'texture-service',
  version: '1.0.0',
  menu: { label: 'Texture Studio' }, // optional: adds a navbar item
  iframeUrl: '/texture-service',      // optional: <iframe> src when the item is opened
  init: ({ area }) => { /* optional */ }
};
```

- `menu` (optional): when present, the frontend adds a navbar item (login only) navigating to `/service/<name>`.
- `iframeUrl` (optional): used as the `<iframe src>` on that page; absolute and relative URLs are both passed through as-is.
- The frontend reads the global object via `getServiceSDK(name)` (see `HRPAuth-Web/src/utils/serviceRegistry.ts`); loading completion is observable via `onSDKLoaded(name)`.

## Route Rules (`POST /services/route`)

A microservice declares its routing rules. Registration requires the service to be registered via `/services/presence` first.

### Request

```json
{
  "name": "texture-service",
  "rules": [
    {
      "scope": "texture-processing",
      "paths": ["/texture/*", "/texture/upload"],
      "pre_url": "http://texture-service:8080",
      "post_url": "http://texture-service:8080/post"
    }
  ]
}
```

| Field | Description |
| --- | --- |
| `scope` | Scope name this rule belongs to. |
| `paths` | Exact paths and `*` prefix wildcards this rule matches. |
| `pre_url` | Non-empty declares a **pre-route**: requests matching the path are forwarded here. |
| `post_url` | Non-empty declares a **post-route**: successful main responses are dispatched here. |

Rules are replaced as a whole per service (last registration wins).

## Relay Rules (`POST` / `DELETE` / `GET /services/relay`)

A microservice asks HRPAuth to act as a relay for a URL mapping: requests hitting `dest` (a public path on the main service) are forwarded to `source` (the microservice address). Registration requires prior presence registration.

### Register

```json
{
  "name": "texture-service",
  "relays": [
    { "dest": "/serviceone", "source": "http://127.0.0.1:2703/serviceone" }
  ]
}
```

### Path Mapping (prefix join)

`dest` acts as a prefix; the remaining path is appended to `source`:

```
dest=/serviceone, source=http://127.0.0.1:2703/serviceone
GET /serviceone       -> http://127.0.0.1:2703/serviceone
GET /serviceone/foo   -> http://127.0.0.1:2703/serviceone/foo
GET /serviceonex      -> not matched (boundary isolation)
```

Longest `dest` prefix wins. `dest` is normalized to start with `/` and have no trailing slash.

### Delete

```json
{ "name": "texture-service", "dest": "/serviceone" }
```

### List

```
GET /services/relay          # all rules
GET /services/relay?name=    # filtered by service
```

## Request Orchestration

Two middlewares are mounted before all main-service routes; controllers are untouched.

### Pre-Routing (orchestration)

When an incoming request path matches rules with `pre_url`:

1. Compute the required auth level = **dynamic max** of the `security_level` of all matched pre services (strictest wins when multiple services participate).
2. Verify the caller's credential level (see [Auth Levels](#auth-levels)); insufficient → `401/403`, request aborted.
3. Fan out: forward the request to each pre service in rule order (method, query, Content-Type, `request_id` passed through).
4. First successful forward short-circuits and returns the microservice's response.
5. **All fail → fail-open**, the request continues to the main service.

### Post-Routing (orchestration)

After the main service responds with a **2xx** status, HRPAuth asynchronously POSTs `{path, method, request_id, status, response}` to every `post_url`. Non-2xx does not trigger. Post dispatch is out-of-band (side semantics); failures are ignored and do not affect the main response.

### Relay (independent mechanism)

Relay is independent from pre/post orchestration and is mounted before it. On a `dest` hit, the caller's auth level is checked against the service's `security_level`, then the request is forwarded. **Relay failure returns `502` and never falls back to the main service** (the path belongs to the microservice). `/services/*` system endpoints never participate in relay or orchestration.

## Auth Levels

Three credential levels are defined:

| Level | Meaning | Accepted Credentials |
| --- | --- | --- |
| `0` | None | No credentials required |
| `1` | User | OAuth2 **user** Bearer token |
| `2` | Ops | Manage Token (M-T) **or** OAuth2 service token (`client_credentials` / `.as-service` scope) |

Resolution order: no `Authorization: Bearer` → `0`; token equals M-T → `2`; resolvable OAuth2 token → `2` if service token, else `1`; unresolvable → `0`.

Enforcement:

- **Single service (implicit "main-only" interaction)**: required level = that service's `security_level`.
- **Multiple services involved in one request** (e.g. pre fan-out): required level = `max` of their `security_level` (strictest wins), computed dynamically at request time.

Insufficient credentials: no credential → `401 oauth_login_required`; credential present but too weak → `403 insufficient_auth_level`.

Post-routing dispatch is initiated by HRPAuth itself and is not subject to caller auth-level checks.
