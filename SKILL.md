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

生成知识库链接时，**必须使用 `lexiangla.com` 域名 + `company_from` 参数**，否则链接无法打开。

**禁止使用**的格式：
- `https://csig.lexiangla.com/pages/{id}`（缺少 company_from，无法打开）
- `https://lexiang.tencent.com/wiki/{id}`（内部地址，外部无法访问）

**正确的链接格式**：

| 资源类型 | URL 格式 |
|---------|----------|
| 团队首页 | `https://lexiangla.com/t/{team_id}/spaces?company_from={company_from}` |
| 知识库 | `https://lexiangla.com/spaces/{space_id}?company_from={company_from}` |
| 知识条目 | `https://lexiangla.com/pages/{entry_id}?company_from={company_from}` |

> `company_from` 参数是企业标识，不同企业值不同。可从用户之前分享的乐享链接中提取，或在首次使用时询问用户。

优先使用 API 响应中的 `links` 字段；如果 API 未返回完整链接，根据上述规则拼接（**不要忘记 `company_from` 参数**）。

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

三种方式对比：

| 方式 | 优点 | 缺点 | 推荐场景 |
|------|------|------|---------|
| **上传 Markdown 文件** | 简单高效 | 创建的是 file 类型，无法在线编辑 | 存档、批量导入 |
| **Markdown → 在线文档** | 保留格式 + 可在线编辑 | 需要转换步骤 | **用户要求可编辑的在线文档时首选** |
| **块接口手动构建** | 精确控制每个块 | 复杂、易出错 | 程序化修改已有文档内容 |

**方式 A：上传 Markdown 文件**（创建为 file 类型，不可在线编辑）

```bash
source scripts/init.sh
bash scripts/upload_file.sh ./document.md SPACE_ID [PARENT_ENTRY_ID]
```

**方式 B：Markdown → 在线文档**（创建为 page 类型，可在线编辑）⭐ 推荐

使用 `scripts/md_to_page.py` 脚本，自动将 Markdown 解析为 blocks 写入在线文档：

```bash
source scripts/init.sh

# 创建新 page 并写入
python3 scripts/md_to_page.py ./document.md --space-id SPACE_ID --parent-id PARENT_ID --name "文档标题"

# 写入已有 page
python3 scripts/md_to_page.py ./document.md --entry-id ENTRY_ID

# 追加模式（不清空已有内容）
python3 scripts/md_to_page.py ./document.md --entry-id ENTRY_ID --append
```

脚本特性：
- 自动解析标题、段落、列表、代码块、引用块、分隔线等
- **引用块(>)自动转为 callout 高亮块**（API 不支持 quote，改用 callout 模拟）
- 内联样式：加粗、斜体、行内代码、链接
- 自动分批提交（每批 ≤20 个顶层块），避免请求过大
- 失败自动逐块重试
- **更新已有页面时默认先清空再写入**（非 `--append` 模式），避免内容重复

> **注意**：image 块不支持通过 API 创建，Markdown 中的图片引用会被忽略。如需图片，请在在线文档中手动插入。

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
4. **嵌套块的 `children` 和 `block_id` 只在块自身声明，不要放到 payload 顶层**：嵌套块（callout/table/toggle 等）通过块自身的 `block_id` + `children` 字段建立父子关系。**不要**在 payload 顶层传 `children` 参数——payload 顶层的 `children` 会让 API 将这些块提升为页面根的第一批子节点，打乱 `descendant` 数组中的顺序，导致嵌套块跑到页面开头（而非按文档中的实际位置渲染）
5. **quote 不在 API 支持列表中**：API 的合法 `block_type` 不包含 `quote`。Markdown 引用块（`>`）应转换为 `callout`（高亮块）模拟。`scripts/md_to_page.py` 已自动处理此转换
6. **不支持嵌套的类型**：`h1`-`h5`、`code`、`image`、`attachment`、`video`、`divider`、`mermaid`、`plantuml`
7. **image 块不支持通过 API 创建**：blocks API 不支持 `image` block_type，暂无法通过 API 在文档中插入图片。上传含图片引用的 MD 文件时，本地图片路径将保持原样（待 API 支持后更新）
8. **文件夹类型用 `folder`**：创建文件夹时 `entry_type` 必须使用 `folder`（不是 `directory`）
9. **file 类型 name 必须带后缀**：如 `文档标题.md`、`image.png`
10. **块数较多时必须分批提交**：建议每批 ≤ 20 个顶层块。`scripts/md_to_page.py` 已内置分批逻辑
11. **`descendant` 接口是追加语义，不是覆盖**：`POST blocks/descendant` 会在页面末尾追加新块，**不会**清除已有内容。更新已有页面时必须先获取所有块 ID 并逐个删除（`DELETE blocks/{block_id}`），否则每次写入都会产生重复内容。`scripts/md_to_page.py` 在非 `--append` 模式下已内置清空逻辑

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
| 属性设置静默失败 | value 传了选项 key 而非文本值 | value 数组中传选项的**显示文本**（如 `"互联网参考"`），不是 key（如 `c0jp3b6qyh`）。传 key 返回 200 但值为空 |
| 属性设置 400 错误 | 请求体格式不对 | 必须使用 JSON:API 格式：`{"data":{"type":"kb_entry","attributes":{"属性ID":{"value":["选项文本"]}}}}` |
| PATCH 重命名 404 | 文件类型条目不支持 PATCH 重命名 | file 类型条目创建后名称无法通过 API 修改，需在上传时就使用正确的文件名（`upload_file.sh` 会用文件的本地文件名） |
| 页面内容出现重复 | `POST blocks/descendant` 是追加语义 | 更新页面前必须先清空已有块（GET children → DELETE 逐个删除），或使用 `md_to_page.py` 的默认模式（自动清空后写入）。只有明确追加时才用 `--append` |
| 嵌套块（callout/table）跑到页面开头 | payload 顶层传了 `children` 参数 | **不要**在 payload 顶层传 `children`。嵌套块的父子关系只通过块自身的 `block_id` + `children` 建立。payload 顶层的 `children` 会让 API 将声明的块提升为页面根的第一批子节点，打乱顺序 |

