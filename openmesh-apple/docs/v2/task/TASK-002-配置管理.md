# TASK-002: 配置管理系统

## 任务信息

- **任务编号**: TASK-002
- **所属阶段**: Phase 1 - Week 1 (Day 3)
- **预计时间**: 1 天
- **依赖任务**: TASK-001
- **状态**: 待开始

## 任务目标

实现灵活的配置管理系统,支持环境变量、YAML/TOML 配置文件、配置验证和敏感信息加密,替代 Phase 0 原型中的硬编码配置。

## 技术背景

### Phase 0 原型情况

**原型代码位置**: `openmesh-apple/docs/v2/Hysteria2_Validation/prototype/metering/main.go`

**现有配置方式**:
```go
const (
    defaultDBPath      = "../../data/metering.db"
    defaultAuthAPIURL  = "http://127.0.0.1:8080"
    defaultInterval    = 10 * time.Second
)
```

**原型的局限性**:
- 配置硬编码在代码中
- 只支持命令行参数
- 无配置验证
- 敏感信息(数据库密码、API 密钥)明文存储
- 不符合 12-factor app 原则

### 为什么需要配置管理系统

1. **环境隔离**: 开发、测试、生产环境使用不同配置
2. **安全性**: 敏感信息通过环境变量注入,不提交到代码库
3. **灵活性**: 无需重新编译即可修改配置
4. **可维护性**: 集中管理所有配置项
5. **验证**: 启动时验证配置,避免运行时错误

## 工作范围

### 1. 配置结构设计

创建配置结构体 (`internal/config/config.go`):

```go
package config

import "time"

// Config 应用配置
type Config struct {
    Database  DatabaseConfig  `yaml:"database" mapstructure:"database"`
    Collector CollectorConfig `yaml:"collector" mapstructure:"collector"`
    Nodes     []NodeConfig    `yaml:"nodes" mapstructure:"nodes"`
    AuthAPI   AuthAPIConfig   `yaml:"auth_api" mapstructure:"auth_api"`
    Server    ServerConfig    `yaml:"server" mapstructure:"server"`
    Logging   LoggingConfig   `yaml:"logging" mapstructure:"logging"`
}

// DatabaseConfig 数据库配置
type DatabaseConfig struct {
    Host     string `yaml:"host" mapstructure:"host" validate:"required"`
    Port     int    `yaml:"port" mapstructure:"port" validate:"required,min=1,max=65535"`
    Name     string `yaml:"name" mapstructure:"name" validate:"required"`
    User     string `yaml:"user" mapstructure:"user" validate:"required"`
    Password string `yaml:"password" mapstructure:"password" validate:"required"`
    SSLMode  string `yaml:"ssl_mode" mapstructure:"ssl_mode" validate:"oneof=disable require verify-ca verify-full"`
    MaxConns int    `yaml:"max_conns" mapstructure:"max_conns" validate:"min=1,max=100"`
    MinConns int    `yaml:"min_conns" mapstructure:"min_conns" validate:"min=1"`
}

// CollectorConfig 采集器配置
type CollectorConfig struct {
    Interval time.Duration `yaml:"interval" mapstructure:"interval" validate:"required,min=5s"`
    Timeout  time.Duration `yaml:"timeout" mapstructure:"timeout" validate:"required,min=1s"`
}

// NodeConfig 节点配置
type NodeConfig struct {
    Name        string `yaml:"name" mapstructure:"name" validate:"required"`
    StatsURL    string `yaml:"stats_url" mapstructure:"stats_url" validate:"required,url"`
    StatsSecret string `yaml:"stats_secret" mapstructure:"stats_secret" validate:"required"`
}

// AuthAPIConfig 认证 API 配置
type AuthAPIConfig struct {
    URL     string        `yaml:"url" mapstructure:"url" validate:"required,url"`
    Timeout time.Duration `yaml:"timeout" mapstructure:"timeout" validate:"required,min=1s"`
}

// ServerConfig 服务器配置
type ServerConfig struct {
    Port     int    `yaml:"port" mapstructure:"port" validate:"required,min=1,max=65535"`
    LogLevel string `yaml:"log_level" mapstructure:"log_level" validate:"oneof=debug info warn error"`
}

// LoggingConfig 日志配置
type LoggingConfig struct {
    Level  string `yaml:"level" mapstructure:"level" validate:"oneof=debug info warn error"`
    Format string `yaml:"format" mapstructure:"format" validate:"oneof=json text"`
}
```

