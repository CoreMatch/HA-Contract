# Knowledge Base

## What This Is

The knowledge base and the contracts have different jobs. **A contract describes a
project's own outward behavior**, so that external developers can build their own
projects against it. **The knowledge base is this project's memo to itself**: it
serves self-hosting and maintenance of this project, and it is not meant to make
external projects accommodate this one. It may therefore record implementation
orientation, boundaries, and why things are designed the way they are — but it never
defines outward behavior.

## Order of Authority

For outward behavior, **the contracts in this repository are authoritative** (OpenAPI
specs in `docs/api/openapi/` and the contract documents under `docs/`). The knowledge
base only explains internal workings and design rationale. If an entry here ever
appears to contradict a contract, the contract wins and the entry is stale — fix the
entry, never the contract, and surface the conflict to the owner.

## Format

Each entry is one page in ADR style:

- **Status** (`accepted` / `superseded` / ...)
- **Context** — the problem and constraints
- **Decision** — what was chosen
- **Consequences** — including costs and limitations
- **Evidence** — `file:line`, protocol entries, commit hashes. Every piece of
  evidence must have been actually checked; anything that could not be verified is
  marked "not verified". Do not fabricate.

## Entries

| # | Title | Status |
|---|-------|--------|
| [0001](0001-ai-behavior-runs-in-the-jvm-engine.md) | AI Behavior Runs Entirely in the JVM Engine | accepted |
| [0002](0002-game-engine-as-external-dependency.md) | The Game Engine Is an External Dependency | accepted |
| [0003](0003-single-room-model.md) | Single-Room Model (RoomID = ServerID) | accepted |
| [0004](0004-simulation-state-ownership.md) | Simulation State Ownership | accepted |
| [0005](0005-anchor-convention-and-drift-check-script.md) | Knowledge Anchor Convention and the Drift-Check Script | accepted |
