# Database Migrations and Schema Sync

This document explains the current database schema management, migration commands, and standard processes for "empty database initialization" and "existing shared database management".

## Goals

- **Schema Source of Truth**: SQL migration
- **Migration Tool**: `golang-migrate`
- **Execution Entry Point**: `go run ./cmd/migrate ...`
- **Runtime Policy**: `AutoMigrate` is **no longer** executed during application startup.

## Current Directory

| Path | Purpose |
|------|---------|
| `cmd/migrate/main.go` | Migration command entry point |
| `database/migrations/000001_baseline.up.sql` | Merged baseline: Final Schema for 5 tables |
| `database/migrations/000001_baseline.down.sql` | Baseline rollback |
| `database/migrations/000002_oauth2.up.sql` | OAuth2 schema (clients, tokens, codes) |
| `database/migrations/000003_add_2fa_to_users.up.sql` | Add 2FA column to users table |

All historical incremental migrations (000002–000007) have been merged into `000001_baseline` and are no longer kept separately.

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

`000001_baseline` is a snapshot of the current final state of the database schema, containing the cumulative effects of all previous incremental migrations (000002–000007).

Includes 5 tables: `users`, `profiles`, `profile_properties`, `sessions`, `tokens`

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

Expected result:
- Version is 1
- `dirty: false`

## Existing Shared Database Management

Applicable for scenarios where "the database already exists and the structure is already aligned" (i.e., the only deployed database).

### Standard Process

1. **Back up the database first**.
2. Confirm that the existing database structure is consistent with `000001_baseline`.
3. Execute:

```bash
go run ./cmd/migrate force 1
```

4. Verify the status:

```bash
go run ./cmd/migrate status
```

Expected result:
- Version is 1
- `dirty: false`

### Why `force 1` first?

Because `000001_baseline` is a snapshot of the current schema, and data already exists in the tables. For databases where these tables already exist, the correct approach is not to re-execute the baseline, but to **align the version of the migration system with the completed baseline**.

## Runtime Constraints

- The application startup is not responsible for modifying tables; database initialization only establishes a connection.
- All schema changes must be landed via `database/migrations/`.
- When modifying GORM models, the need for a new migration must be evaluated simultaneously.
- Before performing schema sync on an existing shared database, the target database version and baseline alignment method must be confirmed.

## Process References

- `references/HA-ROADMAP.md` — Phase 1 Database Migration Design
- `docs/data-models.md` — Data Model Documentation
- `cmd/migrate/main_test.go` — Migration CLI Unit Tests
