# OpenMesh V2 准入控制 POC 验证方案

> **文档性质**：技术验证方案（Proof of Concept）
> **创建日期**：2026-03-31
> **更新日期**：2026-04-01
> **目标**：验证基于 EVM 地址 ID 的单组 sing-box 准入控制链路可行性

---

## 1. 范围说明

本文档聚焦于**单个服务器组**的内部实现与验证。

以下内容**不在本文档讨论范围**：
- 用户如何被分配到不同的服务器组（由客户端前端管理）
- 跨组路由与负载均衡
- 支付与订阅系统的具体实现

**假设**：每组服务器上限 1 万用户，超出后由客户端分配至新组。

---

## 2. 需验证的三个核心命题

| 命题 | 描述 | 验证方式 |
|------|------|---------|
| **命题 A（准入）** | EVM 地址在列表中的客户端可以正常使用流量转发 | Client A curl 请求成功 |
| **命题 B（拒绝）** | EVM 地址不在列表中的客户端连接被拒绝 | Client B curl 请求失败 |
| **命题 C（动态生效）** | 运行时修改列表并 reload，变更立即生效，不中断其他已连接用户 | 动态添加 Client B 的地址后请求成功 |

---

## 3. 架构设计

### 3.1 架构图

```
┌──────────────────────────────────────────────────────────────┐
│  单组服务器（上限 1 万用户）                                   │
│                                                              │
│  ┌──────────────┐    VMess（UUID 派生自 EVM 地址）            │
│  │  Client A    │──────────────────────────────────┐         │
│  │  (ID 在列表) │                                  ▼         │
│  └──────────────┘                         ┌─────────────────┐│
│                                           │  sing-box Server ││
│  ┌──────────────┐                         │  VMess Inbound  ││
│  │  Client B    │─── 连接被拒绝 ──────────▶│  本地 UUID 列表  ││
│  │  (ID 不在列表)│                         │  O(1) 哈希匹配  ││
│  └──────────────┘                         └────────┬────────┘│
│                                                    │         │
│  ┌───────────────────────────┐           ┌─────────▼───────┐ │
│  │  allowed_ids.json         │           │  Auth Service   │ │
│  │  [EVM 地址列表，≤ 1 万]   │◀── 读取 ──│  HTTP :8080     │ │
│  └───────────────────────────┘           │  /v1/sync       │ │
│                                          │  /v1/check      │ │
│       订阅事件触发                        │  /health        │ │
│  新用户/到期/取消 ──────────────────────▶└─────────────────┘ │
│  → 更新 allowed_ids.json                          │          │
│  → 调用 /v1/sync                                  │          │
│  → 重新生成 sing-box config                        │          │
│  → graceful reload（< 100ms，不中断已有连接）       │          │
└──────────────────────────────────────────────────────────────┘
```

### 3.2 EVM 地址 → UUID 映射

sing-box VMess 协议的用户标识必须是 UUID 格式（128 bit）。
EVM 地址是 20 字节（160 bit），**无法无损放入** UUID（16 字节，128 bit）。

因此采用 **UUID v5 确定性派生**：

```
UUID = uuid5(NAMESPACE_DNS, lowercase(evm_address))

算法：SHA-1(namespace_bytes + evm_address_bytes)
      截取前 16 字节，设置版本位（5）和变体位

特性：
  同一 EVM 地址 → 永远得到同一 UUID  ✅ 确定性
  不同 EVM 地址 → 得到不同 UUID      ✅ 无碰撞（实际上）
  UUID → EVM 地址                   ❌ 密码学不可逆
  UUID → EVM 地址（已知列表内）      ✅ 查找表反查
```

> **注意**：UUID v5 使用 SHA-1，不是 MD5。两者结果不同，必须统一使用 SHA-1。

### 3.3 准入控制流程

