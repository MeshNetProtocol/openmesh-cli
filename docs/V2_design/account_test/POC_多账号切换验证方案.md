# POC: 多账号统一切换验证方案

> **目标**：验证通过 OpenMesh 客户端一键切换多个 AI 工具（Claude Desktop、Claude Code、Antigravity）的付费账号的可行性  
> **日期**：2026-04-02  
> **状态**：设计阶段

---

## 1. 需求场景

### 1.1 当前痛点

用户拥有 2 个付费 Google 账号（Account A / Account B），分别用于 Claude Code 和 Antigravity。每个账号额度有限，需要频繁切换。

**现状**：切换账号时需要逐个工具手动操作
```
Account A 额度用完
  → 打开 Claude Code → 退出 → 重新登录 Account B
  → 打开 Antigravity → 退出 → 重新登录 Account B
  → 操作繁琐，打断工作流
```

### 1.2 期望效果

```
OpenMesh 客户端点击 "切换到 Account B"
  → Claude Desktop 自动使用 Account B 的凭证
  → Claude Code 自动使用 Account B 的凭证
  → Antigravity 自动使用 Account B 的凭证
  → 一键完成，无需打断工作流
```

---

## 2. 产品族与凭证文件探查结果

### 2.0 Claude 产品族概览

| 产品 | 形态 | 认证方式 | 凭证存储 | 切换难度 |
|------|------|---------|---------|----------|
| **Claude Desktop** | macOS 桌面 App (Electron) | Google OAuth → `claude.ai` 会话 | Cookies (加密SQLite) + Keychain | ⚠️ 较高 |
| **Claude Code** | CLI + IDE 扩展 | 自定义 API Key 或 OAuth | `~/.claude/settings.json` + Keychain | ✅ 简单 |
| **Antigravity** | IDE 扩展 (Gemini) | Google OAuth | `~/.gemini/oauth_creds.json` | ✅ 简单 |

### 2.1 Antigravity（Google OAuth 模式）

**凭证存储位置**：`~/.gemini/`

| 文件 | 内容 | 切换时是否需要替换 |
|------|------|------------------|
| `oauth_creds.json` | OAuth 凭证（access_token, refresh_token, id_token, scope, expiry_date） | ✅ **核心文件** |
| `google_accounts.json` | 当前活跃账号 `{"active": "xxx@gmail.com", "old": []}` | ✅ 需要更新 |
| `settings.json` | 认证类型设置 `selectedType: "oauth-personal"` | ❌ 无需修改 |
| `state.json` | UI 状态（banner 展示计数等） | ❌ 无需修改 |
| `antigravity-browser-profile/` | Chromium 浏览器配置（用于 OAuth 登录流程） | ⚠️ 可能需要清理 |

**关键发现**：
- `oauth_creds.json` 包含 `refresh_token`，这意味着可以持久化保存，access_token 过期后可自动刷新
- `google_accounts.json` 中的 `active` 字段记录当前登录的邮箱
- OAuth 的 `client_id` 编码在 `id_token` 的 JWT 中：`681255809395-oo8ft2oprdrnp9e3aqf6av3hmdib135j.apps.googleusercontent.com`

### 2.2 Claude Code（自定义 API Key 模式）

**凭证存储位置**：`~/.claude/settings.json`

