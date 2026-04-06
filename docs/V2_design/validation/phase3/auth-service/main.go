package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"time"
)

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
	Email         string                    `json:"email"`
	UUID          string                    `json:"uuid"`
	Enabled       bool                      `json:"enabled"`
	Servers       map[string]*ServerTraffic `json:"servers"`
	TotalUplink   int64                     `json:"total_uplink"`
	TotalDownlink int64                     `json:"total_downlink"`
}

type UsersConfig struct {
	XrayServers []XrayServer `json:"xray_servers"`
	Users       []User       `json:"users"`
	mu          sync.RWMutex
}

var (
	config     *UsersConfig
	configPath string
)

func init() {
	dir, _ := os.Getwd()
	configPath = filepath.Join(dir, "../users.json")
	config = &UsersConfig{}
	if err := config.Load(); err != nil {
		log.Fatalf("Failed to load config: %v", err)
	}
}

func main() {
	http.HandleFunc("/", handleIndex)
	http.HandleFunc("/api/users", handleGetUsers)
	http.HandleFunc("/api/users/toggle", handleToggleUser)
	http.HandleFunc("/api/users/restrict", handleRestrictUser)

	// 启动定时任务，每 5 秒更新一次流量统计
	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			if err := config.UpdateTrafficStats(); err != nil {
				log.Printf("Failed to update traffic stats: %v", err)
			}
		}
	}()

	addr := ":8080"
	log.Printf("Auth Service started at http://localhost%s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func (c *UsersConfig) Load() error {
	c.mu.Lock()
	defer c.mu.Unlock()

	data, err := os.ReadFile(configPath)
	if err != nil {
		return err
	}

	return json.Unmarshal(data, c)
}

func (c *UsersConfig) Save() error {
	data, err := json.MarshalIndent(c, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(configPath, data, 0644)
}

func (c *UsersConfig) GetUsers() []User {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.Users
}

func (c *UsersConfig) GetXrayServers() []XrayServer {
	c.mu.RLock()
	defer c.mu.RUnlock()
	return c.XrayServers
}

// 查询指定服务器的用户流量
func queryUserTrafficFromServer(serverAddr, email string) (uplink int64, downlink int64, err error) {
	cmd := exec.Command("xray", "api", "statsquery",
		fmt.Sprintf("--server=%s", serverAddr),
		fmt.Sprintf("--pattern=user>>>%s>>>", email))

	output, err := cmd.CombinedOutput()
	if err != nil {
		return 0, 0, fmt.Errorf("statsquery failed: %v, output: %s", err, output)
	}

	// 解析 JSON 输出
	var result struct {
		Stat []struct {
			Name  string `json:"name"`
			Value int64  `json:"value"`
		} `json:"stat"`
	}

	if err := json.Unmarshal(output, &result); err != nil {
		return 0, 0, fmt.Errorf("failed to parse JSON: %v, output: %s", err, output)
	}

	// 从结果中提取上行和下行流量
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

// 更新所有服务器的流量统计（带持久化）
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
				log.Printf("Detected %s restart for user %s (uplink: %d->%d, downlink: %d->%d)",
					server.Name, c.Users[i].Email,
					serverTraffic.LastXrayUplink, currentUplink,
					serverTraffic.LastXrayDownlink, currentDownlink)

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

	// 持久化到文件
	if err := c.Save(); err != nil {
		log.Printf("Failed to save traffic stats: %v", err)
		return err
	}

	return nil
}

func (c *UsersConfig) ToggleUser(email string) error {
	c.mu.Lock()
	defer c.mu.Unlock()

	for i := range c.Users {
		if c.Users[i].Email == email {
			c.Users[i].Enabled = !c.Users[i].Enabled

			if err := c.Save(); err != nil {
				return err
			}

			// 调用所有 Xray 服务器的 API
			if c.Users[i].Enabled {
				return c.addUserToAllServers(c.Users[i])
			} else {
				return c.removeUserFromAllServers(c.Users[i])
			}
		}
	}

	return fmt.Errorf("user not found: %s", email)
}

func (c *UsersConfig) addUserToAllServers(user User) error {
	log.Printf("Adding user to all Xray servers: %s", user.Email)

	for _, server := range c.XrayServers {
		// 使用 Python + xtlsapi 库添加用户
		cmd := exec.Command("python3", "../test_xtlsapi.py", "vless-in", user.Email, user.UUID)
		// TODO: 需要修改 test_xtlsapi.py 支持指定服务器地址
		output, err := cmd.CombinedOutput()
		if err != nil {
			log.Printf("Failed to add user to %s: %v, output: %s", server.Name, err, output)
			continue
		}
		log.Printf("User added to %s: %s", server.Name, user.Email)
	}

	return nil
}

func (c *UsersConfig) removeUserFromAllServers(user User) error {
	log.Printf("Removing user from all Xray servers: %s", user.Email)

	for _, server := range c.XrayServers {
		cmd := exec.Command("xray", "api", "rmu",
			fmt.Sprintf("--server=%s", server.Address),
			"-tag=vless-in", user.Email)
		output, err := cmd.CombinedOutput()
		if err != nil {
			log.Printf("Failed to remove user from %s: %v, output: %s", server.Name, err, output)
			continue
		}
		log.Printf("User removed from %s: %s", server.Name, user.Email)
	}

	return nil
}

func handleGetUsers(w http.ResponseWriter, r *http.Request) {
	users := config.GetUsers()
	servers := config.GetXrayServers()
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"users":        users,
		"xray_servers": servers,
	})
}

