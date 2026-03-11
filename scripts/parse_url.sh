#!/bin/bash
# 解析乐享 URL，提取 space_id / entry_id / team_id 等信息
# 并通过 API 获取详细信息
#
# 使用方式：
#   source scripts/parse_url.sh <乐享URL> [--content] [--format=FORMAT] [--output=FILE]
#
# 支持的 URL 格式：
#   https://lexiangla.com/spaces/{space_id}?company_from=xxx
#   https://{domain}.lexiangla.com/spaces/{space_id}
#   https://lexiangla.com/pages/{entry_id}?company_from=xxx
#   https://{domain}.lexiangla.com/pages/{entry_id}
#   https://lexiangla.com/t/{team_id}/spaces
#   https://{domain}.lexiangla.com/t/{team_id}/spaces
#
# 输出（导出环境变量）：
#   LEXIANG_PARSED_TYPE     - 资源类型: space / entry / team
#   LEXIANG_PARSED_ID       - 资源 ID
#   LEXIANG_PARSED_SPACE_ID - 知识库 ID（space/entry 类型时可用）
#   LEXIANG_PARSED_TEAM_ID  - 团队 ID（如果能获取到）
#   LEXIANG_PARSED_NAME     - 资源名称
#   LEXIANG_PARSED_ROOT_ENTRY_ID - 根节点 ID（space 类型时可用）

URL=""
SHOW_CONTENT=0
CONTENT_FORMAT="markdown"
CONTENT_OUTPUT=""

# 解析参数
for arg in "$@"; do
  case "$arg" in
    --content)
      SHOW_CONTENT=1
      ;;
    --format=*)
      CONTENT_FORMAT="${arg#--format=}"
      ;;
    --output=*)
      CONTENT_OUTPUT="${arg#--output=}"
      ;;
    -*)
      # 未知选项，忽略
      ;;
    *)
      if [ -z "$URL" ]; then
        URL="$arg"
      fi
      ;;
  esac
done

if [ -z "$URL" ]; then
  echo "用法: source scripts/parse_url.sh <乐享URL> [--content] [--format=markdown|html|text] [--output=FILE]"
  echo ""
  echo "选项:"
  echo "  --content          解析后直接输出文档内容（仅 entry 类型 URL 有效）"
  echo "  --format=FORMAT    内容输出格式: markdown（默认）、html、text"
  echo "  --output=FILE      将内容保存到文件"
  echo ""
  echo "支持的 URL 格式："
  echo "  知识库: https://lexiangla.com/spaces/{space_id}?company_from=xxx"
  echo "  文档:   https://lexiangla.com/pages/{entry_id}?company_from=xxx"
  echo "  团队:   https://lexiangla.com/t/{team_id}/spaces"
  return 1 2>/dev/null || exit 1
fi

# 清理旧变量
unset LEXIANG_PARSED_TYPE LEXIANG_PARSED_ID LEXIANG_PARSED_SPACE_ID
unset LEXIANG_PARSED_TEAM_ID LEXIANG_PARSED_NAME LEXIANG_PARSED_ROOT_ENTRY_ID

# 去掉 scheme+host 和查询参数，提取路径部分
URL_PATH=$(printf '%s' "$URL" | sed -E 's|https?://[^/]*||' | sed 's|?.*||')

# 解析 URL 类型和 ID
if printf '%s' "$URL_PATH" | grep -qE '^/spaces/[a-f0-9]+'; then
  LEXIANG_PARSED_TYPE="space"
  LEXIANG_PARSED_ID=$(printf '%s' "$URL_PATH" | sed 's|/spaces/\([a-f0-9]*\).*|\1|')
elif printf '%s' "$URL_PATH" | grep -qE '^/pages/[a-f0-9]+'; then
  LEXIANG_PARSED_TYPE="entry"
  LEXIANG_PARSED_ID=$(printf '%s' "$URL_PATH" | sed 's|/pages/\([a-f0-9]*\).*|\1|')
elif printf '%s' "$URL_PATH" | grep -qE '^/t/[a-f0-9]+'; then
  LEXIANG_PARSED_TYPE="team"
  LEXIANG_PARSED_ID=$(printf '%s' "$URL_PATH" | sed 's|/t/\([a-f0-9]*\).*|\1|')
else
  echo "错误：无法识别的 URL 格式: $URL"
  echo "支持 /spaces/{id}、/pages/{id}、/t/{id} 格式"
  return 1 2>/dev/null || exit 1
fi

echo "🔗 URL 类型: $LEXIANG_PARSED_TYPE"
echo "🆔 资源 ID:  $LEXIANG_PARSED_ID"

