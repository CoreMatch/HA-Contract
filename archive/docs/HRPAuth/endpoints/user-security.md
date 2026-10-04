# 用户安全设置 (User Security)

处理已登录用户的高级安全操作，如更换邮箱和修改密码。支持多因子验证豁免机制。

> 详细实现： [`controllers/user_security_controller.go`](../../controllers/user_security_controller.go)

## 安全校验逻辑

系统支持两种平行的验证路径来执行敏感操作：
1. **密码 + 1 因子**：验证用户的现有密码，以及任意一个已开启的双因素认证因子（TOTP、WebAuthn 或 邮件验证码）。
2. **2 因子豁免**：验证任意两个已开启的双因素认证因子。此路径下**无需提供旧密码**，且允许在更换邮箱时同步更新密码。

## 端点

| 端点 | 方法 | 鉴权 |
|------|------|------|
| [POST /user/security/change-email/send-code](#post-usersecuritychange-emailsend-code) | `POST` | **Bearer Token** |
| [POST /user/security/change-email/webauthn-begin](#post-usersecuritychange-emailwebauthn-begin) | `POST` | **Bearer Token** |
| [POST /user/security/change-email](#post-usersecuritychange-email) | `POST` | **Bearer Token** + **Multi-Factor** |

---

## POST /user/security/change-email/send-code

向用户当前的注册邮箱发送用于更换邮箱的验证码。

### 鉴权

**Bearer Token**（要求 scope `user.security.manage`）

---

## POST /user/security/change-email/webauthn-begin

为当前用户启动 WebAuthn Sudo 模式认证流程。

### 鉴权

**Bearer Token**（要求 scope `user.security.manage`）

### 成功响应

返回 WebAuthn 认证选项及 `flow_id`。

---

## POST /user/security/change-email

执行更换邮箱操作。

### 鉴权

**Bearer Token**（要求 scope `user.security.manage`）

### 请求体

```json
{
  "new_email": "new@example.com",
  "current_password": "...",
  "new_password": "...",
  "totp_code": "...",
  "email_code": "...",
  "webauthn": {
    "flow_id": "...",
    "credential": { ... }
  }
}
```

- `new_email`: 必填，新邮箱地址。
- `current_password`: 可选，现有密码。
- `new_password`: 可选，新密码（仅在 2 因子豁免路径下有效，最小长度 6 位）。
- `totp_code`: 可选，TOTP 动态口令。
- `email_code`: 可选，发送至旧邮箱的验证码。
- `webauthn`: 可选，WebAuthn 认证凭证。

### 校验规则

1. 统计有效因子：
   - 正确的 `current_password` 计 1 分。
   - 有效的 `totp_code` 计 1 分。
   - 有效的 `email_code` 计 1 分。
   - 有效的 `webauthn` 凭证计 1 分。
2. 总分必须 **≥ 2** 才能执行更新。
3. 如果未提供 `current_password` 但总分达到 2，且提供了 `new_password`，则系统会同时更新邮箱和密码。
4. 更换邮箱后，用户的 `verified` 状态将被重置为 `false`。
