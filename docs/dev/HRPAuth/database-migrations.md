# Database Migrations and Schema Sync

This document explains the current database schema management, migration commands, and standard processes for "empty database initialization" and "existing shared database management".

## Goals

- **Schema Source of Truth**: SQL migration
- **Migration Tool**: `golang-migrate`
- **Execution Entry Point**: `go run ./cmd/migrate ...`
- **Runtime Policy**: `AutoMigrate` is **no longer** executed during application startup.

## HRPAuth Core Migrations

| Path | Purpose |
|------|---------|
| `cmd/migrate/main.go` | Migration command entry point |
| `database/migrations/000001_baseline.up.sql` | Squashed baseline: current schema for `users`, `oauth2_clients`, `oauth2_authorization_codes`, `oauth2_access_tokens`, `oauth2_refresh_tokens`, `deleted_accounts`, `webauthn_credentials` |
| `database/migrations/000001_baseline.down.sql` | Baseline rollback |

> The historical step-by-step migrations (`000002`–`000012`, including OAuth2 schema, 2FA, profile keys, WebAuthn, email 2FA, recovery key, and the Minecraft-logic removal) were squashed into the single baseline above on 2026-10-14 (`b8a745c`). Minecraft-specific tables no longer belong to the core schema; they live in HRPAuth-Yggdrasil-API.

## HRPAuth-Yggdrasil-API Migrations

The Yggdrasil-API service maintains its own database schema.

| Path | Purpose |
|------|---------|
| `database/migrations/000001_init.up.sql` | Initial schema for accounts, profiles, tokens, etc. |

## Command Usage

All commands are executed from the repository root and reuse the `database.*` configuration in `config.yaml`.

```bash
go run ./cmd/migrate version
go run ./cmd/migrate status
go run ./cmd/migrate up
go run ./cmd/migrate up 1
go run ./cmd/migrate down
go run ./cmd/migrate down 1
go run ./cmd/migrate force 1
```

### Command Descriptions

| Command | Meaning |
|---------|---------|
| `version` / `status` | View current migration version and dirty state |
| `up` | Execute all unapplied migrations |
| `up N` | Execute only `N` steps forward |
| `down` | Rollback 1 step by default |
| `down N` | Rollback `N` steps |
| `force VERSION` | Forcefully mark the database version as VERSION without executing SQL |

## Baseline Explanation

`000001_baseline` is a snapshot of the core schema. For the new Yggdrasil-API service, `000001_init` serves as the baseline.

## Empty Database Initialization

Applicable for a brand new database.

1. Prepare `config.yaml` and ensure `database.*` points to the target database.
2. Execute in the repository root:

```bash
go run ./cmd/migrate up
```

3. Verify the version:

```bash
go run ./cmd/migrate status
```

## Runtime Constraints

- The application startup is not responsible for modifying tables; database initialization only establishes a connection.
- All schema changes must be landed via `database/migrations/`.
- When modifying GORM models, the need for a new migration must be evaluated simultaneously.
