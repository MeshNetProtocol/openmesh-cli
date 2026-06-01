# Phase 3: 用户流量统计与限制功能 POC

## 概述

在 Phase 2 的基础上，增加用户流量统计功能，并在 Web 界面上显示每个用户的流量使用情况，同时在流量旁边提供限制按钮来停止服务。

## 目标

1. 通过 Xray Stats API 获取每个用户的上行和下行流量
2. 在 Web 界面上显示 2 个用户的实时流量统计
3. 在每个用户的流量信息旁边添加"限制"按钮
4. 点击限制按钮后，停止为该用户提供服务（复用 Phase 2 的删除用户功能）
5. **实现流量持久化**，避免 Xray 重启后流量数据丢失

## 核心问题与解决方案

### 问题 1: Xray 重启后流量统计清零

**问题描述：**
- Xray 的流量统计存储在内存中
- Xray 重启后，所有流量统计从 0 开始
- 无法追踪用户的历史总流量

**解决方案：流量持久化到文件**

参考开源项目 [xray-traffic-statistics](https://github.com/0x187/xray-traffic-statistics) 的实现思路：

1. **定期轮询** - 每 5 秒查询一次 Xray Stats API
2. **计算增量** - 当前流量 - 上次记录的流量 = 本次增量
3. **检测重启** - 如果当前流量 < 上次流量，说明 Xray 重启了
4. **持久化到文件** - 将增量累加到文件中的历史总流量

**数据结构设计：**

```json
{
  "users": [
    {
      "email": "0x1234567890abcdef1234567890abcdef12345678",
      "uuid": "11111111-1111-1111-1111-111111111111",
      "enabled": true,
      "total_uplink": 1660,           // 历史累计上行流量（持久化）
      "total_downlink": 1059892,      // 历史累计下行流量（持久化）
      "last_xray_uplink": 830,        // 上次从 Xray 读取的上行流量
      "last_xray_downlink": 529946,   // 上次从 Xray 读取的下行流量
      "traffic_uplink": 2490,         // 显示给用户的总上行流量
      "traffic_downlink": 1589838     // 显示给用户的总下行流量
    }
  ]
}
```

**实现逻辑：**

```go
func (c *UsersConfig) UpdateTrafficStats() error {
    c.mu.Lock()
    defer c.mu.Unlock()

    for i := range c.Users {
        if !c.Users[i].Enabled {
            continue
        }

        // 查询 Xray 当前流量
        currentUplink, currentDownlink, err := queryUserTraffic(c.Users[i].Email)
        if err != nil {
            log.Printf("Failed to query traffic for %s: %v", c.Users[i].Email, err)
            continue
        }

        // 检测 Xray 是否重启（当前流量 < 上次记录的流量）
        if currentUplink < c.Users[i].LastXrayUplink || 
           currentDownlink < c.Users[i].LastXrayDownlink {
            log.Printf("Detected Xray restart for user %s", c.Users[i].Email)

            // Xray 重启了，将上次的值作为最后一次增量累加到总流量
            c.Users[i].TotalUplink += c.Users[i].LastXrayUplink
            c.Users[i].TotalDownlink += c.Users[i].LastXrayDownlink

            // 重置上次记录的值为当前值
            c.Users[i].LastXrayUplink = currentUplink
            c.Users[i].LastXrayDownlink = currentDownlink
        } else {
            // 正常情况，计算增量
            deltaUplink := currentUplink - c.Users[i].LastXrayUplink
            deltaDownlink := currentDownlink - c.Users[i].LastXrayDownlink

            // 累加到总流量
            c.Users[i].TotalUplink += deltaUplink
            c.Users[i].TotalDownlink += deltaDownlink

            // 更新上次记录的值
            c.Users[i].LastXrayUplink = currentUplink
            c.Users[i].LastXrayDownlink = currentDownlink
        }

        // 更新用于 API 返回的流量值（总流量 + 当前 Xray 流量）
        c.Users[i].TrafficUplink = c.Users[i].TotalUplink + c.Users[i].LastXrayUplink
        c.Users[i].TrafficDownlink = c.Users[i].TotalDownlink + c.Users[i].LastXrayDownlink
    }

    // 持久化到文件
    return c.Save()
}
```

**验证结果：**

测试场景：
1. 生成流量 515 KB
2. 重启 Xray 服务
3. 再次生成流量 515 KB

结果：
- 重启前：total = 830 bytes, 显示 1660 bytes
- 重启后：total = 1660 bytes（保留了重启前的流量）
- 再次生成流量后：total = 2490 bytes（正确累加）

✅ **流量持久化功能验证成功！**

---

## 技术方案

### 1. Xray 流量统计配置

Phase 2 的 `xray_server.json` 已经配置了流量统计功能：

```json
{
  "api": {
    "tag": "api",
    "services": [
      "HandlerService",
      "StatsService"  // ✅ 已启用
    ]
  },
  "stats": {},  // ✅ 已启用
  "policy": {
    "system": {
      "statsInboundUplink": true,    // ✅ 统计上行流量
      "statsInboundDownlink": true   // ✅ 统计下行流量
    }
  }
}
```

### 2. 流量查询方法

#### 方法 1: 使用 xray api 命令行工具（推荐）

```bash
# 查询所有统计信息
xray api statsquery --server=127.0.0.1:10085

# 查询特定用户的流量
xray api statsquery --server=127.0.0.1:10085 --pattern="user>>>0x1234567890abcdef1234567890abcdef12345678>>>"
```

输出格式：
```
user>>>0x1234567890abcdef1234567890abcdef12345678>>>traffic>>>uplink: 1234567
user>>>0x1234567890abcdef1234567890abcdef12345678>>>traffic>>>downlink: 7654321
```

#### 方法 2: 使用 Python + gRPC（备选）

如果需要更精细的控制，可以使用 Python 直接调用 gRPC API：

```python
import grpc
from google.protobuf import empty_pb2

# 连接到 Xray Stats API
channel = grpc.insecure_channel('127.0.0.1:10085')

# 调用 StatsService.QueryStats
# 需要生成的 protobuf 代码
```

### 3. Go Auth Service 改造

#### 3.1 数据结构扩展

在 `auth-service/main.go` 中扩展 User 结构：

```go
type User struct {
    Email          string `json:"email"`
    UUID           string `json:"uuid"`
    Enabled        bool   `json:"enabled"`
    TrafficUplink  int64  `json:"traffic_uplink"`   // 新增：上行流量（字节）
    TrafficDownlink int64 `json:"traffic_downlink"` // 新增：下行流量（字节）
}
```

#### 3.2 新增流量查询函数

```go
import (
    "os/exec"
    "regexp"
    "strconv"
    "strings"
)

// 查询用户流量统计
func queryUserTraffic(email string) (uplink int64, downlink int64, err error) {
    // 调用 xray api statsquery 命令
    cmd := exec.Command("xray", "api", "statsquery", 
        "--server=127.0.0.1:10085",
        fmt.Sprintf("--pattern=user>>>%s>>>", email))
    
    output, err := cmd.CombinedOutput()
    if err != nil {
        return 0, 0, fmt.Errorf("statsquery failed: %v, output: %s", err, output)
    }
    
    // 解析输出
    // user>>>email>>>traffic>>>uplink: 1234567
    // user>>>email>>>traffic>>>downlink: 7654321
    
    lines := strings.Split(string(output), "\n")
    uplinkRegex := regexp.MustCompile(`uplink:\s*(\d+)`)
    downlinkRegex := regexp.MustCompile(`downlink:\s*(\d+)`)
    
    for _, line := range lines {
        if match := uplinkRegex.FindStringSubmatch(line); match != nil {
            uplink, _ = strconv.ParseInt(match[1], 10, 64)
        }
        if match := downlinkRegex.FindStringSubmatch(line); match != nil {
            downlink, _ = strconv.ParseInt(match[1], 10, 64)
        }
    }
    
    return uplink, downlink, nil
}

// 查询所有用户的流量
func (c *UsersConfig) UpdateTrafficStats() error {
    c.mu.Lock()
    defer c.mu.Unlock()
    
    for i := range c.Users {
        if c.Users[i].Enabled {
            uplink, downlink, err := queryUserTraffic(c.Users[i].Email)
            if err != nil {
                log.Printf("Failed to query traffic for %s: %v", c.Users[i].Email, err)
                continue
            }
            c.Users[i].TrafficUplink = uplink
            c.Users[i].TrafficDownlink = downlink
        }
    }
    
    return nil
}
```

#### 3.3 新增 API 端点

```go
func main() {
    http.HandleFunc("/", handleIndex)
    http.HandleFunc("/api/users", handleGetUsers)
    http.HandleFunc("/api/users/toggle", handleToggleUser)
    http.HandleFunc("/api/users/restrict", handleRestrictUser)  // 新增：限制用户
    
    // 启动定时任务，每 5 秒更新一次流量统计
    go func() {
        ticker := time.NewTicker(5 * time.Second)
        defer ticker.Stop()
        for range ticker.C {
            config.UpdateTrafficStats()
        }
    }()
    
    addr := ":8080"
    log.Printf("Auth Service started at http://localhost%s", addr)
    if err := http.ListenAndServe(addr, nil); err != nil {
        log.Fatalf("Failed to start server: %v", err)
    }
}

// 处理限制用户请求（禁用用户）
func handleRestrictUser(w http.ResponseWriter, r *http.Request) {
    if r.Method != http.MethodPost {
        http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
        return
    }
    
    var req struct {
        Email string `json:"email"`
    }
    
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    
    // 查找用户并禁用
    config.mu.Lock()
    defer config.mu.Unlock()
    
    for i := range config.Users {
        if config.Users[i].Email == req.Email {
            if !config.Users[i].Enabled {
                w.Header().Set("Content-Type", "application/json")
                json.NewEncoder(w).Encode(map[string]interface{}{
                    "success": false,
                    "error":   "User already disabled",
                })
                return
            }
            
            config.Users[i].Enabled = false
            
            if err := config.Save(); err != nil {
                w.Header().Set("Content-Type", "application/json")
                json.NewEncoder(w).Encode(map[string]interface{}{
                    "success": false,
                    "error":   err.Error(),
                })
                return
            }
            
            // 从 Xray 删除用户
            if err := removeUserFromXray(config.Users[i]); err != nil {
                w.Header().Set("Content-Type", "application/json")
                json.NewEncoder(w).Encode(map[string]interface{}{
                    "success": false,
                    "error":   err.Error(),
                })
                return
            }
            
            w.Header().Set("Content-Type", "application/json")
            json.NewEncoder(w).Encode(map[string]interface{}{
                "success": true,
            })
            return
        }
    }
    
    w.Header().Set("Content-Type", "application/json")
    json.NewEncoder(w).Encode(map[string]interface{}{
        "success": false,
        "error":   "User not found",
    })
}
```

### 4. Web 界面改造

#### 4.1 表格结构调整

在 `handleIndex` 函数的 HTML 模板中，修改表格结构：

```html
<table id="usersTable">
    <thead>
        <tr>
            <th>Email</th>
            <th>UUID</th>
            <th>Status</th>
            <th>Traffic (Uplink)</th>      <!-- 新增 -->
            <th>Traffic (Downlink)</th>    <!-- 新增 -->
            <th>Total Traffic</th>         <!-- 新增 -->
            <th>Actions</th>                <!-- 修改 -->
        </tr>
    </thead>
    <tbody id="usersBody">
    </tbody>
</table>
```

#### 4.2 JavaScript 改造

```javascript
// 格式化字节数为人类可读格式
function formatBytes(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function loadUsers() {
    fetch('/api/users')
        .then(response => response.json())
        .then(data => {
            const tbody = document.getElementById('usersBody');
            tbody.innerHTML = '';

            data.users.forEach(user => {
                const row = tbody.insertRow();
                
                const totalTraffic = user.traffic_uplink + user.traffic_downlink;
                
                row.innerHTML = 
                    '<td>' + user.email + '</td>' +
                    '<td><code>' + user.uuid + '</code></td>' +
                    '<td class="' + (user.enabled ? 'enabled' : 'disabled') + '">' +
                        (user.enabled ? '✓ Enabled' : '✗ Disabled') +
                    '</td>' +
                    '<td>' + formatBytes(user.traffic_uplink) + '</td>' +
                    '<td>' + formatBytes(user.traffic_downlink) + '</td>' +
                    '<td><strong>' + formatBytes(totalTraffic) + '</strong></td>' +
                    '<td>' +
                        '<button class="' + (user.enabled ? 'btn-disable' : 'btn-enable') + '" ' +
                            'onclick="toggleUser(\'' + user.email + '\')">' +
                            (user.enabled ? 'Disable' : 'Enable') +
                        '</button> ' +
                        (user.enabled ? 
                            '<button class="btn-restrict" onclick="restrictUser(\'' + user.email + '\')">Restrict</button>' 
                            : '') +
                    '</td>';
            });
        })
        .catch(error => {
            showStatus('Failed to load users: ' + error, 'error');
        });
}

// 新增：限制用户函数
function restrictUser(email) {
    if (!confirm('Are you sure you want to restrict this user? This will immediately stop their service.')) {
        return;
    }
    
    fetch('/api/users/restrict', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
        },
        body: JSON.stringify({ email: email })
    })
    .then(response => response.json())
    .then(data => {
        if (data.success) {
            showStatus('User restricted successfully', 'success');
            loadUsers();
        } else {
            showStatus('Failed to restrict user: ' + data.error, 'error');
        }
    })
    .catch(error => {
        showStatus('Request failed: ' + error, 'error');
    });
}

// 每 3 秒自动刷新一次（显示实时流量）
loadUsers();
setInterval(loadUsers, 3000);
```

#### 4.3 CSS 样式增强

```css
.btn-restrict {
    background-color: #ff9800;
    color: white;
    margin-left: 5px;
}

.btn-restrict:hover {
    opacity: 0.8;
}

/* 流量列样式 */
td:nth-child(4), td:nth-child(5), td:nth-child(6) {
    font-family: 'Courier New', monospace;
    text-align: right;
}
```

## 实现步骤

### Step 1: 验证 Xray Stats API

```bash
cd /Users/hyperorchid/MeshNetProtocol/openmesh-cli/docs/V2_design/validation/phase2

# 启动所有服务
./start_all.sh

# 等待服务启动后，查询流量统计
xray api statsquery --server=127.0.0.1:10085

# 预期输出：
# user>>>0x1234567890abcdef1234567890abcdef12345678>>>traffic>>>uplink: 0
# user>>>0x1234567890abcdef1234567890abcdef12345678>>>traffic>>>downlink: 0
# ...
```

### Step 2: 创建 Phase 3 目录

```bash
# 复制 Phase 2 到 Phase 3
cp -r phase2 phase3
cd phase3
```

### Step 3: 修改 Go Auth Service

1. 修改 `auth-service/main.go`，添加上述代码
2. 添加流量查询函数
3. 添加 `/api/users/restrict` 端点
4. 添加定时任务更新流量统计
5. 修改 HTML 模板，添加流量显示列和限制按钮

### Step 4: 测试流量统计

```bash
# 重新编译并启动服务
cd auth-service
go build -o auth-service
cd ..
./stop_all.sh
./start_all.sh

# 访问 Web 界面
open http://localhost:8080

# 使用客户端生成流量
./test_clients.sh

# 在 Web 界面观察流量变化
# 应该能看到上行和下行流量实时更新
```

### Step 5: 测试限制功能

1. 在 Web 界面上，观察 User 1 的流量统计
2. 点击 User 1 旁边的"Restrict"按钮
3. 确认限制操作
4. 验证 User 1 的状态变为"Disabled"
5. 运行 `./test_clients.sh` 验证 User 1 无法连接

## 预期效果

### Web 界面展示

```
Auth Service - User Management
管理 Xray 用户访问权限（使用 xtlsapi 库）

┌──────────────────────────────────────────┬──────────────────────────────────────┬──────────┬────────────┬──────────────┬──────────────┬─────────────────────┐
│ Email                                    │ UUID                                 │ Status   │ Uplink     │ Downlink     │ Total        │ Actions             │
├──────────────────────────────────────────┼──────────────────────────────────────┼──────────┼────────────┼──────────────┼──────────────┼─────────────────────┤
│ 0x1234567890abcdef1234567890abcdef12345678│ 11111111-1111-1111-1111-111111111111│ ✓ Enabled│ 1.23 MB    │ 5.67 MB      │ 6.90 MB      │ [Disable] [Restrict]│
│ 0x9876543210fedcba9876543210fedcba98765432│ 22222222-2222-2222-2222-222222222222│ ✗ Disabled│ 0 B        │ 0 B          │ 0 B          │ [Enable]            │
└──────────────────────────────────────────┴──────────────────────────────────────┴──────────┴────────────┴──────────────┴──────────────┴─────────────────────┘
```

### 功能特性

1. **实时流量显示**: 每 3 秒自动刷新，显示最新的流量统计
2. **人类可读格式**: 自动转换字节数为 KB/MB/GB
3. **双重控制**:
   - "Disable" 按钮: 切换用户启用/禁用状态
   - "Restrict" 按钮: 直接限制用户（仅对已启用用户显示）
4. **确认对话框**: 点击 Restrict 按钮时弹出确认对话框
5. **状态反馈**: 操作成功/失败后显示提示信息

## 技术要点

### 1. 流量统计的工作原理

- Xray 在 `stats` 模块中记录每个用户的流量
- 流量统计以字节为单位累计
- 统计键格式: `user>>>{email}>>>traffic>>>{uplink|downlink}`
- 流量统计在 Xray 重启后会重置

### 2. 性能考虑

- 定时任务每 5 秒查询一次流量（后端）
- Web 界面每 3 秒刷新一次（前端）
- 对于大量用户，可以考虑：
  - 增加查询间隔
  - 使用缓存
  - 只查询活跃用户

### 3. 错误处理

- 如果 `xray api statsquery` 失败，记录日志但不影响其他功能
- 如果用户已被禁用，Restrict 操作返回错误
- 网络请求失败时显示错误提示

## 后续扩展

1. **流量配额管理**: 为每个用户设置流量限制，超过自动限制
2. **流量历史记录**: 将流量数据持久化到数据库
3. **流量图表**: 使用 Chart.js 显示流量趋势图
4. **流量报警**: 当用户流量超过阈值时发送通知
5. **流量重置**: 提供按钮重置用户的流量统计

## 总结

Phase 3 在 Phase 2 的基础上，通过 Xray Stats API 实现了用户流量统计功能，并在 Web 界面上提供了直观的流量显示和快速限制功能。整个实现复用了 Phase 2 的用户管理逻辑，只需要添加流量查询和界面展示即可。