func handleToggleUser(w http.ResponseWriter, r *http.Request) {
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

	if err := config.ToggleUser(req.Email); err != nil {
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
}

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

			if err := config.removeUserFromAllServers(config.Users[i]); err != nil {
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

func handleIndex(w http.ResponseWriter, r *http.Request) {
	tmpl := `<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Auth Service - Multi-Server Traffic Stats</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 1400px;
            margin: 50px auto;
            padding: 20px;
        }
        h1 {
            color: #333;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 20px;
        }
        th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #ddd;
        }
        th {
            background-color: #4CAF50;
            color: white;
        }
        .enabled {
            color: green;
            font-weight: bold;
        }
        .disabled {
            color: red;
            font-weight: bold;
        }
        button {
            padding: 8px 16px;
            cursor: pointer;
            border: none;
            border-radius: 4px;
            font-size: 14px;
            margin-right: 5px;
        }
        .btn-enable {
            background-color: #4CAF50;
            color: white;
        }
        .btn-disable {
            background-color: #f44336;
            color: white;
        }
        .btn-restrict {
            background-color: #ff9800;
            color: white;
        }
        button:hover {
            opacity: 0.8;
        }
        .status {
            margin-top: 20px;
            padding: 10px;
            border-radius: 4px;
            display: none;
        }
        .status.success {
            background-color: #d4edda;
            color: #155724;
            display: block;
        }
        .status.error {
            background-color: #f8d7da;
            color: #721c24;
            display: block;
        }
        .traffic-cell {
            font-family: 'Courier New', monospace;
            text-align: right;
            font-size: 12px;
        }
        .server-traffic {
            background-color: #f5f5f5;
            padding: 4px 8px;
            border-radius: 4px;
            margin: 2px 0;
        }
        .total-traffic {
            background-color: #e8f5e9;
            padding: 4px 8px;
            border-radius: 4px;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <h1>Auth Service - Multi-Server Traffic Stats</h1>
    <p>管理 Xray 用户访问权限和多服务器流量统计</p>

    <div id="status" class="status"></div>

    <table id="usersTable">
        <thead id="tableHeader">
        </thead>
        <tbody id="usersBody">
        </tbody>
    </table>

    <script>
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
                    // 动态生成表头
                    const thead = document.getElementById('tableHeader');
                    let headerHTML = '<tr><th>Email</th><th>UUID</th><th>Status</th>';

                    data.xray_servers.forEach(server => {
                        headerHTML += '<th>' + server.name + '<br><small>' + server.location + '</small></th>';
                    });

                    headerHTML += '<th>Total Traffic</th><th>Actions</th></tr>';
                    thead.innerHTML = headerHTML;

                    // 生成表格内容
                    const tbody = document.getElementById('usersBody');
                    tbody.innerHTML = '';

                    data.users.forEach(user => {
                        const row = tbody.insertRow();

                        // Email
                        row.insertCell().innerHTML = user.email;

                        // UUID
                        row.insertCell().innerHTML = '<code>' + user.uuid + '</code>';

                        // Status
                        const statusCell = row.insertCell();
                        statusCell.className = user.enabled ? 'enabled' : 'disabled';
                        statusCell.innerHTML = user.enabled ? '✓ Enabled' : '✗ Disabled';

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
                            cell.innerHTML = '<div class="server-traffic">↑ ' + formatBytes(uplink) + '<br>↓ ' + formatBytes(downlink) + '</div>';
                        });

                        // 总流量
                        const totalCell = row.insertCell();
                        totalCell.className = 'traffic-cell';
                        totalCell.innerHTML = '<div class="total-traffic">↑ ' + formatBytes(user.total_uplink) + '<br>↓ ' + formatBytes(user.total_downlink) + '</div>';

                        // 操作按钮
                        const actionsCell = row.insertCell();
                        actionsCell.innerHTML =
                            '<button class="' + (user.enabled ? 'btn-disable' : 'btn-enable') + '" ' +
                                'onclick="toggleUser(\'' + user.email + '\')">' +
                                (user.enabled ? 'Disable' : 'Enable') +
                            '</button>' +
                            (user.enabled ?
                                '<button class="btn-restrict" onclick="restrictUser(\'' + user.email + '\')">Restrict</button>'
                                : '');
                    });
                })
                .catch(error => {
                    showStatus('Failed to load users: ' + error, 'error');
                });
        }

        function toggleUser(email) {
            fetch('/api/users/toggle', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({ email: email })
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    showStatus('User status updated successfully', 'success');
                    loadUsers();
                } else {
                    showStatus('Failed to update user: ' + data.error, 'error');
                }
            })
            .catch(error => {
                showStatus('Request failed: ' + error, 'error');
            });
        }

        function restrictUser(email) {
            if (!confirm('Are you sure you want to restrict this user? This will immediately stop their service on all servers.')) {
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
                    showStatus('User restricted successfully on all servers', 'success');
                    loadUsers();
                } else {
                    showStatus('Failed to restrict user: ' + data.error, 'error');
                }
            })
            .catch(error => {
                showStatus('Request failed: ' + error, 'error');
            });
        }

        function showStatus(message, type) {
            const status = document.getElementById('status');
            status.textContent = message;
            status.className = 'status ' + type;

            setTimeout(() => {
                status.className = 'status';
            }, 3000);
        }

        loadUsers();
        setInterval(loadUsers, 3000);
    </script>
</body>
</html>`

	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(tmpl))
}
