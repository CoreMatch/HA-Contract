# Agents Guide

This document instructs AI agents on how to work within the **HA-Contract** monorepo. Every agent operating in this repository MUST read this file before starting any task.

---

## Repository Overview

HA-Contract is the single-source-of-truth contract and service collection for the [CoreMatch](https://github.com/CoreMatch) HA (High-performance Authentication) system. It contains **five sub-projects** and a centralized documentation layer.

| Sub-Project | Path | Purpose | Tech Stack |
|---|---|---|---|
| **HRPAuth** | `HRPAuth/` | Core auth service (Business API + Yggdrasil) | Go 1.26+, Gin, MySQL, Redis, GORM |
| **HASkinLib** | `HASkinLib/` | Skin and texture library | Go 1.25+, Gin, MySQL (shared), GORM |
| **WinnerProxy** | `WinnerProxy/` | Server-join proxy (HRPAuth or Mojang upstream) | Go 1.26+, Gin, freecache |
| **HASkinProxy** | `HASkinProxy/` | Yggdrasil-to-CSL compatibility proxy | Go 1.21+, Gin, freecache |
| **HRPAuth-Web** | `HRPAuth-Web/` | Frontend SPA for the auth service | TypeScript, React 19, MUI v7, Vite 7 |
| **Docs & Scripts** | `docs/`, `scripts/` | API specs, dev guides, CI helpers | OpenAPI YAML, Shell |

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

Each sub-project contains an `HRPAuth-Wiki/` directory. Per project rules:

- `HA-Contract/` directory docs → **for AI agents**
- `HRPAuth-Wiki/` directory docs → **for human developers**

Agents should consume docs from `HA-Contract/docs/` and the relevant sub-project's root. Do not modify `HRPAuth-Wiki/` directories.

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
- Declare a `sdk_url` pointing to a JS file that exposes `window['<service-name>-sdk']`.
- Declare relay rules via `POST /services/relay` for frontend-accessible paths.
- See `docs/dev/HRPAuth/microservices.md` for full specification.

### 7. Sub-Project Coupling Awareness

**HASkinLib shares HRPAuth's MySQL database directly.** Any schema migration in HRPAuth (new columns, renames, dropped tables) WILL break HASkinLib if not coordinated. When modifying HRPAuth models:

1. Check HASkinLib's `models/models.go` to see which HRPAuth tables it reads.
2. Ensure backward compatibility or coordinate the migration with HASkinLib.

### 8. Configuration Conventions

- HRPAuth uses versioned `config.yaml` with auto-migration (currently schema v3). When adding new config fields, increment the version and add a migration function.
- HASkinProxy, WinnerProxy use simple `config.yaml` with auto-generation on first run.
- HRPAuth-Web uses `public/config.json` (runtime) and `config/backend-dev.json` (dev proxy).

### 9. Build and CI

- **Go services**: `go build -o ./build/<name>` (each has a `build.sh`).
- **HRPAuth-Web**: `npm run build` (Vite production build).
- **CI**: GitHub Actions on HASkinLib (Go build) and HRPAuth-Web (npm test + publish).
- **No Docker**: The project deploys as native binaries + static frontend.

---

## How to Work on Each Sub-Project

### HRPAuth (Core Auth)

**Key directories**: `config/`, `controllers/`, `database/`, `models/`, `services/`, `utils/`

- Entry point: `main.go`
- Routes are defined in `main.go`. After adding/changing routes, run the anti-drift script.
- Migrations live in `database/migrations/` (golang-migrate format).
- Yggdrasil API is separate from Business API. Yggdrasil routes follow the external spec; Business routes follow `docs/api/openapi/hrpauth-business.yaml`.

### HASkinLib (Skin Library)

**Key directories**: `controllers/`, `models/`, `services/`

- Shares HRPAuth's MySQL database. Reads `users`, `oauth2_access_tokens`, `profiles` tables.
- Own tables: `texture_list_skin`, `texture_list_cape`.
- Generates WebP previews from uploaded textures.
- Business API spec: `docs/api/openapi/haskinlib-business.yaml`.

### WinnerProxy (Server Join Proxy)

**Key directories**: `upstream/`, `controllers/`, `models/`

- Abstracts upstream via `UpstreamService` interface (`HrpauthService` / `MojangService`).
- Uses freecache for in-memory caching.
- No external API spec — it proxies Yggdrasil session endpoints.

### HASkinProxy (CSL Compatibility)

**Key directories**: `controllers/`, `services/`

- Translates Yggdrasil API → CustomSkinLoader JSON format.
- Registers with HRPAuth via the microservice extension layer.
- Business API spec: `docs/api/openapi/haskinproxy-business.yaml`.

### HRPAuth-Web (Frontend SPA)

**Key directories**: `src/`, `public/`, `config/`

- React 19 + MUI v7 + Vite 7 + React Router v7.
- Uses `skinview3d` for 3D skin rendering and `qrcode.react` for QR codes.
- Dev proxy configured in `config/backend-dev.json`.
- Discovers microservices at runtime via `GET /services/list` and loads their SDKs.

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