# 检查是否有 Token
if [ -z "$LEXIANG_TOKEN" ]; then
  echo ""
  echo "⚠️  LEXIANG_TOKEN 未设置，仅返回 URL 解析结果（无法查询 API 获取详细信息）"
  echo "   请先执行: source scripts/init.sh"
  export LEXIANG_PARSED_TYPE LEXIANG_PARSED_ID
  return 0 2>/dev/null || exit 0
fi

# 辅助函数：安全地将变量传给 jq（避免 zsh echo 对 Unicode 的编码问题）
_jq_parse() {
  printf '%s' "$1" | jq -r "$2"
}

# 通过 API 获取详细信息
echo ""
echo "📡 查询 API 获取详细信息..."

if [ "$LEXIANG_PARSED_TYPE" = "space" ]; then
  RESP=$(curl -s "https://lxapi.lexiangla.com/cgi-bin/v1/kb/spaces/$LEXIANG_PARSED_ID" \
    -H "Authorization: Bearer $LEXIANG_TOKEN")

  LEXIANG_PARSED_NAME=$(_jq_parse "$RESP" '.data.attributes.name // empty')
  LEXIANG_PARSED_ROOT_ENTRY_ID=$(_jq_parse "$RESP" '.data.attributes.root_entry_id // .data.relationships.root_entry.data.id // empty')
  LEXIANG_PARSED_TEAM_ID=$(_jq_parse "$RESP" '.data.relationships.team.data.id // empty')
  LEXIANG_PARSED_SPACE_ID="$LEXIANG_PARSED_ID"

  if [ -n "$LEXIANG_PARSED_NAME" ] && [ "$LEXIANG_PARSED_NAME" != "null" ]; then
    echo "  📁 知识库名称:  $LEXIANG_PARSED_NAME"
    echo "  🆔 Space ID:    $LEXIANG_PARSED_SPACE_ID"
    echo "  📂 根节点 ID:   $LEXIANG_PARSED_ROOT_ENTRY_ID"
    [ -n "$LEXIANG_PARSED_TEAM_ID" ] && [ "$LEXIANG_PARSED_TEAM_ID" != "null" ] && \
      echo "  👥 团队 ID:     $LEXIANG_PARSED_TEAM_ID"
  else
    echo "错误：无法获取知识库信息"
    _jq_parse "$RESP" '.' 2>/dev/null || printf '%s\n' "$RESP"
    return 1 2>/dev/null || exit 1
  fi

