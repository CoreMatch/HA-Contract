# Data Models

> Detailed implementation: [`models/models.go`](../../models/models.go)
>
> Migration note: BlessingSkin-to-HRPAuth offline import rules are defined in [`bs2ha-migration.md`](./bs2ha-migration.md).

This project uses GORM to maintain the following data models.

## Model Overview

| Model | Table Name | Description |
|-------|------------|-------------|
| [User](#user) | `users` | User information |
| [Profile](#profile) | `profiles` | Minecraft profile data |
| [ProfileProperty](#profileproperty) | `profile_properties` | Profile properties (e.g., textures) |
| [OAuth2Client](#oauth2client) | `oauth2_clients` | Site-side OAuth2 clients |
| [OAuth2AccessToken](#oauth2accesstoken) | `oauth2_access_tokens` | Site-side OAuth2 access tokens |
| [OAuth2RefreshToken](#oauth2refreshtoken) | `oauth2_refresh_tokens` | Site-side OAuth2 refresh tokens |
| [OAuth2AuthorizationCode](#oauth2authorizationcode) | `oauth2_authorization_codes` | Site-side authorization codes |
| [Token](#token) | `tokens` | Yggdrasil authentication tokens |
| [Session](#session) | `sessions` | Server sessions |
| [ProfileKey](#profilekey) | `profile_keys` | Minecraft 1.19+ chat-signing key pairs (one row per user) |

## User

Table name: `users`

| Field | Type | Description |
|-------|------|-------------|
| `uid` | uint | Primary key, **non-auto-increment**, allocated by backend `MAX(uid)+1` |
| `uuid` | string(32) | Yggdrasil UUID (corresponds to Yggdrasil `selectedProfile.id`) |
| `email` | string(255) | Email (**no database-level unique constraint**, deduplicated at business layer) |
| `avatar` | string(255) | Avatar URL exposed to first-party clients |
| `username` | string(255) | Username (**no database-level unique constraint**, deduplicated at business layer) |
| `password` | string(255) | Password hash or migration marker (`NOT NULL`): bcrypt for native HRPAuth accounts; BlessingSkin imports keep the bcrypt hash only when the source method is bcrypt, otherwise they use the fixed marker `BS2HA$RESET_REQUIRED` |
| `ip` | string(255) | Most recent login IP |
| `permission` | int | Permission bits (default 0) |
| `last_sign_at` | datetime | Last activity (**for business/cleanup use**, used by proxy registration cleanup routine to judge activity) |
| `register_at` | datetime | Registration time (**for business/cleanup use**, used by proxy registration cleanup routine to judge account age) |
| `verified` | tinyint(1) | Whether email is verified (default 0) |
| `remember_token` | string(100) | Legacy site session token field, retained only for backward compatibility |
| `regip` | string(40) | IP at registration |
| `totp` | string(32) | TOTP shared secret (Base32) |
| `2FA` | tinyint(1) | **Two-Factor Authentication**: 1 = Enabled; 0 = Disabled (default 0) |
| `cbh` | tinyint(1) | **Created By Human**: 1 = WebUI registration or claimed proxy registration; 0 = Unclaimed WinnerProxy proxy registration (default 1) |
| `mbe` | tinyint(1) | **Mojang Bind Enabled**: 1 = Allow Mojang players with same name to bind via M.T. `/register`; 0 = HA priority refusal (default 0) |
| `mojang_uuid` | string(32) | Bound Mojang UUID (lowercase hex without hyphens, `NULL`=unbound; `UNIQUE` index `uk_users_mojang_uuid`) |

## Field Semantics

### `cbh` (Created By Human)

- **Values**: `1` (default) = Created by human (WebUI registration or claimed proxy registration); `0` = Robot user created by WinnerProxy proxy registration and **not yet claimed**.
- **Write Rules**:
  - WebUI `/register` (including captcha enabled) → always `1`.
  - Service proxy `/register`:
    - Hit existing user (idempotent / `mbe=1` bind) → **do not change** `cbh` (keep original value).
    - New user with `mojang_uuid` provided → `0` (proxy registration).
    - New user without `mojang_uuid` provided → `1` (equivalent to WebUI).
- **Cleanup Basis**: Users with `cbh=0` and both `register_at` / `last_sign_at` exceeding 30 days are deleted by `BotUserCleanupController` (see `references/HA-ROADMAP.md` §4).
- **Claiming Mechanism**:
  - Via WebUI / MBE: whether `cbh` flips to 1 when a proxy-registered user subsequently registers and binds via WebUI is decided by the business layer; the current implementation keeps the original value.
  - Via operator endpoint `POST /admin/claim-user`: when an operator assigns credentials to a `cbh=0` user, the handler **flips `cbh` to 1** as part of the same transaction, removing the user from the bot-user cleanup eligibility. See "Operator Claiming" below.

### Operator Claiming (`POST /admin/claim-user`)

Proxy-registered users are normally unable to log in to the business system because their email is a placeholder (`<username>@mojang-imported.invalid`) and their password is a WinnerProxy-generated random string. The operator claiming endpoint gives them a real WebUI credential pair.

| Field | Value |
|---|---|
| Authentication | OAuth2 Bearer Service Token, scope `user.claim.as-service` |
| Request body | `username` (≥ 3 chars), `email` (must be unique), `password` (≥ 6 chars) |
| Target | User with `username` equal to the request value AND `cbh=0` |

Handler semantics (`controllers/auth_controller.go > ClaimUser`):

1. Reject when target is missing or `cbh=1` (already a human account).
2. UPDATE the same row with `email`, `password` (bcrypt), `cbh = 1`, `verified = 1`.
3. Return `{uid, username, email}`.

Side effects: after flipping `cbh` to 1, the user is no longer eligible for `BotUserCleanupController`, so operator claiming is the only way to permanently remove a `cbh=0` row without the user having to interact via MBE.

### `mojang_uuid`

- **Format**: 32-bit lowercase hex (UUID without hyphens), isomorphic with Yggdrasil `selectedProfile.id`.
- **Constraint**: `UNIQUE` index `uk_users_mojang_uuid` (`NULL` does not participate in unique constraint, so multiple unbound users can exist).
- **Write Sources**:
  - Service proxy `/register` decision tree 1 (hit by `mojang_uuid`) → idempotent return.
  - Service proxy `/register` decision tree 2.a `mbe=1` → written during bind.
  - **Not** written via WebUI `/register`.
- **Relationship with `users.uuid`**: `users.uuid` is the internal UUID for the user within the HA / Yggdrasil system (unrelated to Mojang); `mojang_uuid` is the bound Mojang authentic UUID. Both can coexist and be different.

### `mbe` (Mojang Bind Enabled)

- **Values**: `0` (default) = Prohibit Mojang players with the same name from binding via service proxy `/register` (**HA priority**, Mojang players receive 409 and are kicked); `1` = Allow binding.
- **Write Endpoints**:
  - `POST /user/mojang-bind-enable` → Player self-enable (Remember Token) or service enable (Manage Token + `uid`/`email`). Sets `mbe = 1`. Idempotent.
  - `POST /user/mojang-bind-disable` → Player self-disable (Remember Token) or service disable (Manage Token + `uid`/`email`). Sets `mbe = 0`. Idempotent.
- **Query**: `mbe` is included in the `POST /user` response as `data.mbe` (0 or 1).
- **Only effective in service proxy `/register` decision tree 2.a**: Checked when a same-name WebUI user is hit and their `mojang_uuid IS NULL`.
- **Once `mojang_uuid` is written, the semantics of `mbe` disappear** (subsequent same-name Mojang players will not trigger 2.a). On successful bind, `mbe` is **automatically reset to 0** together with the `mojang_uuid` write, so the field cleanly reflects the current authorization status.
- **Auto-disable timeout**: After `POST /user/mojang-bind-enable` sets `mbe = 1`, a 15-minute countdown begins. If no bind (`mojang_uuid` write) occurs within that window, the system automatically resets `mbe = 0`. The timeout is cancelled on successful bind (which also resets `mbe = 0`), explicit disable, or re-enable (which restarts the timer). Implementation: `controllers/mbe_timeout_controller.go` — an in-memory event stack scanned every 30 seconds.

### `password`

- **Native HRPAuth write format**: bcrypt.
- **BlessingSkin migration contract**:
  - source method = `BCRYPT` -> copy the existing bcrypt hash directly
  - source method != `BCRYPT` -> write the fixed invalid marker `BS2HA$RESET_REQUIRED`
- **Operational meaning**: non-bcrypt BlessingSkin imports do not log in with their old password and must use password reset.
- **Configuration interaction**: `security.password_cost` applies to newly generated bcrypt hashes, including post-reset passwords.

## Profile

Table name: `profiles`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | UUID (primary key) |
| `user_id` | string | Owner internal UUID (corresponds to `users.uuid`) |
| `name` | string | Minecraft profile name (unique) |
| `model` | enum | Skin model: `default` or `slim` |
| `created_at` / `updated_at` | datetime | Automatically maintained by GORM |

> A User can have multiple Profiles (multiple characters), but the current registration process only creates the first one. For multiple characters, call extension interfaces outside of Yggdrasil `/api/profiles/minecraft`.
>
> BlessingSkin migration intentionally narrows imported profiles according to [`bs2ha-migration.md`](./bs2ha-migration.md): keep the single player when only one exists, otherwise keep only the player matching the imported BlessingSkin username, and create a placeholder profile when no usable BlessingSkin player remains.

## ProfileProperty

Table name: `profile_properties`

| Field | Type | Description |
|-------|------|-------------|
| `id` | uint | Primary key |
| `profile_id` | string | Profile UUID (foreign key) |
| `name` | string | Property name (e.g., `textures`) |
| `value` | string | Property value (base64 encoded JSON) |
| `signature` | string | RSA signature of `value` using private key (nullable, but expected for production `textures` payloads) |

## Token

Table name: `tokens`

| Field | Type | Description |
|-------|------|-------------|
| `id` | uint | Primary key |
| `user_id` | string | Owner internal UUID (corresponds to `users.uuid`) |
| `access_token` | string | Yggdrasil Access Token (unique) |
| `client_token` | string | Yggdrasil Client Token |
| `selected_profile_id` | string | Associated Profile UUID (foreign key, nullable) |
| `issued_at` | int64 | Unix millisecond timestamp |
| `expires_in_days` | int | Validity in days (default 15) |
| `state` | string | State: `valid` / `temporarily_invalid` / `invalid` |
| `created_at` | datetime | Creation time (`DEFAULT CURRENT_TIMESTAMP`) |

> See [tokens.md](./tokens.md) for detailed state machine.

## OAuth2Client

Table name: `oauth2_clients`

| Field | Type | Description |
|-------|------|-------------|
| `id` | uint | Primary key |
| `client_id` | string | Client identifier (unique) |
| `client_secret` | string | Client secret (nullable) |
| `name` | string | Client name |
| `type` | enum | `public` or `confidential` |
| `grant_types` | text | Allowed grant types (comma-separated) |
| `redirect_uris` | text | Whitelisted redirect URIs |
| `scopes` | text | Allowed scopes |
| `is_internal` | bool | Whether client is internal to HA system |
| `is_super` | bool | Whether client has elevated permissions |
| `is_active` | bool | Whether client is active |
| `created_at` / `updated_at` | datetime | Timestamps |

## OAuth2AccessToken

Table name: `oauth2_access_tokens`

| Field | Type | Description |
|-------|------|-------------|
| `id` | uint | Primary key |
| `access_token` | string | The Bearer access token (unique) |
| `client_id` | string | Issuing client ID |
| `user_id` | string | Associated internal UUID (nullable for service mode) |
| `scopes` | text | Granted scopes |
| `subject_type` | enum | `user` or `service` |
| `target_uid` | uint | Explicit target UID for service mode (nullable) |
| `target_email` | string | Explicit target email for service mode (nullable) |
| `expires_at` | datetime | Expiration time |
| `revoked_at` | datetime | Revocation time (nullable) |
| `created_at` | datetime | Creation time |

## OAuth2RefreshToken

Table name: `oauth2_refresh_tokens`

| Field | Type | Description |
|-------|------|-------------|
| `id` | uint | Primary key |
| `refresh_token` | string | The refresh token (unique) |
| `access_token_id` | uint | Linked access token ID |
| `client_id` | string | Issuing client ID |
| `user_id` | string | Associated internal UUID |
| `scopes` | text | Granted scopes |
| `expires_at` | datetime | Expiration time |
| `revoked_at` | datetime | Revocation time (nullable) |
| `created_at` | datetime | Creation time |

## Session

Table name: `sessions`

| Field | Type | Description |
|-------|------|-------------|
| `id` | uint | Primary key |
| `server_id` | string | serverId passed by Minecraft server |
| `profile_id` | string | Associated Profile UUID |
| `ip` | string | Client IP (optional) |
| `created_at` | datetime | Creation time (`DEFAULT CURRENT_TIMESTAMP`) |
| `expires_at` | datetime | Expiration time |

> Sessions are written by `POST /sessionserver/session/minecraft/join` and read by `GET /sessionserver/session/minecraft/hasJoined`.

## ProfileKey

Table name: `profile_keys`

| Field | Type | Description |
|-------|------|-------------|
| `id` | uint | Primary key |
| `user_id` | string(32) | Owner internal UUID (`users.uuid`); `UNIQUE` index `uk_profile_keys_user_id` |
| `public_key` | text | PEM-encoded RSA public key (`BEGIN RSA PUBLIC KEY`) |
| `private_key` | text | PEM-encoded RSA private key (`BEGIN RSA PRIVATE KEY`) |
| `public_key_signature` | text | Base64 SHA1withRSA signature over `<expiresAtMillis><publicKeyPEM>` produced by the Yggdrasil signature private key |
| `expires_at` | datetime | Validity expiry (issued + 48h) |
| `refreshed_after` | datetime | Earliest moment the client may request a new key pair (issued + 40h) |
| `created_at` / `updated_at` | datetime | GORM-managed |

> See [`profile-keys.md`](./profile-keys.md) for the full flow and [`services/profile_key_service.go`](../../services/profile_key_service.go) for the service implementation. The schema is brought in by `database/migrations/000004_profile_keys.up.sql`.