## 经验案例

### 知识库跨库迁移

**场景**：将一个知识库（Space）的全部内容（文件夹结构 + 文件 + 在线文档）迁移到另一个知识库。

**核心挑战**：乐享 API **没有**原生的 move/copy 接口，必须手动遍历 → 重建目录 → 下载/上传。

**迁移流程**：

1. **遍历源知识库目录结构**：`GET /kb/entries?space_id=SOURCE&limit=50`，逐层获取 folder 和子条目
2. **在目标知识库创建同名文件夹**：`POST /kb/entries`，`entry_type: "folder"`
3. **按条目类型分别处理**：
   - `file` 类型：从 `data.links.download` 获取下载链接 → 下载到本地 → 通过三步上传流程（获取凭证 → 上传 COS → 创建条目）重新上传到目标文件夹
   - `page` 类型：通过 content API 获取 HTML → 解析为 blocks → 写入目标页面

**踩坑记录**：

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| **page 内容为空** | 创建 page 条目后没有写入内容块。`POST /kb/entries` 只创建空页面壳，内容需要额外通过 blocks API 写入 | 用 `GET /kb/entries/{id}/content?content_type=html` 获取源页面 HTML，解析后用 `POST /kb/page/entries/{id}/blocks/descendant` 写入目标页面 |
| **上传凭证解析错误** | `Bucket`/`Region` 在响应的 `options` 层级，而非 `object` 层级；`key`/`state`/`auth` 在 `object` 层级 | 上传凭证响应结构：`options.Bucket`、`options.Region`、`object.key`、`object.state`、`object.auth.Authorization`、`object.auth.XCosSecurityToken` |
| **文件下载链接取错** | 文件下载链接在 `data.links.download`，而非 `included` 中 | 优先从 `data.links.download` 获取，`included` 中的 `kb_file` 链接作为备选 |
| **文件名缺少扩展名** | 条目 `name` 字段不一定包含扩展名 | 从下载 URL 的路径中解析扩展名（`os.path.splitext(urlparse(url).path)[1]`），补到文件名末尾 |

**HTML → Blocks 转换要点**：

乐享在线文档的 HTML 使用 `lx-*` 类名标识块类型（如 `<p class="lx-p">`、`<h2 class="lx-h2">`）。转换时：
- 段落（`p`）→ `{"block_type": "p", "text": {"elements": [...]}}`
- 标题（`h1`-`h5`）→ `{"block_type": "h2", "heading2": {"elements": [...]}}`（注意字段名是 `heading{N}` 不是 `text`）
- 内联样式通过 `<b>`/`<i>`/`<u>`/`<span style="...">` 映射到 `text_style`
- 空段落可跳过不写入
- 块数较多时分批写入（建议每批 ≤ 20 个块）

### 自定义属性设置

**场景**：为知识条目设置自定义属性（如"内容性质"、"内容来源"），便于 Agent 按类型过滤检索。

**正确的 API 调用方式**：

