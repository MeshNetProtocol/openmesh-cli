# Phase 3 扩展: 多 Xray 服务器流量汇总方案

## 概述

在 Phase 3 流量持久化的基础上，支持用户在多个 Xray 服务器（不同国家/地区）之间切换使用，并汇总所有服务器的流量统计。

## 使用场景

用户可能希望：
- 连接到美国的 Xray 服务器访问美国内容
- 连接到日本的 Xray 服务器访问日本内容
- 连接到欧洲的 Xray 服务器访问欧洲内容

**需求**：无论用户连接到哪个服务器，都需要统计该用户的**总流量**。

## 技术方案

### 1. 数据结构设计

**配置文件结构：**

```json
{
  "xray_servers": [
    {
      "name": "US-Server",
      "address": "192.168.1.100:10085",
      "location": "United States"
    },
    {
      "name": "JP-Server",
      "address": "192.168.1.101:10085",
      "location": "Japan"
    }
  ],
  "users": [
    {
      "email": "0x1234567890abcdef1234567890abcdef12345678",
      "uuid": "11111111-1111-1111-1111-111111111111",
      "enabled": true,
      "servers": {
        "US-Server": {
          "total_uplink": 1024000,
          "total_downlink": 5120000,
          "last_xray_uplink": 512000,
          "last_xray_downlink": 2560000
        },
        "JP-Server": {
          "total_uplink": 2048000,
          "total_downlink": 10240000,
          "last_xray_uplink": 1024000,
          "last_xray_downlink": 5120000
        }
      },
      "total_uplink": 3072000,
      "total_downlink": 15360000
    }
  ]
}
```

### 2. Go 数据结构

```go
type XrayServer struct {
	Name     string `json:"name"`
	Address  string `json:"address"`
	Location string `json:"location"`
}

type ServerTraffic struct {
	TotalUplink      int64 `json:"total_uplink"`
	TotalDownlink    int64 `json:"total_downlink"`
	LastXrayUplink   int64 `json:"last_xray_uplink"`
	LastXrayDownlink int64 `json:"last_xray_downlink"`
}

type User struct {
	Email         string                   `json:"email"`
	UUID          string                   `json:"uuid"`
	Enabled       bool                     `json:"enabled"`
	Servers       map[string]*ServerTraffic `json:"servers"`
	TotalUplink   int64                    `json:"total_uplink"`
	TotalDownlink int64                    `json:"total_downlink"`
}

type UsersConfig struct {
	XrayServers []XrayServer `json:"xray_servers"`
	Users       []User       `json:"users"`
	mu          sync.RWMutex
}
```

### 3. 流量查询逻辑

```go
// 查询指定服务器的用户流量
func queryUserTrafficFromServer(serverAddr, email string) (uplink, downlink int64, err error) {
	cmd := exec.Command("xray", "api", "statsquery",
		fmt.Sprintf("--server=%s", serverAddr),
		fmt.Sprintf("--pattern=user>>>%s>>>", email))

	output, err := cmd.CombinedOutput()
	if err != nil {
		return 0, 0, fmt.Errorf("statsquery failed: %v", err)
	}

	var result struct {
		Stat []struct {
			Name  string `json:"name"`
			Value int64  `json:"value"`
		} `json:"stat"`
	}

	if err := json.Unmarshal(output, &result); err != nil {
		return 0, 0, err
	}

	for _, stat := range result.Stat {
		if strings.Contains(stat.Name, "uplink") {
			uplink = stat.Value
		}
		if strings.Contains(stat.Name, "downlink") {
			downlink = stat.Value
		}
	}

	return uplink, downlink, nil
}

// 更新所有服务器的流量统计
func (c *UsersConfig) UpdateTrafficStats() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	for i := range c.Users {
		if !c.Users[i].Enabled {
			continue
		}

		// 初始化 servers map
		if c.Users[i].Servers == nil {
			c.Users[i].Servers = make(map[string]*ServerTraffic)
		}

		// 重置用户总流量
		c.Users[i].TotalUplink = 0
		c.Users[i].TotalDownlink = 0

		// 遍历所有 Xray 服务器
		for _, server := range c.XrayServers {
			// 初始化服务器流量记录
			if c.Users[i].Servers[server.Name] == nil {
				c.Users[i].Servers[server.Name] = &ServerTraffic{}
			}

			serverTraffic := c.Users[i].Servers[server.Name]

			// 查询当前服务器的流量
			currentUplink, currentDownlink, err := queryUserTrafficFromServer(
				server.Address, c.Users[i].Email)
			if err != nil {
				log.Printf("Failed to query %s for %s: %v", 
					server.Name, c.Users[i].Email, err)
				continue
			}

			// 检测服务器重启
			if currentUplink < serverTraffic.LastXrayUplink || 
			   currentDownlink < serverTraffic.LastXrayDownlink {
				log.Printf("Detected %s restart for user %s", 
					server.Name, c.Users[i].Email)

				// 累加重启前的流量
				serverTraffic.TotalUplink += serverTraffic.LastXrayUplink
				serverTraffic.TotalDownlink += serverTraffic.LastXrayDownlink

				// 重置
				serverTraffic.LastXrayUplink = currentUplink
				serverTraffic.LastXrayDownlink = currentDownlink
			} else {
				// 计算增量
				deltaUplink := currentUplink - serverTraffic.LastXrayUplink
				deltaDownlink := currentDownlink - serverTraffic.LastXrayDownlink

				// 累加
				serverTraffic.TotalUplink += deltaUplink
				serverTraffic.TotalDownlink += deltaDownlink

				// 更新
				serverTraffic.LastXrayUplink = currentUplink
				serverTraffic.LastXrayDownlink = currentDownlink
			}

			// 累加到用户总流量
			c.Users[i].TotalUplink += serverTraffic.TotalUplink + serverTraffic.LastXrayUplink
			c.Users[i].TotalDownlink += serverTraffic.TotalDownlink + serverTraffic.LastXrayDownlink
		}
	}

	return c.Save()
}
```

