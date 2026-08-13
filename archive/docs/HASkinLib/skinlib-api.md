# HASkinLib API 文档

> 当前业务 API 的权威规范源已切换到根目录 [`docs/api/`](file:///home/lnb/HA-Contract/docs/api/README.md)。
> 本文档保留详细说明；接口路径、响应结构、错误码调整时，请优先更新 OpenAPI 与错误码注册表。

当前版本已开放以下接口：

- `POST /texture/upload`：上传材质并生成预览图
- `GET /texture/listpreview`：获取材质预览列表
- `GET /texture/preview/:preview_file`：直接访问预览图文件
- `GET /texture/pull/:hash`：根据哈希值直接拉取材质原文件
- `GET /profile/textures`：获取当前登录用户的材质列表（**[状态：暂时搁置]**）

说明：

- 当前项目会在上传时生成预览图文件，并在数据库中记录 `previewfile`
- 预览列表接口返回的是预览元数据，不直接返回图片二进制内容

## 1. 上传材质

**端点**

`POST /texture/upload`

**鉴权**

需要 `remember token`

支持以下三种传递方式：

- `Authorization: Bearer <token>`
- 表单字段 `remember_token`
- 表单字段 `rt` / `token`

**请求格式**

`multipart/form-data`

**请求参数**

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `uid` | integer | 是 | 上传目标用户 ID |
| `type` | string | 是 | 材质类型：`skin` 或 `cape` |
| `model` | string | 否 | 仅 `skin` 使用：`default` 或 `slim`；缺省为 `default` |
| `name` | string | 是 | 材质名称 |
| `description` | string | 否 | 材质描述 |
| `tags` | string | 否 | 标签，多个标签可用英文逗号、中文逗号、分号、换行分隔 |
| `file` | file | 是 | PNG 材质文件 |
| `texture` | file | 否 | `file` 的兼容字段名，二选一即可 |

**尺寸规则**

- `skin`：只允许 `64x32` 或 `64x64`
- `cape`：只允许 `64x32` 或 `22x17`
- `cape=22x17` 会在服务端自动标准化为 `64x32`

**上传副作用**

- 原始 PNG 材质文件会保存到 `textures.storage_dir`
- WebP 预览图会保存到 `textures.preview_storage_dir`
- `skin` 会生成 2D 全身预览图
- `cape` 会生成平铺正面预览图
- 元数据会写入：
  - `texture_list_skin`
  - `texture_list_cape`

**成功响应**

新建记录时返回 `201 Created`

```json
{
  "success": true,
  "message": "texture uploaded successfully",
  "data": {
    "id": 12,
    "hash": "8c9b0f...",
    "type": "skin",
    "uid": 10001,
    "model": "slim",
    "width": 64,
    "height": 64,
    "file_name": "my-skin.png",
    "preview_file": "8c9b0f..._skin.webp",
    "name": "Blue Girl",
    "description": "demo skin",
    "tags": "展示,蓝色",
    "created_at": "2026-08-02 12:00:00",
    "updated_at": "2026-08-02 12:00:00"
  }
}
```

已存在相同用户、相同材质文件时会更新元数据并返回 `200 OK`

```json
{
  "success": true,
  "message": "texture metadata updated successfully",
  "data": {
    "id": 12,
    "hash": "8c9b0f...",
    "type": "skin",
    "uid": 10001,
    "model": "default",
    "width": 64,
    "height": 64,
    "file_name": "my-skin.png",
    "preview_file": "8c9b0f..._skin.webp",
    "name": "Blue Girl v2",
    "description": "updated",
    "tags": "展示,新版",
    "created_at": "2026-08-02 12:00:00",
    "updated_at": "2026-08-02 12:30:00"
  }
}
```

`cape` 成功响应中不会包含 `model`

```json
{
  "success": true,
  "message": "texture uploaded successfully",
  "data": {
    "id": 20,
    "hash": "2a13de...",
    "type": "cape",
    "uid": 10001,
    "width": 64,
    "height": 32,
    "file_name": "my-cape.png",
    "preview_file": "2a13de..._cape.webp",
    "name": "Red Cape",
    "description": "",
    "tags": "披风,展示",
    "created_at": "2026-08-02 12:00:00",
    "updated_at": "2026-08-02 12:00:00"
  }
}
```

**失败响应**

| HTTP | message |
|---|---|
| `400` | `failed to parse upload form` |
| `400` | `uid must be a positive integer` |
| `400` | `file is required` |
| `400` | `texture type must be skin or cape` |
| `400` | `texture model must be default or slim` |
| `400` | `texture file must be a valid PNG image` |
| `400` | `skin texture must be 64x32 or 64x64` |
| `400` | `cape texture must be 64x32 or 22x17` |
| `400` | `texture name is required` |
| `401` | `remember token is required` |
| `401` | `invalid remember token` |
| `403` | `remember token does not match the requested uid` |
| `413` | `upload request is too large` |
| `413` | `texture file must be <n> bytes or smaller` |
| `429` | `upload rate limit exceeded, please try again later` |
| `500` | 其他服务端错误 |

**curl 示例**

```bash
curl -X POST "http://127.0.0.1:2701/texture/upload" \
  -H "Authorization: Bearer <remember_token>" \
  -F "uid=10001" \
  -F "type=skin" \
  -F "model=slim" \
  -F "name=Blue Girl" \
  -F "description=demo skin" \
  -F "tags=展示,蓝色" \
  -F "file=@skin.png"
```

## 2. 获取预览列表

**端点**

`GET /texture/listpreview`

**用途**

返回材质预览列表元数据，供前端做“皮肤库 / 披风库 / 预览列表页”使用。

**默认行为**

- 默认筛选：`all`
- 默认排序：`id desc`
- 默认每页：`16`
- 默认页码：`1`

其中：

- `all` 表示**所有 skin**
- 不包含 `cape`

**查询参数**

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---:|---|---|
| `type` | string | 否 | `all` | `all`、`default`、`slim`、`cape` |
| `order` | string | 否 | `desc` | `desc` 或 `asc` |
| `tag` | string | 否 | 空 | 按标签筛选；当前仅取第一个标签 |
| `page` | integer | 否 | `1` | 页码，从 `1` 开始 |

**筛选规则**

- `type=all`：所有 skin
- `type=default`：只看默认臂 skin
- `type=slim`：只看 slim skin
- `type=cape`：只看 cape

**分页规则**

- 每页固定返回 `16` 条
- `page=1` 返回第 `1-16` 条
- `page=2` 返回第 `17-32` 条
- 以此类推

**成功响应**

```json
{
  "success": true,
  "message": "texture preview list retrieved successfully",
  "data": {
    "items": [
      {
        "id": 12,
        "hash": "8c9b0f...",
        "type": "skin",
        "model": "slim",
        "uid": 10001,
        "width": 64,
        "height": 64,
        "file_name": "my-skin.png",
        "preview_file": "8c9b0f..._skin.webp",
        "name": "Blue Girl",
        "description": "demo skin",
        "tags": "展示,蓝色",
        "created_at": "2026-08-02 12:00:00",
        "updated_at": "2026-08-02 12:00:00"
      },
      {
        "id": 11,
        "hash": "6ab442...",
        "type": "skin",
        "model": "default",
        "uid": 10002,
        "width": 64,
        "height": 64,
        "file_name": "steve.png",
        "preview_file": "6ab442..._skin.webp",
        "name": "Steve Like",
        "description": "",
        "tags": "默认,展示",
        "created_at": "2026-08-02 11:00:00",
        "updated_at": "2026-08-02 11:00:00"
      }
    ],
    "filter": "all",
    "order": "desc",
    "tag": "",
    "page": 1,
    "page_size": 16,
    "total": 28,
    "has_more": true
  }
}
```

`type=cape` 时，列表项不会包含 `model`

```json
{
  "success": true,
  "message": "texture preview list retrieved successfully",
  "data": {
    "items": [
      {
        "id": 20,
        "hash": "2a13de...",
        "type": "cape",
        "uid": 10001,
        "width": 64,
        "height": 32,
        "file_name": "my-cape.png",
        "preview_file": "2a13de..._cape.webp",
        "name": "Red Cape",
        "description": "",
        "tags": "披风,展示",
        "created_at": "2026-08-02 12:00:00",
        "updated_at": "2026-08-02 12:00:00"
      }
    ],
    "filter": "cape",
    "order": "desc",
    "tag": "",
    "page": 1,
    "page_size": 16,
    "total": 1,
    "has_more": false
  }
}
```

**失败响应**

| HTTP | message |
|---|---|
| `400` | `type must be one of all, default, slim, cape` |
| `400` | `order must be asc or desc` |
| `400` | `page must be a positive integer` |
| `500` | `failed to query texture preview list` |

**curl 示例**

获取默认第一页：

```bash
curl "http://127.0.0.1:2701/texture/listpreview"
```

获取 slim 皮肤，按 `id asc` 排序，第 2 页：

```bash
curl "http://127.0.0.1:2701/texture/listpreview?type=slim&order=asc&page=2"
```

获取带 `展示` 标签的 cape：

```bash
curl "http://127.0.0.1:2701/texture/listpreview?type=cape&tag=%E5%B1%95%E7%A4%BA"
```

## 3. 相关配置

## 3. 获取预览图文件

**端点**

`GET /texture/preview/:preview_file`

**用途**

按 `preview_file` 直接返回预览图文件内容，适合前端 `<img>`、外链展示和静态资源引用。

**访问方式**

- 公开访问
- 不需要鉴权

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `preview_file` | string | 是 | 预览图文件名，必须是 `.webp` 文件名，例如 `8c9b0f..._skin.webp` |

**来源**

这个值可从以下接口返回中获得：

- `POST /texture/upload` 的 `data.preview_file`
- `GET /texture/listpreview` 的 `data.items[].preview_file`

**成功响应**

- HTTP `200 OK`
- `Content-Type: image/webp`
- `Cache-Control: public, max-age=86400`
- 响应体为预览图二进制内容

**失败响应**

| HTTP | message |
|---|---|
| `400` | `preview_file must be a valid webp file name` |
| `404` | `preview file not found` |
| `500` | `texture preview storage directory is not configured` |
| `500` | `failed to read preview file` |

**curl 示例**

```bash
curl "http://127.0.0.1:2701/texture/preview/8c9b0f..._skin.webp" --output preview.webp
```

**HTML 示例**

```html
<img src="http://127.0.0.1:2701/texture/preview/8c9b0f..._skin.webp" alt="skin preview">
```

## 4. 获取材质原文件

**端点**

`GET /texture/pull/:hash`

**用途**

按材质文件的 SHA-256 哈希值直接返回原始 PNG 材质文件内容，适合游戏客户端、外部渲染器或需要获取原始像素数据的场景。

**访问方式**

- 公开访问
- 不需要鉴权

**路径参数**

| 参数 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| `hash` | string | 是 | 材质文件的 SHA-256 哈希值，必须是 64 位十六进制字符串 |

**来源**

这个值可从以下接口返回中获得：

- `POST /texture/upload` 的 `data.hash`
- `GET /texture/listpreview` 的 `data.items[].hash`

**成功响应**

- HTTP `200 OK`
- `Content-Type: image/png`
- `Cache-Control: public, max-age=86400`
- 响应体为材质文件二进制内容

**失败响应**

| HTTP | message |
|---|---|
| `400` | `texture hash must be a valid 64-character hex string` |
| `404` | `texture file not found` |
| `500` | `texture storage directory is not configured` |
| `500` | `failed to read texture file` |

**curl 示例**

```bash
curl "http://127.0.0.1:2701/texture/pull/e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" --output texture.png
```

## 5. 获取个人材质列表

> **注意：此接口当前状态为 [暂时搁置]**。
> 后端已完成初步实现，但根据开发计划，该功能目前不对前端开放或暂不启用。

**端点**

`GET /profile/textures`

**鉴权**

需要 `remember token` (与上传接口一致)

**查询参数**

| 参数 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---:|---|---|
| `type` | string | 否 | `all` | `all`, `skin`, `cape` |

**成功响应**

```json
{
  "success": true,
  "message": "profile textures retrieved successfully",
  "data": {
    "uid": 10001,
    "items": [
      {
        "id": 12,
        "hash": "8c9b0f...",
        "type": "skin",
        "model": "slim",
        "width": 64,
        "height": 64,
        "file_name": "my-skin.png",
        "preview_file": "8c9b0f..._skin.webp",
        "name": "Blue Girl",
        "description": "demo skin",
        "tags": "展示,蓝色",
        "created_at": "2026-08-02 12:00:00",
        "updated_at": "2026-08-02 12:00:00"
      }
    ]
  }
}
```

**失败响应**

| HTTP | message |
|---|---|
| `401` | `remember token is required` |
| `401` | `invalid remember token` |

## 6. 相关配置

配置文件中的 `textures` 段与这两组接口直接相关：

```yaml
textures:
  storage_dir: ./data/textures
  preview_storage_dir: ./data/previews
  max_upload_bytes: 2097152
  max_request_bytes: 2359296
  rate_limit_per_minute: 5
  rate_limit_window_seconds: 60
```

说明：

- `storage_dir`：原始 PNG 材质文件存储目录
- `preview_storage_dir`：生成后的 WebP 预览图存储目录
- `max_upload_bytes`：单文件大小上限
- `max_request_bytes`：整个上传请求大小上限
- `rate_limit_per_minute` / `rate_limit_window_seconds`：上传限流配置

## 6. 当前未开放的能力

当前版本还**没有**这些接口：

- 材质详情接口
- 材质删除接口
- 材质编辑接口

如果后续开放，建议延续当前命名风格，例如：

- `GET /texture/detail/:id`
- `POST /texture/delete`
- `POST /texture/update`
