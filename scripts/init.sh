#!/bin/bash
# 乐享知识库凭证加载和 Token 获取脚本
# 优先级：环境变量 > openclaw.json (env) > ~/.config/lexiang/credentials > 交互式输入
#
# 使用方式：source scripts/init.sh
# 执行后可使用 $LEXIANG_TOKEN 和 $LEXIANG_STAFF_ID 变量

LEXIANG_CONFIG_DIR="$HOME/.config/lexiang"
LEXIANG_CREDENTIALS_FILE="$LEXIANG_CONFIG_DIR/credentials"
LEXIANG_TOKEN_FILE="$LEXIANG_CONFIG_DIR/token"
LEXIANG_STAFF_ID_FILE="$LEXIANG_CONFIG_DIR/staff_id"

# ==========================================
# 辅助函数：尝试使用缓存的 Token
# ==========================================
_try_cached_token() {
  if [ -f "$LEXIANG_TOKEN_FILE" ]; then
    TOKEN_AGE=$(($(date +%s) - $(stat -f %m "$LEXIANG_TOKEN_FILE" 2>/dev/null || stat -c %Y "$LEXIANG_TOKEN_FILE")))
    if [ $TOKEN_AGE -lt 7000 ]; then
      export LEXIANG_TOKEN=$(cat "$LEXIANG_TOKEN_FILE")
      if [ -n "$LEXIANG_TOKEN" ] && [ "$LEXIANG_TOKEN" != "null" ] && [ ${#LEXIANG_TOKEN} -gt 20 ]; then
        echo "使用缓存的 Token (剩余有效期: $((7200 - TOKEN_AGE))秒)"
        return 0
      fi
    fi
  fi
  return 1
}

# ==========================================
# 辅助函数：加载 Staff ID
# ==========================================
_load_staff_id() {
  # 已有则跳过
  if [ -n "$LEXIANG_STAFF_ID" ]; then
    return 0
  fi
  # 从 staff_id 文件读取
  if [ -f "$LEXIANG_STAFF_ID_FILE" ]; then
    local sid=$(cat "$LEXIANG_STAFF_ID_FILE" | tr -d '[:space:]')
    if [ -n "$sid" ]; then
      export LEXIANG_STAFF_ID="$sid"
      return 0
    fi
  fi
  # 从 credentials 文件读取
  if [ -f "$LEXIANG_CREDENTIALS_FILE" ]; then
    local sid=$(jq -r '.staff_id // empty' "$LEXIANG_CREDENTIALS_FILE" 2>/dev/null)
    if [ -n "$sid" ]; then
      export LEXIANG_STAFF_ID="$sid"
      return 0
    fi
  fi
  # 从 openclaw.json 读取
  if [ -f ~/.openclaw/openclaw.json ]; then
    local sid=$(jq -r '.skills.entries.lexiang.env.LEXIANG_STAFF_ID // empty' ~/.openclaw/openclaw.json 2>/dev/null)
    if [ -n "$sid" ]; then
      export LEXIANG_STAFF_ID="$sid"
      return 0
    fi
  fi
  return 1
}

# ==========================================
# 辅助函数：获取新 Token（需要 app_key + app_secret）
# ==========================================
_fetch_new_token() {
  if [ -z "$LEXIANG_APP_KEY" ] || [ -z "$LEXIANG_APP_SECRET" ]; then
    return 1
  fi

  local response=$(curl -s -X POST "https://lxapi.lexiangla.com/cgi-bin/token" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "{\"grant_type\":\"client_credentials\",\"app_key\":\"$LEXIANG_APP_KEY\",\"app_secret\":\"$LEXIANG_APP_SECRET\"}")

  local token=$(echo "$response" | jq -r '.access_token // empty')
  if [ -n "$token" ] && [ "$token" != "null" ]; then
    export LEXIANG_TOKEN="$token"
    mkdir -p "$LEXIANG_CONFIG_DIR"
    echo "$token" > "$LEXIANG_TOKEN_FILE"
    chmod 600 "$LEXIANG_TOKEN_FILE"
    echo "已获取新 Token 并缓存"
    return 0
  else
    local err=$(echo "$response" | jq -r '.error_description // .error // empty' 2>/dev/null)
    echo "错误：获取 Token 失败${err:+: $err}"
    return 1
  fi
}

# ==========================================
# 辅助函数：交互式引导用户输入凭证
# ==========================================
_interactive_setup() {
  echo ""
  echo "============================================================"
  echo "🔐 乐享知识库凭证配置"
  echo "============================================================"
  echo ""
  echo "未找到乐享 API 凭证，需要以下信息才能继续："
  echo "  - App Key：乐享开放平台的应用 Key"
  echo "  - App Secret：乐享开放平台的应用 Secret"
  echo "  - Staff ID：您的员工标识（写操作必需）"
  echo ""
  echo "获取方式：登录乐享开放平台 → 创建/查看应用 → 复制凭证"
  echo "============================================================"
  echo ""

  # 读取 App Key
  local app_key=""
  while [ -z "$app_key" ]; do
    printf "请输入 App Key: "
    read -r app_key
    app_key=$(echo "$app_key" | tr -d '[:space:]')
    if [ -z "$app_key" ]; then
      echo "  ⚠️  App Key 不能为空，请重新输入"
    fi
  done

  # 读取 App Secret
  local app_secret=""
  while [ -z "$app_secret" ]; do
    printf "请输入 App Secret: "
    read -r app_secret
    app_secret=$(echo "$app_secret" | tr -d '[:space:]')
    if [ -z "$app_secret" ]; then
      echo "  ⚠️  App Secret 不能为空，请重新输入"
    fi
  done

  # 读取 Staff ID（可选但推荐）
  printf "请输入 Staff ID（写操作必需，可回车跳过）: "
  read -r staff_id
  staff_id=$(echo "$staff_id" | tr -d '[:space:]')

  # 验证凭证有效性
  echo ""
  echo "正在验证凭证..."
  local response=$(curl -s -X POST "https://lxapi.lexiangla.com/cgi-bin/token" \
    -H "Content-Type: application/json; charset=utf-8" \
    -d "{\"grant_type\":\"client_credentials\",\"app_key\":\"$app_key\",\"app_secret\":\"$app_secret\"}")

  local token=$(echo "$response" | jq -r '.access_token // empty')
  if [ -z "$token" ] || [ "$token" = "null" ]; then
    local err=$(echo "$response" | jq -r '.error_description // .error // empty' 2>/dev/null)
    echo "❌ 凭证验证失败${err:+: $err}"
    echo "   请检查 App Key 和 App Secret 是否正确"
    return 1
  fi

  echo "✅ 凭证验证通过！"

  # 持久化保存
  mkdir -p "$LEXIANG_CONFIG_DIR"

  # 保存 credentials
  cat > "$LEXIANG_CREDENTIALS_FILE" <<EOF
{
  "app_key": "$app_key",
  "app_secret": "$app_secret"$([ -n "$staff_id" ] && echo ",
  \"staff_id\": \"$staff_id\"")
}
EOF
  chmod 600 "$LEXIANG_CREDENTIALS_FILE"

  # 保存 token
  echo "$token" > "$LEXIANG_TOKEN_FILE"
  chmod 600 "$LEXIANG_TOKEN_FILE"

  # 保存 staff_id
  if [ -n "$staff_id" ]; then
    echo "$staff_id" > "$LEXIANG_STAFF_ID_FILE"
  fi

  # 导出环境变量
  export LEXIANG_APP_KEY="$app_key"
  export LEXIANG_APP_SECRET="$app_secret"
  export LEXIANG_TOKEN="$token"
  if [ -n "$staff_id" ]; then
    export LEXIANG_STAFF_ID="$staff_id"
  fi

  echo ""
  echo "💾 凭证已保存到 $LEXIANG_CREDENTIALS_FILE"
  echo "   后续使用将自动加载，无需重复输入"
  return 0
}

# ==========================================
# 主流程
# ==========================================

# 加载 Staff ID（从所有可能来源）
_load_staff_id

# ----- 优先级 0: 缓存的有效 Token（无需 app_key/app_secret） -----
if _try_cached_token; then
  if [ -n "$LEXIANG_STAFF_ID" ]; then
    echo "员工身份标识：$LEXIANG_STAFF_ID"
  else
    echo "警告：未配置 LEXIANG_STAFF_ID，写操作可能会失败"
  fi
  return 0 2>/dev/null || exit 0
fi

# ----- 优先级 1: 环境变量 -----
if [ -n "$LEXIANG_APP_KEY" ] && [ -n "$LEXIANG_APP_SECRET" ]; then
  echo "使用环境变量中的凭证"

# ----- 优先级 2: openclaw.json -----
elif [ -f ~/.openclaw/openclaw.json ]; then
  APP_KEY=$(jq -r '.skills.entries.lexiang.env.LEXIANG_APP_KEY // empty' ~/.openclaw/openclaw.json 2>/dev/null)
  APP_SECRET=$(jq -r '.skills.entries.lexiang.env.LEXIANG_APP_SECRET // empty' ~/.openclaw/openclaw.json 2>/dev/null)
  if [ -n "$APP_KEY" ] && [ -n "$APP_SECRET" ]; then
    export LEXIANG_APP_KEY="$APP_KEY"
    export LEXIANG_APP_SECRET="$APP_SECRET"
    echo "使用 ~/.openclaw/openclaw.json 中的凭证"
  fi

# ----- 优先级 3: credentials 文件 -----
elif [ -f "$LEXIANG_CREDENTIALS_FILE" ]; then
  APP_KEY=$(jq -r '.app_key // empty' "$LEXIANG_CREDENTIALS_FILE" 2>/dev/null)
  APP_SECRET=$(jq -r '.app_secret // empty' "$LEXIANG_CREDENTIALS_FILE" 2>/dev/null)
  if [ -n "$APP_KEY" ] && [ -n "$APP_SECRET" ]; then
    export LEXIANG_APP_KEY="$APP_KEY"
    export LEXIANG_APP_SECRET="$APP_SECRET"
    echo "使用 $LEXIANG_CREDENTIALS_FILE 中的凭证"
  fi
fi

# ----- 尝试获取 Token -----
if [ -n "$LEXIANG_APP_KEY" ] && [ -n "$LEXIANG_APP_SECRET" ]; then
  if _fetch_new_token; then
    if [ -n "$LEXIANG_STAFF_ID" ]; then
      echo "员工身份标识：$LEXIANG_STAFF_ID"
    else
      echo "警告：未配置 LEXIANG_STAFF_ID，写操作可能会失败"
    fi
    return 0 2>/dev/null || exit 0
  fi
fi

# ----- 优先级 4: 交互式引导 -----
# stdin 可用时交互式引导，否则报错
if [ -t 0 ]; then
  if _interactive_setup; then
    if [ -n "$LEXIANG_STAFF_ID" ]; then
      echo "员工身份标识：$LEXIANG_STAFF_ID"
    fi
    return 0 2>/dev/null || exit 0
  else
    return 1 2>/dev/null || exit 1
  fi
else
  echo ""
  echo "错误：未找到乐享凭证。请通过以下任一方式配置："
  echo "  1. 在对话中提供 App Key、App Secret、Staff ID，我会自动保存到 ~/.config/lexiang/credentials"
  echo "  2. 设置环境变量 LEXIANG_APP_KEY 和 LEXIANG_APP_SECRET"
  echo "  3. 在 ~/.openclaw/openclaw.json 中配置 skills.entries.lexiang.env"
  echo "  4. 手动创建 ~/.config/lexiang/credentials 文件（JSON 格式）"
  echo ""
  echo "格式示例："
  echo '  {"app_key": "your_key", "app_secret": "your_secret", "staff_id": "your_id"}'
  return 1 2>/dev/null || exit 1
fi
