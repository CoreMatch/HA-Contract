# 用户安全设置 (User Security)

处理已登录用户的高级安全操作，如更换邮箱。该流程已简化，仅需单一验证因子即可执行。

> 详细实现： [`controllers/user_security_controller.go`](../../controllers/user_security_controller.go)

## 安全校验逻辑

系统要求用户提供任意一个已开启的双因素认证因子（TOTP、WebAuthn 或 邮件验证码）即可执行更换邮箱操作。不再需要提供账号密码，也不支持在此流程中修改密码。

## 端点

| 端点 | 方法 | 鉴权 |
|------|------|------|
| [POST /user/security/change-email/send-code](#post-usersecuritychange-emailsend-code) | `POST` | **Bearer Token** |
| [POST /user/security/change-email/webauthn-begin](#post-usersecuritychange-emailwebauthn-begin) | `POST` | **Bearer Token** |
| [POST /user/security/change-email](#post-usersecuritychange-email) | `POST` | **Bearer Token** + **Single-Factor** |

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
  "totp_code": "...",
  "email_code": "...",
  "webauthn": {
    "flow_id": "...",
    "credential": { ... }
  }
}
```

- `new_email`: 必填，新邮箱地址。
- `totp_code`: 可选，TOTP 动态口令。
- `email_code`: 可选，发送至旧邮箱的验证码。
- `webauthn`: 可选，WebAuthn 认证凭证。

### 校验规则

1. 验证因子要求：
   - 用户必须提供并成功验证至少一个已开启的双因素认证因子（TOTP、WebAuthn 或 邮件验证码）。
2. 更新逻辑：
   - 验证通过后，系统将更新用户的邮箱地址。
   - 更换邮箱后，用户的 `verified` 状态将被重置为 `false`，需要重新进行邮箱验证。