### 2. 配置加载实现

实现配置加载逻辑 (`internal/config/loader.go`):

**功能**:
1. 从 YAML/TOML 文件加载配置
2. 从环境变量覆盖配置
3. 设置默认值
4. 验证配置有效性

**环境变量映射规则**:
- 使用前缀 `METERING_`
- 嵌套结构用下划线分隔
- 例如: `database.host` → `METERING_DATABASE_HOST`

**示例实现**:
```go
package config

import (
    "fmt"
    "os"
    "strings"

    "github.com/go-playground/validator/v10"
    "github.com/spf13/viper"
)

// Load 加载配置
func Load(configPath string) (*Config, error) {
    v := viper.New()

    // 1. 设置默认值
    setDefaults(v)

    // 2. 读取配置文件
    if configPath != "" {
        v.SetConfigFile(configPath)
        if err := v.ReadInConfig(); err != nil {
            return nil, fmt.Errorf("failed to read config file: %w", err)
        }
    }

    // 3. 读取环境变量
    v.SetEnvPrefix("METERING")
    v.SetEnvKeyReplacer(strings.NewReplacer(".", "_"))
    v.AutomaticEnv()

    // 4. 解析配置
    var cfg Config
    if err := v.Unmarshal(&cfg); err != nil {
        return nil, fmt.Errorf("failed to unmarshal config: %w", err)
    }

    // 5. 验证配置
    if err := validateConfig(&cfg); err != nil {
        return nil, fmt.Errorf("config validation failed: %w", err)
    }

    return &cfg, nil
}

// setDefaults 设置默认值
func setDefaults(v *viper.Viper) {
    // 数据库默认值
    v.SetDefault("database.host", "localhost")
    v.SetDefault("database.port", 5432)
    v.SetDefault("database.ssl_mode", "disable")
    v.SetDefault("database.max_conns", 10)
    v.SetDefault("database.min_conns", 2)

    // 采集器默认值
    v.SetDefault("collector.interval", "15s")
    v.SetDefault("collector.timeout", "5s")

    // 认证 API 默认值
    v.SetDefault("auth_api.timeout", "3s")

    // 服务器默认值
    v.SetDefault("server.port", 8090)
    v.SetDefault("server.log_level", "info")

    // 日志默认值
    v.SetDefault("logging.level", "info")
    v.SetDefault("logging.format", "json")
}

// validateConfig 验证配置
func validateConfig(cfg *Config) error {
    validate := validator.New()
    return validate.Struct(cfg)
}
```

### 3. 配置文件示例

创建配置文件示例 (`configs/config.example.yaml`):

```yaml
# Metering Service 配置示例
# 复制此文件为 config.yaml 并修改相应配置

database:
  host: localhost
  port: 5432
  name: metering
  user: metering_user
  password: ${DB_PASSWORD}  # 从环境变量读取
  ssl_mode: disable
  max_conns: 10
  min_conns: 2

collector:
  interval: 15s
  timeout: 5s

nodes:
  - name: node-a
    stats_url: http://node-a:8081/traffic
    stats_secret: ${NODE_A_SECRET}
  - name: node-b
    stats_url: http://node-b:8081/traffic
    stats_secret: ${NODE_B_SECRET}

auth_api:
  url: http://auth-api:8080
  timeout: 3s

server:
  port: 8090
  log_level: info

logging:
  level: info
  format: json
```

创建开发环境配置 (`configs/config.dev.yaml`):

```yaml
database:
  host: localhost
  port: 5432
  name: metering_dev
  user: dev_user
  password: dev_password
  ssl_mode: disable

collector:
  interval: 10s
  timeout: 5s

nodes:
  - name: local-node
    stats_url: http://localhost:8081/traffic
    stats_secret: dev_secret

auth_api:
  url: http://localhost:8080
  timeout: 3s

server:
  port: 8090
  log_level: debug

logging:
  level: debug
  format: text
```

### 4. 环境变量模板

创建环境变量模板 (`configs/.env.example`):

```bash
# 数据库配置
METERING_DATABASE_HOST=localhost
METERING_DATABASE_PORT=5432
METERING_DATABASE_NAME=metering
METERING_DATABASE_USER=metering_user
METERING_DATABASE_PASSWORD=your_secure_password_here

# 节点密钥
METERING_NODES_0_STATS_SECRET=node_a_secret_key
METERING_NODES_1_STATS_SECRET=node_b_secret_key

# 认证 API
METERING_AUTH_API_URL=http://auth-api:8080

# 服务器
METERING_SERVER_PORT=8090
METERING_SERVER_LOG_LEVEL=info
```

