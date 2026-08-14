# HA Business API Standard

This is the single source of truth for the HA Business API, and it also records the internal implementation logic of this project for external protocols.

## Documentation Positioning

- **This Directory (`docs/api/`, `docs/dev/`)**: Shows **how this project internally implements** these APIs (including route mapping, internal processing logic, and business extensions).
- **Reference Directory ([`docs/references/`](../references/))**: Shows the **protocol standards themselves**. This project must comply with these standards.

## External Protocol Compliance (Implementation Layer)

This project implements the following external standards. For detailed protocol definitions, please refer to [docs/references/](../references/).

1. **Yggdrasil API / authlib-injector**: Implementation of the official Minecraft authentication protocol and its injector compatibility layer.
2. **CustomSkinAPI**: Implementation of the skin library standard interface.
3. **HASkinProxy (Protocol Translation)**: A dedicated service that bridges Yggdrasil API to CustomSkinAPI for CSL-compatible clients.

## Unified Constraints

1. OpenAPI is the source for paths and response structures.
2. Error codes use stable `lower_snake_case`.
3. Business errors return a unified format:

```json
{
  "success": false,
  "message": "Invalid email",
  "code": "invalid_email",
  "error": "invalid_email",
  "meta": {
    "request_id": "ab12cd34"
  }
}
```

Explanation:

- `code` is the standard field.
- `error` is a compatible alias, making it easier to maintain existing callers.
- `request_id` is used for troubleshooting logs and user feedback.

4. Business success responses return a unified format:

```json
{
  "success": true,
  "message": "Login successful",
  "data": {
    "token": "..."
  },
  "meta": {
    "request_id": "ab12cd34"
  }
}
```

During the transition period, some success fields will be mirrored at the top level to avoid immediate failure of old frontends; new callers should always read from `data`.

## File Descriptions

- `openapi/hrpauth-business.yaml`: HRPAuth Business API specification
- `openapi/haskinlib-business.yaml`: HASkinLib Business API specification
- `error-codes.md`: Unified error code registry

## Anti-Drift

Run before submission:

```bash
./scripts/check-business-api-drift.sh
```

It checks whether all business routes appear in the OpenAPI specification.