当前你的 Claude Code 使用的是**自定义 API Key 模式**（非 Google OAuth），关键配置：

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.lycloud.top",
    "ANTHROPIC_AUTH_TOKEN": "sk-xxxx..."
  }
}
```

**关键发现**：
- Claude Code 当前通过第三方 API 代理（lycloud.top）访问，不是直接用 Google OAuth
- 切换方式更简单：只需要替换 `settings.json` 中的 `ANTHROPIC_AUTH_TOKEN` 和 `ANTHROPIC_BASE_URL`
- `config.json` 中有 `customApiKeyResponses` 记录已认可的 API Key，切换时可能需要更新

> **注意**：如果后续 Claude Code 切换到 Google OAuth 登录模式，需要探查不同的凭证文件路径。目前方案基于你已有的 API Key 模式设计。
>
> Claude Code 在 macOS Keychain 中也有条目（service: `"Claude Code"`, account: `"hyperorchid"`），这是 OAuth 登录模式使用的凭证。如果切换到 OAuth 模式，需要同时管理 Keychain 条目。

### 2.3 Claude Desktop（Electron 桌面应用）

**凭证存储位置**：`~/Library/Application Support/Claude/`

| 文件/位置 | 内容 | 切换时是否需要替换 |
|----------|------|------------------|
| `Cookies` (SQLite) | 加密的会话 Cookies，包含 `sessionKey` 等 | ✅ **核心文件** |
| `config.json` → `oauth:tokenCache` | 加密的 OAuth token 缓存 | ✅ 需要替换 |
| macOS Keychain → `"Claude Safe Storage"` | Cookies 的加密密钥 | ❌ 所有账号共用同一个密钥 |
| `claude_desktop_config.json` | MCP 等设置 | ❌ 无需修改 |

**关键发现**：
- Claude Desktop 是 Electron 应用，使用 Chromium 的加密 Cookie 存储
- Cookies 文件中包含 `claude.ai` 的 `sessionKey`，这是维持登录状态的核心
- Cookie 值使用 `"Claude Safe Storage"` Keychain 条目中的密钥加密
- `config.json` 中的 `oauth:tokenCache` 是加密的 token 缓存

**切换方案（两种路径）**：

**路径 A：文件级替换（推荐先尝试）**
```bash
# 思路：直接替换整个 Cookies 文件 + config.json 中的 oauth 字段
# 前提：两个账号使用同一个 Keychain 加密密钥（大概率成立，因为密钥与 app 绑定而非用户）
cp ~/Library/Application\ Support/Claude/Cookies  profile_a/claude_desktop_cookies
cp ~/Library/Application\ Support/Claude/config.json profile_a/claude_desktop_config.json
```

**路径 B：Session Cookie 解密替换（复杂但精确）**
```python
# 需要：
# 1. 从 Keychain 读取 "Claude Safe Storage" 密钥
# 2. 用密钥解密 Cookies SQLite 中的 sessionKey
# 3. 替换为目标账号的 sessionKey
# 4. 重新加密写回
```

> **建议**：先尝试路径 A（整个 Cookies 文件替换），如果生效就不需要复杂的解密操作。

---

## 3. POC 实施计划

### 阶段 1：凭证备份与档案管理（手动验证）

**目标**：验证凭证文件替换后工具能否正常工作

**步骤**：

```bash
# 1. 创建 profile 存储目录
mkdir -p ~/.openmesh/profiles/account_a
mkdir -p ~/.openmesh/profiles/account_b

# 2. 当前 Account A 已登录，备份凭证
# -- Antigravity
cp ~/.gemini/oauth_creds.json ~/.openmesh/profiles/account_a/gemini_oauth_creds.json
cp ~/.gemini/google_accounts.json ~/.openmesh/profiles/account_a/gemini_google_accounts.json

# -- Claude Code
cp ~/.claude/settings.json ~/.openmesh/profiles/account_a/claude_settings.json

# -- Claude Desktop（需要先退出 Claude Desktop 再操作）
cp ~/Library/Application\ Support/Claude/Cookies ~/.openmesh/profiles/account_a/claude_desktop_cookies
cp ~/Library/Application\ Support/Claude/Cookies-journal ~/.openmesh/profiles/account_a/claude_desktop_cookies_journal
cp ~/Library/Application\ Support/Claude/config.json ~/.openmesh/profiles/account_a/claude_desktop_config.json

# 3. 手动登录 Account B（在各工具中操作一次）
# 登录后同样备份
cp ~/.gemini/oauth_creds.json ~/.openmesh/profiles/account_b/gemini_oauth_creds.json
cp ~/.gemini/google_accounts.json ~/.openmesh/profiles/account_b/gemini_google_accounts.json
cp ~/.claude/settings.json ~/.openmesh/profiles/account_b/claude_settings.json
cp ~/Library/Application\ Support/Claude/Cookies ~/.openmesh/profiles/account_b/claude_desktop_cookies
cp ~/Library/Application\ Support/Claude/Cookies-journal ~/.openmesh/profiles/account_b/claude_desktop_cookies_journal
cp ~/Library/Application\ Support/Claude/config.json ~/.openmesh/profiles/account_b/claude_desktop_config.json
```

**验证点**：
- [ ] 将 Account B 的凭证恢复到 `~/.gemini/` 后，Antigravity 能否正常工作？
- [ ] 切换回 Account A 的凭证后，Antigravity 是否正常？
- [ ] Claude Code 替换 settings.json 后，是否需要重启才能生效？
- [ ] Antigravity 的 `antigravity-browser-profile/` 是否会干扰切换？
- [ ] Claude Desktop 退出后替换 Cookies 文件，重新启动后是否进入 Account B？
- [ ] Claude Desktop 的 Cookies 文件替换是否会导致 `"Claude Safe Storage"` 密钥不匹配？

**成功标准**：通过文件替换能让工具在两个账号间正常切换

---

### 阶段 2：CLI 切换脚本（自动化验证）

**目标**：编写一个简单的 shell 脚本实现一键切换

**文件**：`~/.openmesh/switch_account.sh`

```bash
#!/bin/bash
# OpenMesh Account Switcher - POC v0.1

