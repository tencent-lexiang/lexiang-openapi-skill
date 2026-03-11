#!/bin/bash
# 获取乐享知识库条目内容
# 自动判断 entry 类型（page/file/folder），返回对应内容
#
# 使用方式：
#   source scripts/init.sh
#   bash scripts/get_content.sh <ENTRY_ID> [--format markdown|html|text] [--output FILE]
#
# 输出：
#   page 类型  → 文档内容（默认 markdown，可选 html/text）
#   file 类型  → 输出下载链接和文件信息
#   folder 类型 → 列出子条目
#   root 类型  → 同 folder，列出子条目
#
# 环境变量要求：$LEXIANG_TOKEN（通过 source scripts/init.sh 获取）

set -e

ENTRY_ID=""
FORMAT="markdown"
OUTPUT_FILE=""

# 解析参数
while [[ $# -gt 0 ]]; do
  case "$1" in
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --output)
      OUTPUT_FILE="$2"
      shift 2
      ;;
    -*)
      echo "未知选项: $1" >&2
      exit 1
      ;;
    *)
      if [ -z "$ENTRY_ID" ]; then
        ENTRY_ID="$1"
      fi
      shift
      ;;
  esac
done

if [ -z "$ENTRY_ID" ]; then
  echo "用法: bash scripts/get_content.sh <ENTRY_ID> [--format markdown|html|text] [--output FILE]"
  echo ""
  echo "选项:"
  echo "  --format markdown  输出 Markdown 格式（默认，仅 page 类型）"
  echo "  --format html      输出原始 HTML（仅 page 类型）"
  echo "  --format text      输出纯文本（仅 page 类型）"
  echo "  --output FILE      将内容写入文件而非标准输出"
  echo ""
  echo "示例:"
  echo "  bash scripts/get_content.sh 855d2c89eb344644a44166a3e6d4304a"
  echo "  bash scripts/get_content.sh 855d2c89eb344644a44166a3e6d4304a --format html"
  echo "  bash scripts/get_content.sh 855d2c89eb344644a44166a3e6d4304a --output ./output.md"
  exit 1
fi

if [ -z "$LEXIANG_TOKEN" ]; then
  echo "错误：LEXIANG_TOKEN 未设置，请先执行 source scripts/init.sh" >&2
  exit 1
fi

API_BASE="https://lxapi.lexiangla.com/cgi-bin/v1"
AUTH_HEADER="Authorization: Bearer $LEXIANG_TOKEN"

# ── 步骤1: 获取 entry 基本信息 ───────────────────────────────────────

echo "📡 获取条目信息: $ENTRY_ID" >&2
ENTRY_RESP=$(curl -s "$API_BASE/kb/entries/$ENTRY_ID" -H "$AUTH_HEADER")

ENTRY_NAME=$(echo "$ENTRY_RESP" | jq -r '.data.attributes.name // empty')
ENTRY_TYPE=$(echo "$ENTRY_RESP" | jq -r '.data.attributes.entry_type // empty')

if [ -z "$ENTRY_NAME" ] || [ "$ENTRY_NAME" = "null" ]; then
  echo "错误：无法获取条目信息（ID: $ENTRY_ID）" >&2
  echo "$ENTRY_RESP" | jq . 2>/dev/null >&2 || echo "$ENTRY_RESP" >&2
  exit 1
fi

echo "📄 名称: $ENTRY_NAME" >&2
echo "📝 类型: $ENTRY_TYPE" >&2

# ── 步骤2: 根据类型获取内容 ───────────────────────────────────────────

