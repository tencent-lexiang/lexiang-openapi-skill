---
name: lexiang
description: 腾讯乐享知识库 API 集成。提供团队、知识库、知识节点、在线文档块的完整 CRUD 操作，以及通讯录管理、AI 搜索/问答、文件上传、任务管理等功能。此 skill 适用于需要通过 API 管理乐享知识库内容（创建/查询/编辑文档、搜索知识、管理团队权限等）的场景。
homepage: https://lexiang.tencent.com/wiki/api/?event_type=link_exchange&event_channel=skill&event_detail=github
metadata: {"openclaw":{"emoji":"📚"}}
allowed-tools: 
disable: false
---

# 腾讯乐享知识库 API

腾讯乐享知识库是企业级知识管理平台，提供知识库、团队协作、文档管理、AI助手等功能。

## 数据模型

- **Team（团队）**：顶级组织单元，一个团队下可以有多个知识库（Space）
- **Space（知识库）**：知识的容器，属于某个团队，包含多个条目（Entry），有 `root_entry_id` 作为根节点
- **Entry（条目/知识）**：知识库中的内容单元，可以是页面（page）、文件夹（folder）或文件（file），支持树形结构（parent_id）
- **File（文件）**：附件类型的条目，如 PDF、Word、图片等

层级关系：`Team -> Space -> Entry（树形结构，root_entry_id 为根）`

## URL 规则

生成知识库链接时，必须使用企业专属域名（如 `csig.lexiangla.com`），**禁止使用** `https://lexiang.tencent.com/wiki/{id}` 格式。

| 资源类型 | URL 格式 |
|---------|----------|
| 团队首页 | `https://{domain}/t/{team_id}/spaces` |
| 知识库 | `https://{domain}/spaces/{space_id}` |
| 知识条目 | `https://{domain}/pages/{entry_id}` |

优先使用 API 响应中的 `links` 字段；如果 API 未返回完整链接，根据上述规则拼接。

## 凭证配置

### 所需凭证
| 凭证 | 说明 | 是否必需 |
|------|------|---------|
| `LEXIANG_APP_KEY` | 乐享开放平台应用 Key | 是（获取 Token） |
| `LEXIANG_APP_SECRET` | 乐享开放平台应用 Secret | 是（获取 Token） |
| `LEXIANG_STAFF_ID` | 员工身份标识 | 是（写操作必需） |

### 凭证加载优先级
1. **缓存的有效 Token**（`~/.config/lexiang/token`，2 小时有效期内直接复用，无需 app_key）
2. **环境变量**（`LEXIANG_APP_KEY` / `LEXIANG_APP_SECRET`）
3. **openclaw.json**（`~/.openclaw/openclaw.json` 的 `skills.entries.lexiang.env` 字段）
4. **credentials 文件**（`~/.config/lexiang/credentials`，JSON 格式）
5. **交互式引导**（stdin 可用时自动引导用户输入，验证后持久化保存到 credentials 文件）

### 初始化（加载凭证 + 获取 Token）

执行 `scripts/init.sh` 脚本自动处理凭证加载和 Token 获取：
```bash
source scripts/init.sh
# 之后可使用 $LEXIANG_TOKEN 和 $LEXIANG_STAFF_ID
```

**首次使用时**，如果没有任何已配置的凭证，脚本会自动引导用户在终端中输入 App Key、App Secret 和 Staff ID，验证通过后自动保存到 `~/.config/lexiang/credentials`，后续无需重复输入。

**非交互式环境（如 CI/CD）**，脚本会输出清晰的配置提示和格式示例，方便用户手动创建配置文件。

Token 有效期 2 小时，获取频率限制 20次/10分钟。脚本会自动缓存到 `~/.config/lexiang/token`。

### 手动配置 credentials 文件
```bash
mkdir -p ~/.config/lexiang
cat > ~/.config/lexiang/credentials << 'EOF'
{
  "app_key": "your_app_key",
  "app_secret": "your_app_secret",
  "staff_id": "your_staff_id"
}
EOF
chmod 600 ~/.config/lexiang/credentials
```

