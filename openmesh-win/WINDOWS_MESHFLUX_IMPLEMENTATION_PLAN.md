# Windows MeshFlux 实施计划（面向接手 AI）

更新时间：2026-02-26  
仓库根目录：`D:\worker\openmesh-cli`

---

## 1. 目标与约束

### 1.1 最终目标
- Windows 客户端实现与 `openmesh-apple\MeshFluxMac` 同级别可用性：
  - 使用 **embedded + tun** 架构启动真实 VPN。
  - 可通过已安装 profile 建立真实隧道并访问真实 Market。
  - 支持 profile 导入/安装/激活/更新闭环。
  - UI 行为与 Mac 版本核心流程一致（不要求像素级一致，但交互一致）。

### 1.2 平台约束（必须理解）
- Apple 使用 `NetworkExtension`；Windows 没有 NE。
- Windows 必须走 `Wintun + 路由/接口控制`。
- 结论：功能要对齐，但技术实现不能照搬 Mac。

---

## 2. 当前状态（已完成）

### 2.1 架构状态
- 已切换到 **embedded core backend**（非外部 `sing-box.exe` 子进程模式）。
- Go 侧由 `openmesh_core.dll` 提供接口，WinForms 侧通过 `EmbeddedCoreClient` 调用。
- `start_vpn` 可到达成功状态：日志出现  
  - `start_vpn -> ok: vpn started (embedded in-process sing-box)`  
  - `real tunnel state -> ready`

### 2.2 关键改造已落地
- Go embedded 启动路径已改为进程内 `box.New(...).Start()`。
- 配置清洗已加入 Windows 兼容处理（rule_set、cache_file、inbound rule_set 引用等）。
- profile/market 本地缓存和恢复链路已具备。
- UI 已加入：
  - 启停 VPN 忙碌态（Starting/Stopping）
  - 非管理员权限提示与拦截
  - embedded 调用后台执行，减少 UI 假死

### 2.3 已知现象
- 首次启动 VPN 偶发 `Cannot create a file when that file already exists`，已加一次自动重试。
- 非管理员会触发 `administrator privileges required`，这是 Windows tun 真实约束。

---

## 3. 代码入口（接手 AI 必看）

### 3.1 Windows UI 层
- 主界面：`openmesh-win/MeshFluxMainForm.cs`
  - 启停动作：`StartVpnAsync` / `StopVpnAsync`
  - 状态刷新：`RefreshStatusAsync` / `UpdateStatusUi`
  - 管理员提示与拦截：在此文件内
- 嵌入式客户端：`openmesh-win/EmbeddedCoreClient.cs`
  - P/Invoke：`om_request` / `om_free_string`
  - 当前已做后台线程调用与串行锁

### 3.2 Go embedded 核心
- 主入口：`go-cli-lib/cmd/openmesh-win-core-embedded/main.go`
  - action 路由：`start_vpn/stop_vpn/reload/provider_*`
  - 配置清洗：`sanitizeConfigForSingbox(...)`
  - 运行时目录：`%LOCALAPPDATA%\OpenMeshWin\runtime`
- 管理员检测：
  - `go-cli-lib/cmd/openmesh-win-core-embedded/admin_windows.go`
  - `go-cli-lib/cmd/openmesh-win-core-embedded/admin_other.go`

### 3.3 构建脚本
- `openmesh-win/tests/Build-Embedded-GoCore.ps1`
  - 产物：`openmesh-win/bin/Debug/net10.0-windows/openmesh_core.dll`
  - 默认包含 `with_clash_api` tag

---

## 4. 本地运行与验证路径（标准流程）

## 4.1 构建 embedded DLL
```powershell
cd D:\worker\openmesh-cli
$env:Path = "C:\msys64\ucrt64\bin;$env:Path"
powershell -ExecutionPolicy Bypass -File .\openmesh-win\tests\Build-Embedded-GoCore.ps1 -CC gcc -GoExe "C:\Program Files\Go\bin\go.exe"
```

