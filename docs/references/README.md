# External API References

This directory contains external API standards followed by this project.

## Important Notes

1. **Protocol Standards**: This directory stores the **original protocol definitions**. They define the expected behavior of external systems (e.g., Minecraft client, authlib-injector).
2. **Read-Only**: These documents are the authoritative definitions of external protocols and **must not be modified**.
3. **Compliance Principle**: When implementing relevant compatibility layers, this project must strictly adhere to the behaviors and data structures defined in these documents.

## Document List

- [CustomSkinAPI.md](./CustomSkinAPI.md): Skin library standard protocol.
- [authlib-injectorwiki.pdf](./authlib-injectorwiki.pdf): authlib-injector / Yggdrasil API protocol reference.
- **Yggdrasil API / authlib-injector**: Minecraft official authentication protocol and its extended implementation standards in third-party authenticators.