## API 调用基础

### 请求头
```bash
# 读操作
-H "Authorization: Bearer $LEXIANG_TOKEN"
-H "Content-Type: application/json; charset=utf-8"

# 写操作（额外需要）
-H "x-staff-id: $LEXIANG_STAFF_ID"
```

### 需要 x-staff-id 的接口
所有写操作（创建/更新/删除）、AI 搜索/问答、权限设置

### 创建知识节点的格式
使用 **JSON:API 规范格式**，通过 `relationships` 指定所属知识库和父节点：
```json
{
  "data": {
    "type": "kb_entry",
    "attributes": {"entry_type": "page", "name": "标题"},
    "relationships": {
      "space": {"data": {"type": "kb_space", "id": "SPACE_ID"}},
      "parent_entry": {"data": {"type": "kb_entry", "id": "PARENT_ID"}}
    }
  }
}
```

### 通用限制
- 频率限制：大部分接口 3000次/分钟
- 权限要求：需在 AppKey 的授权范围内

## 核心工作流

### 1. 解析乐享 URL

当用户提供乐享链接时，可通过 `scripts/parse_url.sh` 自动解析并获取 API 所需的详细信息：

```bash
source scripts/init.sh
source scripts/parse_url.sh "https://lexiangla.com/spaces/{space_id}?company_from=xxx"
# 之后可使用以下环境变量：
# $LEXIANG_PARSED_TYPE       - 资源类型: space / entry / team
# $LEXIANG_PARSED_ID         - 资源 ID
# $LEXIANG_PARSED_SPACE_ID   - 知识库 ID
# $LEXIANG_PARSED_TEAM_ID    - 团队 ID
# $LEXIANG_PARSED_NAME       - 资源名称
# $LEXIANG_PARSED_ROOT_ENTRY_ID - 根节点 ID
```

支持的 URL 格式：
| URL 格式 | 解析结果 |
|----------|---------|
| `https://lexiangla.com/spaces/{space_id}?...` | 知识库信息（含 root_entry_id、team_id） |
| `https://lexiangla.com/pages/{entry_id}?...` | 文档信息（自动反查所属知识库和团队） |
| `https://lexiangla.com/t/{team_id}/spaces` | 团队信息 |

对于 entry 类型 URL，脚本会通过 parent 链向上查找 root entry，再通过 team → spaces 反查知识库。查找结果自动缓存到 `~/.config/lexiang/space_cache.json`。

### 2. 查询知识

```bash
# 获取团队列表
curl "https://lxapi.lexiangla.com/cgi-bin/v1/kb/teams?limit=20" \
  -H "Authorization: Bearer $LEXIANG_TOKEN"

# 获取知识库列表
curl "https://lxapi.lexiangla.com/cgi-bin/v1/kb/spaces?team_id={team_id}&limit=20" \
  -H "Authorization: Bearer $LEXIANG_TOKEN"

# 获取知识列表
curl "https://lxapi.lexiangla.com/cgi-bin/v1/kb/entries?space_id={space_id}&limit=20" \
  -H "Authorization: Bearer $LEXIANG_TOKEN"

# 获取文档内容（HTML 格式）
curl "https://lxapi.lexiangla.com/cgi-bin/v1/kb/entries/{entry_id}/content?content_type=html" \
  -H "Authorization: Bearer $LEXIANG_TOKEN"
```

### 3. 创建文档

两种方式对比：

| 方式 | 优点 | 推荐场景 |
|------|------|---------|
| **上传 Markdown 文件** | 简单高效、格式完整保留 | 批量创建文档、Markdown 内容发布 |
| **块接口 (page + blocks)** | 精确控制格式、可实时编辑 | 需要程序化编辑文档内容 |

**推荐方式：上传 Markdown 文件**

使用 `scripts/upload_file.sh` 脚本：
```bash
source scripts/init.sh
bash scripts/upload_file.sh ./document.md SPACE_ID [PARENT_ENTRY_ID]
```