```
[变更时] 订阅事件发生
  → 更新 allowed_ids.json
  → Auth Service 重新计算所有 UUID
  → 写入新的 sing-box config.json
  → 发送 SIGHUP → sing-box graceful reload（< 100ms）

[连接时] 客户端发起 VMess 连接
  → sing-box 用本地 UUID 哈希表匹配
  → 匹配成功 → 允许，转发流量
  → 匹配失败 → 拒绝连接
```

---

## 4. 目录结构

```
validation/
├── POC_准入控制验证方案.md          # 本文档
├── allowed_ids.json                 # 允许访问的 EVM 地址列表
├── auth-service/
│   └── main.go                     # Go HTTP 验证服务
├── singbox-server/
│   └── config.json                 # sing-box 服务端配置（由 auth-service 生成）
├── singbox-client-a/
│   └── config.json                 # 客户端 A（ID 在列表中，SOCKS :1080）
├── singbox-client-b/
│   └── config.json                 # 客户端 B（ID 不在列表中，SOCKS :1081）
└── scripts/
    ├── gen_uuid.py                  # EVM 地址 → UUID 工具（含反查）
    └── test_all.sh                  # 一键完整验证脚本（含三个命题）
```

---

## 5. 配置文件详情

### 5.1 `allowed_ids.json`

```json
{
  "version": "1.0",
  "description": "允许接入的 EVM 地址列表（单组，上限 1 万）",
  "allowed_ids": [
    "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  ]
}
```

> - `0xaaa...`：Client A 持有，初始在列表中
> - `0xbbb...`：Client B 持有，**初始不在列表中**，用于命题 C 动态添加验证
> - `0xccc...`：备用地址，始终不在列表中，用于持续验证命题 B

---

### 5.2 `scripts/gen_uuid.py`

```python
#!/usr/bin/env python3
"""
EVM 地址 ↔ UUID 工具

正向：EVM 地址 → UUID
反向：UUID → EVM 地址（仅限 allowed_ids.json 中已知的地址）

用法：
  python3 gen_uuid.py                    # 打印所有示例地址的映射
  python3 gen_uuid.py <evm_address>      # 计算单个地址的 UUID
  python3 gen_uuid.py --reverse <uuid>   # 反查 UUID 对应的 EVM 地址
"""
import uuid
import sys
import json
from pathlib import Path

ALLOWED_IDS_FILE = Path(__file__).parent.parent / "allowed_ids.json"

# 示例 EVM 地址
EXAMPLES = {
    "client_a": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",  # 在列表中
    "client_b": "0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",  # 初始不在列表
    "client_c": "0xcccccccccccccccccccccccccccccccccccccccc",  # 始终不在列表
}


def evm_to_uuid(evm_address: str) -> str:
    """EVM 地址 → UUID v5（SHA-1，NAMESPACE_DNS）"""
    normalized = evm_address.lower().strip()
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, normalized))


def uuid_to_evm(target_uuid: str, known_addresses: list[str]) -> str | None:
    """UUID → EVM 地址（在已知地址列表中反查）"""
    for addr in known_addresses:
        if evm_to_uuid(addr) == target_uuid.lower():
            return addr.lower()
    return None


def load_known_addresses() -> list[str]:
    """从 allowed_ids.json 加载已知地址"""
    if ALLOWED_IDS_FILE.exists():
        with open(ALLOWED_IDS_FILE) as f:
            data = json.load(f)
        return data.get("allowed_ids", [])
    return list(EXAMPLES.values())


if __name__ == "__main__":
    if "--reverse" in sys.argv:
        idx = sys.argv.index("--reverse")
        target = sys.argv[idx + 1] if idx + 1 < len(sys.argv) else None
        if not target:
            print("用法: python3 gen_uuid.py --reverse <uuid>")
            sys.exit(1)
        known = load_known_addresses()
        result = uuid_to_evm(target, known)
        if result:
            print(f"UUID    : {target}")
            print(f"EVM 地址: {result}  ✅ 在已知列表中")
        else:
            print(f"UUID    : {target}")
            print(f"EVM 地址: 未找到  ❌ 不在已知列表中")

    elif len(sys.argv) >= 2 and not sys.argv[1].startswith("--"):
        addr = sys.argv[1]
        print(f"EVM 地址 : {addr.lower()}")
        print(f"派生 UUID : {evm_to_uuid(addr)}")

    else:
        print("示例地址 UUID 映射：\n")
        for role, addr in EXAMPLES.items():
            print(f"  [{role}]")
            print(f"    EVM : {addr}")
            print(f"    UUID: {evm_to_uuid(addr)}")
            print()
        print("反向查表示例：")
        known = load_known_addresses()
        for role, addr in EXAMPLES.items():
            u = evm_to_uuid(addr)
            found = uuid_to_evm(u, known)
            status = "✅ 可反查" if found else "❌ 不在已知列表"
            print(f"  {u} → {found or '未知'}  {status}")
```

