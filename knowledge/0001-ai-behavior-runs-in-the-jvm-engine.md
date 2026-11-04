# ADR-0001: AI Behavior Runs Entirely in the JVM Engine

- **Status**: accepted
- **Date**: 2026-11-04

## Context

The Go server (RW-HPS Go-Server) re-hosts a game server whose original runs on the
JVM with the game engine in-process. AI players are part of the game: pathfinding,
decision-making, combat execution, and difficulty behavior all live inside the game
engine. A question that recurs during maintenance is where AI behavior is
implemented in the Go port, and whether any Go-side AI code can be removed.

## Decision

All AI behavior (pathfinding, decision-making, combat, difficulty execution) runs
inside the JVM game engine hosted by the helper process. The Go side never
implements AI behavior. Go contributes only three kinds of adaptation code:

1. **Command forwarding** — AI creation and engine-side operations are forwarded to
   the helper as v2-ext protocol operations: `room.addai`, `room.sync`,
   `room.removeplayer`, `game.result` (the four D-9 extensions; a fifth operation
   `room.settings` was added later for room settings and is not AI behavior).
2. **Profile registration** — the engine creates the AI; the created profile is
   returned in the `room.addai` response (`ai` field: PlayerProfile + `position`)
   and registered into the room roster on the Go side, wrapped as the `AiPlayer`
   marker type. The engine does not emit a `player.join` event for AIs, so the
   response is the only registration path.
3. **Room lifecycle** — the per-second check thread handles the all-AI situation:
   warn once (`aiWarn`), and once no human players remain, end the match after the
   `maxOnlyAIGameIngTime` countdown. Settlement data for AI-driven matches is
   fetched with `game.result` and broadcast (`survive.player`).

## Consequences

- AI capability is exactly as portable as the helper protocol: with a v2-ext helper,
  `addai` works end to end; without a helper, `addai` degrades with a "not portable"
  message and the server keeps running.
- AI-related Go code is small (on the order of 250–300 lines per the 2026-11-04
  audit) but load-bearing: deleting it breaks the `addai` command, AI removal, the
  all-AI match lifecycle, and settlement broadcasting. There is no redundant AI
  implementation to delete.
- Difficulty handling is split: per-player difficulty of existing AIs is Go-side
  bookkeeping (`SetAiDifficulty`), while the engine default difficulty for newly
  created AIs is engine-side and answered "not portable" by the `ai <difficulty>`
  command.
- Known gap: the `ServerCacheFlag.ai` flag that arms the all-AI countdown branch has
  no writer in Go yet. Upstream maintains it in the TEAM_LIST rewrite path; that
  maintenance has not been ported, so the countdown branch exists but is currently
  never armed.

## Evidence

All paths relative to the RW-HPS Go-Server repository (checked at commit
`b0fbccfa`), unless noted.

- v2-ext operation constants and validation: `internal/game/external/protocol.go:95`
  (`OpRoomAddAI = "room.addai"`), `:97` (`room.sync`), `:100` (`room.removeplayer`),
  `:103` (`game.result`); AI response field `:232`, result payload `:242`.
- Backend methods forwarding to the helper: `internal/game/external/ext.go:26`
  (`AddAI`), `:50` (`SyncAllPlayer`), `:61` (`RemovePlayer`), `:78` (`GameResult`).
- Registration chain: `internal/game/manage/playermanage.go:55-72` (`AddAI`),
  `internal/game/room/serverroom.go:121-132` (wraps the engine profile).
- `AiPlayer` marker type: `internal/game/player/aiplayer.go:14` (struct), `:34-35`
  (`IsAi() bool { return true }`); base `Player.IsAi()` returns false at
  `internal/game/player/player.go:181-182`; remove-on-kick hook `player.go:90-94`.
- Commands: `internal/command/clientcommands.go:146-159` (`addai`, gated by
  `EnableAI`, calls `PlayerManage.AddAI`), `:196-230` (`ai <difficulty>`).
- Lifecycle: `internal/data/temp/servercacheflag.go:23-26` (`ai`/`aiWarn` flags),
  `internal/game/manage/callmanage.go:147-161` (all-AI countdown branch),
  `:182-203` (settlement via `game.result` → `survive.player`). Flag writer gap:
  `SetAi` (`servercacheflag.go:103`) has no callers in non-test code.
- Protocol entries: `Go-Server/docs/HELPER-PROTOCOL.md`, v2-ext section lines
  144-272 — operation table `:169-177`, `ai` response field `:214-230` ("the engine
  does not trigger a player.join event for AIs"), Go-side consumers `:264-272`.
- History: `git log -S AddAI` shows only additive commits (`b2464c78` player entity
  chain incl. AiPlayer, `db6220bf` manage layer, `724f25d7` commands, `e8d236f8`
  v2-ext protocol layer, `7418e25a` v2-ext wiring, `6863563e` addai profile return);
  no commit ever removed an AI implementation.
- Audit conclusion (2026-11-04, full sweep of AI/bot-related Go code): no AI
  behavior implementation exists on the Go side; all AI logic executes in the helper
  JVM engine; all Go AI code is forwarding/registration/lifecycle adaptation.
