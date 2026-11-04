# Agents Guide

This document instructs AI agents on how to work within the **HA-Contract** repository. Every agent operating in this repository MUST read this file before starting any task.

## Repository Overview and Scope

HA-Contract is the single-source-of-truth **contract and documentation center** for the [CoreMatch](https://github.com/CoreMatch) HA (High-performance Authentication) system. The services themselves live in **separate sibling repositories**. This repository exists for **secondary development** on top of the HA platform: new services, clients, and integrations are built against the contracts defined here, and this is the single place where those contracts are kept current.

## Documentation Directories

1. **No project maintains its own contracts or documentation.** Service repositories do not keep their own API specs or development documentation.
2. **All contracts are centralized in this repository.** HA-Contract is the single source of truth: the OpenAPI specs in `docs/api/openapi/` define the contract, and code must match the spec, not the other way around. Do NOT rely on code comments or in-repo READMEs as the authoritative API source.
3. **All documentation is centralized in the [Wiki](https://wiki.mcnb.dev/).** Deployment and operations documentation belongs there and must not be added to this repository. Exception: this repository's own `knowledge/` directory holds internal ADR-style memos about this project's design and operations; it is not outward-facing documentation and is outside the Wiki centralization above.

If a service repository keeps a README at all, limit it to build-and-run entry points; do not add development or deployment documentation there.

## Mandatory Rules for All Agents

- **Language**: All documentation must be written in **English**.
- **External standards** in `docs/references/` (CustomSkinAPI, authlib-injector/Yggdrasil) are **read-only**. Never modify files in this directory. Old/drifted docs in `archive/docs/` must not be used as development references.
- **Error codes**: Use stable `lower_snake_case` error codes. Register new codes in `docs/api/error-codes.md`.
- **Anti-Drift Check**: Before submitting changes that touch API routes, run:
  ```bash
  ./scripts/check-business-api-drift.sh
  ```

### Unified Response Format

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

- `code` is the standard error field (`error` is a legacy alias), `request_id` is used for tracing, and new code must always read/write from `data` on success.

### Authentication Levels

| Level | Meaning | Credentials |
|---|---|---|
| 0 | None | No credentials required |
| 1 | User | OAuth2 user Bearer token |
| 2 | Ops | Manage Token (M-T) **or** OAuth2 service token |

When creating new endpoints, declare the required auth level and document it in the OpenAPI spec.

## Roadmap

> Cross-project dependencies and new requirements are tracked here; check this table before starting any task and acknowledge related items. **Always ask the owner before adding or modifying roadmap items, before modifying this file, or before making breaking changes to shared interfaces.**

| # | Item | Owner | Depends On | Status | Notes |
|---|---|---|---|---|---|
| 1.1 | *Example: Ensure all business routes appear in OpenAPI specs* | *HRPAuth, HASkinLib* | *—* | *Pending* | *Use `check-business-api-drift.sh` to verify* |
| 2.1 | `POST /admin/force-bind`: transfer `mojang_uuid` from proxy account (cbh=0) to manual account, delete proxy account | HRPAuth | — | Pending | Contract & wiki updated; Velocity plugin (`HRPAuth-Spigot`) `ForceBindCommand` implemented; HA backend handler not yet implemented |