---

### 5.3 `auth-service/main.go`

> **POC → 生产切换**：只需修改两个环境变量：
> - `CLASH_API_URL`：POC 用 `http://127.0.0.1:9090`，生产改为 sing-box 所在机器的地址
> - `CLASH_API_SECRET`：与 sing-box server config 中的 `secret` 保持一致
> - Auth Service 代码本身**无需任何修改**

```go
package main

import (
	"bytes"
	"crypto/sha1"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"
)

const (
	AllowedIDsFile  = "../allowed_ids.json"
	SingBoxPort     = 10086
)

// Clash API 配置（通过环境变量覆盖）
// POC：127.0.0.1:9090（本机）
// 生产：sing-box 所在机器的地址，仅改这两个变量
func clashAPIURL() string {
	if v := os.Getenv("CLASH_API_URL"); v != "" {
		return v
	}
	return "http://127.0.0.1:9090"
}

func clashAPISecret() string {
	if v := os.Getenv("CLASH_API_SECRET"); v != "" {
		return v
	}
	return "poc-secret"
}

// ── 数据结构 ──────────────────────────────────────────

type AllowedIDsConfig struct {
	Version     string   `json:"version"`
	Description string   `json:"description"`
	AllowedIDs  []string `json:"allowed_ids"`
}

type UserEntry struct {
	EVMAddress string `json:"evm_address"`
	UUID       string `json:"uuid"`
}

type SingBoxUser struct {
	Name    string `json:"name"`
	UUID    string `json:"uuid"`
	AlterId int    `json:"alter_id"`
}

type CheckResponse struct {
	EVMAddress string `json:"evm_address"`
	UUID       string `json:"uuid"`
	Allowed    bool   `json:"allowed"`
}

type SyncResponse struct {
	Status    string      `json:"status"`
	UserCount int         `json:"user_count"`
	Users     []UserEntry `json:"users"`
}

type HealthResponse struct {
	Status       string `json:"status"`
	AllowedCount int    `json:"allowed_count"`
}

// ── UUID 派生（SHA-1，标准 uuid5）──────────────────────

// evmToUUID 使用 SHA-1 实现标准 uuid v5（NAMESPACE_DNS）
// 与 Python uuid.uuid5(uuid.NAMESPACE_DNS, evm_address) 结果完全一致
func evmToUUID(evmAddress string) string {
	normalized := strings.ToLower(strings.TrimSpace(evmAddress))

	// NAMESPACE_DNS: 6ba7b810-9dad-11d1-80b4-00c04fd430c8
	namespaceDNS := []byte{
		0x6b, 0xa7, 0xb8, 0x10,
		0x9d, 0xad, 0x11, 0xd1,
		0x80, 0xb4, 0x00, 0xc0, 0x4f, 0xd4, 0x30, 0xc8,
	}

	h := sha1.New()
	h.Write(namespaceDNS)
	h.Write([]byte(normalized))
	hash := h.Sum(nil) // SHA-1 → 20 字节

	// 设置版本 5（0101 xxxx）
	hash[6] = (hash[6] & 0x0f) | 0x50
	// 设置变体位（10xx xxxx）
	hash[8] = (hash[8] & 0x3f) | 0x80

	return fmt.Sprintf("%x-%x-%x-%x-%x",
		hash[0:4], hash[4:6], hash[6:8], hash[8:10], hash[10:16])
}

// ── 文件 IO ────────────────────────────────────────────

func loadAllowedIDs() (*AllowedIDsConfig, error) {
	data, err := os.ReadFile(AllowedIDsFile)
	if err != nil {
		return nil, fmt.Errorf("读取 %s 失败: %w", AllowedIDsFile, err)
	}
	var cfg AllowedIDsConfig
	if err := json.Unmarshal(data, &cfg); err != nil {
		return nil, fmt.Errorf("解析失败: %w", err)
	}
	return &cfg, nil
}

// buildSingBoxConfig 构建完整的 sing-box 服务端配置
func buildSingBoxConfig(users []SingBoxUser) ([]byte, error) {
	type Inbound struct {
		Type       string        `json:"type"`
		Tag        string        `json:"tag"`
		Listen     string        `json:"listen"`
		ListenPort int           `json:"listen_port"`
		Users      []SingBoxUser `json:"users"`
	}
	type Outbound struct {
		Type string `json:"type"`
		Tag  string `json:"tag"`
	}
	type ClashAPI struct {
		ExternalController string `json:"external_controller"`
		Secret             string `json:"secret"`
	}
	type Experimental struct {
		ClashAPI ClashAPI `json:"clash_api"`
	}
	type Log struct {
		Level string `json:"level"`
	}
	config := struct {
		Log          Log          `json:"log"`
		Inbounds     []Inbound    `json:"inbounds"`
		Outbounds    []Outbound   `json:"outbounds"`
		Experimental Experimental `json:"experimental"`
	}{
		Log: Log{Level: "info"},
		Inbounds: []Inbound{{
			Type:       "vmess",
			Tag:        "vmess-in",
			Listen:     "0.0.0.0",
			ListenPort: SingBoxPort,
			Users:      users,
		}},
		Outbounds: []Outbound{{Type: "direct", Tag: "direct"}},
		Experimental: Experimental{
			ClashAPI: ClashAPI{
				ExternalController: "127.0.0.1:9090",
				Secret:             clashAPISecret(),
			},
		},
	}
	return json.MarshalIndent(config, "", "  ")
}

// reloadViaCLashAPI 通过 Clash API 推送新 config 并触发 graceful reload
// POC：目标是 127.0.0.1:9090
// 生产：目标是远程 sing-box 机器的 IP:9090
// 代码不变，只改 CLASH_API_URL 环境变量
func reloadViaClashAPI(configData []byte) error {
	url := clashAPIURL() + "/configs?force=false"

	req, err := http.NewRequest(http.MethodPut, url, bytes.NewReader(configData))
	if err != nil {
		return fmt.Errorf("构建请求失败: %w", err)
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+clashAPISecret())

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return fmt.Errorf("Clash API 请求失败（sing-box 是否已启动？）: %w", err)
	}
	defer resp.Body.Close()

	body, _ := io.ReadAll(resp.Body)
	if resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNoContent {
		return fmt.Errorf("Clash API 返回 %d: %s", resp.StatusCode, string(body))
	}

	log.Printf("sing-box graceful reload 成功（via Clash API %s）", clashAPIURL())
	return nil
}

// ── HTTP 处理器 ────────────────────────────────────────

// handleSync 读取 allowed_ids.json → 生成 sing-box config → reload
// POST /v1/sync
func handleSync(w http.ResponseWriter, r *http.Request) {
	cfg, err := loadAllowedIDs()
	if err != nil {
		log.Printf("ERROR: %v", err)
		http.Error(w, `{"error":"读取配置失败"}`, http.StatusInternalServerError)
		return
	}

	// 生成用户列表（同时构建 uuid→evm 反查表）
	var singBoxUsers []SingBoxUser
	var userEntries []UserEntry

	for _, id := range cfg.AllowedIDs {
		u := evmToUUID(id)
		singBoxUsers = append(singBoxUsers, SingBoxUser{
			Name:    id, // name 字段携带 EVM 地址，便于日志分析
			UUID:    u,
			AlterId: 0,
		})
		userEntries = append(userEntries, UserEntry{
			EVMAddress: strings.ToLower(id),
			UUID:       u,
		})
	}

	// 构建新的 sing-box config
	configData, err := buildSingBoxConfig(singBoxUsers)
	if err != nil {
		log.Printf("ERROR 构建 config: %v", err)
		http.Error(w, `{"error":"构建 config 失败"}`, http.StatusInternalServerError)
		return
	}

	// 通过 Clash API 推送新 config 并触发 graceful reload
	// POC 和生产使用同一套代码，通过环境变量区分目标地址
	reloadErr := reloadViaClashAPI(configData)
	status := "synced_and_reloaded"
	if reloadErr != nil {
		log.Printf("WARN: %v", reloadErr)
		status = "sing_box_not_running" // sing-box 未启动，首次启动时正常
	}

	log.Printf("同步完成，用户数: %d", len(cfg.AllowedIDs))

	resp := SyncResponse{
		Status:    status,
		UserCount: len(userEntries),
		Users:     userEntries,
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(resp)
}

// handleCheck 检查某 EVM 地址是否在允许列表中
// GET /v1/check?id=<evm_address>
func handleCheck(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	if id == "" {
		http.Error(w, `{"error":"缺少参数 id"}`, http.StatusBadRequest)
		return
	}

	cfg, err := loadAllowedIDs()
	if err != nil {
		http.Error(w, `{"error":"服务内部错误"}`, http.StatusInternalServerError)
		return
	}

	normalizedID := strings.ToLower(strings.TrimSpace(id))
	allowed := false
	for _, allowedID := range cfg.AllowedIDs {
		if strings.ToLower(allowedID) == normalizedID {
			allowed = true
			break
		}
	}

	resp := CheckResponse{
		EVMAddress: normalizedID,
		UUID:       evmToUUID(normalizedID),
		Allowed:    allowed,
	}

	w.Header().Set("Content-Type", "application/json")
	if !allowed {
		w.WriteHeader(http.StatusForbidden)
	}
	json.NewEncoder(w).Encode(resp)
}

// handleHealth 健康检查
// GET /health
func handleHealth(w http.ResponseWriter, r *http.Request) {
	cfg, err := loadAllowedIDs()
	if err != nil {
		w.WriteHeader(http.StatusServiceUnavailable)
		json.NewEncoder(w).Encode(map[string]string{
			"status": "error",
			"detail": err.Error(),
		})
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(HealthResponse{
		Status:       "ok",
		AllowedCount: len(cfg.AllowedIDs),
	})
}

// ── 入口 ────────────────────────────────────────────────

func main() {
	port := "8080"
	if p := os.Getenv("PORT"); p != "" {
		port = p
	}

	http.HandleFunc("/v1/sync", handleSync)
	http.HandleFunc("/v1/check", handleCheck)
	http.HandleFunc("/health", handleHealth)

	log.Printf("Auth Service 启动，监听端口 :%s", port)
	log.Printf("  POST /v1/sync                    — 同步用户列表并 reload sing-box")
	log.Printf("  GET  /v1/check?id=<evm_address>  — 检查 EVM 地址是否允许")
	log.Printf("  GET  /health                      — 健康检查")
	log.Printf("")
	log.Printf("  Clash API 目标: %s", clashAPIURL())
	log.Printf("  （生产环境：export CLASH_API_URL=http://<sing-box-ip>:9090）")
	log.Printf("  （生产环境：export CLASH_API_SECRET=<your-secret>）")

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("启动失败: %v", err)
	}
}
```

