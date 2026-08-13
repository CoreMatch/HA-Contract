# Error Codes

以下错误码为当前 HA 业务 API 的稳定注册表。后续新增错误码应先加这里，再进实现与 OpenAPI。

| Code | 含义 |
|---|---|
| `invalid_json_body` | JSON 请求体无法解析 |
| `invalid_request` | 通用参数错误 |
| `invalid_email` | 邮箱格式或邮箱参数非法 |
| `invalid_credentials` | 登录凭据错误 |
| `invalid_auth_type_or_token` | `auth_type` 与 token 组合非法 |
| `invalid_manage_token` | Manage Token 无效 |
| `remember_token_required` | 缺少 Remember Token |
| `invalid_remember_token` | Remember Token 无效 |
| `manage_target_required` | Manage 路径缺少目标用户标识 |
| `user_not_found` | 目标用户不存在 |
| `username_too_short` | 用户名长度不足 |
| `password_too_short` | 密码长度不足 |
| `username_already_taken` | 用户名已被占用 |
| `email_already_registered` | 邮箱已被注册 |
| `invalid_mojang_uuid` | Mojang UUID 格式非法 |
| `mojang_uuid_required_for_existing_user` | 既有用户缺少 `mojang_uuid` |
| `username_already_bound` | 用户名已绑定，不能再抢占 |
| `captcha_disabled` | 图形验证码未启用 |
| `captcha_invalid` | 图形验证码无效或已过期 |
| `verification_code_already_sent` | 验证码发送过于频繁 |
| `verification_code_expired_or_missing` | 验证码已过期或不存在 |
| `verification_code_invalid` | 验证码错误 |
| `email_send_failed` | 邮件发送失败 |
| `verification_status_update_failed` | 验证状态更新失败 |
| `invalid_username` | 用户名不满足约束 |
| `invalid_profile_name` | 角色名不满足约束 |
| `username_conflict` | 用户名冲突 |
| `profile_name_conflict` | 角色名冲突 |
| `profile_not_found` | 角色不存在 |
| `profile_access_denied` | 无权访问或修改角色 |
| `totp_secret_required` | 缺少 TOTP secret |
| `totp_not_configured` | TOTP 未配置 |
| `invalid_passcode` | TOTP passcode 错误 |
| `invalid_texture_type` | 材质类型非法 |
| `texture_file_required` | 缺少材质文件 |
| `invalid_texture_file` | 材质文件格式非法 |
| `invalid_texture_model` | 材质模型非法 |
| `texture_name_required` | 缺少材质名称 |
| `invalid_texture_size` | 材质尺寸非法 |
| `texture_upload_failed` | 材质上传失败 |
| `texture_delete_failed` | 材质删除失败 |
| `texture_read_failed` | 材质读取失败 |
| `upload_request_too_large` | 上传请求过大 |
| `upload_rate_limited` | 上传触发限流 |
| `texture_not_found` | 材质文件不存在 |
| `preview_not_found` | 预览文件不存在 |
| `storage_not_configured` | 存储目录未配置 |
| `keygen_disabled` | 密钥生成接口已禁用 |
| `keygen_failed` | 密钥生成失败 |
| `internal_error` | 未分类内部错误 |
