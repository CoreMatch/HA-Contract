# Error Codes

The following error codes are the stable registry for current HA business APIs. New error codes should be added here first, then implemented in the code and OpenAPI specs.

| Code | Meaning |
|---|---|
| `invalid_json_body` | JSON request body cannot be parsed |
| `invalid_request` | General parameter error |
| `invalid_email` | Invalid email format or email parameter |
| `invalid_credentials` | Invalid login credentials |
| `invalid_auth_type_or_token` | Legacy invalid combination of `auth_type` and token |
| `invalid_manage_token` | Legacy invalid Manage Token. Defined in this registry only; no current implementation returns it — the HRPAuth core keeps the constant as part of the legacy Manage Token mechanism but has no code path that emits it, and the Yggdrasil-API force-bind `manage_token` check was retired on 2026-11-05 in favor of service-token scopes |
| `remember_token_required` | Legacy Remember Token missing |
| `invalid_remember_token` | Legacy invalid Remember Token |
| `manage_target_required` | Missing target user identifier for delegated/service operation |
| `user_not_found` | Target user does not exist |
| `target_not_found` | Target account (identified by email/password) does not exist or credentials are invalid |
| `no_mojang_uuid` | Proxy-registered account has no `mojang_uuid` to transfer |
| `user_not_claimable` | Target user is not a proxy-registered account, or its bound `mojang_uuid` does not match |
| `username_too_short` | Username is too short |
| `password_too_short` | Password is too short |
| `username_already_taken` | Username is already taken |
| `email_already_registered` | Email is already registered |
| `invalid_mojang_uuid` | Invalid Mojang UUID format |
| `mojang_uuid_required_for_existing_user` | `mojang_uuid` missing for existing user |
| `mojang_uuid_already_bound` | The account is already bound to a different `mojang_uuid`: returned by `/admin/force-bind` for the target account, and by `/player/microsoft-bind` for the caller's account (unbind first) |
| `mojang_uuid_bound_to_another_account` | `/player/microsoft-bind`: the verified `mojang_uuid` is already bound to a different HA account (operator force-bind territory) |
| `minecraft_verification_failed` | `/player/microsoft-bind`: Minecraft Services rejected the supplied access token (re-verification failed) |
| `minecraft_profile_missing` | Microsoft-login mapping: the account owns a Minecraft license but has no game profile yet (profile endpoint answered 404 while entitlements show ownership) |
| `minecraft_license_not_found` | Microsoft-login mapping: no Minecraft ownership and no game profile (profile endpoint answered 404 without entitlements) |
| `username_already_bound` | Username is already bound and cannot be claimed or taken: returned by the core's `/internal/claim-user` when the username belongs to another user (passed through by `/admin/claim-user`), and by `/internal/proxy-register` when the username collides with an account that is not in an open mbe bind window |
| `captcha_disabled` | Graphical captcha is disabled |
| `captcha_invalid` | Graphical captcha is invalid or expired |
| `verification_code_already_sent` | Verification code sent too frequently |
| `verification_code_expired_or_missing` | Verification code expired or missing |
| `verification_code_invalid` | Incorrect verification code |
| `email_send_failed` | Email sending failed |
| `verification_status_update_failed` | Failed to update verification status |
| `invalid_username` | Username does not meet constraints |
| `invalid_profile_name` | Profile name does not meet constraints |
| `username_conflict` | Username conflict |
| `profile_name_conflict` | Profile name conflict |
| `profile_not_found` | Profile does not exist |
| `profile_access_denied` | No permission to access or modify profile |
| `profile_already_exists` | A profile has already been created for this account (HRPAuth-Yggdrasil-API) |
| `profile_uuid_conflict` | Requested profile UUID is already used by another local profile (HRPAuth-Yggdrasil-API) |
| `totp_secret_required` | TOTP secret missing |
| `totp_not_configured` | TOTP not configured |
| `invalid_passcode` | Incorrect TOTP passcode |
| `webauthn_not_configured` | WebAuthn is not configured for the requested operation |
| `email_2fa_not_configured` | Email 2FA is not configured for the requested operation |
| `invalid_webauthn_flow` | WebAuthn flow_id is invalid, expired, or does not match the expected flow |
| `webauthn_credential_not_found` | Requested WebAuthn credential record does not exist |
| `webauthn_verification_failed` | WebAuthn ceremony verification failed |
| `recovery_key_already_configured` | Recovery key is already configured for the user |
| `recovery_key_not_configured` | Recovery key is not configured for the user |
| `invalid_texture_type` | Invalid texture type |
| `texture_file_required` | Texture file missing |
| `invalid_texture_file` | Invalid texture file format |
| `invalid_texture_model` | Invalid texture model |
| `texture_name_required` | Texture name missing |
| `invalid_texture_size` | Texture file exceeds the configured maximum file size (`max_texture_file_size`). Dimension mismatches are now soft warnings, not errors. |
| `texture_upload_failed` | Texture upload failed |
| `texture_delete_failed` | Texture deletion failed |
| `texture_read_failed` | Texture read failed |
| `texture_fetch_failed` | Failed to fetch texture from upstream (e.g. Mojang Session Server or texture CDN) |
| `profile_query_failed` | Profile texture query failed (HASkinLib). Defined in the HASkinLib constant table; no handler currently returns it |
| `upload_request_too_large` | Upload request is too large |
| `upload_rate_limited` | Upload rate limited |
| `texture_not_found` | Texture file does not exist |
| `preview_not_found` | Preview file does not exist |
| `storage_not_configured` | Storage directory not configured |
| `keygen_disabled` | Key generation endpoint is disabled |
| `keygen_failed` | Key generation failed |
| `oauth_invalid_client` | Invalid OAuth2 client credentials |
| `oauth_invalid_grant` | Invalid, expired, or revoked OAuth2 grant/token |
| `oauth_invalid_scope` | Requested OAuth2 scope is not allowed |
| `oauth_unauthorized_client` | Client is not allowed to use this grant type |
| `oauth_invalid_redirect_uri` | Redirect URI is invalid or not whitelisted |
| `oauth_unsupported_grant_type` | Unsupported OAuth2 grant type |
| `oauth_invalid_code_challenge` | Invalid or missing PKCE code challenge |
| `oauth_insufficient_scope` | Token does not carry the required scope |
| `oauth_access_denied` | Access denied by OAuth2 authorization policy |
| `invalid_client_metadata` | Self-service client registration metadata is invalid (HRPAuth core `POST /oauth/register`; the RFC 7591 §3.2.2 error code): the service name is not presence-registered, a requested scope lies outside the service's `oauth2.service_scope_allowlist` entry (or is a super/`db.*` scope), `client_name` is missing, the body is malformed, or the requested `client_name` collides with a legacy client row carrying the super client secret — such a row is refused, never returned (HTTP 400) |
| `oauth_login_required` | Missing Bearer access token |
| `login_ticket_required` | Missing login ticket |
| `invalid_login_ticket` | Login ticket is invalid or expired |
| `endpoint_deprecated` | Endpoint has been removed from active auth flow (constant defined in HRPAuth core; no endpoint currently returns it) |
| `hook_denied` | A registered webhook hook vetoed the request (HRPAuth core OAuth2 flow) |
| `hook_failed` | A required webhook hook failed and the fail policy closed the request (HRPAuth core OAuth2 flow) |
| `database_not_ready` | Database middleware rejected the request before the schema was ready (HRPAuth core; returned without the unified `error` alias and `meta` fields) |
| `route_not_found` | No registered route matched the request (HRPAuth core NoRoute handler) |
| `service_not_registered` | Service not registered; send `/services/presence` first |
| `relay_failed` | Relay forwarding to microservice failed |
| `relay_not_found` | Relay rule not found for deletion |
| `sdk_package_conflict` | A SDK package with the same name already exists (HTTP 409) |
| `sdk_package_not_found` | Requested SDK package does not exist (HTTP 404) |
| `sdk_package_invalid` | SDK package archive is malformed or unreadable (HTTP 400) |
| `sdk_package_invalid_manifest` | SDK package `manifest.json` is missing or fails validation (HTTP 422) |
| `sdk_package_invalid_path` | SDK package archive contains an illegal path (traversal / absolute / symlink) (HTTP 400) |
| `sdk_package_too_large` | SDK package exceeds the configured size limit (HTTP 413) |
| `sdk_not_found` | SDK package lookup failed. Defined in the HRPAuth core and Yggdrasil-API constant tables; no handler currently returns it (the sdk-package endpoints use `sdk_package_not_found`) |
| `insufficient_auth_level` | Credential present but below the required auth level |
| `internal_error` | Unclassified internal error |
| `oauth_state_mismatch` | OAuth2 state parameter mismatch (CSRF / replay protection). Defined in the HRPAuth core and MatchCoreArena registries; no current implementation returns it. |
| `oauth_token_expired` | OAuth2 access token expired. Returned by MatchCoreArena's auth middleware (`401`); in the HRPAuth core expired tokens surface as `oauth_invalid_grant`. |
| `oauth_refresh_failed` | OAuth2 refresh token is invalid, expired, or revoked. Returned by MatchCoreArena `POST /api/auth/refresh`; in the HRPAuth core refresh failures surface as `oauth_invalid_grant`. |
| `oauth_revoke_failed` | OAuth2 token revocation request failed. Returned by MatchCoreArena `POST /api/auth/logout`. Defined in the HRPAuth core registry only; no core endpoint returns it. |
| `oauth_rate_limited` | Too many auth requests; retry later (MatchCoreArena login-ticket flow). |
| `oauth_hrpauth_down` | HRPAuth upstream unavailable during an auth flow or a service-to-service call (MatchCoreArena; since 2026-11-05 also the settlement identity-resolution failure: service credentials unavailable or HRPAuth outage, HTTP 502). The code string was misspelled `oauth_hrpaauth_down` until the spelling fix; no external consumer ever used the old form. |
| `mca_invalid_request` | MatchCoreArena: general parameter error |
| `mca_user_not_found` | MatchCoreArena: user does not exist. Since 2026-11-05 also returned (HTTP 404) when a match-report participant's UUID is unknown to HRPAuth (`GET /services/users/{uuid}` answered 404). |
| `mca_user_not_provisioned` | MatchCoreArena: settlement lazy-provisioning failed — the participant's HRPAuth UID could not get a local `users` row (e.g. the uid is held by a soft-deleted row), so the report aborts and rolls back (HTTP 409). Ordinary missing rows are auto-provisioned inside the settlement transaction since 2026-11-05 (author decision: lazy initialization; uid only from the verified resolution, rating from table defaults) and do not produce this code. |
| `mca_friend_not_found` | MatchCoreArena: friend relationship does not exist. Reserved for the unimplemented friend feature; no code path currently returns it (friend endpoints answer `501 mca_not_implemented`). |
| `mca_friend_request_exists` | MatchCoreArena: friend request already exists. Reserved for the unimplemented friend feature; no code path currently returns it (friend endpoints answer `501 mca_not_implemented`). |
| `mca_team_not_found` | MatchCoreArena: team does not exist. Reserved for the unimplemented team feature; no code path currently returns it (team endpoints answer `501 mca_not_implemented`). |
| `mca_team_name_taken` | MatchCoreArena: team name is already in use. Reserved for the unimplemented team feature; no code path currently returns it (team endpoints answer `501 mca_not_implemented`). |
| `mca_not_team_leader` | MatchCoreArena: only the team leader can perform this action. Reserved for the unimplemented team feature; no code path currently returns it (team endpoints answer `501 mca_not_implemented`). |
| `mca_match_not_found` | MatchCoreArena: match does not exist |
| `mca_queue_already_joined` | MatchCoreArena: the user already has a matchmaking queue entry (HTTP 409); one queue entry per user overall |
| `mca_queue_not_joined` | MatchCoreArena: the user has no matchmaking queue entry to leave (HTTP 404) |
| `mca_not_implemented` | MatchCoreArena: the endpoint exists but the feature is explicitly unimplemented (HTTP 501). Returned by all friend and team endpoints. |
| `mca_report_inconsistent` | MatchCoreArena: a match report is self-contradictory and rejected before settlement (HTTP 400) — multiple winning teams, win/draw mixing, duplicate participant UUIDs, `initial_count` < 1 or `alive_count` outside [0, initial_count], negative kills/deaths/survival_time/duration, `perf_tweak` outside [0.95, 1.05], `finished_at` before `started_at`, or a positive `duration_seconds` disagreeing with the timestamp difference. Validation parity with the ops panel's client-side checks. |
| `mca_game_id_conflict` | MatchCoreArena: a match report reuses a `game_id` that is already recorded with a DIFFERENT payload (HTTP 409). Identical-payload duplicates are not errors — they replay the existing record with HTTP 200 (`game_id` idempotency). |
| `mca_party_already_in_party` | MatchCoreArena: a matchmaking party roster member is already in another queued party, or a user already in a queued party tries to solo-queue (HTTP 409). |
| `mca_party_full` | MatchCoreArena: a matchmaking party roster exceeds the mode's max team size (HTTP 409). |
| `mca_ranking_not_found` | MatchCoreArena: the user has no ranking entry for the requested type/season (`GET /api/rankings/me`, HTTP 404). |
| `cascade_room_conflict` | Cascade management API: a room code is claimed by more than one backend and cannot be routed |
| `cascade_backend_unavailable` | Cascade management API: the owning backend is unhealthy or unreachable, so the request cannot be forwarded |
| `cascade_invalid_internal_key` | Cascade management API: the `X-Internal-Key` header is missing or does not match the key issued by HRPAuth Core |
| `cascade_database_not_configured` | Cascade management API: the endpoint needs the player-binding database, which is not available |
| `cascade_binding_not_found` | Cascade management API: no player binding exists for the given game UUID, or (on the claim path) no unclaimed binding exists (HTTP 404) |

Cascade note: the backend-facing `/v1` surface is governed by
`docs/dev/Cascade/Cascade-Backend-v1.md`, whose stable `UPPER_SNAKE` error
codes (`FORBIDDEN`, `SESSION_NOT_FOUND`, `ROOM_CONFLICT`, ...) are forwarded
verbatim through the Cascade management API when a backend error is passed
through; they are registered in that contract, not in this registry.
