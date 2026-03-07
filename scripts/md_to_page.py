#!/usr/bin/env python3
"""
Markdown → 乐享在线文档(page) Blocks 转换上传脚本

功能：将本地 Markdown 文件内容转换为乐享 blocks API 格式，写入指定的在线文档(page)。

使用方式：
    # 创建新 page 并写入（需要 SPACE_ID 和可选 PARENT_ENTRY_ID）
    python3 scripts/md_to_page.py <md_file> --space-id <SPACE_ID> [--parent-id <PARENT_ID>] [--name <标题>]

    # 写入已有 page（覆盖或追加）
    python3 scripts/md_to_page.py <md_file> --entry-id <ENTRY_ID> [--append]

前置条件：
    环境变量 LEXIANG_TOKEN 和 LEXIANG_STAFF_ID 已设置（通过 source scripts/init.sh）

依赖：仅使用 Python 标准库，无需额外安装。
"""

import json
import os
import re
import sys
import urllib.request
import urllib.error
import argparse


BASE_URL = "https://lxapi.lexiangla.com/cgi-bin/v1"
BATCH_SIZE = 20  # 每批最多提交的块数（避免请求过大）


def get_headers(write=False):
    token = os.environ.get("LEXIANG_TOKEN", "")
    staff_id = os.environ.get("LEXIANG_STAFF_ID", "")
    if not token:
        print("错误：LEXIANG_TOKEN 未设置，请先执行 source scripts/init.sh", file=sys.stderr)
        sys.exit(1)
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json; charset=utf-8",
    }
    if write:
        if not staff_id:
            print("错误：LEXIANG_STAFF_ID 未设置", file=sys.stderr)
            sys.exit(1)
        headers["x-staff-id"] = staff_id
    return headers


def api_request(method, path, data=None):
    url = f"{BASE_URL}{path}"
    body = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=body, headers=get_headers(write=(method != "GET")), method=method)
    try:
        with urllib.request.urlopen(req) as resp:
            if resp.status == 204:
                return {}
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8", errors="replace")
        print(f"API 错误 [{e.code}]: {err_body}", file=sys.stderr)
        raise


# ── Markdown 解析 ──────────────────────────────────────────────────

def parse_markdown(text):
    """
    将 Markdown 文本解析为 block 描述列表。
    每个 block 是一个 dict，包含 type 和相关内容。
    """
    lines = text.split("\n")
    blocks = []
    i = 0

    while i < len(lines):
        line = lines[i]

        # 空行 → 跳过
        if not line.strip():
            i += 1
            continue

        # 分隔线 ---/***/___ (至少3个)
        if re.match(r'^(\s*[-*_]\s*){3,}$', line):
            blocks.append({"type": "divider"})
            i += 1
            continue

        # 标题 # ~ #####
        m = re.match(r'^(#{1,5})\s+(.+)', line)
        if m:
            level = len(m.group(1))
            blocks.append({"type": f"h{level}", "text": m.group(2).strip()})
            i += 1
            continue

        # 代码块 ```
        if line.strip().startswith("```"):
            lang = line.strip()[3:].strip()
            code_lines = []
            i += 1
            while i < len(lines) and not lines[i].strip().startswith("```"):
                code_lines.append(lines[i])
                i += 1
            i += 1  # skip closing ```
            blocks.append({"type": "code", "language": lang or "plain", "content": "\n".join(code_lines)})
            continue

        # 引用块 > (连续的引用行合并为一个 quote block)
        if line.startswith(">"):
            quote_lines = []
            while i < len(lines) and lines[i].startswith(">"):
                quote_lines.append(re.sub(r'^>\s?', '', lines[i]))
                i += 1
            quote_text = "\n".join(quote_lines).strip()
            # 引用块内可能有多个段落，按空行分割
            quote_paragraphs = [p.strip() for p in quote_text.split("\n\n") if p.strip()]
            if not quote_paragraphs:
                quote_paragraphs = [quote_text]
            blocks.append({"type": "quote", "paragraphs": quote_paragraphs})
            continue

        # 无序列表 - / * / +
        if re.match(r'^[\s]*[-*+]\s+', line):
            items = []
            while i < len(lines) and re.match(r'^[\s]*[-*+]\s+', lines[i]):
                items.append(re.sub(r'^[\s]*[-*+]\s+', '', lines[i]).strip())
                i += 1
            for item in items:
                blocks.append({"type": "bulleted_list", "text": item})
            continue

        # 有序列表 1. 2. ...
        if re.match(r'^[\s]*\d+\.\s+', line):
            items = []
            while i < len(lines) and re.match(r'^[\s]*\d+\.\s+', lines[i]):
                items.append(re.sub(r'^[\s]*\d+\.\s+', '', lines[i]).strip())
                i += 1
            for item in items:
                blocks.append({"type": "numbered_list", "text": item})
            continue

        # 普通段落（连续非空行合并）
        para_lines = []
        while i < len(lines) and lines[i].strip() and not any([
            re.match(r'^#{1,5}\s+', lines[i]),
            lines[i].strip().startswith("```"),
            lines[i].startswith(">"),
            re.match(r'^[\s]*[-*+]\s+', lines[i]),
            re.match(r'^[\s]*\d+\.\s+', lines[i]),
            re.match(r'^(\s*[-*_]\s*){3,}$', lines[i]),
        ]):
            para_lines.append(lines[i])
            i += 1
        if para_lines:
            blocks.append({"type": "p", "text": " ".join(para_lines)})

    return blocks


