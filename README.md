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

## Documentation Center (Single Source of Truth)

To prevent documentation drift from the actual project, this project adopts a unified API standard and documentation management mechanism:

### API Specification
- [API Standard Description](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/README.md): Contains unified response formats, pagination specifications, base paths, etc.
- [Error Code Definitions](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/error-codes.md): Globally unified error code registry.

### Interface Definitions (OpenAPI)
- [HRPAuth Business API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/hrpauth-business.yaml)
- [HRPAuth Yggdrasil Business API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/hrpauth-yggdrasil-business.yaml)
- [HASkinLib Business API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/haskinlib-business.yaml)
- [MatchCoreArena Business API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/matchcorearena-business.yaml)
- [WinnerProxy Business API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/winnerproxy-business.yaml)
- [Cascade Proxy API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/cascade-proxy.yaml): management surface of the Cascade proxy
- [Cascade Backend API](https://github.com/CoreMatch/HA-Contract/blob/main/docs/api/openapi/cascade-backend-v1.yaml): control-plane contract between the Cascade proxy and a Rusted Warfare backend

### Development and Internal Documentation
- [HRPAuth Development Guide](https://github.com/CoreMatch/HA-Contract/tree/main/docs/dev/HRPAuth/): Data models, Token mechanisms, feature flags, microservice extension protocol, SDK package contract. (Runtime configuration and deployment live in the service repositories / Wiki.)
- [HASkinProxy Development Guide](https://github.com/CoreMatch/HA-Contract/tree/main/docs/dev/HASkinProxy/): Technical details on the Yggdrasil-to-CSL proxy.
- [WinnerProxy Service Contract](https://github.com/CoreMatch/HA-Contract/tree/main/docs/dev/WinnerProxy/): Inbound routes and current outbound calls.
- [Cascade Backend Contract](https://github.com/CoreMatch/HA-Contract/tree/main/docs/dev/Cascade/): Authoritative proxy↔backend contract (transport, preamble, session gating, control plane).

### External Reference Standards (Immutable)
- [External API Standards](https://github.com/CoreMatch/HA-Contract/tree/main/docs/references/): Contains external protocol standards such as CustomSkinAPI, Yggdrasil API (authlib-injector), etc.
- **Note**: Documents in this directory belong to external standards. This project is only responsible for compliance; **modifying their content is strictly prohibited**.

## Business API Drift Check (Method-Level)

Every repository that has an OpenAPI contract is wired into
[scripts/check-business-api-drift.sh](https://github.com/CoreMatch/HA-Contract/blob/main/scripts/check-business-api-drift.sh),
which compares each implementation's registered routes against its contract
at the **METHOD + path** level, in **both directions**:

- implementation has the route but the contract does not, and
- the contract declares a METHOD + path that no registered route serves.

| Implementation repository | Route source scanned | Contract file |
|---|---|---|
| HRPAuth | `main.go` | `docs/api/openapi/hrpauth-business.yaml` |
| HASkinLib | `main.go` | `docs/api/openapi/haskinlib-business.yaml` |
| HRPAuth-Yggdrasil-API | `main.go` | `docs/api/openapi/hrpauth-yggdrasil-business.yaml` |
| MatchCoreArena-Server | `api/router.go` | `docs/api/openapi/matchcorearena-business.yaml` |
| WinnerProxy | `internal/router/router.go` | `docs/api/openapi/winnerproxy-business.yaml` |
| Cascade (proxy) | `internal/api/proxy_http.go` | `docs/api/openapi/cascade-proxy.yaml` |

Run it from a checkout of this repository:

```bash
./scripts/check-business-api-drift.sh
```

It prints `Business API drift check passed.` and exits 0 when every pair
agrees. Implementation repositories are resolved through the environment
variables `HRPAUTH_REPO_DIR`, `HASKINLIB_REPO_DIR`, `YGGDRASIL_REPO_DIR`,
`MATCHCOREARENA_REPO_DIR`, `WINNERPROXY_REPO_DIR`, `CASCADE_REPO_DIR`,
falling back to sibling directories of this repository and then to
`~/Desktop/HA` (`~/Cascade` for Cascade). A missing repository or contract
file is a hard error (exit 2), never a silent pass.

When a new repository gains an OpenAPI contract, add it to the script:
extract its routes from the single file that registers them, add a
`check_set` pair against its yaml, and list any deliberate exclusions
(protocol aliases, tombstoned endpoints) in the script's inline exclusion
blocks so they stay visible.

## Knowledge Anchors (Drift Check)

The ADR-style knowledge bases cite code with stable anchors (symbol / field /
line — see [knowledge/0005](knowledge/0005-anchor-convention-and-drift-check-script.md)).
[scripts/check-knowledge-anchors.sh](scripts/check-knowledge-anchors.sh)
verifies every anchor mechanically, and CI enforces it on every push/PR via
[.github/workflows/knowledge-anchors.yml](.github/workflows/knowledge-anchors.yml)
(checker self-test + this repository's own anchors; the cross-repo batch is
excluded because it needs the sibling checkouts). Local equivalents:

```bash
bash scripts/check-knowledge-anchors.sh --self-test
bash scripts/check-knowledge-anchors.sh
```

In a full workspace checkout,
[scripts/check-all-knowledge-anchors.sh](scripts/check-all-knowledge-anchors.sh)
checks every repository's knowledge base in one pass.

## Archive Note

Old and drifted documents have been moved to the [archive/docs/](https://github.com/CoreMatch/HA-Contract/tree/main/archive/docs/) directory and are no longer used as development references.

## Documentation Convention

**All documentation in this project must be written in English.** This applies to both existing and future documents.
