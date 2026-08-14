# Error Codes

The following error codes are the stable registry for current HA business APIs. New error codes should be added here first, then implemented in the code and OpenAPI specs.

| Code | Meaning |
|---|---|
| `invalid_json_body` | JSON request body cannot be parsed |
| `invalid_request` | General parameter error |
| `invalid_email` | Invalid email format or email parameter |
| `invalid_credentials` | Invalid login credentials |
| `invalid_auth_type_or_token` | Invalid combination of `auth_type` and token |
| `invalid_manage_token` | Invalid Manage Token |
| `remember_token_required` | Remember Token missing |
| `invalid_remember_token` | Invalid Remember Token |
| `manage_target_required` | Missing target user identifier in manage path |
| `user_not_found` | Target user does not exist |
| `username_too_short` | Username is too short |
| `password_too_short` | Password is too short |
| `username_already_taken` | Username is already taken |
| `email_already_registered` | Email is already registered |
| `invalid_mojang_uuid` | Invalid Mojang UUID format |
| `mojang_uuid_required_for_existing_user` | `mojang_uuid` missing for existing user |
| `username_already_bound` | Username is already bound and cannot be claimed |
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
| `totp_secret_required` | TOTP secret missing |
| `totp_not_configured` | TOTP not configured |
| `invalid_passcode` | Incorrect TOTP passcode |
| `invalid_texture_type` | Invalid texture type |
| `texture_file_required` | Texture file missing |
| `invalid_texture_file` | Invalid texture file format |
| `invalid_texture_model` | Invalid texture model |
| `texture_name_required` | Texture name missing |
| `invalid_texture_size` | Invalid texture size |
| `texture_upload_failed` | Texture upload failed |
| `texture_delete_failed` | Texture deletion failed |
| `texture_read_failed` | Texture read failed |
| `upload_request_too_large` | Upload request is too large |
| `upload_rate_limited` | Upload rate limited |
| `texture_not_found` | Texture file does not exist |
| `preview_not_found` | Preview file does not exist |
| `storage_not_configured` | Storage directory not configured |
| `keygen_disabled` | Key generation endpoint is disabled |
| `keygen_failed` | Key generation failed |
| `internal_error` | Unclassified internal error |