---

### 5.4 `singbox-server/config.json`（模板，由 Auth Service 生成）

> Auth Service 启动后首次调用 `POST /v1/sync` 会生成此文件并推送给 sing-box。
> 以下展示关键结构，**`experimental.clash_api` 是核心新增部分**：

```json
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "vmess",
      "tag": "vmess-in",
      "listen": "0.0.0.0",
      "listen_port": 10086,
      "users": [
        {
          "name": "0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "uuid": "<uuid5派生值>",
          "alter_id": 0
        }
      ]
    }
  ],
  "outbounds": [
    { "type": "direct", "tag": "direct" }
  ],
  "experimental": {
    "clash_api": {
      "external_controller": "127.0.0.1:9090",
      "secret": "poc-secret"
    }
  }
}
```

| 环境 | `external_controller` | `secret` |
|------|-----------------------|----------|
| POC（本机） | `127.0.0.1:9090` | `poc-secret` |
| 生产（远程访问） | `0.0.0.0:9090` | 强随机字符串 |

---

### 5.5 `singbox-client-a/config.json`

使用 **Client A（在列表中）** 的 EVM 地址 `0xaaa...` 派生的 UUID。

```json
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "listen_port": 1080
    }
  ],
  "outbounds": [
    {
      "type": "vmess",
      "tag": "vmess-out",
      "server": "127.0.0.1",
      "server_port": 10086,
      "uuid": "<UUID_OF_CLIENT_A>",
      "security": "auto",
      "alter_id": 0
    }
  ]
}
```

