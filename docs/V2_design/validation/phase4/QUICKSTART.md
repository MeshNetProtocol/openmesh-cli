# Phase 4 Quickstart

## 目标

快速启动当前 Phase 4 文件型 POC，并验证以下 4 条业务链路：

- 首次订阅
- 自动续费
- 取消订阅
- 升级 / 降级

---

## 当前 POC 约束

- 不使用数据库
- 使用 JSON 文件保存状态
- 智能合约只负责 permit / 绑定 / 扣费 / 去重
- 订阅状态全部放在服务端

---

## 关键文件

- `plans.json`
- `subscriptions.json`
- `authorizations.json`
- `charges.json`
- `events.json`

---

## 启动服务

```bash
./start.sh
```

或者手动启动：

```bash
cd auth-service
go mod download
go build -o auth-service
./auth-service
```

默认地址：

- 服务端：`http://localhost:8080`
- 页面：`http://localhost:8080/subscribe.html?identity_address=0xYourIdentity`

---

## 推荐测试顺序

## 1. 测试订阅

验证项：

- 是否创建 subscription
- 是否生成 authorization 记录
- 是否生成 initial charge
- 是否写入事件镜像

## 2. 测试续费

验证项：

- 到期后是否生成 renewal charge
- 同一账期是否只生成一个 charge
- allowance 剩余额度是否被更新

## 3. 测试取消订阅

验证项：

- `auto_renew` 是否关闭
- `status` 是否变成 `cancelled`
- 后续是否停止生成 renewal charge

## 4. 测试升级 / 降级

验证项：

- 升级是否生成差价 charge
- 降级是否只影响下一周期

---

## 预期接口方向

当前 POC 最终建议具备以下接口：

- `POST /poc/subscriptions`
- `POST /poc/authorizations/permit`
- `POST /poc/charges/initial`
- `POST /poc/charges/renew`
- `POST /poc/subscriptions/cancel`
- `POST /poc/subscriptions/upgrade`
- `POST /poc/subscriptions/downgrade`
- `POST /poc/subscriptions/query`

---

## POC 成功判定

满足以下条件即可：

- 能成功围绕 `VPNCreditVaultV4` 完成授权与扣费
- 订阅、续费、取消、升降级四个流程都能在 JSON 状态中闭环
- 同一条 charge 不会重复执行
