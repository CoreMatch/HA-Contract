# Knowledge Base

As of 2026-11-07 this repository no longer hosts project knowledge bases:
each repository keeps its own ADR-style `knowledge/` directory (repatriation
from this repository, source: HA-Contract@bab2a05). This repository keeps
only API contracts (OpenAPI yaml + error codes), the drift/anchor check
scripts, and the anchor-convention entry below.

## Where the knowledge bases live now

| Repository | Knowledge directory |
|---|---|
| HRPAuth | `HRPAuth/knowledge/` (incl. `archive/` historical docs) |
| HRPAuth-Yggdrasil-API | `HRPAuth-Yggdrasil-API/knowledge/` |
| HASkinLib | `HASkinLib/knowledge/` (incl. `archive/`) |
| HASkinProxy | `HASkinProxy/knowledge/` |
| WinnerProxy | `WinnerProxy/knowledge/` (incl. `archive/`) |
| HA-Cupbearer | `HA-Cupbearer/knowledge/` |
| HA-Services-MaintenanceView | `HA-Services-MaintenanceView/knowledge/` |
| HA-WebUI-SDKHandler | `HA-WebUI-SDKHandler/knowledge/` |
| MatchCoreArena-Server | `MatchCoreArena-Server/knowledge/` |
| Avalon | `Avalon/knowledge/` (game-engine ADRs, migrated 2026-11-07) |
| (others) | any repository with a `knowledge/` directory |

`scripts/check-all-knowledge-anchors.sh` discovers every checkout with a
`knowledge/` directory automatically.

## Entries (this repository)

| # | Title | Status |
|---|-------|--------|
| [0005](0005-anchor-convention-and-drift-check-script.md) | Knowledge Anchor Convention and the Drift-Check Script | accepted |

0005 stays here because it documents the anchor convention and the check
scripts whose canonical location is this repository.
