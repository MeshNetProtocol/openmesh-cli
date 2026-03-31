package main

import (
	"encoding/json"
	"os"
	"sync"
	"time"
)

// UserTraffic 用户流量数据
type UserTraffic struct {
	UserID      string            `json:"user_id"`
	TotalTx     int64             `json:"total_tx"`
	TotalRx     int64             `json:"total_rx"`
	ByNode      map[string]int64  `json:"by_node"`
	LastUpdated time.Time         `json:"last_updated"`
}

// TrafficData 流量数据文件结构
type TrafficData struct {
	Users map[string]*UserTraffic `json:"users"`
}

// FileStorage 文件存储实现
type FileStorage struct {
	dataFile string
	data     *TrafficData
	mu       sync.RWMutex
}

// NewFileStorage 创建文件存储
func NewFileStorage(dataFile string) (*FileStorage, error) {
	fs := &FileStorage{
		dataFile: dataFile,
		data: &TrafficData{
			Users: make(map[string]*UserTraffic),
		},
	}

	// 尝试加载现有数据
	if err := fs.load(); err != nil && !os.IsNotExist(err) {
		return nil, err
	}

	return fs, nil
}

// load 从文件加载数据
func (fs *FileStorage) load() error {
	data, err := os.ReadFile(fs.dataFile)
	if err != nil {
		return err
	}

	return json.Unmarshal(data, &fs.data)
}

// save 保存数据到文件
func (fs *FileStorage) save() error {
	data, err := json.MarshalIndent(fs.data, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(fs.dataFile, data, 0644)
}

// RecordTraffic 记录流量
func (fs *FileStorage) RecordTraffic(userID string, nodeID string, tx, rx int64) error {
	fs.mu.Lock()
	defer fs.mu.Unlock()

	user, exists := fs.data.Users[userID]
	if !exists {
		user = &UserTraffic{
			UserID: userID,
			ByNode: make(map[string]int64),
		}
		fs.data.Users[userID] = user
	}

	user.TotalTx += tx
	user.TotalRx += rx
	user.ByNode[nodeID] += (tx + rx)
	user.LastUpdated = time.Now()

	return fs.save()
}

// GetUserTraffic 查询用户总流量
func (fs *FileStorage) GetUserTraffic(userID string) (int64, error) {
	fs.mu.RLock()
	defer fs.mu.RUnlock()

	user, exists := fs.data.Users[userID]
	if !exists {
		return 0, nil
	}

	return user.TotalTx + user.TotalRx, nil
}

// GetAllUsers 获取所有用户
func (fs *FileStorage) GetAllUsers() ([]*UserTraffic, error) {
	fs.mu.RLock()
	defer fs.mu.RUnlock()

	users := make([]*UserTraffic, 0, len(fs.data.Users))
	for _, user := range fs.data.Users {
		users = append(users, user)
	}

	return users, nil
}
