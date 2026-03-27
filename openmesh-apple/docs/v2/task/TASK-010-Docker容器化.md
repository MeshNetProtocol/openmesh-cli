# TASK-010: Docker 容器化

## 任务信息

- **任务编号**: TASK-010
- **所属阶段**: Phase 1 - Week 2 (Day 10-11)
- **预计时间**: 1.5 天
- **依赖任务**: TASK-007, TASK-008
- **状态**: 待开始

## 任务目标

实现 Metering Service 的 Docker 容器化,包括多阶段构建的 Dockerfile、Docker Compose 配置和数据持久化。

## 工作范围

### 1. Dockerfile (多阶段构建)

创建 `Dockerfile`:

```dockerfile
# 构建阶段
FROM golang:1.21-alpine AS builder

WORKDIR /build

# 复制依赖文件
COPY go.mod go.sum ./
RUN go mod download

# 复制源代码
COPY . .

# 构建二进制文件
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o metering-service ./cmd/metering

# 运行阶段
FROM alpine:latest

RUN apk --no-cache add ca-certificates tzdata

WORKDIR /app

# 从构建阶段复制二进制文件
COPY --from=builder /build/metering-service .
COPY --from=builder /build/migrations ./migrations
COPY --from=builder /build/configs ./configs

# 创建非 root 用户
RUN addgroup -g 1000 metering && \
    adduser -D -u 1000 -G metering metering && \
    chown -R metering:metering /app

USER metering

EXPOSE 8090

ENTRYPOINT ["./metering-service"]
CMD ["--config", "/app/configs/config.yaml"]
```

### 2. Docker Compose 配置

创建 `docker-compose.yaml`:

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:14-alpine
    container_name: metering-postgres
    environment:
      POSTGRES_USER: ${DB_USER:-metering_user}
      POSTGRES_PASSWORD: ${DB_PASSWORD:-metering_password}
      POSTGRES_DB: ${DB_NAME:-metering}
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "${DB_PORT:-5432}:5432"
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${DB_USER:-metering_user}"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - metering-network

  metering:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: metering-service
    depends_on:
      postgres:
        condition: service_healthy
    environment:
      METERING_DATABASE_HOST: postgres
      METERING_DATABASE_PORT: 5432
      METERING_DATABASE_NAME: ${DB_NAME:-metering}
      METERING_DATABASE_USER: ${DB_USER:-metering_user}
      METERING_DATABASE_PASSWORD: ${DB_PASSWORD:-metering_password}
      METERING_SERVER_PORT: 8090
      METERING_COLLECTOR_INTERVAL: ${COLLECTOR_INTERVAL:-15s}
    ports:
      - "${SERVER_PORT:-8090}:8090"
    volumes:
      - ./configs:/app/configs:ro
    networks:
      - metering-network
    restart: unless-stopped

volumes:
  postgres_data:
    driver: local

networks:
  metering-network:
    driver: bridge
```

### 3. 环境变量配置

创建 `.env.example`:

```bash
# 数据库配置
DB_USER=metering_user
DB_PASSWORD=your_secure_password_here
DB_NAME=metering
DB_PORT=5432

# 服务器配置
SERVER_PORT=8090

# 采集器配置
COLLECTOR_INTERVAL=15s

# 节点配置
NODE_A_SECRET=your_node_a_secret
NODE_B_SECRET=your_node_b_secret
```

### 4. Docker 启动脚本

创建 `scripts/docker-start.sh`:

```bash
#!/bin/bash

set -e

echo "Starting Metering Service with Docker Compose..."

# 检查 .env 文件
if [ ! -f .env ]; then
    echo "Error: .env file not found"
    echo "Please copy .env.example to .env and configure it"
    exit 1
fi

# 启动服务
docker-compose up -d

echo "Waiting for services to be ready..."
sleep 10

# 检查服务状态
docker-compose ps

# 检查健康状态
echo "Checking service health..."
curl -f http://localhost:8090/health || echo "Service not ready yet"

echo "Metering Service started successfully!"
echo "API: http://localhost:8090"
echo "Metrics: http://localhost:8090/metrics"
```

### 5. Docker 停止脚本

创建 `scripts/docker-stop.sh`:

```bash
#!/bin/bash

set -e

echo "Stopping Metering Service..."

docker-compose down

echo "Metering Service stopped successfully!"
```

## 交付物

### 代码文件
- [ ] `Dockerfile` - 多阶段构建配置
- [ ] `docker-compose.yaml` - Docker Compose 配置
- [ ] `.dockerignore` - Docker 忽略文件
- [ ] `.env.example` - 环境变量示例

### 脚本
- [ ] `scripts/docker-start.sh` - 启动脚本
- [ ] `scripts/docker-stop.sh` - 停止脚本

### 文档
- [ ] `docs/docker.md` - Docker 部署文档

## 验收标准

### 功能验收
- [ ] Docker 镜像成功构建
- [ ] Docker Compose 正常启动
- [ ] 服务可以正常访问
- [ ] 数据持久化正常工作

### 安全验收
- [ ] 使用非 root 用户运行
- [ ] 敏感信息通过环境变量注入
- [ ] 镜像大小合理 (< 50MB)

---

**创建日期**: 2026-03-26
**负责人**: 开发 AI
**验收人**: 验收 AI (参考 AC-010)
