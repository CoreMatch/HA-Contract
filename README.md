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
- [MatchCoreArena-Server](https://github.com/CoreMatch/MatchCoreArena-Server): Match arena server
- [HA-WebUI-SDKHandler](https://github.com/CoreMatch/HA-WebUI-SDKHandler): Compile-time SDK aggregation build service
- [HA-Services-Deployer](https://github.com/CoreMatch/HA-Services-Deployer): Release distribution and deployment service (also hosts the orchestration template)
- [HA-Services-MaintenanceView](https://github.com/CoreMatch/HA-Services-MaintenanceView): Maintenance console for the deployed services
- [BS2HA](https://github.com/CoreMatch/BS2HA): Blessing-Skin-Server to HRPAuth database migration tool

## Container Orchestration

Every backend service of the platform is containerized. Each service repository
ships a multi-stage `Dockerfile` (Go builder stage, `alpine:3.22` runtime stage,
non-root user), and a single Compose template orchestrates the whole set.

- Template: [`CoreMatch/HA-Services-Deployer/deploy/docker-compose.yml`](https://github.com/CoreMatch/HA-Services-Deployer/blob/main/deploy/docker-compose.yml)
- Configuration templates: [`CoreMatch/HA-Services-Deployer/deploy/config/`](https://github.com/CoreMatch/HA-Services-Deployer/tree/main/deploy/config)
- Environment template: [`CoreMatch/HA-Services-Deployer/deploy/.env.example`](https://github.com/CoreMatch/HA-Services-Deployer/blob/main/deploy/.env.example)
- Detailed contract: [Container Orchestration](https://github.com/CoreMatch/HA-Contract/blob/main/docs/dev/HA-Services-Deployer/container-orchestration.md)

| Service | Image | Container ports |
|---|---|---|
| HRPAuth | `ha/hrpauth` | 2778 |
| HRPAuth-Yggdrasil-API | `ha/hrpauth-yggdrasil-api` | 2770 |
| HASkinLib | `ha/haskinlib` | 2701 |
| HASkinProxy | `ha/haskinproxy` | 2702 |
| WinnerProxy | `ha/winnerproxy` | 2777 |
| MatchCoreArena-Server | `ha/mca-server` | 9178 |
| HA-WebUI-SDKHandler | `ha/ha-webui-sdkhandler` | 2704, 2705 |
| HA-Services-Deployer | `ha/ha-services-deployer` | 18080 |
| HA-Services-MaintenanceView | `ha/ha-services-maintenance-view` | 18081 |

Deployment model:

- Images are built locally from each service repository; tags follow `ha/<service>:<version>`.
- MySQL and Redis are **not** started by the stack; they are addressed through `DB_*` and `REDIS_*` environment variables.
- Each service reads a YAML configuration file. The image entrypoint renders it from an `envsubst` template at startup, so deployment-scoped values (database host, upstream URLs, secrets) are supplied by the environment.
- Inter-service calls use the Compose service names, for example `http://hrpauth:2778` and `http://ha-services-deployer:18080`.

```bash
cd HA-Services-Deployer/deploy
cp .env.example .env   # then fill in database, redis, OAuth and SMTP values
docker compose up -d --build
```

The build contexts of the Compose template point at the sibling service
repositories, so the services must be checked out next to the deployer
repository before the stack can be built. `BS2HA` is containerized as well, but
it is a one-shot migration CLI and is not part of the running stack.

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
