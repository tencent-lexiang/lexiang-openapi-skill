# 在线文档块接口 API

> **文档参考**: https://lexiang.tencent.com/wiki/api/15016.html

## 创建嵌套块

**接口地址**: `POST /cgi-bin/v1/kb/page/entries/{entry_id}/blocks/descendant`

**请求头**:
- `Authorization: Bearer {access_token}`
- `x-staff-id`: 成员账号（作为创建者）
- `Content-Type: application/json; charset=utf-8`

**核心参数说明**:
| 参数 | 类型 | 必须 | 说明 |
|------|------|------|------|
| parent_block_id | String | 否 | 父块 ID。**留空则插入到页面根节点** |
| index | Int | 否 | 插入位置索引（从 0 开始） |
| children | Array | 见说明 | ⚠️ **payload 顶层的 children 表示"页面根节点的第一级子块"，会将声明的块提升到页面开头**。嵌套块的父子关系应只在块自身的 `children` 字段声明（配合 `block_id`），**不要**在 payload 顶层传 `children`，否则嵌套块渲染位置会错乱 |
| descendant | Array | 是 | 所有待创建块的数组 |

> **提示**：对于新建的空白文档，**不传 parent_block_id** 即可直接插入内容到页面根节点。

**descendant 数组对象结构**:
| 参数 | 说明 |
|------|------|
| block_id | 嵌套块模式必填，自定义临时 ID（字符串），用于建立父子关系 |
| block_type | 块类型（见下表） |
| children | 该块包含的子块临时 ID 列表 |
| [内容字段] | 根据 block_type 不同使用不同字段 |

**块类型**:

| 类型 | 说明 | 嵌套 | 内容字段 |
|------|------|------|---------|
| `p` | 段落 | 否 | `text` |
| `h1`-`h5` | 标题 | 否 | `heading1`-`heading5`（注意不是 `text`） |
| `code` | 代码块 | 否 | `code` (含 `language`, `content`) |
| `quote` | 引用块 | - | ⚠️ **API 实际不支持**，不在合法 block_type 列表中。用 `callout` 替代 |
| `callout` | 高亮块 | **是** | `callout` (含 `background_color`, `icon`) |
| `toggle` | 折叠块 | **是** | - |
| `table` | 表格 | **是** | `table` (含 `row_size`, `column_size` 等) |
| `table_cell` | 表格单元格 | **是** | `table_cell` (含 `align` 等) |
| `task` | 任务块 | 否 | `task` (含 `name`, `done` 等) |
| `bulleted_list` | 无序列表 | 否 | `bulleted`（注意不是 `bulleted_list`） |
| `numbered_list` | 有序列表 | 否 | `numbered`（注意不是 `numbered_list`） |
| `divider` | 分隔线 | 否 | 无 |
| `column_list` | 分栏 | **是** | - |
| `column` | 列 | **是** | - |
| `mermaid` | Mermaid 图 | 否 | - |
| `plantuml` | PlantUML 图 | 否 | - |

**不支持嵌套子块的类型**: `h1`-`h5`, `code`, `image`, `attachment`, `video`, `divider`, `mermaid`, `plantuml`

> ⚠️ **嵌套块**（quote, callout, toggle, table 等）必须使用 `children` + `block_id` 的方式创建，不能只传一个扁平的 block。详见下方引用块、高亮块、表格示例。

---

## 示例

### 简单段落
```bash
curl -X POST "https://lxapi.lexiangla.com/cgi-bin/v1/kb/page/entries/{entry_id}/blocks/descendant" \
  -H "Authorization: Bearer $LEXIANG_TOKEN" \
  -H "x-staff-id: $LEXIANG_STAFF_ID" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{
    "descendant": [
      {
        "block_type": "p",
        "text": {
          "elements": [{"text_run": {"content": "这是一段普通文本"}}]
        }
      }
    ]
  }'
```

### 带样式的标题
```bash
{
  "block_type": "h2",
  "heading2": {
    "elements": [
      {"text_run": {"content": "普通文本"}},
      {"text_run": {"content": "加粗", "text_style": {"bold": true}}},
      {"text_run": {"content": "下划线", "text_style": {"underline": true}}}
    ]
  }
}
```

**text_style 支持的样式**: bold, italic, underline, strikethrough, code, color, background_color

### 任务块
```json
{
  "block_type": "task",
  "task": {
    "name": "完成 API 文档更新",
    "done": false,
    "due_at": {"date": "2025-12-31", "time": "18:00:00"},
    "assignees": [{"staff_uuid": "员工UUID"}]
  }
}
```