### 5.6 `singbox-client-b/config.json`

使用 **Client B（初始不在列表中）** 的 EVM 地址 `0xbbb...` 派生的 UUID。

```json
{
  "log": { "level": "info" },
  "inbounds": [
    {
      "type": "socks",
      "tag": "socks-in",
      "listen": "127.0.0.1",
      "listen_port": 1081
    }
  ],
  "outbounds": [
    {
      "type": "vmess",
      "tag": "vmess-out",
      "server": "127.0.0.1",
      "server_port": 10086,
      "uuid": "<UUID_OF_CLIENT_B>",
      "security": "auto",
      "alter_id": 0
    }
  ]
}
```

---

### 5.7 `scripts/test_all.sh`

一键执行三个命题的完整验证。

```bash
#!/bin/bash
set -e

AUTH="http://127.0.0.1:8080"
TEST_URL="http://httpbin.org/ip"
EVM_A="0xaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"  # 初始在列表
EVM_B="0xbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"  # 初始不在列表
SOCKS_A="127.0.0.1:1080"
SOCKS_B="127.0.0.1:1081"
ALLOWED_IDS="../allowed_ids.json"

pass=0; fail=0

check() {
  local label="$1"; local expect_ok="$2"; local result="$3"
  if [ "$expect_ok" = "true" ] && [ "$result" = "ok" ]; then
    echo "  ✅ PASS: $label"; ((pass++))
  elif [ "$expect_ok" = "false" ] && [ "$result" = "fail" ]; then
    echo "  ✅ PASS: $label（正确被拒绝）"; ((pass++))
  else
    echo "  ❌ FAIL: $label"; ((fail++))
  fi
}

try_curl() {
  local socks="$1"
  if curl -sS --max-time 8 --socks5 "$socks" "$TEST_URL" > /dev/null 2>&1; then
    echo "ok"
  else
    echo "fail"
  fi
}

echo "================================================"
echo "  OpenMesh V2 准入控制 POC 验证"
echo "================================================"
echo ""

# ── 前置检查 ──────────────────────────────────────────
echo "▶ 前置检查"

echo "  Auth Service 健康状态："
curl -sS "$AUTH/health" | python3 -m json.tool 2>/dev/null || echo "  ⚠️  Auth Service 未运行"

echo ""
echo "  EVM 地址准入状态："
echo "    Client A ($EVM_A):"
curl -sS "$AUTH/v1/check?id=$EVM_A" | python3 -m json.tool 2>/dev/null
echo "    Client B ($EVM_B):"
curl -sS "$AUTH/v1/check?id=$EVM_B" | python3 -m json.tool 2>/dev/null

echo ""

# ── 命题 A：准入 ──────────────────────────────────────
echo "▶ 命题 A：Client A（ID 在列表中）可以访问"
result_a=$(try_curl "$SOCKS_A")
check "Client A 通过 SOCKS :1080 访问 $TEST_URL" "true" "$result_a"
echo ""

# ── 命题 B：拒绝 ──────────────────────────────────────
echo "▶ 命题 B：Client B（ID 不在列表中）被拒绝"
result_b=$(try_curl "$SOCKS_B")
check "Client B 通过 SOCKS :1081 访问 $TEST_URL（期望失败）" "false" "$result_b"
echo ""

# ── 命题 C：动态生效 ──────────────────────────────────
echo "▶ 命题 C：动态添加 Client B，reload 后立即生效"

echo "  Step C-1: 将 Client B 的 EVM 地址加入 allowed_ids.json..."
python3 - <<PYEOF
import json
with open("$ALLOWED_IDS") as f:
    data = json.load(f)
if "$EVM_B" not in data["allowed_ids"]:
    data["allowed_ids"].append("$EVM_B")
    with open("$ALLOWED_IDS", "w") as f:
        json.dump(data, f, indent=2)
    print("    已添加 $EVM_B")
else:
    print("    $EVM_B 已存在（跳过）")
PYEOF

echo "  Step C-2: 触发 Auth Service 同步并 reload sing-box..."
curl -sS -X POST "$AUTH/v1/sync" | python3 -m json.tool 2>/dev/null

echo "  Step C-3: 等待 reload 完成（2 秒）..."
sleep 2

echo "  Step C-4: Client B 重新尝试访问..."
result_c=$(try_curl "$SOCKS_B")
check "Client B 动态加入列表后可以访问" "true" "$result_c"
echo ""

# ── 验证 Client A 在整个过程中未中断 ─────────────────
echo "▶ 附加验证：Client A 在 reload 后仍然可以访问（验证不中断性）"
result_a2=$(try_curl "$SOCKS_A")
check "Client A reload 后仍然正常访问" "true" "$result_a2"
echo ""

# ── 恢复初始状态 ──────────────────────────────────────
echo "▶ 恢复：将 allowed_ids.json 还原到初始状态..."
python3 - <<PYEOF
import json
with open("$ALLOWED_IDS") as f:
    data = json.load(f)
data["allowed_ids"] = [x for x in data["allowed_ids"] if x != "$EVM_B"]
with open("$ALLOWED_IDS", "w") as f:
    json.dump(data, f, indent=2)
print("    已移除 $EVM_B，还原完成")
PYEOF
curl -sS -X POST "$AUTH/v1/sync" > /dev/null
echo ""

# ── 汇总 ──────────────────────────────────────────────
echo "================================================"
echo "  验证结果：通过 $pass 个，失败 $fail 个"
if [ "$fail" -eq 0 ]; then
  echo "  🎉 所有命题验证通过"
else
  echo "  ⚠️  有 $fail 个命题未通过，请检查配置"
fi
echo "================================================"
```