PROFILE_DIR="$HOME/.openmesh/profiles"
CURRENT_FILE="$HOME/.openmesh/current_profile"

switch_to() {
    local profile=$1
    local profile_dir="$PROFILE_DIR/$profile"
    
    if [ ! -d "$profile_dir" ]; then
        echo "❌ Profile '$profile' not found"
        exit 1
    fi
    
    echo "🔄 Switching to profile: $profile"
    
    # 1. 先保存当前凭证（如果有当前 profile）
    if [ -f "$CURRENT_FILE" ]; then
        current=$(cat "$CURRENT_FILE")
        echo "  💾 Saving current profile: $current"
        cp ~/.gemini/oauth_creds.json "$PROFILE_DIR/$current/gemini_oauth_creds.json"
        cp ~/.gemini/google_accounts.json "$PROFILE_DIR/$current/gemini_google_accounts.json"
        # Claude Code: 只保存 env 字段，不保存整个 settings.json
        python3 -c "
import json
with open('$HOME/.claude/settings.json') as f: data = json.load(f)
env_data = data.get('env', {})
with open('$PROFILE_DIR/$current/claude_env.json', 'w') as f: json.dump(env_data, f, indent=2)
"
    fi
    
    # 2. 替换 Antigravity 凭证
    echo "  📝 Switching Antigravity credentials..."
    cp "$profile_dir/gemini_oauth_creds.json" ~/.gemini/oauth_creds.json
    cp "$profile_dir/gemini_google_accounts.json" ~/.gemini/google_accounts.json
    
    # 3. 替换 Claude Code 凭证（仅 env 字段，保留其他设置）
    echo "  📝 Switching Claude Code credentials..."
    if [ -f "$profile_dir/claude_env.json" ]; then
        python3 -c "
import json
# 读取当前 settings
with open('$HOME/.claude/settings.json') as f: settings = json.load(f)
# 读取目标 profile 的 env
with open('$profile_dir/claude_env.json') as f: new_env = json.load(f)
# 只替换 env 字段
settings['env'] = new_env
with open('$HOME/.claude/settings.json', 'w') as f: json.dump(settings, f, indent=2)
"
    fi
    
    # 4. 记录当前 profile
    echo "$profile" > "$CURRENT_FILE"
    
    echo "✅ Switched to $profile"
    echo ""
    echo "⚠️  提示：可能需要重启 Claude Code 和 Antigravity 才能生效"
    echo "    - Claude Code: 重新打开终端或 IDE 窗口"
    echo "    - Antigravity: 可能需要重新打开 IDE"
}

