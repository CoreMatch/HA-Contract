# HA-Contract

This project is the core contract and service collection of the [CoreMatch](https://github.com/CoreMatch) HA system, including authentication services, skin library services, and proxy services.

## Project Structure

- [HRPAuth](https://github.com/CoreMatch/HRPAuth): Authentication service (Business API + Yggdrasil compatible)
- [HASkinLib](https://github.com/CoreMatch/HASkinLib): Skin library service
- [WinnerProxy](https://github.com/CoreMatch/WinnerProxy): Proxy service
- [HASkinProxy](https://github.com/CoreMatch/HASkinProxy): Yggdrasil-to-CSL compatibility proxy
- [HRPAuth-WebUI](https://github.com/CoreMatch/HRPAuth-WebUI): Frontend interface for the authentication service

## Documentation Center (Single Source of Truth)

To prevent documentation drift from the actual project, this project adopts a unified API standard and documentation management mechanism:

### API Specification
- [API Standard Description](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/README.md): Contains unified response formats, pagination specifications, base paths, etc.
- [Error Code Definitions](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/error-codes.md): Globally unified error code registry.

### Interface Definitions (OpenAPI)
- [HRPAuth Business API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/hrpauth-business.yaml)
- [HASkinLib Business API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/haskinlib-business.yaml)

### Development and Internal Documentation
- [HRPAuth Development Guide](https://github.com/CoreMatch/HA-Contract/tree/main/docs/dev/HRPAuth/): Includes configuration, data models, migrations, Token mechanisms, etc.
- [HASkinProxy Development Guide](https://github.com/CoreMatch/HA-Contract/tree/main/docs/dev/HASkinProxy/): Technical details on the Yggdrasil-to-CSL proxy.

### External Reference Standards (Immutable)
- [External API Standards](https://github.com/CoreMatch/HA-Contract/tree/main/docs/references/): Contains external protocol standards such as CustomSkinAPI, Yggdrasil API (authlib-injector), etc.
- **Note**: Documents in this directory belong to external standards. This project is only responsible for compliance; **modifying their content is strictly prohibited**.

## Archive Note

Old and drifted documents have been moved to the [archive/docs/](https://github.com/CoreMatch/HA-Contract/tree/main/archive/docs/) directory and are no longer used as development references.

## Documentation Convention

**All documentation in this project must be written in English.** This applies to both existing and future documents.