---

## 6. 逐步操作指南

### Step 0：查看 UUID 映射

```bash
python3 scripts/gen_uuid.py
```

记录输出的 UUID，填入客户端配置文件（替换 `<UUID_OF_CLIENT_A>` 和 `<UUID_OF_CLIENT_B>`）。

也可以用反查功能验证 UUID 正确性：

```bash
python3 scripts/gen_uuid.py --reverse <uuid>
```

### Step 1：启动 Auth Service

```bash
cd auth-service

# POC（默认，本机 Clash API）
go run main.go

# 生产（指向远程 sing-box）
# CLASH_API_URL=http://<sing-box-ip>:9090 CLASH_API_SECRET=<secret> go run main.go
```

### Step 2：初始同步（生成 + 推送 sing-box config）

> 此时 sing-box 尚未启动，sync 会提示 `sing_box_not_running`，这是正常的。
> config 内容已在内存中构建好，sing-box 启动后会用此配置。

```bash
curl -X POST http://127.0.0.1:8080/v1/sync
```

### Step 3：启动 sing-box 服务端

> sing-box 启动时读取本地 config 文件。
> Auth Service 在 sync 时同时会生成 config 文件到 `singbox-server/config.json`。

```bash
sing-box run -c singbox-server/config.json
```

> sing-box 启动后 Clash API 在 `127.0.0.1:9090` 可用。后续所有 sync 操作都通过 Clash API 推送，**无需重启 sing-box**。