### 5. 配置工具函数

实现配置工具函数 (`internal/config/utils.go`):

```go
package config

import "fmt"

// GetDatabaseDSN 获取数据库连接字符串
func (c *DatabaseConfig) GetDSN() string {
    return fmt.Sprintf(
        "host=%s port=%d user=%s password=%s dbname=%s sslmode=%s",
        c.Host, c.Port, c.User, c.Password, c.Name, c.SSLMode,
    )
}

// Validate 验证数据库配置
func (c *DatabaseConfig) Validate() error {
    if c.MinConns > c.MaxConns {
        return fmt.Errorf("min_conns (%d) cannot be greater than max_conns (%d)",
            c.MinConns, c.MaxConns)
    }
    return nil
}
```

## 技术约束

1. **安全性**: 敏感信息(密码、密钥)不能硬编码或提交到代码库
2. **向后兼容**: 保持与 Phase 0 原型的配置项兼容
3. **12-factor app**: 遵循 12-factor app 配置原则
4. **验证**: 启动时必须验证所有配置项

## 依赖

### 外部依赖
- `github.com/spf13/viper` - 配置管理
- `github.com/go-playground/validator/v10` - 配置验证
- Go 1.21+

### 内部依赖
- TASK-001: 需要数据库配置结构

### 参考资料
- Phase 0 原型: `openmesh-apple/docs/v2/Hysteria2_Validation/prototype/metering/main.go`
- Phase 1 工作计划: `openmesh-apple/docs/v2/Phase1-工作计划.md` (第 3.2 节)

## 交付物

### 代码文件
- [ ] `internal/config/config.go` - 配置结构定义
- [ ] `internal/config/loader.go` - 配置加载逻辑
- [ ] `internal/config/utils.go` - 配置工具函数
- [ ] `configs/config.example.yaml` - 配置文件示例
- [ ] `configs/config.dev.yaml` - 开发环境配置
- [ ] `configs/.env.example` - 环境变量模板

### 测试
- [ ] `internal/config/loader_test.go` - 配置加载测试
- [ ] `internal/config/validation_test.go` - 配置验证测试

### 文档
- [ ] `internal/config/README.md` - 配置系统使用文档
- [ ] 配置项说明文档

## 验收标准

### 功能验收
- [ ] 可以从 YAML 文件加载配置
- [ ] 环境变量可以覆盖配置文件
- [ ] 配置验证正常工作
- [ ] 默认值正确设置
- [ ] 敏感信息通过环境变量注入

### 安全验收
- [ ] 配置文件示例中不包含真实密码
- [ ] 敏感信息使用环境变量占位符
- [ ] `.env.example` 不包含真实密钥

### 代码质量
- [ ] 配置结构清晰,易于扩展
- [ ] 错误信息清晰,便于调试
- [ ] 单元测试覆盖率 > 80%

## 实施建议

### 第一步: 安装依赖
```bash
cd openmesh-apple/metering-service
go get github.com/spf13/viper
go get github.com/go-playground/validator/v10
```

### 第二步: 定义配置结构
先定义完整的配置结构体,确保覆盖所有配置项。

### 第三步: 实现加载逻辑
实现配置加载和验证逻辑,编写单元测试。

### 第四步: 创建配置示例
创建各种环境的配置文件示例。

### 第五步: 集成到主程序
在 `cmd/metering/main.go` 中集成配置加载。

## 注意事项

1. **环境变量优先级**: 环境变量 > 配置文件 > 默认值
2. **敏感信息**: 绝不在配置文件中硬编码密码和密钥
3. **配置验证**: 启动时立即验证,避免运行时错误
4. **错误提示**: 配置错误时给出清晰的错误信息
5. **文档**: 每个配置项都要有清晰的说明

## 参考 Phase 0 原型

原型使用的配置项:
- `dbPath` → `database.host`, `database.name`
- `authAPIURL` → `auth_api.url`
- `interval` → `collector.interval`

确保这些配置项在新系统中都有对应。

---

**创建日期**: 2026-03-26
**负责人**: 开发 AI
**验收人**: 验收 AI (参考 AC-002)
