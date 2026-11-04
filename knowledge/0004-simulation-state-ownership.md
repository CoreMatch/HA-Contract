# ADR-0004: Simulation State Ownership

- **Status**: accepted
- **Date**: 2026-11-04

## Context

Two processes hold state about the same match: the JVM engine (inside the helper)
and the Go server. Without a clear ownership rule, both sides drift — the Go side
starts caching what the engine knows better, or the engine's results get re-derived
from Go-side bookkeeping.

## Decision

**The engine is authoritative for simulation state.** Units, positions, and the
progress/outcome of the battle exist only in the engine. The Go side keeps just
what the protocol and server behavior need, in three distinct roles:

1. **Mirrored from the wire** — extracted from packets in transit, never computed:
   the TEAM_LIST packet (ptype 115) is parsed on the forwarding path to backfill
   the connection's own `site` / `team` / `name` into the player relay.
2. **Registered from engine messages** — player profiles arrive via `player.join` /
   `player.leave` / `player.update` events; AI profiles arrive in the `room.addai`
   response (`id`/`name`/`team`/`position`). The room roster (`PlayerManage`)
   stores these registrations, including per-player bookkeeping such as
   `aiDifficulty`.
3. **Go-side bookkeeping** — fields the server itself owns: room lifecycle state
   (`IsStartGame`, `StartTime`/`EndTime`, maps, `ReplayFileName`, `Sync`,
   `MuteAll`), one-shot lifecycle flags (`ServerCacheFlag`: settlement announced,
   forced-close warned, one-player warned, all-AI state), and the settlement
   payload staged for the game-over event.

Live facts about the match are read from the engine on demand, not cached in Go:
`Running()` and `PlayerCount()` delegate to the simulation backend.

## Consequences

- Settlement is engine-produced end to end: the check thread pulls `game.result`
  (the upstream `getGameOverData()` shape: `gameTime`, `allPlayerList`,
  `winPlayerList`, `mapName`, per-player six-stat `playerData`, `replayName`),
  stages it on the room, and broadcasts the winners (`survive.player`). When the
  engine reports no outcome yet, Go skips the broadcast — it never invents results.
- Anything that needs real-time simulation detail (unit positions, battle progress)
  must come from engine packets or operations; adding Go-side caches of such state
  violates this rule and needs an explicit decision.
- The one-shot flags are Go's own invention surface: they must be reset per match
  (they are, in the room's data cleanup), and flags whose upstream writer lives in
  the TEAM_LIST rewrite path (the all-AI flag) stay inert until that writer is
  ported.

## Evidence

All paths relative to the RW-HPS Go-Server repository (checked at commit
`b0fbccfa`), unless noted.

- Engine authority and live reads: `internal/game/seam.go:43-52` (`Simulation`
  interface — Start/Stop/Running/PlayerCount belong to the backend), `:305-308`
  (`GameSession.PlayerCount`/`Running` delegate to the simulation).
- TEAM_LIST mirroring: `internal/io/packettype/packettype.go:36` (`TEAM_LIST = 115`);
  `internal/net/netconnectprotocol/realize/gameversionrelay.go:917-941` (extraction
  on the forwarding path, `TEAM_LIST` case at `:923`);
  `internal/net/netconnectprotocol/universalanalysis.go:70-156`
  (`GetPacketTeamData` backfills site/team/name; note the upstream setter quirk
  where `team` ends up equal to `site`).
- Registration: `Go-Server/docs/HELPER-PROTOCOL.md:93-114` (player events and
  `PlayerProfile` shape), `:214-230` (AI profile in the `room.addai` response);
  `internal/game/seam.go:127-142` (`AIProfile`); roster registration chain
  `internal/game/manage/playermanage.go:55-72`, `internal/game/room/serverroom.go:121-132`.
- Go-side bookkeeping: `internal/game/seam.go:179-209` (`GameSession` fields),
  `internal/data/temp/servercacheflag.go:13-27` (one-shot flags incl. `ai`),
  `internal/game/player/player.go:169-170` (`SetAiDifficulty`).
- Settlement flow: `internal/game/manage/callmanage.go:182-203` (`game.result` →
  `SetGameOverData` → `survive.player` broadcast; no outcome → skip),
  `internal/game/external/protocol.go:242` (`GameResult` payload); result field
  shapes in `HELPER-PROTOCOL.md:232-262`.
