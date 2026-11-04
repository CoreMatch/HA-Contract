# HA-Contract

This project is the core contract and service collection of the [CoreMatch](https://github.com/CoreMatch) HA system, including authentication services, skin library services, and proxy services.

## Project Structure

- [HRPAuth](https://github.com/CoreMatch/HRPAuth): Core authentication service (Generic Auth)
- [HRPAuth-Yggdrasil-API](https://github.com/CoreMatch/HRPAuth-Yggdrasil-API): Yggdrasil API provider and game account management (Minecraft-specific)
- [HASkinLib](https://github.com/CoreMatch/HASkinLib): Skin and texture library service
- [WinnerProxy](https://github.com/CoreMatch/WinnerProxy): Proxy service
- [HASkinProxy](https://github.com/CoreMatch/HASkinProxy): Yggdrasil-to-CSL compatibility proxy
- [Cascade](https://github.com/CoreMatch/Cascade): Rusted Warfare edge proxy (backend contract lives in this repository)
- [HRPAuth-WebUI](https://github.com/CoreMatch/HRPAuth-WebUI): Frontend interface for the authentication service

## Container Orchestration (Platform-wide)

Every Go service listed above ships a multi-stage `Dockerfile` (static Go build on
`golang:<go.mod version>-alpine`, Alpine runtime, non-root user). The platform as
a whole is orchestrated by a single Compose template that lives in the deployer
repository, not in this one:

- Compose template: [`CoreMatch/HA-Services-Deployer` → `deploy/docker-compose.yml`](https://github.com/CoreMatch/HA-Services-Deployer/blob/main/deploy/docker-compose.yml)
- Per-service config templates: `deploy/config/*.yaml.tmpl`, rendered at container
  start with `envsubst`
- Deployment-scoped values (MySQL/Redis addresses, upstream URLs, secrets):
  `deploy/.env`, see `deploy/.env.example`

| Image | Repository | Container port |
|---|---|---|
| `ha/hrpauth` | [HRPAuth](https://github.com/CoreMatch/HRPAuth) | 2778 |
| `ha/hrpauth-yggdrasil-api` | [HRPAuth-Yggdrasil-API](https://github.com/CoreMatch/HRPAuth-Yggdrasil-API) | 2770 |
| `ha/haskinlib` | [HASkinLib](https://github.com/CoreMatch/HASkinLib) | 2701 |
| `ha/haskinproxy` | [HASkinProxy](https://github.com/CoreMatch/HASkinProxy) | 2702 |
| `ha/winnerproxy` | [WinnerProxy](https://github.com/CoreMatch/WinnerProxy) | 2777 |
| `ha/ha-webui-sdkhandler` | [HA-WebUI-SDKHandler](https://github.com/CoreMatch/HA-WebUI-SDKHandler) | 2704, 2705 |
| `ha/ha-services-deployer` | [HA-Services-Deployer](https://github.com/CoreMatch/HA-Services-Deployer) | 18080 |

MySQL and Redis are **not** started by the template: every service reads them
from the `DB_*` / `REDIS_*` environment variables, which point at externally
managed instances. Service-to-service calls use Compose service names
(`http://hrpauth:2778`, `http://ha-services-deployer:18080`, …).

Configuration loading differs per service (this is the deployment contract, not
an API contract): HRPAuth, HRPAuth-Yggdrasil-API, HASkinLib, HASkinProxy and
HA-WebUI-SDKHandler read `config.yaml`, WinnerProxy reads `config.yml`, and
MatchCoreArena-Server reads `config/config.yaml` via `CONFIG_PATH`. The Compose
template renders each of them to the path its service expects.

Frontend, desktop (Wails) and Java plugin repositories are not part of the
container template.

## Documentation Center (Single Source of Truth)

To prevent documentation drift from the actual project, this project adopts a unified API standard and documentation management mechanism:

### API Specification
- [API Standard Description](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/README.md): Contains unified response formats, pagination specifications, base paths, etc.
- [Error Code Definitions](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/error-codes.md): Globally unified error code registry.

### Interface Definitions (OpenAPI)
- [HRPAuth Business API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/hrpauth-business.yaml)
- [HRPAuth Yggdrasil Business API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/hrpauth-yggdrasil-business.yaml)
- [HASkinLib Business API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/haskinlib-business.yaml)
- [Cascade Backend API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/cascade-backend-v1.yaml): control-plane contract between the Cascade proxy and a Rusted Warfare backend

### Development and Internal Documentation
- [HRPAuth Development Guide](https://github.com/CoreMatch/HA-Contract/tree/main/docs/dev/HRPAuth/): Includes configuration, data models, migrations, Token mechanisms, etc.
- [HASkinProxy Development Guide](https://github.com/CoreMatch/HA-Contract/tree/main/docs/dev/HASkinProxy/): Technical details on the Yggdrasil-to-CSL proxy.
- [WinnerProxy Service Contract](https://github.com/CoreMatch/HA-Contract/tree/main/docs/dev/WinnerProxy/): Inbound routes and current outbound calls.
- [Cascade Backend Contract](https://github.com/CoreMatch/HA-Contract/tree/main/docs/dev/Cascade/): Authoritative proxy↔backend contract (transport, preamble, session gating, control plane).

### External Reference Standards (Immutable)
- [External API Standards](https://github.com/CoreMatch/HA-Contract/tree/main/docs/references/): Contains external protocol standards such as CustomSkinAPI, Yggdrasil API (authlib-injector), etc.
- **Note**: Documents in this directory belong to external standards. This project is only responsible for compliance; **modifying their content is strictly prohibited**.

## Archive Note

Old and drifted documents have been moved to the [archive/docs/](https://github.com/CoreMatch/HA-Contract/tree/main/archive/docs/) directory and are no longer used as development references.

## Documentation Convention

**All documentation in this project must be written in English.** This applies to both existing and future documents.
