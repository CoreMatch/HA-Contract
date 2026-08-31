# HA-Contract Roadmap

This document outlines the current active migrations and future planned changes for the HA ecosystem.

## Active Migration: OAuth2 Upgrade

The ecosystem is currently transitioning from legacy `remember_token` authentication to a standardized **OAuth2 (RFC 6749)** framework.

| Project         | Role in Migration | Follow-up Status | Action Required                                                   |
| :-------------- | :---------------- | :--------------- | :---------------------------------------------------------------- |
| **HRPAuth**     | Provider          | **Completed**    | Core OAuth2 flow and endpoints are implemented.                   |
| **HASkinLib**   | Client/Consumer   | **Completed**    | Must replace `remember_token` with Bearer Token validation.       |
| **WinnerProxy** | Client/Admin      | **Completed**    | Migrated from M.T. (Manage Token) to OAuth2 `client_credentials`. |
| **HASkinProxy** | Consumer          | **Stable**       | Minimal impact; continue using Yggdrasil for profile conversion.  |

***

## Planned Changes & Follow-up Actions

### Phase 1: Database Architecture Refactoring

- **Description**: Restructuring the core database schema to improve cross-service data consistency.
- **Projects to Follow-up**:
  - **HRPAuth**: Update GORM models and repository layers.
  - **HASkinLib**: Update user-related foreign key constraints.
- **Status**: In Progress (Secondary to OAuth2)

### Phase 4: Bot User Cleanup Mechanism

- **Description**: Implementation of `BotUserCleanupController` to automatically remove inactive accounts.
- **Status**: On Hold (Pending OAuth2 completion)

### Phase 5: BlessingSkin to HRPAuth Migration

- **Description**: Add an offline BS2HA migration path that converts BlessingSkin SQL dumps into HRPAuth import SQL, copies texture assets, and emits a migration report.
- **Required Contract Follow-up**:
  - **HRPAuth**: Optionally detect the fixed marker `BS2HA$RESET_REQUIRED` and guide imported non-bcrypt users into password reset.
  - **BS2HA**: Implement dump parsing, SQL-based password-method inspection, narrowed profile selection, placeholder profile creation, texture property signing, and deterministic SQL/report output.
- **Status**: Planned

### Phase 6: Microservice Extension Layer

- **Description**: Add an edge orchestration layer to HRPAuth that routes frontend requests to registered microservices **before** and **after** the main service flow. The main service flow strictly follows external standards and is not extended; extensions only cover pre-flow and post-flow routing.
- **HRPAuth Implemented**:
  - Service registration and heartbeat (`POST /services/presence`, self-declared TTL or never-expiring).
  - Frontend service discovery (`GET /services/list`) and SDK relaying (`GET /services/sdk/:name`).
  - Route rules (`POST /services/route`) for pre/post orchestration.
  - Relay rules (`POST/DELETE/GET /services/relay`) for URL forwarding.
  - Three-level auth (`0` none / `1` user / `2` ops) with dynamic strictest-level enforcement for multi-service requests.
- **Documentation**: [microservices.md](docs/dev/HRPAuth/microservices.md)
- **Status**: In Progress

***

## Completed Changes Table

| Project         | Change Description                   | Completion Date | Documentation Reference                                                                                 |
| :-------------- | :----------------------------------- | :-------------- | :------------------------------------------------------------------------------------------------------ |
| **All**         | Documentation Centralization         | 2026-08-23      | [API README](file:///home/lnb/Desktop/HA/HA-Contract/docs/api/README.md)                                |
| **All**         | English-Only Documentation Policy    | 2026-08-23      | N/A                                                                                                     |
| **HRPAuth**     | Core OAuth2 Implementation           | 2026-08-23      | [hrpauth-business.yaml](file:///home/lnb/Desktop/HA/HA-Contract/docs/api/openapi/hrpauth-business.yaml) |
| **WinnerProxy** | OAuth2 client\_credentials Migration | 2026-08-23      | N/A                                                                                                     |