### 4. Web UI 改造

**表格结构：**

```html
<table>
  <thead>
    <tr>
      <th>Email</th>
      <th>UUID</th>
      <th>Status</th>
      <th>US-Server</th>
      <th>JP-Server</th>
      <th>Total Traffic</th>
      <th>Actions</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>0x1234...</td>
      <td>11111111-1111...</td>
      <td>✓ Enabled</td>
      <td>
        ↑ 1.00 MB<br>
        ↓ 5.00 MB
      </td>
      <td>
        ↑ 2.00 MB<br>
        ↓ 10.00 MB
      </td>
      <td>
        <strong>↑ 3.00 MB<br>
        ↓ 15.00 MB</strong>
      </td>
      <td>
        <button>Disable</button>
        <button>Restrict</button>
      </td>
    </tr>
  </tbody>
</table>
```

**JavaScript 渲染逻辑：**

```javascript
function loadUsers() {
    fetch('/api/users')
        .then(response => response.json())
        .then(data => {
            const tbody = document.getElementById('usersBody');
            tbody.innerHTML = '';

            data.users.forEach(user => {
                const row = tbody.insertRow();
                
                // 基本信息
                row.innerHTML = `
                    <td>${user.email}</td>
                    <td><code>${user.uuid}</code></td>
                    <td class="${user.enabled ? 'enabled' : 'disabled'}">
                        ${user.enabled ? '✓ Enabled' : '✗ Disabled'}
                    </td>
                `;

                // 每个服务器的流量
                data.xray_servers.forEach(server => {
                    const serverTraffic = user.servers[server.name] || {
                        total_uplink: 0,
                        total_downlink: 0,
                        last_xray_uplink: 0,
                        last_xray_downlink: 0
                    };
                    
                    const uplink = serverTraffic.total_uplink + serverTraffic.last_xray_uplink;
                    const downlink = serverTraffic.total_downlink + serverTraffic.last_xray_downlink;
                    
                    const cell = row.insertCell();
                    cell.className = 'traffic-cell';
                    cell.innerHTML = `
                        ↑ ${formatBytes(uplink)}<br>
                        ↓ ${formatBytes(downlink)}
                    `;
                });

                // 总流量
                const totalCell = row.insertCell();
                totalCell.className = 'traffic-cell';
                totalCell.innerHTML = `
                    <strong>↑ ${formatBytes(user.total_uplink)}<br>
                    ↓ ${formatBytes(user.total_downlink)}</strong>
                `;

                // 操作按钮
                const actionsCell = row.insertCell();
                actionsCell.innerHTML = `
                    <button class="${user.enabled ? 'btn-disable' : 'btn-enable'}" 
                            onclick="toggleUser('${user.email}')">
                        ${user.enabled ? 'Disable' : 'Enable'}
                    </button>
                    ${user.enabled ? 
                        `<button class="btn-restrict" onclick="restrictUser('${user.email}')">Restrict</button>` 
                        : ''}
                `;
            });
        });
}
```

## 验证方案

### 测试环境搭建

1. **启动两个 Xray 服务器**
   - Server 1: 端口 10085
   - Server 2: 端口 10086

2. **配置两个 Sing-box 客户端**
   - Client 1 连接到 Server 1
   - Client 2 连接到 Server 2（使用相同的 UUID）

3. **生成流量**
   - 通过 Client 1 生成 500 KB 流量
   - 通过 Client 2 生成 500 KB 流量

4. **验证结果**
   - Server 1 显示约 500 KB
   - Server 2 显示约 500 KB
   - 用户总流量显示约 1 MB

### 预期界面效果

```
┌──────────────┬──────────┬─────────┬────────────┬────────────┬────────────┬─────────┐
│ Email        │ UUID     │ Status  │ US-Server  │ JP-Server  │ Total      │ Actions │
├──────────────┼──────────┼─────────┼────────────┼────────────┼────────────┼─────────┤
│ 0x1234...    │ 11111... │ Enabled │ ↑ 1.00 MB  │ ↑ 2.00 MB  │ ↑ 3.00 MB  │ [Dis]   │
│              │          │         │ ↓ 5.00 MB  │ ↓ 10.00 MB │ ↓ 15.00 MB │ [Res]   │
└──────────────┴──────────┴─────────┴────────────┴────────────┴────────────┴─────────┘
```

## 优势

1. **灵活性** - 用户可以自由切换服务器
2. **透明性** - 清楚显示每个服务器的流量使用情况
3. **准确性** - 正确汇总所有服务器的流量
4. **持久化** - 每个服务器的流量独立持久化，重启不丢失

## 实现步骤

1. 修改 users.json 数据结构，添加 xray_servers 和 servers 字段
2. 修改 Go Auth Service，实现多服务器流量查询
3. 更新 Web UI，显示每个服务器的流量和总流量
4. 搭建测试环境，验证多服务器流量汇总功能
