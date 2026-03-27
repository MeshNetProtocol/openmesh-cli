# AC-010: Docker 容器化验收

## 验收信息

- **验收编号**: AC-010
- **对应任务**: [TASK-010](TASK-010-Docker容器化.md)
- **验收人**: 验收 AI
- **状态**: 待验收

## 功能测试

### 测试 1: Docker 镜像构建
```bash
docker build -t metering-service:test .
```

**预期结果**:
- [ ] 镜像构建成功
- [ ] 镜像大小 < 50MB
- [ ] 多阶段构建正确

### 测试 2: Docker Compose 启动
```bash
docker-compose up -d
docker-compose ps
```

**预期结果**:
- [ ] 所有服务启动成功
- [ ] 服务健康检查通过
- [ ] 可以访问 API

### 测试 3: 数据持久化
```bash
# 创建测试数据
curl -X POST http://localhost:8090/api/v1/admin/users \
  -H "Authorization: Bearer admin_token" \
  -d '{"user_id":"test","quota":1048576}'

# 重启服务
docker-compose restart metering

# 验证数据仍然存在
curl http://localhost:8090/api/v1/quota/test
```

**预期结果**:
- [ ] 数据在重启后仍然存在
- [ ] 数据库 volume 正常工作

### 测试 4: 环境变量配置
```bash
# 修改 .env 文件
echo "METERING_SERVER_PORT=9090" >> .env

# 重启服务
docker-compose down
docker-compose up -d

# 验证新端口
curl http://localhost:9090/health
```

**预期结果**:
- [ ] 环境变量正确应用
- [ ] 服务使用新配置启动

## 安全测试

### 测试 5: 非 root 用户
```bash
docker exec metering-service whoami
```

**预期结果**:
- [ ] 返回 "metering" 而不是 "root"
- [ ] 服务以非 root 用户运行

### 测试 6: 敏感信息
```bash
# 检查镜像中是否包含敏感信息
docker history metering-service:test
docker inspect metering-service:test
```

**预期结果**:
- [ ] 镜像中不包含密码
- [ ] 镜像中不包含密钥

## 验收标准

### 通过条件
- [ ] 所有功能测试通过
- [ ] 安全测试通过
- [ ] 镜像大小合理
- [ ] 数据持久化正常

### 失败条件
- [ ] 任何测试失败
- [ ] 存在安全隐患
- [ ] 镜像过大 (> 50MB)

---

**创建日期**: 2026-03-26
**对应任务**: TASK-010