# ── Inline 样式解析 ────────────────────────────────────────────────

def parse_inline_elements(text):
    """
    解析 inline Markdown 标记（加粗、斜体、行内代码、链接），
    生成 blocks API 的 elements 数组。
    """
    elements = []
    # 使用正则匹配 inline 标记
    # 顺序：行内代码 → 加粗+斜体 → 加粗 → 斜体 → 链接 → 普通文本
    pattern = re.compile(
        r'(`[^`]+`)'                 # 行内代码
        r'|(\*\*\*(.+?)\*\*\*)'     # 加粗+斜体
        r'|(\*\*(.+?)\*\*)'         # 加粗
        r'|(\*(.+?)\*)'             # 斜体
        r'|(\[([^\]]+)\]\(([^)]+)\))'  # 链接
    )

    last_end = 0
    for m in pattern.finditer(text):
        # 前面的普通文本
        if m.start() > last_end:
            plain = text[last_end:m.start()]
            if plain:
                elements.append({"text_run": {"content": plain}})

        if m.group(1):  # 行内代码
            code_text = m.group(1)[1:-1]
            elements.append({"text_run": {"content": code_text, "text_style": {"code": True}}})
        elif m.group(2):  # 加粗+斜体
            elements.append({"text_run": {"content": m.group(3), "text_style": {"bold": True, "italic": True}}})
        elif m.group(4):  # 加粗
            elements.append({"text_run": {"content": m.group(5), "text_style": {"bold": True}}})
        elif m.group(6):  # 斜体
            elements.append({"text_run": {"content": m.group(7), "text_style": {"italic": True}}})
        elif m.group(8):  # 链接
            link_text = m.group(9)
            link_url = m.group(10)
            elements.append({"text_run": {"content": link_text, "text_style": {"link": link_url}}})

        last_end = m.end()

    # 尾部普通文本
    if last_end < len(text):
        remaining = text[last_end:]
        if remaining:
            elements.append({"text_run": {"content": remaining}})

    if not elements:
        elements.append({"text_run": {"content": text}})

    return elements


# ── Block → API Payload 转换 ──────────────────────────────────────

def block_to_descendant(block):
    """
    将解析后的 block dict 转换为 blocks API 的 descendant 格式。
    返回 (descendant_items, children_ids)：
      - descendant_items: descendant 数组中需要的所有块
      - children_ids: 顶层 children 数组（用于嵌套块的根级引用）
    """
    btype = block["type"]

    if btype == "divider":
        return [{"block_type": "divider"}], []

    if btype == "code":
        return [{"block_type": "code", "code": {"language": block["language"], "content": block["content"]}}], []

    if btype in ("h1", "h2", "h3", "h4", "h5"):
        level = btype[1]
        field_name = f"heading{level}"
        return [{"block_type": btype, field_name: {"elements": parse_inline_elements(block["text"])}}], []

    if btype == "p":
        return [{"block_type": "p", "text": {"elements": parse_inline_elements(block["text"])}}], []

    if btype == "bulleted_list":
        return [{"block_type": "bulleted_list", "bulleted": {"elements": parse_inline_elements(block["text"])}}], []

    if btype == "numbered_list":
        return [{"block_type": "numbered_list", "numbered": {"elements": parse_inline_elements(block["text"])}}], []

    if btype == "quote":
        # API 不支持 quote block_type，改用 callout（高亮块）模拟引用效果
        # callout 是嵌套块，需要 children + block_id
        import uuid
        quote_id = f"callout-{uuid.uuid4().hex[:8]}"
        items = []
        child_ids = []
        for j, para in enumerate(block["paragraphs"]):
            text_id = f"{quote_id}-p{j}"
            child_ids.append(text_id)
            items.append({
                "block_id": text_id,
                "block_type": "p",
                "text": {"elements": parse_inline_elements(para)}
            })
        callout_block = {
            "block_id": quote_id,
            "block_type": "callout",
            "callout": {"background_color": "#F3F3F3", "icon": "💬"},
            "children": child_ids,
        }
        return [callout_block] + items, [quote_id]

    # fallback: 当作段落
    return [{"block_type": "p", "text": {"elements": [{"text_run": {"content": str(block)}}]}}], []


