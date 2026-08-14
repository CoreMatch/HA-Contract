# Feature Flags

Feature flags for the Yggdrasil protocol layer, corresponding to `yggdrasil.feature_flags.*` configuration items.

> For HRPAuth's own switches (`security.*`), see [configuration.md](./configuration.md).

| Configuration Item | Default | Description |
|--------------------|---------|-------------|
| `non_email_login` | `true` | Allows login via **Minecraft profile name** (in addition to email) at `POST /authserver/authenticate`. Implementation in [`../services/auth_service.go::VerifyCredentials`](../services/auth_service.go); when `true`, users can input `email` or `profiles.name`. Only affects Yggdrasil endpoints; `POST /login` (this site) still only accepts email. |
| `legacy_skin_api` | `false` | Enables the legacy skin API (`/skins/MinecraftSkins/...`). No longer used by modern clients. |
| `no_mojang_namespace` | `false` | Disables Mojang namespace. When enabled, the namespace of profile properties will not have the `minecraft:` prefix. |
| `enable_mojang_anti_features` | `false` | Enables Mojang anti-cheat features. Specific behavior is interpreted by the client. |
| `enable_profile_key` | `false` | Enables profile keys (Yggdrasil 1.1+). Mojang 1.19+ clients will request new endpoints like `/player/certificates`. |
| `username_check` | `true` | Enables username checking (restricts Minecraft profile name format). **Highly recommended to keep `true`**. |
| `enable_ip_check` | `false` | Enables IP validation. When enabled, `GET /sessionserver/session/minecraft/hasJoined` will check if `query.ip` matches the IP in the session record; if not, it will be rejected (returns 204). |

## Position in Responses

Some flags are returned as-is in the `meta` section of `GET /` (Yggdrasil metadata):

```json
{
  "meta": {
    "serverName": "HRPAuth",
    "implementationName": "HRPAuth",
    "implementationVersion": "1.0.0"
  },
  "feature.non_email_login": false,
  "feature.legacy_skin_api": false,
  "feature.no_mojang_namespace": false,
  "feature.enable_mojang_anti_features": false,
  "feature.enable_profile_key": false,
  "feature.username_check": true
}
```

> The specific returned fields depend on the implementation and can be viewed in [`controllers/yggdrasil_controller.go`](../../controllers/yggdrasil_controller.go).
