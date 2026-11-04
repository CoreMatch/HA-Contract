# Agents Guide

This document instructs AI agents on how to work within the **HA-Contract** repository. Every agent operating in this repository MUST read this file before starting any task.

---

## Repository Overview

HA-Contract is the single-source-of-truth **contract and documentation center** for the [CoreMatch](https://github.com/CoreMatch) HA (High-performance Authentication) system. The services themselves live in **separate sibling repositories**; this repository contains only contracts, documentation, and helper scripts (the legacy root-level symlinks into a local monorepo were removed on 2026-11-03).

This repository exists for **secondary development** on top of the HA platform. New services, clients, and integrations are built against the contracts defined here, and this is the single place where those contracts are kept current.

| Service | Repository | Purpose | Tech Stack |
|---|---|---|---|
| **HRPAuth** | [`CoreMatch/HRPAuth`](https://github.com/CoreMatch/HRPAuth) | Core auth service (Business API, OAuth2 authorization server) | Go 1.26+, Gin, MySQL, Redis, GORM |
| **HRPAuth-Yggdrasil-API** | [`CoreMatch/HRPAuth-Yggdrasil-API`](https://github.com/CoreMatch/HRPAuth-Yggdrasil-API) | Yggdrasil protocol provider and game account management (split out of HRPAuth in 2026-10) | Go, Gin, MySQL, Redis, GORM |
| **HASkinLib** | [`CoreMatch/HASkinLib`](https://github.com/CoreMatch/HASkinLib) | Skin and texture library | Go 1.25+, Gin, MySQL (shared), GORM |
| **WinnerProxy** | [`CoreMatch/WinnerProxy`](https://github.com/CoreMatch/WinnerProxy) | Server-join proxy (HRPAuth or Mojang upstream) | Go 1.26+, Gin, freecache |
| **HASkinProxy** | [`CoreMatch/HASkinProxy`](https://github.com/CoreMatch/HASkinProxy) | Yggdrasil-to-CSL compatibility proxy | Go 1.21+, Gin, freecache |
| **HRPAuth-WebUI** | [`CoreMatch/HRPAuth-WebUI`](https://github.com/CoreMatch/HRPAuth-WebUI) | Frontend SPA for the auth service | TypeScript, React 19, MUI v7, Vite 7 |
| **HA-WebUI-SDKHandler** | [`CoreMatch/HA-WebUI-SDKHandler`](https://github.com/CoreMatch/HA-WebUI-SDKHandler) | Compile-time SDK aggregation build service | Go 1.25+, Gin |
| **Docs & Scripts** | `docs/`, `scripts/` in this repository | API specs, dev guides, CI helpers | OpenAPI YAML, Shell |

---

## Repository Scope

HA-Contract is used for **secondary development**: everything in this repository exists so that other people and other repositories can build on the HA platform against a stable contract.

Material that describes how the platform is operated rather than how it is built against is **out of scope here**. Deployment and operations documentation belongs to the [Wiki](https://github.com/SamuelCheston/SamuelWiki), and must not be added to this repository.

---

## Mandatory Rules for All Agents

### 1. Documentation Rules

- **Single Source of Truth**: All API definitions, error codes, and development specifications live in `docs/`. Do NOT rely on code comments or in-repo READMEs as the authoritative API source.
- **OpenAPI specs** (`docs/api/openapi/`) define the contract. Code must match the spec, not the other way around.
- **External standards** in `docs/references/` (CustomSkinAPI, authlib-injector/Yggdrasil) are **read-only**. Never modify files in this directory.
- **Archive**: Old/drifted docs are in `archive/docs/`. Do NOT use them as development references.
- **Language**: All documentation must be written in **English**.
- **Anti-Drift Check**: Before submitting changes that touch API routes, run:
  ```bash
  ./scripts/check-business-api-drift.sh
  ```

### 2. Documentation Directories

Documentation lives in two independent places:

- `HA-Contract/docs/` (this repository) → **for AI agents** and as the authoritative contract source
- [`SamuelCheston/SamuelWiki`](https://github.com/SamuelCheston/SamuelWiki) → **for human developers** (separate content repository), and the home of all deployment and operations documentation

Agents should consume docs from `HA-Contract/docs/` and the relevant service repository's root. Do not modify Wiki content as part of contract work.

### 3. Unified Response Format

All business APIs follow this schema:

```json
{
  "success": true,
  "message": "...",
  "data": { },
  "code": "error_code",
  "meta": { "request_id": "..." }
}
```

- `code` is the standard error field; `error` is a legacy alias.
- `request_id` is used for tracing.
- New code must always read/write from `data` on success.

### 4. Error Codes

Use stable `lower_snake_case` error codes. Register new codes in `docs/api/error-codes.md`.

### 5. Authentication Levels

| Level | Meaning | Credentials |
|---|---|---|
| 0 | None | No credentials required |
| 1 | User | OAuth2 user Bearer token |
| 2 | Ops | Manage Token (M-T) **or** OAuth2 service token |

When creating new endpoints, declare the required auth level and document it in the OpenAPI spec.

### 6. Microservice Extension Protocol

HRPAuth exposes a microservice extension layer (relay, pre-routing, post-routing). If your sub-project needs to integrate with HRPAuth's WEBUI, follow the extension protocol:

- Register via `POST /services/presence` (bonjour handshake).
- Upload an SDK source package (tar.gz/zip with a root-level `manifest.json`, `schema_version=1`) to `POST /services/sdk-packages` to integrate into the WebUI at compile time.
- Treat HRPAuth WebUI as **one overall SDK host**. `frontend_areas` are mount zones inside that single WebUI, not separate WebUIs or separate SDK runtimes. HA-WebUI-SDKHandler polls `GET /services/sdk-packages` (ETag-based) and aggregates all SDK source packages into the WebUI build.
- Declare relay rules via `POST /services/relay` for frontend-accessible paths.
- See `docs/dev/HRPAuth/sdk-package.md` for the SDK package format.
- See `docs/dev/HRPAuth/microservices.md` for full specification.

### 7. Sub-Project Coupling Awareness

**HASkinLib uses its own MySQL database** (startup refuses a shared HRPAuth
database layout) and authenticates users by calling HRPAuth core HTTP APIs
(`POST /internal/verify-token`, `GET /services/users/{uuid}`). Coupling is at
the HTTP contract level: changes to those core endpoints or to the user
identity fields they return affect HASkinLib.

### 8. Configuration Conventions

- HRPAuth uses versioned `config.yaml` with auto-migration (currently schema v11). When adding new config fields, increment the version and add a migration function.
- HASkinProxy uses a simple `config.yaml` with auto-generation on first run; WinnerProxy uses `config.yml` with auto-generation on first run.
- HRPAuth-WebUI uses `public/config.json` (runtime) and `config/backend-dev.json` (dev proxy).

### 9. Build and CI

- **Go services**: `go build -o ./build/<name>` (each has a `build.sh`).
- **HRPAuth-Web**: `npm run build` (Vite production build).
- **CI**: GitHub Actions on HASkinLib (Go build) and HRPAuth-Web (npm test + publish).

---

## How to Work on Each Service

### HRPAuth (Core Auth)

**Key directories**: `config/`, `controllers/`, `database/`, `models/`, `services/`, `utils/`

- Entry point: `main.go`
- Routes are defined in `main.go`. After adding/changing routes, run the anti-drift script.
- Migrations live in `database/migrations/` (golang-migrate format).
- The Yggdrasil protocol surface no longer lives here; it is served by `HRPAuth-Yggdrasil-API`. Business routes follow `docs/api/openapi/hrpauth-business.yaml`.

### HASkinLib (Skin Library)

**Key directories**: `controllers/`, `models/`, `services/`

- Uses its own MySQL database (config schema v6, versioned with backup support); user authentication goes through HRPAuth core HTTP APIs (`/internal/verify-token`, `/services/users/{uuid}`), not shared tables.
- Own tables: `hasl_texture_list_skin`, `hasl_texture_list_cape` (table prefix configurable).
- Generates WebP previews from uploaded textures.
- Business API spec: `docs/api/openapi/haskinlib-business.yaml` in this repository (rebuilt 2026-11-04 from the current implementation); see also `HASkinLib/docs/skinlib-api.md` in the service repository.

### WinnerProxy (Server Join Proxy)

**Key directories**: `internal/handler/`, `internal/proxy/`, `internal/hrpauth/`, `internal/cache/`, `internal/router/`

- Abstracts upstream via `UpstreamService` interface (`HrpauthService` / `MojangService`).
- Uses freecache for in-memory caching.
- No external API spec — it proxies Yggdrasil session endpoints.

### HASkinProxy (CSL Compatibility)

**Key directories**: `controllers/`, `services/`

- Translates Yggdrasil API → CustomSkinLoader JSON format.
- Registers with HRPAuth via the microservice extension layer.
- Business API spec: **pending** — no `haskinproxy-business.yaml` exists in `docs/api/openapi/` yet; see `docs/dev/HASkinProxy/README.md` in this repository.

### HRPAuth-WebUI (Frontend SPA)

**Key directories**: `src/`, `public/`, `config/`

- React 19 + MUI v7 + Vite 7 + React Router v7.
- Uses `skinview3d` for 3D skin rendering and `qrcode.react` for QR codes.
- Dev proxy configured in `config/backend-dev.json`.
- Has all satellite SDKs injected as source packages at compile time by HA-WebUI-SDKHandler.

---

## Roadmap

> **Agents must check this section before starting any task.**
> If your task relates to a roadmap item, acknowledge it in your output.
> If your task reveals a cross-project dependency or new requirement, propose adding it here and **ask the owner before modifying this section**.

### Roadmap Items

| # | Item | Owner | Depends On | Status | Notes |
|---|---|---|---|---|---|
| 1.1 | *Example: Ensure all business routes appear in OpenAPI specs* | *HRPAuth, HASkinLib* | *—* | *Pending* | *Use `check-business-api-drift.sh` to verify* |
| 2.1 | `POST /admin/force-bind`: transfer `mojang_uuid` from proxy account (cbh=0) to manual account, delete proxy account | HRPAuth | — | Pending | Contract & wiki updated; Velocity plugin (`HRPAuth-Spigot`) `ForceBindCommand` implemented; HA backend handler not yet implemented |

> Agents should add items to this table when a task reveals a cross-project dependency or a new requirement.
> Always ask the owner before adding or modifying roadmap items.

---

## Agent Task Checklist

Before starting any task, an agent MUST:

1. **Read this file** (`agents.md`) to understand the project structure and rules.
2. **Check the Roadmap** section above to see if your task relates to an existing item. If yes, acknowledge it.
3. **Identify cross-project impact**: Does your change affect another sub-project? If yes, note the dependency in the Roadmap's Cross-Project Dependencies table and flag it.
4. **Consult the relevant OpenAPI spec** in `docs/api/openapi/` before modifying any API route.
5. **Run the anti-drift script** (`./scripts/check-business-api-drift.sh`) if you modified business API routes.
6. **Ask the owner** before modifying this `agents.md` file or making breaking changes to shared interfaces.

When proposing new roadmap items or cross-project dependencies, **always ask the owner first** before adding them.