def blocks_to_batches(parsed_blocks):
    """
    将解析后的 blocks 分批转换为 API 请求 payload。
    每批最多 BATCH_SIZE 个顶层块（嵌套块的子块不计入限制）。
    返回 payload 列表，每个 payload 是一个完整的 descendant 请求体。

    注意：不在 payload 顶层传 children 参数。
    嵌套块（callout/table 等）的父子关系通过块自身的 block_id + children 字段建立。
    如果在 payload 顶层传 children，API 会将这些块提升为页面根的第一批子节点，
    打乱 descendant 数组中的顺序，导致嵌套块位置错乱（跑到页面开头）。
    """
    batches = []
    current_descendant = []
    top_level_count = 0

    for block in parsed_blocks:
        desc_items, _child_ids = block_to_descendant(block)

        # 嵌套块（有 children_ids）整体算一个顶层块
        if _child_ids:
            top_level_count += 1
        else:
            top_level_count += len(desc_items)

        current_descendant.extend(desc_items)

        if top_level_count >= BATCH_SIZE:
            batches.append({"descendant": current_descendant})
            current_descendant = []
            top_level_count = 0

    if current_descendant:
        batches.append({"descendant": current_descendant})

    return batches


# ── 主流程 ─────────────────────────────────────────────────────────

def create_page(space_id, parent_id=None, name="新文档"):
    """创建一个空白 page 条目，返回 entry_id"""
    body = {
        "data": {
            "type": "kb_entry",
            "attributes": {"entry_type": "page", "name": name},
            "relationships": {
                "space": {"data": {"type": "kb_space", "id": space_id}},
            }
        }
    }
    if parent_id:
        body["data"]["relationships"]["parent_entry"] = {"data": {"type": "kb_entry", "id": parent_id}}

    resp = api_request("POST", "/kb/entries", body)
    entry_id = resp.get("data", {}).get("id")
    if not entry_id:
        print(f"创建 page 失败: {json.dumps(resp, ensure_ascii=False)}", file=sys.stderr)
        sys.exit(1)
    return entry_id


def clear_page_blocks(entry_id):
    """清空 page 已有的所有根块内容（并行删除提升性能）"""
    import concurrent.futures
    print("清空已有内容...")

    def _get_block_ids():
        resp = api_request("GET", f"/kb/page/entries/{entry_id}/blocks/children?with_descendants=0")
        data = resp.get("data", {})
        blocks = data.get("blocks", []) if isinstance(data, dict) else []
        return [b["block_id"] for b in blocks if b.get("block_id")]

    def _delete_one(block_id):
        headers = get_headers(write=True)
        url = f"{BASE_URL}/kb/page/entries/{entry_id}/blocks/{block_id}"
        req = urllib.request.Request(url, headers=headers, method="DELETE")
        try:
            with urllib.request.urlopen(req) as resp:
                return True
        except Exception:
            return False

    try:
        # 循环删除直到清空（嵌套块删除父块后子块自动消失，但可能需要多轮）
        round_num = 0
        while True:
            block_ids = _get_block_ids()
            if not block_ids:
                if round_num == 0:
                    print("  页面为空，无需清理")
                else:
                    print("  页面已清空")
                return
            round_num += 1
            print(f"  第 {round_num} 轮: 待删除 {len(block_ids)} 个块...")
            with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
                results = list(executor.map(_delete_one, block_ids))
            deleted = sum(results)
            failed = len(results) - deleted
            print(f"  已删除 {deleted}" + (f"，{failed} 个失败" if failed else ""))
            if round_num > 5:
                print("  警告：超过 5 轮仍未清空，停止清理", file=sys.stderr)
                break
    except Exception as e:
        print(f"  清空失败: {e}", file=sys.stderr)
        print("  尝试继续写入（内容可能重复）", file=sys.stderr)


