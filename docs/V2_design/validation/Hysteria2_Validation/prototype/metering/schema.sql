-- Metering Service 数据库 Schema

-- 用户表
CREATE TABLE IF NOT EXISTS users (
    user_id TEXT PRIMARY KEY,
    quota INTEGER NOT NULL,                    -- 配额（bytes）
    used INTEGER NOT NULL DEFAULT 0,           -- 已用流量（bytes）
    status TEXT NOT NULL DEFAULT 'active',     -- active/blocked
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 流量日志表
CREATE TABLE IF NOT EXISTS traffic_logs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id TEXT NOT NULL,
    node_id TEXT NOT NULL,
    tx INTEGER NOT NULL,                       -- 上传流量（bytes）
    rx INTEGER NOT NULL,                       -- 下载流量（bytes）
    collected_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);

-- 节点表
CREATE TABLE IF NOT EXISTS nodes (
    node_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    traffic_api_url TEXT NOT NULL,
    secret TEXT NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 创建索引
CREATE INDEX IF NOT EXISTS idx_traffic_logs_user_id ON traffic_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_traffic_logs_collected_at ON traffic_logs(collected_at);
CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);

-- 插入测试数据
INSERT OR REPLACE INTO users (user_id, quota, used, status) VALUES
    ('user_001', 1048576, 0, 'active'),      -- 1MB 配额
    ('user_002', 524288, 0, 'active'),       -- 512KB 配额
    ('user_003', 2097152, 0, 'active');      -- 2MB 配额

INSERT OR REPLACE INTO nodes (node_id, name, traffic_api_url, secret, enabled) VALUES
    ('node-a', 'Node A', 'http://127.0.0.1:8081', 'test_secret_key_12345', 1),
    ('node-b', 'Node B', 'http://127.0.0.1:8082', 'test_secret_key_12345', 1);
