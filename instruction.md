# HA-Contract Usage Instruction

This repository serves as the **Single Source of Truth** for the HA ecosystem's API standards, data models, and development protocols. All sub-projects must align their implementations with the definitions found here.

## General Principles

1.  **Contract-First Development**: Before implementing any API change, the corresponding OpenAPI specification in `docs/api/openapi/` must be updated and reviewed.
2.  **English-Only**: All documentation, including comments in YAML files and markdown guides, must be written in English.
3.  **Error Consistency**: Use the codes defined in [error-codes.md](file:///home/lnb/Desktop/HA/HA-Contract/docs/api/error-codes.md) for all API responses.

## How Each Project Uses This Repo

### 1. HRPAuth (Authentication Server)
*   **OAuth2 Provider**: Responsible for issuing Bearer tokens via `/oauth/token`.
*   **API Implementation**: Must strictly follow [hrpauth-business.yaml](file:///home/lnb/Desktop/HA/HA-Contract/docs/api/openapi/hrpauth-business.yaml).
*   **Models**: Refer to [data-models.md](file:///home/lnb/Desktop/HA/HA-Contract/docs/dev/HRPAuth/data-models.md) for database schema requirements.

### 2. HASkinLib (Texture Service)
*   **OAuth2 Follow-up**: **REQUIRED**. All texture modification endpoints must now validate the Bearer Token from HRPAuth.
*   **Auth Integration**: Deprecate `remember_token` logic immediately. Refer to [tokens.md](file:///home/lnb/Desktop/HA/HA-Contract/docs/dev/HRPAuth/tokens.md) for token validation standards.

### 3. WinnerProxy (Identity Converter)
*   **OAuth2 Follow-up**: **REQUIRED**. Replace the legacy Manage Token (M.T.) in `POST /register` with OAuth2 `client_credentials`.
*   **Security**: Ensure all internal service requests include the appropriate Authorization header.

### 4. HASkinProxy (Compatibility Layer)
*   **Protocol Mapping**: Refer to the [README.md](file:///home/lnb/Desktop/HA/HA-Contract/docs/dev/HASkinProxy/README.md) in the dev docs to understand how to map Yggdrasil profiles to CSL formats.

## Contributing to the Contract

1.  **Propose Changes**: Open a PR updating the relevant `.yaml` or `.md` files.
2.  **Update Roadmap**: If the change requires follow-up actions from other projects, add a new entry to the [roadmap.MD](file:///home/lnb/Desktop/HA/HA-Contract/roadmap.MD).
3.  **Validate**: Use scripts in `scripts/` (e.g., `check-business-api-drift.sh`) to ensure implementations haven't drifted from the contract.