### 4.2 启动 UI（管理员 PowerShell）
```powershell
cd D:\worker\openmesh-cli
dotnet run --project .\openmesh-win\OpenMeshWin.csproj
```

### 4.3 A/B 路由诊断模式
- 环境变量：`OPENMESH_WIN_ROUTE_MODE`
  - `profile`（A）：按 profile 原始策略
  - `force_proxy`（B）：强制全量走 proxy（诊断用）

PowerShell:
```powershell
$env:OPENMESH_WIN_ROUTE_MODE="force_proxy"
dotnet run --project .\openmesh-win\OpenMeshWin.csproj
```

CMD:
```bat
set OPENMESH_WIN_ROUTE_MODE=force_proxy
dotnet run --project .\openmesh-win\OpenMeshWin.csproj
```

---

## 5. 剩余工作（按优先级）

## P0（立即）
- 修复“VPN 已启动但实际无法访问外网”的可用性问题。
- 建立稳定的可观测性：
  - 明确区分：隧道已起、代理握手成功、首包转发成功、DNS 成功。
  - 在 UI 日志输出关键阶段，不再只显示 start/stop 结果。

### P0 验收标准
- 管理员模式下，点击一次“连接”，30 秒内完成。
- 在 `force_proxy` 模式可访问目标站点（如 Google）。
- 日志可看到完整链路状态（而不是只有 `start_vpn -> ok`）。

## P1（核心功能闭环）
- profile 生命周期闭环：
  - 导入 -> 安装 -> 激活 -> 重载 -> 启动 -> 可访问 Market。
- Market 数据源闭环：
  - 先用本地导入的 bootstrap profile 建隧道；
  - 再拉取真实 market；
  - 支持后续 profile 更新安装。

### P1 验收标准
- 重启 app 后不丢已安装 profile 与已选 provider。
- 可从真实 market 拉取并完成安装/更新动作。

## P2（稳定性与体验）
- 首次启动偶发冲突进一步收敛（tun 初始化/残留会话清理）。
- UI 交互完善：
  - 操作中禁用重复动作
  - 失败给明确可执行建议（权限、配置、网络、节点）

### P2 验收标准
- 连续 20 次启动/停止无卡死、无假成功。
- 非管理员场景提示一致、无误导。

---

## 6. 与 Mac 对齐的实现原则

- 对齐“能力与流程”，不对齐“平台机制”：
  - Mac: NE
  - Windows: Wintun + routing
- 不允许回退到外部 `sing-box.exe` 主路径（仅可作为临时诊断工具，不可作为产品主链路）。
- 所有新增逻辑优先放在：
  - `openmesh-win/`（UI 与桥接）
  - `go-cli-lib/cmd/openmesh-win-core-embedded/`（embedded 核心）

---

## 7. 交接给其它 AI 的执行清单

接手后按顺序执行：
1. 阅读本文件与以下代码：
   - `openmesh-win/MeshFluxMainForm.cs`
   - `openmesh-win/EmbeddedCoreClient.cs`
   - `go-cli-lib/cmd/openmesh-win-core-embedded/main.go`
2. 在管理员 PowerShell 按 4.1 / 4.2 跑通当前版本。
3. 用 4.3 的 A/B 模式复现“可访问性”问题并定位层级（路由/节点/DNS）。
4. 先完成 P0，再推进 P1，最后做 P2。
5. 每次改动后至少验证：
   - 非管理员提示路径
   - 管理员单次连接路径
   - profile 重启持久化路径

---

## 8. 成功定义（Done）

满足以下条件才算阶段完成：
- embedded+tun 在 Windows 下稳定可用（单击连接可用，不依赖重复点击）。
- 使用本地安装 profile 可以建立真实 VPN 并访问真实 market。
- profile 安装/更新可闭环，重启后状态保持。
- UI 对失败原因可解释、可操作，不再出现“看起来成功但无法使用”的黑盒体验。
