# HA Business API Standard

它是 HA 业务 API 的单一事实源。所有旧文档已废弃并归档。
当前只覆盖：

- `HRPAuth` 业务接口
- `HASkinLib` 业务接口

不覆盖：

- `Yggdrasil` 兼容接口
- `WinnerProxy` 代理逻辑

## 统一约束

1. OpenAPI 是路径与响应结构的源头。
2. 错误码使用稳定的 `lower_snake_case`。
3. 业务错误统一返回：

```json
{
  "success": false,
  "message": "Invalid email",
  "code": "invalid_email",
  "error": "invalid_email",
  "meta": {
    "request_id": "ab12cd34"
  }
}
```

说明：

- `code` 是规范字段。
- `error` 是兼容别名，便于保留已有调用方。
- `request_id` 用于排查日志与用户反馈。

4. 业务成功响应统一返回：

```json
{
  "success": true,
  "message": "Login successful",
  "data": {
    "token": "..."
  },
  "meta": {
    "request_id": "ab12cd34"
  }
}
```

过渡期内，部分成功字段会保留顶层镜像，避免旧前端立即失效；新增调用方一律读取 `data`。

## 文件说明

- `openapi/hrpauth-business.yaml`: HRPAuth 业务接口规范
- `openapi/haskinlib-business.yaml`: HASkinLib 业务接口规范
- `error-codes.md`: 统一错误码注册表

## 防漂移

提交前运行：

```bash
./scripts/check-business-api-drift.sh
```

它会检查业务路由是否全部出现在 OpenAPI 规范中。