elif [ "$LEXIANG_PARSED_TYPE" = "entry" ]; then
  RESP=$(curl -s "https://lxapi.lexiangla.com/cgi-bin/v1/kb/entries/$LEXIANG_PARSED_ID" \
    -H "Authorization: Bearer $LEXIANG_TOKEN")

  LEXIANG_PARSED_NAME=$(_jq_parse "$RESP" '.data.attributes.name // empty')
  ENTRY_TYPE=$(_jq_parse "$RESP" '.data.attributes.entry_type // empty')
  LEXIANG_PARSED_SPACE_ID=$(_jq_parse "$RESP" '.data.relationships.space.data.id // empty')

  # 如果 API 没直接返回 space_id，通过 parent 链向上查找 root entry
  if [ -z "$LEXIANG_PARSED_SPACE_ID" ] || [ "$LEXIANG_PARSED_SPACE_ID" = "null" ]; then
    # 先检查当前 entry 本身是否就是 root
    CURRENT_TYPE=$(_jq_parse "$RESP" '.data.attributes.entry_type // empty')
    if [ "$CURRENT_TYPE" = "root" ]; then
      ROOT_ENTRY_ID="$LEXIANG_PARSED_ID"
    else
      ROOT_ENTRY_ID=""
      PARENT_ID=$(_jq_parse "$RESP" '.data.relationships.parent.data.id // empty')
      # 先检查 included 中是否已有 root 类型的祖先
      INCLUDED_ROOT=$(_jq_parse "$RESP" '.included[]? | select(.attributes.entry_type == "root") | .id' | head -1)
      if [ -n "$INCLUDED_ROOT" ] && [ "$INCLUDED_ROOT" != "null" ]; then
        ROOT_ENTRY_ID="$INCLUDED_ROOT"
      else
        WALK_COUNT=0
        while [ -n "$PARENT_ID" ] && [ "$PARENT_ID" != "null" ] && [ $WALK_COUNT -lt 10 ]; do
          PARENT_RESP=$(curl -s "https://lxapi.lexiangla.com/cgi-bin/v1/kb/entries/$PARENT_ID" \
            -H "Authorization: Bearer $LEXIANG_TOKEN")
          PARENT_TYPE=$(_jq_parse "$PARENT_RESP" '.data.attributes.entry_type // empty')
          if [ "$PARENT_TYPE" = "root" ]; then
            ROOT_ENTRY_ID="$PARENT_ID"
            break
          fi
          INCLUDED_ROOT=$(_jq_parse "$PARENT_RESP" '.included[]? | select(.attributes.entry_type == "root") | .id' | head -1)
          if [ -n "$INCLUDED_ROOT" ] && [ "$INCLUDED_ROOT" != "null" ]; then
            ROOT_ENTRY_ID="$INCLUDED_ROOT"
            break
          fi
          NEW_PARENT=$(_jq_parse "$PARENT_RESP" '.data.relationships.parent.data.id // empty')
          if [ -z "$NEW_PARENT" ] || [ "$NEW_PARENT" = "null" ] || [ "$NEW_PARENT" = "$PARENT_ID" ]; then
            ROOT_ENTRY_ID="$PARENT_ID"
            break
          fi
          PARENT_ID="$NEW_PARENT"
          WALK_COUNT=$((WALK_COUNT + 1))
        done
      fi
    fi

    # 找到 root_entry_id 后，通过缓存或 API 反查 space_id
    if [ -n "$ROOT_ENTRY_ID" ]; then
      CACHE_FILE="$HOME/.config/lexiang/space_cache.json"
      # 先查缓存
      if [ -f "$CACHE_FILE" ]; then
        LEXIANG_PARSED_SPACE_ID=$(jq -r --arg rid "$ROOT_ENTRY_ID" '.[$rid].space_id // empty' "$CACHE_FILE" 2>/dev/null)
        [ -n "$LEXIANG_PARSED_SPACE_ID" ] && [ "$LEXIANG_PARSED_SPACE_ID" != "null" ] && \
          LEXIANG_PARSED_TEAM_ID=$(jq -r --arg rid "$ROOT_ENTRY_ID" '.[$rid].team_id // empty' "$CACHE_FILE" 2>/dev/null)
      fi

      # 缓存未命中，尝试通过已知 team_id 或 teams API 查找
      if [ -z "$LEXIANG_PARSED_SPACE_ID" ] || [ "$LEXIANG_PARSED_SPACE_ID" = "null" ]; then
        TEAM_IDS=""
        CRED_FILE="$HOME/.config/lexiang/credentials"
        if [ -f "$CRED_FILE" ]; then
          DEFAULT_TEAM_ID=$(jq -r '.team_id // empty' "$CRED_FILE" 2>/dev/null)
          [ -n "$DEFAULT_TEAM_ID" ] && TEAM_IDS="$DEFAULT_TEAM_ID"
        fi
        if [ -f "$CACHE_FILE" ]; then
          CACHED_TEAMS=$(jq -r '[.[].team_id] | unique | .[]' "$CACHE_FILE" 2>/dev/null)
          for ct in $CACHED_TEAMS; do
            printf '%s' "$TEAM_IDS" | grep -q "$ct" || TEAM_IDS="$TEAM_IDS $ct"
          done
        fi
        if [ -z "$TEAM_IDS" ]; then
          TEAMS_RESP=$(curl -s "https://lxapi.lexiangla.com/cgi-bin/v1/kb/teams?limit=50" \
            -H "Authorization: Bearer $LEXIANG_TOKEN" \
            -H "x-staff-id: ${LEXIANG_STAFF_ID:-}")
          TEAM_IDS=$(_jq_parse "$TEAMS_RESP" '.data[]?.id' 2>/dev/null)
        fi

        for tid in $TEAM_IDS; do
          [ -z "$tid" ] && continue
          SPACES_RESP=$(curl -s "https://lxapi.lexiangla.com/cgi-bin/v1/kb/spaces?team_id=$tid&limit=100" \
            -H "Authorization: Bearer $LEXIANG_TOKEN" \
            -H "x-staff-id: ${LEXIANG_STAFF_ID:-}")
          FOUND_SPACE=$(printf '%s' "$SPACES_RESP" | jq -r --arg rid "$ROOT_ENTRY_ID" \
            '.data[]? | select(.relationships.root_entry.data.id == $rid or .attributes.root_entry_id == $rid) | .id' | head -1)
          if [ -n "$FOUND_SPACE" ]; then
            LEXIANG_PARSED_SPACE_ID="$FOUND_SPACE"
            LEXIANG_PARSED_TEAM_ID="$tid"
            mkdir -p "$(dirname "$CACHE_FILE")"
            if [ -f "$CACHE_FILE" ]; then
              TMP=$(jq --arg rid "$ROOT_ENTRY_ID" --arg sid "$FOUND_SPACE" --arg tid "$tid" \
                '. + {($rid): {"space_id": $sid, "team_id": $tid}}' "$CACHE_FILE")
            else
              TMP=$(jq -n --arg rid "$ROOT_ENTRY_ID" --arg sid "$FOUND_SPACE" --arg tid "$tid" \
                '{($rid): {"space_id": $sid, "team_id": $tid}}')
            fi
            printf '%s\n' "$TMP" > "$CACHE_FILE"
            break
          fi
        done
      fi
    fi
  fi

  # 如果找到了 space_id，查询知识库详情
  if [ -n "$LEXIANG_PARSED_SPACE_ID" ] && [ "$LEXIANG_PARSED_SPACE_ID" != "null" ]; then
    SPACE_RESP=$(curl -s "https://lxapi.lexiangla.com/cgi-bin/v1/kb/spaces/$LEXIANG_PARSED_SPACE_ID" \
      -H "Authorization: Bearer $LEXIANG_TOKEN")
    LEXIANG_PARSED_TEAM_ID=$(_jq_parse "$SPACE_RESP" '.data.relationships.team.data.id // empty')
    LEXIANG_PARSED_ROOT_ENTRY_ID=$(_jq_parse "$SPACE_RESP" '.data.attributes.root_entry_id // .data.relationships.root_entry.data.id // empty')
    SPACE_NAME=$(_jq_parse "$SPACE_RESP" '.data.attributes.name // empty')
  fi

  if [ -n "$LEXIANG_PARSED_NAME" ] && [ "$LEXIANG_PARSED_NAME" != "null" ]; then
    echo "  📄 文档名称:    $LEXIANG_PARSED_NAME"
    echo "  📝 文档类型:    $ENTRY_TYPE"
    echo "  🆔 Entry ID:    $LEXIANG_PARSED_ID"
    [ -n "$LEXIANG_PARSED_SPACE_ID" ] && [ "$LEXIANG_PARSED_SPACE_ID" != "null" ] && \
      echo "  📁 所属知识库:  ${SPACE_NAME:-$LEXIANG_PARSED_SPACE_ID}"
    [ -n "$LEXIANG_PARSED_TEAM_ID" ] && [ "$LEXIANG_PARSED_TEAM_ID" != "null" ] && \
      echo "  👥 团队 ID:     $LEXIANG_PARSED_TEAM_ID"
  else
    echo "错误：无法获取文档信息"
    _jq_parse "$RESP" '.' 2>/dev/null || printf '%s\n' "$RESP"
    return 1 2>/dev/null || exit 1
  fi