```bash
# 获取条目当前属性值
curl "https://lxapi.lexiangla.com/cgi-bin/v1/kb/entries/{entry_id}/properties/values" \
  -H "Authorization: Bearer $LEXIANG_TOKEN"

# 设置属性值（必须使用 JSON:API 格式）
curl -X PUT "https://lxapi.lexiangla.com/cgi-bin/v1/kb/entries/{entry_id}/properties/values" \
  -H "Authorization: Bearer $LEXIANG_TOKEN" \
  -H "x-staff-id: $LEXIANG_STAFF_ID" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"data":{"type":"kb_entry","attributes":{"属性ID":{"value":["选项显示文本"]}}}}'
```

**踩坑记录**：

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| PUT 返回 200 但属性值为空 | `value` 传了选项的 key（如 `c0jp3b6qyh`） | 改为传选项的**显示文本**（如 `"互联网参考"`）|
| PUT 返回 400 `data/data.attributes 不能为空` | 请求体用了 `{"properties": [...]}` 格式 | 必须用 JSON:API 格式：`{"data":{"type":"kb_entry","attributes":{...}}}` |
| 属性 ID 和选项 key 的区别 | 属性 ID 是属性本身的 UUID，选项 key 是选项的标识符 | GET `/kb/properties/{id}` 获取属性详情和选项列表 |

### 在线文档更新导致内容重复（严重）

**场景**：使用 `md_to_page.py --entry-id` 更新已有在线文档时，页面内容出现 2~4 倍的重复。

**根因分析**：

Blocks API 的 `POST /kb/page/entries/{id}/blocks/descendant` 是**追加**语义——它不会覆盖已有内容，而是在页面末尾追加新块。脚本最初没有清空逻辑，每次运行都会向已有页面追加完整内容。再加上首次写入部分失败后重试，最终导致页面累积了 580 个块（正常应为 ~147 个）。

**问题暴露的时间线**：
1. 第一次写入：部分块因 `quote` 类型不被支持而失败 → 修复后重试
2. 第二次写入：全部成功，但此时内容已是两份
3. 后续调试中又触发了几次写入 → 内容膨胀到 4 倍

**修复措施**：

1. **`md_to_page.py` 新增 `clear_page_blocks()`**：非 `--append` 模式下，写入前先删除页面所有已有根块
2. **使用并行删除**（`ThreadPoolExecutor(max_workers=10)`）+ 多轮循环，确保大量块也能在合理时间内清空
3. **API 返回格式与预期不同**（踩坑见下表）

**踩坑记录**：

| 问题 | 原因 | 解决方案 |
|------|------|---------|
| **更新已有页面导致内容重复** | Blocks `descendant` API 是追加语义，不会覆盖已有内容 | 更新前先调用 `GET blocks/children` 获取所有块 ID，逐个 `DELETE` 清空，再写入新内容。`--append` 参数跳过清空 |
| **清空时 `str has no attribute get`** | `blocks/children` API 返回 `{"data": {"blocks": [...]}}` 而非 `{"data": [...]}` | 用 `resp["data"]["blocks"]` 取块列表，不是 `resp["data"]` |
| **块 ID 字段名错误** | 块的唯一标识字段是 `block_id`，不是 `id` | 删除时用 `block["block_id"]` |
| **逐个删除太慢（580 块超时）** | 串行 HTTP 请求，每个约 200ms | 改用 `ThreadPoolExecutor(max_workers=10)` 并行删除，循环多轮直到清空 |
| **嵌套块（callout）跑到页面最开头** | payload 顶层传了 `children: ["callout-xxx"]`，API 将其提升为页面根的第一批子节点 | **不要**在 payload 顶层传 `children`。嵌套块的父子关系只通过块自身的 `block_id` + `children` 建立即可，API 会按 `descendant` 数组顺序渲染 |

**核心教训**：

> **对远程 API 的操作必须是幂等的**。写入内容前，如果不是追加模式，必须先确认目标是否为空——不能假设 API 会自动覆盖。这类问题在本地文件操作中不会出现（`write` 默认覆盖），但在 API 场景中极其常见。
>
> **首次集成新 API 时，必须验证**：该接口是"覆盖"还是"追加"语义？失败重试是否会产生副作用？
>
> **API 参数的语义不能想当然**。`descendant` 请求体中的 `children` 参数看似用于声明嵌套块关系，但实际含义是"**指定页面根节点的第一级子块**"——它会改变块的渲染位置。嵌套块（callout/table）的父子关系应该只在块自身声明（`block_id` + `children`），不需要也不应该在 payload 顶层重复声明。**遇到 API 行为不符合预期时，先做小规模对照实验（传/不传某参数），再应用到完整数据**。

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
