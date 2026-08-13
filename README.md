# HA-Contract

本项目是 HA 系统的核心契约与服务集合，包含了认证服务、皮肤库服务以及代理服务。

## 项目结构

- [HRPAuth](./HRPAuth): 认证服务 (业务接口 + Yggdrasil 兼容)
- [HASkinLib](./HASkinLib): 皮肤库服务
- [WinnerProxy](./WinnerProxy): 代理服务
- [HRPAuth-WebUI](./HRPAuth-WebUI): 认证服务前端界面

## 文档中心 (单一事实源)

为了防止文档与实际项目偏移，本项目采用统一的 API 标准和文档管理机制：

### API 规范
- [API 标准说明](./docs/api/README.md): 包含统一响应格式、分页规范、基础路径等。
- [错误码定义](./docs/api/error-codes.md): 全局统一的错误码注册表。

### 接口定义 (OpenAPI)
- [HRPAuth 业务接口](./docs/api/openapi/hrpauth-business.yaml)
- [HASkinLib 业务接口](./docs/api/openapi/haskinlib-business.yaml)

### 开发与内部文档
- [HRPAuth 开发指南](./docs/dev/HRPAuth/): 包含配置、数据模型、迁移、Token 机制等。

## 归档说明

旧的、已漂移的文档已全部移至 [archive/docs/](./archive/docs/) 目录，不再作为开发参考。