### 4. AI 搜索与问答

```bash
# AI 搜索
curl -X POST "https://lxapi.lexiangla.com/cgi-bin/v1/ai/search" \
  -H "Authorization: Bearer $LEXIANG_TOKEN" \
  -H "x-staff-id: $LEXIANG_STAFF_ID" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"query": "搜索关键词"}'

# AI 问答（research=true 使用专业研究模式）
curl -X POST "https://lxapi.lexiangla.com/cgi-bin/v1/ai/qa" \
  -H "Authorization: Bearer $LEXIANG_TOKEN" \
  -H "x-staff-id: $LEXIANG_STAFF_ID" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"query": "问题内容", "research": false}'
```

## 使用块接口的关键注意事项

对于需要使用在线文档块接口的场景，注意以下要点（详细示例见 `references/api-blocks.md`）：

1. **新建文档不传 parent_block_id**：直接插入内容到页面根节点
2. **列表块字段名不同于类型名**：`bulleted_list` 用 `bulleted` 字段，`numbered_list` 用 `numbered` 字段
3. **标题块字段需匹配**：`h1` 用 `heading1`，`h2` 用 `heading2`，不是 `text`
4. **嵌套块必须使用 children 和 block_id**：表格/引用/高亮块通过临时 ID 建立父子关系
5. **不支持嵌套的类型**：`h1`-`h5`、`code`、`image`、`attachment`、`video`、`divider`、`mermaid`、`plantuml`
6. **image 块不支持通过 API 创建**：blocks API 不支持 `image` block_type，暂无法通过 API 在文档中插入图片。上传含图片引用的 MD 文件时，本地图片路径将保持原样（待 API 支持后更新）
7. **文件夹类型用 `folder`**：创建文件夹时 `entry_type` 必须使用 `folder`（不是 `directory`）
8. **file 类型 name 必须带后缀**：如 `文档标题.md`、`image.png`

## 常见错误排查

| 错误信息 | 原因 | 解决方案 |
|----------|------|---------|
| `必须指定员工账号` | 缺少 x-staff-id | 添加 `-H "x-staff-id: $LEXIANG_STAFF_ID"` |
| `data.attributes.entry_type 不能为空` | 请求格式错误 | 使用 JSON:API 规范格式 |
| `entry_type` 值无效 | 使用了 `directory` | 改为 `folder` |
| `content_type 不能为空` | 缺少参数 | 添加 `?content_type=html` |
| 列表内容为空 | 字段名错误 | 无序列表用 `bulleted`，有序列表用 `numbered` |
| 嵌套块创建失败 | 缺少关联 | 确保 `children` + `block_id` 配对 |
| file name 缺少后缀 | name 字段无扩展名 | 添加 `.md`、`.png` 等后缀 |
| 上传接口 404 | 旧版路径 | 使用 `/v1/kb/files/upload-params` |

## 详细 API 参考

按需查阅以下参考文件获取完整的接口文档：

| 文件 | 内容 | 搜索关键词 |
|------|------|-----------|
| `references/api-contact.md` | 通讯录管理（成员/部门 CRUD） | contact, user, department, staff |
| `references/api-team-space.md` | 团队与知识库管理 | team, space, 权限, subject |
| `references/api-entries.md` | 知识节点 CRUD 与权限 | entry, entries, page, directory, file |
| `references/api-blocks.md` | 在线文档块接口（创建/编辑块内容） | block, descendant, paragraph, table, list |
| `references/api-other.md` | 任务/属性/日志/AI/素材/导出/SSO | task, property, log, ai, search, qa, upload, sso |

## HTTP 错误码

| 状态码 | 说明 |
|--------|------|
| 200/201 | 成功 |
| 204 | 删除成功 |
| 400 | 请求参数错误 |
| 401 | Token 无效或过期 |
| 403 | 无权限 |
| 404 | 资源不存在 |
| 429 | 超出频率限制 |