def write_blocks(entry_id, batches):
    """将块内容分批写入 page"""
    total_batches = len(batches)
    success_count = 0
    fail_count = 0

    for i, payload in enumerate(batches, 1):
        block_count = len(payload["descendant"])
        try:
            api_request("POST", f"/kb/page/entries/{entry_id}/blocks/descendant", payload)
            success_count += block_count
            print(f"  批次 {i}/{total_batches}: 写入 {block_count} 个块 ✓")
        except Exception as e:
            fail_count += block_count
            print(f"  批次 {i}/{total_batches}: 写入 {block_count} 个块失败 ✗ - {e}")
            # 尝试逐个写入失败批次中的块
            # 先收集所有嵌套块子块的 ID，跳过它们（只单独提交顶层块）
            nested_child_ids = set()
            for item in payload["descendant"]:
                if "children" in item:
                    nested_child_ids.update(item["children"])

            for item in payload["descendant"]:
                if "block_type" not in item:
                    continue
                # 跳过嵌套块的子块（它们会跟随父块一起提交）
                block_id = item.get("block_id")
                if block_id and block_id in nested_child_ids:
                    continue
                single = {"descendant": [item]}
                if "children" in item:
                    child_ids = item["children"]
                    child_blocks = [b for b in payload["descendant"] if b.get("block_id") in child_ids]
                    single["descendant"].extend(child_blocks)
                try:
                    api_request("POST", f"/kb/page/entries/{entry_id}/blocks/descendant", single)
                    btype = item.get("block_type", "?")
                    print(f"    逐块重试 [{btype}] ✓")
                    success_count += 1
                    fail_count -= 1
                except Exception:
                    btype = item.get("block_type", "?")
                    text_preview = ""
                    for field in ["text", "bulleted", "numbered", "heading1", "heading2", "heading3", "heading4", "heading5"]:
                        if field in item:
                            els = item[field].get("elements", [])
                            if els:
                                text_preview = els[0].get("text_run", {}).get("content", "")[:30]
                                break
                    print(f"    逐块重试 [{btype}] ✗: {text_preview}...")

    return success_count, fail_count


def main():
    parser = argparse.ArgumentParser(description="将 Markdown 文件转换为乐享在线文档")
    parser.add_argument("md_file", help="Markdown 文件路径")
    parser.add_argument("--entry-id", help="已有 page 的 entry_id（直接写入）")
    parser.add_argument("--space-id", help="知识库 ID（创建新 page 时必填）")
    parser.add_argument("--parent-id", help="父文件夹 entry_id（可选）")
    parser.add_argument("--name", help="文档标题（默认使用文件名或 Markdown 首个标题）")
    parser.add_argument("--append", action="store_true", help="追加模式（不清空已有内容）")

    args = parser.parse_args()

    # 读取 Markdown 文件
    if not os.path.isfile(args.md_file):
        print(f"错误：文件不存在: {args.md_file}", file=sys.stderr)
        sys.exit(1)

    with open(args.md_file, "r", encoding="utf-8") as f:
        md_text = f.read()

    # 解析 Markdown
    parsed_blocks = parse_markdown(md_text)
    print(f"解析 Markdown：{len(parsed_blocks)} 个内容块")

    # 确定文档标题
    doc_name = args.name
    if not doc_name:
        # 尝试从 Markdown 首个标题提取
        for b in parsed_blocks:
            if b["type"] in ("h1", "h2", "h3"):
                doc_name = b["text"]
                break
        if not doc_name:
            doc_name = os.path.splitext(os.path.basename(args.md_file))[0]

    # 确定 entry_id
    entry_id = args.entry_id
    if not entry_id:
        if not args.space_id:
            print("错误：未指定 --entry-id 或 --space-id，无法确定目标文档", file=sys.stderr)
            sys.exit(1)
        print(f"创建在线文档: {doc_name}")
        entry_id = create_page(args.space_id, args.parent_id, doc_name)
        print(f"  Entry ID: {entry_id}")

    # 非追加模式 + 已有 entry_id 时，先清空已有内容
    if args.entry_id and not args.append:
        clear_page_blocks(entry_id)

    # 转换为 API batches
    batches = blocks_to_batches(parsed_blocks)
    print(f"分为 {len(batches)} 个批次写入...")

    # 写入
    success, fail = write_blocks(entry_id, batches)
    print(f"\n完成: 成功 {success} 块, 失败 {fail} 块")
    print(f"Entry ID: {entry_id}")

    # 输出 JSON 结果（方便脚本调用解析）
    result = {"entry_id": entry_id, "name": doc_name, "success": success, "fail": fail}
    print(f"\n__RESULT_JSON__:{json.dumps(result)}")


if __name__ == "__main__":
    main()
