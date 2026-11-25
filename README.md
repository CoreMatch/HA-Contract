<div align="center">
  <h1>Armorial Contract</h1>
  <p><strong>One contract. Fewer integration guesses.</strong></p>
  <p><a href="./README.zh-CN.md">简体中文</a></p>
</div>

Armorial Contract gives Armorial service integrators versioned API schemas, OpenAPI definitions, and shared response and error conventions. It replaces reverse-engineering with explicit agreements that implementations and consumers can reference.

## Why Armorial Contract

- **Integrate from evidence.** OpenAPI definitions describe service surfaces without requiring a tour of each implementation.
- **Keep responses predictable.** Shared response and error conventions reduce special cases across services.
- **Catch route drift mechanically.** METHOD + path checks compare registered routes with their contracts in both directions.
- **Keep knowledge anchored.** Mechanical checks help detect documentation references that no longer match the code they cite.

## Learn more

- [Armorial Contract on GitHub](https://github.com/CoreMatch/HA-Contract) — canonical repository
- [OpenAPI definitions](docs/api/openapi/) — versioned service contracts
- [Business API drift check](scripts/check-business-api-drift.sh) — route-to-contract comparison
- [Armorial Wiki](https://wiki.mcnb.dev/) — deployment and development documentation

## Boundary

Armorial Contract is not a runtime authentication layer or the authority for all Armorial documentation.

## License

No license is declared in this repository.