list_profiles() {
    echo "📋 Available profiles:"
    for dir in "$PROFILE_DIR"/*/; do
        name=$(basename "$dir")
        # 显示邮箱
        if [ -f "$PROFILE_DIR/$name/gemini_google_accounts.json" ]; then
            email=$(python3 -c "import json; print(json.load(open('$PROFILE_DIR/$name/gemini_google_accounts.json')).get('active','unknown'))")
            echo "  - $name ($email)"
        else
            echo "  - $name"
        fi
    done
    
    if [ -f "$CURRENT_FILE" ]; then
        echo ""
        echo "🔵 Current: $(cat "$CURRENT_FILE")"
    fi
}

status() {
    echo "📊 Current Status:"
    
    # Antigravity
    if [ -f ~/.gemini/google_accounts.json ]; then
        email=$(python3 -c "import json; print(json.load(open('$HOME/.gemini/google_accounts.json')).get('active','unknown'))")
        echo "  Antigravity: $email"
    fi
    
    # Claude Code
    if [ -f ~/.claude/settings.json ]; then
        base_url=$(python3 -c "import json; print(json.load(open('$HOME/.claude/settings.json')).get('env',{}).get('ANTHROPIC_BASE_URL','N/A'))")
        echo "  Claude Code: $base_url"
    fi
    
    if [ -f "$CURRENT_FILE" ]; then
        echo "  Profile: $(cat "$CURRENT_FILE")"
    fi
}

case "$1" in
    switch)
        switch_to "$2"
        ;;
    list)
        list_profiles
        ;;
    status)
        status
        ;;
    *)
        echo "Usage: $0 {switch <profile_name> | list | status}"
        ;;
esac
```

**验证点**：
- [ ] `switch_account.sh switch account_b` 后 Antigravity 是否正常
- [ ] Claude Code 的非认证配置（permissions, model 等）是否被保留
- [ ] refresh_token 是否在切换后仍然有效
- [ ] 并发使用场景：两个工具同时运行时切换是否有问题

---

### 阶段 3：热加载验证

**目标**：确认工具是否能在运行中感知凭证变化

**测试场景**：

| 场景 | 操作 | 预期 | 实际 |
|------|------|------|------|
| Antigravity 运行中切换 | 替换 oauth_creds.json | 下次请求使用新凭证 | 待验证 |
| Claude Code 运行中切换 | 替换 settings.json env | 下次请求使用新凭证 | 待验证 |
| Token 过期自动刷新 | 等待 access_token 过期 | 使用 refresh_token 刷新 | 待验证 |
| 切换后立即发送请求 | 切换后马上对话 | 新账号生效 | 待验证 |

**如果不支持热加载**（大概率），备选方案：
1. 切换后提示用户重启工具
2. 研究信号机制（如 SIGHUP）触发工具重新加载配置
3. 通过 kill + restart 自动重启工具进程

---

### 阶段 4：集成到 OpenMesh 客户端

**目标**：将切换功能集成到 OpenHub macOS 应用

**设计思路**：
```
OpenHub App
  ├── 设置页面
  │     └── 账号管理
  │           ├── Profile A (ribencong@gmail.com) [当前]
  │           ├── Profile B (another@gmail.com)
  │           └── [+ 添加新账号]
  │
  └── 状态栏菜单
        ├── 🟢 当前账号: ribencong@gmail.com
        ├── 切换到 → Profile B
        └── 管理账号...
```

**实现方式**：
- OpenHub 调用 Swift Process 执行凭证文件替换
- 切换后通过 `NSNotificationCenter` 或类似机制通知用户
- 可选：集成 `killall` 重启相关工具进程

---

## 4. 风险与注意事项

### 4.1 技术风险

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| 工具不支持热加载凭证 | 需要重启工具 | 阶段 3 验证；提供自动重启功能 |
| refresh_token 失效 | 需要重新手动 OAuth 登录 | 监控 token 有效期；提前刷新 |
| 工具版本更新后凭证格式变化 | 切换脚本失效 | 版本检测 + 适配层 |
| settings.json 中包含非认证配置 | 切换时覆盖用户的个性化设置 | 只替换 `env` 字段，不替换其他配置 |
| 并发写入冲突 | 工具正在写入时被覆盖 | 加文件锁；或先停止工具再切换 |

### 4.2 关键设计决策：字段级替换 vs 文件级替换

**Claude Code**：`settings.json` 包含 `env`、`permissions`、`model` 等多个配置。  
→ **必须使用字段级替换**，只修改 `env` 中的认证相关字段

**Antigravity**：`oauth_creds.json` 整个文件都是认证信息。  
→ **可以使用文件级替换**

---

## 5. POC 执行顺序

```
Step 1: 手动验证（阶段 1）          ← 先从这里开始
  ↓ 确认可行
Step 2: CLI 脚本（阶段 2）
  ↓ 自动化验证通过
Step 3: 热加载测试（阶段 3）
  ↓ 明确工具行为
Step 4: 集成 OpenHub（阶段 4）       ← 最终目标
```

**预计 POC 验证时间**：阶段 1-2 约 30 分钟即可完成

---

## 6. 附录：实际凭证文件结构参考

### Antigravity oauth_creds.json 结构
```json
{
  "access_token": "ya29.xxxx...",
  "scope": "userinfo.email openid cloud-platform userinfo.profile",
  "token_type": "Bearer",
  "id_token": "eyJhbGci...",
  "expiry_date": 1775103858000,
  "refresh_token": "1//0eXXXX..."
}
```

### Antigravity google_accounts.json 结构
```json
{
  "active": "ribencong@gmail.com",
  "old": []
}
```

### Claude Code settings.json 认证相关字段
```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "https://api.lycloud.top",
    "ANTHROPIC_AUTH_TOKEN": "sk-xxxx..."
  }
}
```