case "$ENTRY_TYPE" in
  page)
    echo "📖 获取在线文档内容..." >&2
    CONTENT_RESP=$(curl -s "$API_BASE/kb/entries/$ENTRY_ID/content?content_type=html" -H "$AUTH_HEADER")

    # 提取 HTML 内容（API 返回字段名为 html_content，非 content）
    HTML_CONTENT=$(echo "$CONTENT_RESP" | jq -r '.data.attributes.html_content // .data.attributes.content // empty')

    if [ -z "$HTML_CONTENT" ] || [ "$HTML_CONTENT" = "null" ]; then
      echo "警告：文档内容为空" >&2
      exit 0
    fi

    case "$FORMAT" in
      html)
        RESULT="$HTML_CONTENT"
        ;;
      text)
        # 去除 HTML 标签，保留纯文本
        RESULT=$(echo "$HTML_CONTENT" | python3 -c "
import sys, html, re
content = sys.stdin.read()
# 替换 <br> 为换行
content = re.sub(r'<br\s*/?>', '\n', content)
# 替换块级元素结束标签为换行
content = re.sub(r'</(?:p|div|h[1-6]|li|tr|blockquote)>', '\n', content)
# 去除所有 HTML 标签
content = re.sub(r'<[^>]+>', '', content)
# 解码 HTML 实体
content = html.unescape(content)
# 清理多余空行
content = re.sub(r'\n{3,}', '\n\n', content)
print(content.strip())
")
        ;;
      markdown|*)
        # HTML → Markdown 转换
        RESULT=$(echo "$HTML_CONTENT" | python3 -c "
import sys, html, re

content = sys.stdin.read()

def convert_html_to_md(html_str):
    lines = []
    
    # 处理标题
    for level in range(1, 6):
        html_str = re.sub(
            rf'<h{level}[^>]*>(.*?)</h{level}>',
            lambda m: '\n' + '#' * level + ' ' + strip_tags(m.group(1)) + '\n',
            html_str, flags=re.DOTALL
        )
    
    # 处理代码块
    def code_block_replace(m):
        lang = ''
        lang_m = re.search(r'class=\"[^\"]*language-(\w+)', m.group(0))
        if lang_m:
            lang = lang_m.group(1)
        code = strip_tags(m.group(1))
        code = html.unescape(code)
        return f'\n\`\`\`{lang}\n{code}\n\`\`\`\n'
    html_str = re.sub(r'<pre[^>]*>(.*?)</pre>', code_block_replace, html_str, flags=re.DOTALL)
    
    # 处理行内代码
    html_str = re.sub(r'<code[^>]*>(.*?)</code>', r'\`\1\`', html_str, flags=re.DOTALL)
    
    # 处理加粗
    html_str = re.sub(r'<(?:b|strong)[^>]*>(.*?)</(?:b|strong)>', r'**\1**', html_str, flags=re.DOTALL)
    
    # 处理斜体
    html_str = re.sub(r'<(?:i|em)[^>]*>(.*?)</(?:i|em)>', r'*\1*', html_str, flags=re.DOTALL)
    
    # 处理链接
    html_str = re.sub(r'<a[^>]+href=\"([^\"]+)\"[^>]*>(.*?)</a>', r'[\2](\1)', html_str, flags=re.DOTALL)
    
    # 处理无序列表项
    html_str = re.sub(r'<li[^>]*>(.*?)</li>', lambda m: '- ' + strip_tags(m.group(1)).strip() + '\n', html_str, flags=re.DOTALL)
    
    # 处理引用块
    def blockquote_replace(m):
        inner = strip_tags(m.group(1)).strip()
        return '\n' + '\n'.join('> ' + line for line in inner.split('\n')) + '\n'
    html_str = re.sub(r'<blockquote[^>]*>(.*?)</blockquote>', blockquote_replace, html_str, flags=re.DOTALL)
    
    # 处理分隔线
    html_str = re.sub(r'<hr[^>]*/?>',  '\n---\n', html_str)
    
    # 处理 <br>
    html_str = re.sub(r'<br\s*/?>', '\n', html_str)
    
    # 处理段落
    html_str = re.sub(r'<p[^>]*>(.*?)</p>', lambda m: strip_tags_preserve_inline(m.group(1)) + '\n\n', html_str, flags=re.DOTALL)
    
    # 处理 div
    html_str = re.sub(r'<div[^>]*>(.*?)</div>', lambda m: m.group(1) + '\n', html_str, flags=re.DOTALL)
    
    # 清理剩余标签
    html_str = re.sub(r'<[^>]+>', '', html_str)
    
    # 解码 HTML 实体
    html_str = html.unescape(html_str)
    
    # 清理多余空行
    html_str = re.sub(r'\n{3,}', '\n\n', html_str)
    
    return html_str.strip()

def strip_tags(s):
    return re.sub(r'<[^>]+>', '', s)

def strip_tags_preserve_inline(s):
    # 保留已转换的 Markdown 内联标记
    s = re.sub(r'<(?!/?(?:code|b|strong|i|em|a)\b)[^>]+>', '', s)
    s = re.sub(r'<[^>]+>', '', s)
    return s

print(convert_html_to_md(content))
")
        ;;
    esac

    CONTENT_SIZE=$(echo "$RESULT" | wc -c | tr -d ' ')
    echo "✅ 获取成功（${CONTENT_SIZE} 字节）" >&2

    if [ -n "$OUTPUT_FILE" ]; then
      echo "$RESULT" > "$OUTPUT_FILE"
      echo "📁 已保存到: $OUTPUT_FILE" >&2
    else
      echo "$RESULT"
    fi
    ;;

  file)
    DOWNLOAD_URL=$(echo "$ENTRY_RESP" | jq -r '.data.links.download // empty')
    FILE_SIZE=$(echo "$ENTRY_RESP" | jq -r '.data.attributes.size // "未知"')

    echo "" >&2
    echo "📎 文件类型条目" >&2
    echo "  名称: $ENTRY_NAME" >&2
    echo "  大小: $FILE_SIZE" >&2

    if [ -n "$DOWNLOAD_URL" ] && [ "$DOWNLOAD_URL" != "null" ]; then
      echo "  下载链接: $DOWNLOAD_URL" >&2
      if [ -n "$OUTPUT_FILE" ]; then
        echo "📥 正在下载..." >&2
        curl -s -L -o "$OUTPUT_FILE" "$DOWNLOAD_URL"
        echo "📁 已保存到: $OUTPUT_FILE" >&2
      else
        echo "$DOWNLOAD_URL"
      fi
    else
      echo "  ⚠️  无法获取下载链接" >&2
    fi
    ;;

  folder|root)
    echo "" >&2
    echo "📂 目录类型条目，列出子条目..." >&2

    # 获取子条目
    CHILDREN_RESP=$(curl -s "$API_BASE/kb/entries?parent_id=$ENTRY_ID&limit=100" -H "$AUTH_HEADER")
    CHILD_COUNT=$(echo "$CHILDREN_RESP" | jq '.data | length')

    echo "  共 ${CHILD_COUNT} 个子条目:" >&2
    echo "" >&2

    # 格式化输出
    echo "$CHILDREN_RESP" | jq -r '.data[]? | "  [\(.attributes.entry_type)] \(.attributes.name)  (ID: \(.id))"'
    ;;

  *)
    echo "⚠️  未知的条目类型: $ENTRY_TYPE" >&2
    echo "  尝试作为 page 获取内容..." >&2
    CONTENT_RESP=$(curl -s "$API_BASE/kb/entries/$ENTRY_ID/content?content_type=html" -H "$AUTH_HEADER")
    HTML_CONTENT=$(echo "$CONTENT_RESP" | jq -r '.data.attributes.content // empty')
    if [ -n "$HTML_CONTENT" ] && [ "$HTML_CONTENT" != "null" ]; then
      echo "$HTML_CONTENT"
    else
      echo "无法获取内容" >&2
      exit 1
    fi
    ;;
esac