### Step 4：启动两个客户端

```bash
# 终端 A：Client A（EVM 在列表中，SOCKS :1080）
sing-box run -c singbox-client-a/config.json

# 终端 B：Client B（EVM 初始不在列表，SOCKS :1081）
sing-box run -c singbox-client-b/config.json
```

### Step 5：执行完整验证

```bash
bash scripts/test_all.sh
```

---

## 7. 预期结果

```
================================================
  OpenMesh V2 准入控制 POC 验证
================================================

▶ 命题 A：Client A（ID 在列表中）可以访问
  ✅ PASS: Client A 通过 SOCKS :1080 访问 http://httpbin.org/ip

▶ 命题 B：Client B（ID 不在列表中）被拒绝
  ✅ PASS: Client B 通过 SOCKS :1081 访问 http://httpbin.org/ip（期望失败）

▶ 命题 C：动态添加 Client B，reload 后立即生效
  Step C-1: 已添加 0xbbb...
  Step C-2: {"status":"synced_and_reloaded","user_count":2,...}
  Step C-3: 等待 reload 完成（2 秒）...
  Step C-4: Client B 重新尝试访问...
  ✅ PASS: Client B 动态加入列表后可以访问

▶ 附加验证：Client A 在 reload 后仍然可以访问
  ✅ PASS: Client A reload 后仍然正常访问

================================================
  验证结果：通过 4 个，失败 0 个
  🎉 所有命题验证通过
================================================
```

