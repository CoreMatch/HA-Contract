# ADR-0002: The Game Engine Is an External Dependency

- **Status**: accepted
- **Date**: 2026-11-04

## Context

The upstream server does not implement the game itself. It loads the closed-source
`rusted-warfare.jar` inside its own JVM and uses ASM bytecode rewriting to attach
the game's server-side main loop to its event bus. The Go port must provide the
same game behavior from a process that cannot execute JVM bytecode.

## Decision

The game engine is kept as an **external dependency**: a separate JVM process
(the "helper") hosts the engine, and the Go server talks to it over the helper
protocol (JSON lines over the helper's stdin/stdout, protocol version 2).

- **Why external**: a Go process cannot execute Java bytecode and has no equivalent
  of the upstream's bytecode rewriting, so the simulation layer cannot be ported
  1:1. The Go side declares only the operations the network and command layers
  actually call, and deliberately provides no fake implementation — a start without
  a backend must fail explicitly rather than produce an empty room that "looks like
  it runs".
- **What the protocol carries**: v2 covers the room/connection lifecycle and packet
  relay (`hello`, `room.create/destroy/start/stop/status`, `conn.open/close/packet`,
  plus `player.*`/`chat`/`command` events back to Go). v2-ext adds the operations
  that upstream performs on in-process engine objects (`room.addai`, `room.sync`,
  `room.removeplayer`, `game.result`; later `room.settings`), without changing the
  wire version — a v2-only helper answers `unsupported` and Go degrades those calls
  to logged no-ops.
- **Degradation without a helper**: the server still starts and serves connections.
  Match start returns the readable error `game: no simulation backend available`.

## Consequences

- Building and deploying the helper (JDK 17 required; JDK 25 crashes the Kotlin
  2.0.0 compiler) is part of operating a full-featured server; a host without it
  runs a degraded server that cannot start matches.
- Every engine-side capability needs a protocol operation; capabilities added later
  (e.g. room settings for the Cascade facade) extend v2-ext rather than the Go
  process.
- Misconfiguration is checked statically at startup (parameters present, files
  exist) instead of surfacing as an opaque EOF at first match start; a broken helper
  configuration falls back to the no-backend state with a warning instead of
  preventing startup.
- Cost: one extra process to supervise, one protocol to keep in sync, and a hard
  rule that unknown helper message types are fatal (silent ignoring would let the
  two sides drift).

## Evidence

All paths relative to the RW-HPS Go-Server repository (checked at commit
`b0fbccfa`), unless noted.

- Boundary rationale: `internal/game/seam.go:30-42` — upstream loads the
  closed-source jar in-JVM and rewires it via ASM; "Go 进程无法执行 Java 字节码"
  (a Go process cannot execute Java bytecode), no fake implementations.
- Explicit-failure design: `internal/game/seam.go:17-21`
  (`ErrNotImplemented = "game: no simulation backend available"`), `:144-164`
  (`Unimplemented` placeholder; `Backend` defaults to it).
- v2 operation set and validation: `Go-Server/docs/HELPER-PROTOCOL.md:73-89`;
  transport and wire format `:15-28`; events `:93-105`.
- v2-ext purpose and compatibility: `HELPER-PROTOCOL.md:144-167` (same wire
  version; v2-only helpers answer `unsupported`; Go normalizes to
  `game.ErrUnsupported` and degrades to logged no-ops); `internal/game/seam.go:23-28`
  (`ErrUnsupported`), `:54-90` (`RoomControl` interface).
- Degradation path: `internal/app/simulation.go:29-49` (no backend → `Unimplemented`,
  "开局返回可读的错误"), `:54-57` (helper not configured is the silent default),
  `:64-69` (broken helper config → warn + fall back to no backend);
  `internal/app/bootstrap.go:66-67` ("没有后端时 start 会返回 ErrNotImplemented").
- JDK constraint: recorded in the 2026-11-04 helper landing notes (JDK 25 crashes
  the Kotlin 2.0.0 compiler; build with JDK 17). Not independently re-verified in
  this pass.
