# TASK-011: 文档编写

## 任务信息

- **任务编号**: TASK-011
- **所属阶段**: Phase 1 - Week 2 (Day 12)
- **预计时间**: 1 天
- **依赖任务**: TASK-009, TASK-010
- **状态**: 待开始

## 任务目标

编写完整的项目文档,包括 API 文档、部署指南、运维手册和监控配置指南。

## 工作范围

### 1. API 文档 (OpenAPI)

创建 `docs/api/openapi.yaml`:

```yaml
openapi: 3.0.0
info:
  title: Metering Service API
  version: 1.0.0
  description: 流量计费服务 API

servers:
  - url: http://localhost:8090
    description: 本地开发环境

paths:
  /health:
    get:
      summary: 健康检查
      responses:
        '200':
          description: 服务健康

  /api/v1/quota/{user_id}:
    get:
      summary: 查询用户配额
      parameters:
        - name: user_id
          in: path
          required: true
          schema:
            type: string
      responses:
        '200':
          description: 配额信息
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/QuotaInfo'

  /api/v1/traffic/{user_id}:
    get:
      summary: 查询用户流量统计
      parameters:
        - name: user_id
          in: path
          required: true
          schema:
            type: string
        - name: start_time
          in: query
          schema:
            type: string
            format: date-time
        - name: end_time
          in: query
          schema:
            type: string
            format: date-time
      responses:
        '200':
          description: 流量统计

components:
  schemas:
    QuotaInfo:
      type: object
      properties:
        user_id:
          type: string
        total_quota:
          type: integer
        used:
          type: integer
        remaining:
          type: integer
        status:
          type: string
        usage_percent:
          type: number
```

### 2. 部署指南

创建 `docs/deployment.md`:

```markdown
# Metering Service 部署指南

## 环境要求

- Docker 20.10+
- Docker Compose 2.0+
- PostgreSQL 14+ (如果不使用 Docker)

## 快速开始

### 使用 Docker Compose

1. 复制环境变量模板
```bash
cp .env.example .env
```

2. 编辑 .env 文件,配置数据库密码和节点密钥

3. 启动服务
```bash
./scripts/docker-start.sh
```

4. 验证服务
```bash
curl http://localhost:8090/health
```

### 手动部署

1. 安装 PostgreSQL
2. 创建数据库
3. 配置环境变量
4. 运行数据库迁移
5. 启动服务

详细步骤见文档...
```

### 3. 运维手册

创建 `docs/operations.md`:

```markdown
# Metering Service 运维手册

## 日常运维

### 查看日志
```bash
docker-compose logs -f metering
```

### 重启服务
```bash
docker-compose restart metering
```

### 备份数据库
```bash
docker exec metering-postgres pg_dump -U metering_user metering > backup.sql
```

## 监控

### 关键指标

- `metering_collection_total` - 采集次数
- `metering_quota_exceeded_total` - 超额用户数
- `metering_api_requests_total` - API 请求数

### 告警规则

1. 采集失败率 > 1%
2. API 响应时间 > 200ms
3. 数据库连接数 > 80%

## 故障排查

### 采集失败

1. 检查节点连接
2. 检查节点密钥
3. 查看采集器日志

### 数据库连接失败

1. 检查数据库状态
2. 检查连接配置
3. 检查连接池设置

详细排查步骤见文档...
```

### 4. 监控配置指南

创建 `docs/monitoring.md`:

```markdown
# 监控配置指南

## Prometheus 配置

```yaml
scrape_configs:
  - job_name: 'metering-service'
    static_configs:
      - targets: ['localhost:8090']
    metrics_path: '/metrics'
    scrape_interval: 15s
```

## Grafana 仪表板

导入 `configs/grafana-dashboard.json` 到 Grafana。

关键面板:
- 采集成功率
- API 响应时间
- 活跃用户数
- 超额用户数

## 告警配置

使用 Prometheus Alertmanager 配置告警规则。

示例规则见 `configs/alert-rules.yaml`。
```

## 交付物

### 文档文件
- [ ] `docs/api/openapi.yaml` - OpenAPI 规范
- [ ] `docs/deployment.md` - 部署指南
- [ ] `docs/operations.md` - 运维手册
- [ ] `docs/monitoring.md` - 监控配置指南
- [ ] `README.md` - 项目主文档

### 配置文件
- [ ] `configs/grafana-dashboard.json` - Grafana 仪表板
- [ ] `configs/alert-rules.yaml` - Prometheus 告警规则

## 验收标准

### 文档完整性
- [ ] API 文档完整,包含所有端点
- [ ] 部署指南清晰,可按步骤操作
- [ ] 运维手册覆盖常见场景
- [ ] 监控配置可直接使用

### 文档质量
- [ ] 文档结构清晰
- [ ] 示例代码可运行
- [ ] 截图清晰(如有)

---

**创建日期**: 2026-03-26
**负责人**: 开发 AI
**验收人**: 验收 AI (参考 AC-011)
