<div align="center">
  <h1>HA-Contract</h1>
  <p><strong>统一契约，让集成有据可依。</strong></p>
  <p><a href="./README.md">English</a></p>
</div>

HA-Contract 为 HA 服务集成者提供版本化 API 架构、OpenAPI 定义，以及统一的响应与错误约定。它用实现方和消费方都能引用的明确协议，取代逆向推导。

## 为什么选择 HA-Contract

- **基于证据集成。** OpenAPI 定义描述服务接口，无需逐一走读实现代码。
- **响应更可预期。** 共享的响应与错误约定，减少跨服务特殊处理。
- **机械检查路由漂移。** METHOD + path 检查双向比对已注册路由与契约。
- **知识保持锚定。** 机械检查帮助发现已与所引用代码不一致的文档引用。

## 进一步了解

- [GitHub 上的 HA-Contract](https://github.com/CoreMatch/HA-Contract) — 规范仓库
- [OpenAPI 定义](docs/api/openapi/) — 版本化服务契约
- [业务 API 漂移检查](scripts/check-business-api-drift.sh) — 路由与契约比对
- [HA Wiki](https://wiki.mcnb.dev/) — 部署与开发文档

## 边界

HA-Contract 不是运行时认证层，也不是所有 HA 文档的权威来源。

## 许可证

本仓库未声明许可证。
