# HA Business API Standard

它是 HA 业务 API 的单一事实源，同时记录了本项目对外部协议的内部实现逻辑。

## 文档定位

- **本目录 (`docs/api/`, `docs/dev/`)**: 展示本项目**是如何内部实现**这些 API 的（包括路由映射、内部处理逻辑、业务扩展）。
- **参考目录 ([`docs/references/`](../references/))**: 展示**协议标准本身**。本项目必须遵循这些标准。

## 外部协议遵循 (实现层)

本项目实现了以下外部标准。详细的协议定义请参考 [docs/references/](../references/)。

1. **Yggdrasil API / authlib-injector**: Minecraft 官方认证协议及其注入器兼容层实现。
2. **CustomSkinAPI**: 皮肤库标准接口实现。

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
