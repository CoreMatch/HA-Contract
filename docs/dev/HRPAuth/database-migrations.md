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
| `database/migrations/000001_baseline.up.sql` | Merged baseline: Final Schema for 5 tables |
| `database/migrations/000001_baseline.down.sql` | Baseline rollback |
| `database/migrations/000002_oauth2.up.sql` | OAuth2 schema (clients, tokens, codes) |
| `database/migrations/000003_add_2fa_to_users.up.sql` | Add 2FA column to users table |
| `database/migrations/000004_profile_keys.up.sql` | Profile keys table (Minecraft 1.19+ chat-signing) |
| `database/migrations/000005_add_delete_when_to_profile_properties.up.sql` | Add delete_when to profile_properties |
| `database/migrations/000006_drop_remember_token.up.sql` | Drop remember_token from users |
| `database/migrations/000007_add_deleted_at_to_users.up.sql` | Add deleted_at to users |
| `database/migrations/000008_create_deleted_accounts_table.up.sql` | Create deleted_accounts table |
| `database/migrations/000009_add_webauthn_support.up.sql` | Add WebAuthn support |
| `database/migrations/000010_add_email_2fa_support.up.sql` | Add Email 2FA support |
| `database/migrations/000011_add_recovery_key_support.up.sql` | Add Recovery Key support |
| `database/migrations/000012_remove_minecraft_logic.up.sql` | Decouple: Remove Minecraft-specific tables and fields |

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
