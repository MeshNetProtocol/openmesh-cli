package main

import (
	"database/sql"
	"fmt"
	"time"

	_ "github.com/mattn/go-sqlite3"
)

// User 用户结构
type User struct {
	UserID    string
	Quota     int64
	Used      int64
	Status    string
	CreatedAt time.Time
	UpdatedAt time.Time
}

// TrafficLog 流量日志结构
type TrafficLog struct {
	ID          int64
	UserID      string
	NodeID      string
	Tx          int64
	Rx          int64
	CollectedAt time.Time
}

// Node 节点结构
type Node struct {
	NodeID         string
	Name           string
	TrafficAPIURL  string
	Secret         string
	Enabled        bool
	CreatedAt      time.Time
}

// Database 数据库管理器
type Database struct {
	db *sql.DB
}

// NewDatabase 创建数据库管理器
func NewDatabase(dbPath string) (*Database, error) {
	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// 测试连接
	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	return &Database{db: db}, nil
}

// Close 关闭数据库连接
func (d *Database) Close() error {
	return d.db.Close()
}

// InitSchema 初始化数据库表结构
func (d *Database) InitSchema() error {
	schema := `
	CREATE TABLE IF NOT EXISTS users (
		user_id TEXT PRIMARY KEY,
		quota INTEGER NOT NULL,
		used INTEGER NOT NULL DEFAULT 0,
		status TEXT NOT NULL DEFAULT 'active',
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);

	CREATE TABLE IF NOT EXISTS traffic_logs (
		id INTEGER PRIMARY KEY AUTOINCREMENT,
		user_id TEXT NOT NULL,
		node_id TEXT NOT NULL,
		tx INTEGER NOT NULL,
		rx INTEGER NOT NULL,
		collected_at DATETIME DEFAULT CURRENT_TIMESTAMP,
		FOREIGN KEY (user_id) REFERENCES users(user_id)
	);

	CREATE TABLE IF NOT EXISTS nodes (
		node_id TEXT PRIMARY KEY,
		name TEXT NOT NULL,
		traffic_api_url TEXT NOT NULL,
		secret TEXT NOT NULL,
		enabled INTEGER NOT NULL DEFAULT 1,
		created_at DATETIME DEFAULT CURRENT_TIMESTAMP
	);

	CREATE INDEX IF NOT EXISTS idx_traffic_logs_user_id ON traffic_logs(user_id);
	CREATE INDEX IF NOT EXISTS idx_traffic_logs_collected_at ON traffic_logs(collected_at);
	CREATE INDEX IF NOT EXISTS idx_users_status ON users(status);
	`

	_, err := d.db.Exec(schema)
	return err
}

// GetUser 获取用户信息
func (d *Database) GetUser(userID string) (*User, error) {
	var user User
	err := d.db.QueryRow(`
		SELECT user_id, quota, used, status, created_at, updated_at
		FROM users WHERE user_id = ?
	`, userID).Scan(&user.UserID, &user.Quota, &user.Used, &user.Status,
		&user.CreatedAt, &user.UpdatedAt)

	if err == sql.ErrNoRows {
		return nil, fmt.Errorf("user not found: %s", userID)
	}
	if err != nil {
		return nil, err
	}

	return &user, nil
}

// IncrementTraffic 增加用户流量
func (d *Database) IncrementTraffic(userID string, tx, rx int64) error {
	_, err := d.db.Exec(`
		UPDATE users
		SET used = used + ?, updated_at = CURRENT_TIMESTAMP
		WHERE user_id = ?
	`, tx+rx, userID)

	return err
}

// UpdateUserStatus 更新用户状态
func (d *Database) UpdateUserStatus(userID, status string) error {
	_, err := d.db.Exec(`
		UPDATE users
		SET status = ?, updated_at = CURRENT_TIMESTAMP
		WHERE user_id = ?
	`, status, userID)

	return err
}

// LogTraffic 记录流量日志
func (d *Database) LogTraffic(userID, nodeID string, tx, rx int64) error {
	_, err := d.db.Exec(`
		INSERT INTO traffic_logs (user_id, node_id, tx, rx)
		VALUES (?, ?, ?, ?)
	`, userID, nodeID, tx, rx)

	return err
}

// GetNodes 获取所有启用的节点
func (d *Database) GetNodes() ([]Node, error) {
	rows, err := d.db.Query(`
		SELECT node_id, name, traffic_api_url, secret, enabled, created_at
		FROM nodes WHERE enabled = 1
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var nodes []Node
	for rows.Next() {
		var node Node
		var enabled int
		err := rows.Scan(&node.NodeID, &node.Name, &node.TrafficAPIURL,
			&node.Secret, &enabled, &node.CreatedAt)
		if err != nil {
			return nil, err
		}
		node.Enabled = enabled == 1
		nodes = append(nodes, node)
	}

	return nodes, rows.Err()
}

// GetAllUsers 获取所有用户
func (d *Database) GetAllUsers() ([]User, error) {
	rows, err := d.db.Query(`
		SELECT user_id, quota, used, status, created_at, updated_at
		FROM users
	`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var users []User
	for rows.Next() {
		var user User
		err := rows.Scan(&user.UserID, &user.Quota, &user.Used, &user.Status,
			&user.CreatedAt, &user.UpdatedAt)
		if err != nil {
			return nil, err
		}
		users = append(users, user)
	}

	return users, rows.Err()
}

// GetUserTrafficLogs 获取用户的流量日志
func (d *Database) GetUserTrafficLogs(userID string, limit int) ([]TrafficLog, error) {
	rows, err := d.db.Query(`
		SELECT id, user_id, node_id, tx, rx, collected_at
		FROM traffic_logs
		WHERE user_id = ?
		ORDER BY collected_at DESC
		LIMIT ?
	`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var logs []TrafficLog
	for rows.Next() {
		var log TrafficLog
		err := rows.Scan(&log.ID, &log.UserID, &log.NodeID, &log.Tx, &log.Rx,
			&log.CollectedAt)
		if err != nil {
			return nil, err
		}
		logs = append(logs, log)
	}

	return logs, rows.Err()
}