elif [ "$LEXIANG_PARSED_TYPE" = "team" ]; then
  RESP=$(curl -s "https://lxapi.lexiangla.com/cgi-bin/v1/kb/teams/$LEXIANG_PARSED_ID" \
    -H "Authorization: Bearer $LEXIANG_TOKEN" \
    -H "x-staff-id: ${LEXIANG_STAFF_ID:-}")

  LEXIANG_PARSED_NAME=$(_jq_parse "$RESP" '.data.attributes.name // empty')
  LEXIANG_PARSED_TEAM_ID="$LEXIANG_PARSED_ID"

  if [ -n "$LEXIANG_PARSED_NAME" ] && [ "$LEXIANG_PARSED_NAME" != "null" ]; then
    echo "  👥 团队名称:    $LEXIANG_PARSED_NAME"
    echo "  🆔 Team ID:     $LEXIANG_PARSED_TEAM_ID"
  else
    echo "警告：无法获取团队详情（可能权限不足）"
    echo "  🆔 Team ID:     $LEXIANG_PARSED_TEAM_ID"
  fi
fi

export LEXIANG_PARSED_TYPE LEXIANG_PARSED_ID LEXIANG_PARSED_SPACE_ID
export LEXIANG_PARSED_TEAM_ID LEXIANG_PARSED_NAME LEXIANG_PARSED_ROOT_ENTRY_ID

# ── --content 选项：解析后直接获取内容 ──────────────────────────────
if [ "$SHOW_CONTENT" = "1" ]; then
  if [ "$LEXIANG_PARSED_TYPE" = "entry" ]; then
    # 定位 get_content.sh：优先用 BASH_SOURCE，兼容 zsh source 场景
    if [ -n "${BASH_SOURCE[0]:-}" ]; then
      _PARSE_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    elif [ -n "${(%):-%x}" ] 2>/dev/null; then
      _PARSE_SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
    else
      # fallback: 尝试从 skill 的标准安装路径查找
      _PARSE_SCRIPT_DIR="$HOME/.codebuddy/skills/lexiang/scripts"
    fi
    echo ""
    if [ -n "$CONTENT_OUTPUT" ]; then
      bash "$_PARSE_SCRIPT_DIR/get_content.sh" "$LEXIANG_PARSED_ID" --format "$CONTENT_FORMAT" --output "$CONTENT_OUTPUT"
    else
      bash "$_PARSE_SCRIPT_DIR/get_content.sh" "$LEXIANG_PARSED_ID" --format "$CONTENT_FORMAT"
    fi
    unset _PARSE_SCRIPT_DIR
  else
    echo ""
    echo "⚠️  --content 选项仅支持 entry 类型 URL（pages/xxx），当前类型: $LEXIANG_PARSED_TYPE"
  fi
fi
