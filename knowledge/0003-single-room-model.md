# ADR-0003: Single-Room Model (RoomID = ServerID)

- **Status**: accepted
- **Date**: 2026-11-04

## Context

Upstream hangs room objects off the game module's class loader
(`HeadlessModuleManage.hessLoaderMap`), one `ServerRoom` per game module instance.
Go has no class-loader dimension, so the port had to choose how rooms are held.
Meanwhile the Cascade proxy — which this backend can serve — assumes backends own
**multiple coded rooms**: it routes requests by room code, keeps room snapshots,
and exposes a multi-room CRUD facade (`/rooms`, `/rooms/{code}`, `.../settings`,
`.../kick`, `.../ban`, `.../players`).

## Decision

The Go server keeps a **single room** (decision record D-5, `accepted`, re-affirmed
by the author on 2026-11-04):

- One `ServerRoom` is created at boot and stored in a package-level singleton slot
  (`room.SetDefault` / `room.Default()`); connections take the current room at
  construction time, mirroring the upstream access path with minimal change.
- The room's ID is the configured server ID: `RoomID = ConfigServer.ServerID`.
  There are no room codes and no room registry.
- Cascade integration accepts the mismatch instead of restructuring: the gateway
  maps the contract's room facade onto the singleton room (decision records
  D-17–D-21, option B), and the single-room constraint is not hidden from the
  contract side.

## Consequences

- **Why multi-room is not done now**: it is the most expensive structural change in
  the Cascade alignment. Revisiting D-5 would ripple through the whole chain —
  `room.Default()` access points, connection routing, the per-second check thread,
  and settlement broadcasting — plus require a room registry with code allocation
  and ownership snapshots to match what Cascade's directory expects.
- **Where the cost would land**: replacing the singleton slot with a registry,
  giving each room its own backend/helper routing, and teaching the connection
  layer to resolve a room per request instead of taking the default.
- Cascade routes by room code today: exact room-code ownership from backend
  snapshots first, then longest matching room prefix, then the default backend.
  A single-room backend registers under the default/prefix path and works, but
  cannot host independently addressable rooms.
- The contract's room facade reads as multi-room CRUD while this backend answers
  from one room; that tension is deliberate and tracked (see Evidence), not an
  oversight to fix silently.

## Evidence

- Singleton wiring (RW-HPS Go-Server, checked at commit `b0fbccfa`):
  `internal/app/bootstrap.go:72` (`room.NewServerRoom(game.NewGameSession(
  global.ConfigServer.ServerID, game.Backend))` — RoomID = ServerID), `:75`
  (`room.SetDefault`); `internal/game/room/serverroom.go:407` (`SetDefault`),
  `:414` (`Default`).
- Decision record D-5 (author decision log `RW-HPS-GO-DECISIONS.md`, entry D-5,
  `accepted`, author re-check 2026-11-04): singleton slot chosen over dependency
  injection; "若将来要支持一个 Go 进程多个独立房间，槽位要换成注册表" (multi-room
  would replace the slot with a registry).
- Cascade routing (Cascade repository, checked locally):
  `internal/backend/directory.go:220-258` (`RouteRoom`: snapshot room-code
  ownership → longest prefix → default backend), `:78-96` (`validatePrefixes`,
  overlapping prefixes rejected).
- Contract room facade: HA-Contract `docs/api/openapi/cascade-backend-v1.yaml`,
  paths `/rooms` and `/rooms/{code}...` (v1.1.1).
- Cost analysis: Cascade/Go alignment research notes (`CASCADE-GO-RESEARCH.md`):
  single-room vs multi-room listed as the largest structural gap (line 104);
  multi-room work "推翻 D-5 单例房间，波及 room.Default()、连接路由、检查线程、
  结算播报一整条链" — the most expensive alignment item (line 122); the chosen
  option B deliberately does not touch D-5 (line 135).
