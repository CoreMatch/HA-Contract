# Container Orchestration

## Purpose

Every backend service of the HA platform ships a multi-stage `Dockerfile`, and
a single Compose template orchestrates the whole set. This document describes
that template: where it lives, how images are built, how configuration is
injected, and which external dependencies the platform expects.

The orchestration template is **not** stored in this repository. It lives in the
deployer repository, because that service already owns release distribution and
deployment concerns:

- Template: [`CoreMatch/HA-Services-Deployer/deploy/docker-compose.yml`](https://github.com/CoreMatch/HA-Services-Deployer/blob/main/deploy/docker-compose.yml)
- Configuration templates: [`CoreMatch/HA-Services-Deployer/deploy/config/`](https://github.com/CoreMatch/HA-Services-Deployer/tree/main/deploy/config)
- Environment template: [`CoreMatch/HA-Services-Deployer/deploy/.env.example`](https://github.com/CoreMatch/HA-Services-Deployer/blob/main/deploy/.env.example)

## Repository Layout

The Compose file sits in `deploy/` inside the deployer repository, and its
build contexts point at the **sibling repositories**:

```
HA-Services-Deployer/
├── Dockerfile                     # image of the deployer service itself
├── deploy/
│   ├── docker-compose.yml        # orchestration template
│   ├── .env.example              # every environment variable the template consumes
│   ├── config/*.yaml.tmpl        # per-service configuration templates
│   ├── secrets/                  # signature key pairs (git-ignored)
│   └── sdkhandler-template/      # optional frontend template mount (git-ignored)
├── ../HRPAuth/                   # sibling checkout, used as a build context
├── ../HRPAuth-Yggdrasil-API/
├── ../HASkinLib/
├── ../HASkinProxy/
├── ../WinnerProxy/
├── ../MatchCoreArena-Server/
├── ../HA-WebUI-SDKHandler/
└── ../HA-Services-MaintenanceView/
```

Because the build contexts are relative (`../HRPAuth` and friends), the services
must be checked out **next to** the deployer repository before the stack can be
built. A standalone clone of the deployer repository alone is enough to read the
contract, but not enough to run `docker compose build`.

## Services

| Compose service | Repository | Image | Container ports | Configuration template |
|---|---|---|---|---|
| `hrpauth` | [CoreMatch/HRPAuth](https://github.com/CoreMatch/HRPAuth) | `ha/hrpauth` | 2778 | `config/hrpauth.yaml.tmpl` |
| `hrpauth-yggdrasil-api` | [CoreMatch/HRPAuth-Yggdrasil-API](https://github.com/CoreMatch/HRPAuth-Yggdrasil-API) | `ha/hrpauth-yggdrasil-api` | 2770 | `config/hrpauth-yggdrasil-api.yaml.tmpl` |
| `haskinlib` | [CoreMatch/HASkinLib](https://github.com/CoreMatch/HASkinLib) | `ha/haskinlib` | 2701 | `config/haskinlib.yaml.tmpl` |
| `haskinproxy` | [CoreMatch/HASkinProxy](https://github.com/CoreMatch/HASkinProxy) | `ha/haskinproxy` | 2702 | `config/haskinproxy.yaml.tmpl` |
| `winnerproxy` | [CoreMatch/WinnerProxy](https://github.com/CoreMatch/WinnerProxy) | `ha/winnerproxy` | 2777 | `config/winnerproxy.yaml.tmpl` |
| `mca-server` | [CoreMatch/MatchCoreArena-Server](https://github.com/CoreMatch/MatchCoreArena-Server) | `ha/mca-server` | 9178 | `config/mca-server.yaml.tmpl` |
| `ha-webui-sdkhandler` | [CoreMatch/HA-WebUI-SDKHandler](https://github.com/CoreMatch/HA-WebUI-SDKHandler) | `ha/ha-webui-sdkhandler` | 2704, 2705 | `config/sdkhandler.yaml.tmpl` |
| `ha-services-deployer` | [CoreMatch/HA-Services-Deployer](https://github.com/CoreMatch/HA-Services-Deployer) | `ha/ha-services-deployer` | 18080 | `config/ha-services-deployer.yaml.tmpl` |
| `ha-services-maintenance-view` | [CoreMatch/HA-Services-MaintenanceView](https://github.com/CoreMatch/HA-Services-MaintenanceView) | `ha/ha-services-maintenance-view` | 18081 | `config/ha-services-maintenance-view.yaml.tmpl` |

Host ports are published through `${PORT}` variables and default to the values
above; every one of them can be overridden in `.env`.

`BS2HA` is also containerized, but it is a one-shot migration CLI rather than a
long-running service, so it is not part of the Compose stack. Run it on demand:

```bash
docker build -t ha/bs2ha ../BS2HA
docker run --rm -v "$PWD:/work" ha/bs2ha
```

## Image Build

Every service image is built locally from the multi-stage `Dockerfile` in its own
repository:

- Builder stage: `golang:<version>-alpine`, `CGO_ENABLED=0`, `go build -trimpath -ldflags="-s -w"`.
- Runtime stage: `alpine:3.22`, non-root user (uid 10001), `ca-certificates`, `tzdata`, and `gettext` (for `envsubst`).

Two services need extra build stages:

- `HA-Services-MaintenanceView` builds its React frontend in a `node:22-alpine` stage; the compiled `frontend/dist` is copied next to the binary because the server serves it from disk at runtime.
- `HA-WebUI-SDKHandler` compiles the frontend at **runtime**, so its runtime image ships `nodejs`, `npm` and `git`.

Images are tagged `ha/<service>:${VERSION}`, with `VERSION` defaulting to `latest`.

## Configuration Injection

The services read YAML configuration files, not environment variables. To let
the deployment supply environment-scoped values (database host, upstream URLs,
secrets), each service image ships an entrypoint that renders a template before
starting the binary:

```sh
envsubst < "${CONFIG_TEMPLATE}" > "${RENDERED_CONFIG}"
exec "$@"
```

The templates live in `deploy/config/*.yaml.tmpl` and use `${VAR}` placeholders.
Numeric values are deliberately left unquoted, because the services parse them
as integers rather than strings.

The rendered file location differs per service, because the services resolve
their configuration differently:

| Service | Configuration path | Mechanism |
|---|---|---|
| `HRPAuth`, `HASkinLib`, `HA-Services-Deployer`, `HA-Services-MaintenanceView` | `/app/config.yaml` | relative to the working directory |
| `HRPAuth-Yggdrasil-API`, `HASkinProxy` | `/app/config.yaml` | next to the executable |
| `WinnerProxy` | `/app/config.yml` | next to the executable (`config.yml`, not `config.yaml`) |
| `MatchCoreArena-Server` | `/app/config/config.yaml` | `CONFIG_PATH` environment variable |
| `HA-WebUI-SDKHandler` | `/app/config.yaml` | `SDKHANDLER_CONFIG` environment variable |

## External Dependencies

MySQL and Redis are **not** started by the Compose stack. They are expected to
exist already and are addressed through environment variables:

| Variable | Meaning |
|---|---|
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` | MySQL connection |
| `REDIS_HOST`, `REDIS_PORT`, `REDIS_PASSWORD`, `REDIS_DB` | Redis connection |

Note that the configuration schema of `HRPAuth`, `HASkinLib` and
`HRPAuth-Yggdrasil-API` has **no database port field**; those services always
connect to port 3306. Only `MatchCoreArena-Server` reads `DB_PORT`.

Service-to-service wiring uses the Compose service names:

| Variable | Resolves to |
|---|---|
| `HRPAUTH_URL` | `http://hrpauth:2778` |
| `HRPAUTH_YGG_URL` | `http://hrpauth-yggdrasil-api:2770/yggdrasil-api/` |
| `DEPLOYER_URL` | `http://ha-services-deployer:18080` |

## Secrets

| Secret | Location | Consumed by |
|---|---|---|
| `private_key.pem`, `public_key.pem` | `deploy/secrets/` (git-ignored) | `HRPAuth`, `HRPAuth-Yggdrasil-API` |
| `MANAGE_TOKEN` | `.env` | `HRPAuth` management API |
| `HRPAUTH_SUPER_CLIENT_SECRET`, `*_CLIENT_SECRET` | `.env` | OAuth2 client credentials of the satellite services |
| `SMTP_PASSWORD` | `.env` | `HRPAuth` mail delivery |

`deploy/secrets/` and `deploy/.env` are excluded from version control, and
`deploy/secrets` is excluded from the Docker build context, so private keys
never end up in an image layer.

## Running the Stack

```bash
cd HA-Services-Deployer/deploy
cp .env.example .env      # then edit database, redis, OAuth and SMTP values
docker compose up -d --build
docker compose ps
docker compose logs -f hrpauth
```

Stop and remove the stack with `docker compose down`. Named volumes
(`hrpauth-storage`, `ygg-storage`, `haskinlib-data`, `mca-data`, …) hold
uploads, textures and service state and survive `down`.

## Limitations

- The stack requires the sibling service repositories to be checked out next to
  the deployer repository; the build contexts are not downloadable artifacts.
- The template renders configuration from environment variables only. Fields
  that a service hardcodes in its own schema (for example the missing MySQL
  port mentioned above) cannot be overridden.
- `HA-WebUI-SDKHandler` performs a full frontend build on every poll cycle, so
  its container needs outbound network access to the template repository and the
  npm registry.