### 代码块
```json
{
  "block_type": "code",
  "code": {
    "language": "python",
    "content": "def hello():\n    print(\"Hello, World!\")"
  }
}
```

### 引用块（嵌套结构）

> ⚠️ API 不支持 `quote` block_type，改用 `callout` 模拟。见下方高亮块示例。

### 高亮块 (Callout)

> ⚠️ **不要**在 payload 顶层传 `children`，否则 callout 会被提升到页面开头。嵌套关系只在块自身声明即可。

```json
{
  "descendant": [
    {"block_type": "p", "text": {"elements": [{"text_run": {"content": "callout 前的段落"}}]}},
    {
      "block_id": "callout-1",
      "block_type": "callout",
      "callout": {"background_color": "#FFF3E0", "icon": "⚠️"},
      "children": ["callout-text-1"]
    },
    {
      "block_id": "callout-text-1",
      "block_type": "p",
      "text": {"elements": [{"text_run": {"content": "callout 内容"}}]}
    },
    {"block_type": "p", "text": {"elements": [{"text_run": {"content": "callout 后的段落"}}]}}
  ]
}
```

> 注意：嵌套块的父子关系通过块自身的 `block_id` + `children` 建立。API 按 `descendant` 数组顺序渲染，callout 会正确出现在两个段落之间。

### 无序列表
```json
{
  "block_type": "bulleted_list",
  "bulleted": {
    "elements": [{"text_run": {"content": "列表项内容"}}]
  }
}
```
> 注意：`block_type` 是 `bulleted_list`，但内容字段是 `bulleted`

### 有序列表
```json
{
  "block_type": "numbered_list",
  "numbered": {
    "elements": [{"text_run": {"content": "列表项内容"}}]
  }
}
```
> 注意：`block_type` 是 `numbered_list`，但内容字段是 `numbered`

### 表格（嵌套块典型用法）
```json
{
  "children": ["table-1"],
  "descendant": [
    {
      "block_id": "table-1",
      "block_type": "table",
      "table": {
        "row_size": 2,
        "column_size": 2,
        "column_width": [200, 200],
        "header_row": true,
        "header_column": false
      },
      "children": ["cell-1-1", "cell-1-2", "cell-2-1", "cell-2-2"]
    },
    {
      "block_id": "cell-1-1",
      "block_type": "table_cell",
      "table_cell": {"align": "center", "vertical_align": "middle"},
      "children": ["text-1-1"]
    },
    {
      "block_id": "text-1-1",
      "block_type": "p",
      "text": {"elements": [{"text_run": {"content": "表头", "text_style": {"bold": true}}}]}
    }
  ]
}
```

**table 参数**: row_size(行数), column_size(列数), column_width(各列宽度), header_row(是否有表头行), header_column(是否有表头列)
**table_cell 参数**: align(left/center/right), vertical_align(top/middle/bottom)

### 批量创建多个块
将多个块放在同一个 `descendant` 数组中，一次请求完成。

---

## 更新块内容
```bash
curl -X PUT "https://lxapi.lexiangla.com/cgi-bin/v1/kb/page/entries/{entry_id}/blocks/{block_id}" \
  -H "Authorization: Bearer $LEXIANG_TOKEN" \
  -H "x-staff-id: $LEXIANG_STAFF_ID" \
  -H "Content-Type: application/json; charset=utf-8" \
  -d '{"action": "update_text_elements", "text_elements": [{"type": "text", "text": "更新内容"}]}'
```

## 删除块
```bash
curl -X DELETE "https://lxapi.lexiangla.com/cgi-bin/v1/kb/page/entries/{entry_id}/blocks/{block_id}" \
  -H "Authorization: Bearer $LEXIANG_TOKEN" \
  -H "x-staff-id: $LEXIANG_STAFF_ID"
```

## 获取块详情
```bash
curl "https://lxapi.lexiangla.com/cgi-bin/v1/kb/page/entries/{entry_id}/blocks/{block_id}" \
  -H "Authorization: Bearer $LEXIANG_TOKEN"
```

## 获取子块列表
```bash
curl "https://lxapi.lexiangla.com/cgi-bin/v1/kb/page/entries/{entry_id}/blocks/children?parent_block_id={block_id}&with_descendants=0" \
  -H "Authorization: Bearer $LEXIANG_TOKEN"
```

## 获取附件详情
```bash
curl "https://lxapi.lexiangla.com/cgi-bin/v1/kb/files/{file_id}" \
  -H "Authorization: Bearer $LEXIANG_TOKEN"
```
> 响应包含 `links.download` 附件下载链接