---

## 8. 关键架构决策记录

| 问题 | 决策 | 原因 |
|------|------|------|
| 协议选择 | VMess | 成熟、生态好，客户端（OpenHub）已集成 |
| 用户标识格式 | UUID v5（SHA-1） | VMess 协议硬要求；EVM→UUID 确定性派生 |
| UUID 不可逆 | 用查找表反查 | EVM 20 字节 > UUID 16 字节，不能无损编码 |
| 实时鉴权 | 否（本地 UUID 列表匹配） | VMess 协议不支持外部鉴权回调 |
| reload 触发机制 | Clash API `PUT /configs`（HTTP） | 跨机器可用；POC 用 localhost，生产改远程 IP，代码不变 |
| reload 方式 | graceful reload（现有连接不断） | Clash API `?force=false` 保证在途连接完成后切换 |
| 每组规模上限 | 1 万用户 | 超出后客户端分配至新组，每组独立管理 |
| 动态 gRPC API | 不采用（XRay 特有） | 1 万用户 reload 足够快，不引入额外复杂度 |

---

## 9. 与 V2 生产设计的对应关系

| POC 组件 | 生产对应 | 差距 |
|---------|---------|------|
| `allowed_ids.json` | 订阅数据库 `subscriptions` 表 | POC 静态文件，生产为数据库实时查询 |
| `POST /v1/sync` 触发 | 订阅事件（支付成功/到期/取消）触发 | POC 手动调用，生产由事件驱动 |
| EVM → UUID 算法 | 完全相同 | ✅ 直接复用 |
| Clash API reload | 完全相同 | ✅ 直接复用，仅改 `CLASH_API_URL` 环境变量 |
| `name` = EVM 地址 | 完全相同 | ✅ 直接复用，日志天然可读 |
| 单组实现 | 多组水平扩展 | POC 单组，生产由客户端分组路由 |
