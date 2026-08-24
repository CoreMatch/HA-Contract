# HA-Contract Roadmap

This document outlines the current active migrations and future planned changes for the HA ecosystem.

## Active Migration: OAuth2 Upgrade

The ecosystem is currently transitioning from legacy `remember_token` authentication to a standardized **OAuth2 (RFC 6749)** framework.

| Project | Role in Migration | Follow-up Status | Action Required |
| :--- | :--- | :--- | :--- |
| **HRPAuth** | Provider | **Completed** | Core OAuth2 flow and endpoints are implemented. |
| **HASkinLib** | Client/Consumer | **Pending** | Must replace `remember_token` with Bearer Token validation. |
| **WinnerProxy** | Client/Admin | **Completed** | Migrated from M.T. (Manage Token) to OAuth2 `client_credentials`. |
| **HASkinProxy** | Consumer | **Stable** | Minimal impact; continue using Yggdrasil for profile conversion. |

---

## Planned Changes & Follow-up Actions

### Phase 1: Database Architecture Refactoring
*   **Description**: Restructuring the core database schema to improve cross-service data consistency.
*   **Projects to Follow-up**:
    *   **HRPAuth**: Update GORM models and repository layers.
    *   **HASkinLib**: Update user-related foreign key constraints.
*   **Status**: In Progress (Secondary to OAuth2)

### Phase 4: Bot User Cleanup Mechanism
*   **Description**: Implementation of `BotUserCleanupController` to automatically remove inactive accounts.
*   **Status**: On Hold (Pending OAuth2 completion)

---

## Completed Changes Table

| Project | Change Description | Completion Date | Documentation Reference |
| :--- | :--- | :--- | :--- |
| **All** | Documentation Centralization | 2026-08-23 | [API README](file:///home/lnb/Desktop/HA/HA-Contract/docs/api/README.md) |
| **All** | English-Only Documentation Policy | 2026-08-23 | N/A |
| **HRPAuth** | Core OAuth2 Implementation | 2026-08-23 | [hrpauth-business.yaml](file:///home/lnb/Desktop/HA/HA-Contract/docs/api/openapi/hrpauth-business.yaml) |
| **WinnerProxy** | OAuth2 client_credentials Migration | 2026-08-23 | N/A |
