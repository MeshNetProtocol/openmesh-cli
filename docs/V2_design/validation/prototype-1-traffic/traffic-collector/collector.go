package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"time"
)

// Traffic 流量数据
type Traffic struct {
	Tx uint64 `json:"tx"`
	Rx uint64 `json:"rx"`
}

// Node 节点配置
type Node struct {
	NodeID        string
	TrafficAPIURL string
	Secret        string
}

// Collector 流量采集器
type Collector struct {
	storage *FileStorage
	nodes   []Node
	client  *http.Client
}

// NewCollector 创建流量采集器
func NewCollector(storage *FileStorage, nodes []Node) *Collector {
	return &Collector{
		storage: storage,
		nodes:   nodes,
		client: &http.Client{
			Timeout: 5 * time.Second,
		},
	}
}

// fetchNodeTraffic 从单个节点获取流量数据
func (c *Collector) fetchNodeTraffic(node Node) (map[string]Traffic, error) {
	url := fmt.Sprintf("%s/traffic?clear=true", node.TrafficAPIURL)

	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, fmt.Errorf("failed to create request: %w", err)
	}

	req.Header.Set("Authorization", node.Secret)

	resp, err := c.client.Do(req)
	if err != nil {
		return nil, fmt.Errorf("failed to fetch traffic: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		return nil, fmt.Errorf("unexpected status code %d: %s", resp.StatusCode, string(body))
	}

	var traffic map[string]Traffic
	if err := json.NewDecoder(resp.Body).Decode(&traffic); err != nil {
		return nil, fmt.Errorf("failed to decode response: %w", err)
	}

	return traffic, nil
}

// CollectAll 采集所有节点的流量
func (c *Collector) CollectAll() error {
	log.Println("========================================")
	log.Println("Starting traffic collection cycle")
	log.Println("========================================")

	totalUsers := 0

	for _, node := range c.nodes {
		log.Printf("Collecting from node: %s", node.NodeID)

		traffic, err := c.fetchNodeTraffic(node)
		if err != nil {
			log.Printf("Failed to collect from node %s: %v", node.NodeID, err)
			continue
		}

		if len(traffic) == 0 {
			log.Printf("No traffic data from node %s", node.NodeID)
			continue
		}

		// 保存流量数据
		for userID, t := range traffic {
			if t.Tx == 0 && t.Rx == 0 {
				continue
			}

			if err := c.storage.RecordTraffic(userID, node.NodeID, int64(t.Tx), int64(t.Rx)); err != nil {
				log.Printf("Failed to record traffic for user %s: %v", userID, err)
				continue
			}

			log.Printf("Recorded traffic for user %s on node %s: tx=%d, rx=%d",
				userID, node.NodeID, t.Tx, t.Rx)
			totalUsers++
		}
	}

	log.Printf("Collection completed, updated %d user records", totalUsers)

	// 打印统计信息
	c.printStats()

	return nil
}

// printStats 打印统计信息
func (c *Collector) printStats() {
	users, err := c.storage.GetAllUsers()
	if err != nil {
		log.Printf("Failed to get users: %v", err)
		return
	}

	if len(users) == 0 {
		log.Println("No user traffic data")
		return
	}

	log.Println("User traffic statistics:")
	for _, user := range users {
		total := user.TotalTx + user.TotalRx
		log.Printf("  - %s: tx=%d, rx=%d, total=%d bytes",
			user.UserID, user.TotalTx, user.TotalRx, total)

		for nodeID, traffic := range user.ByNode {
			log.Printf("    - node %s: %d bytes", nodeID, traffic)
		}
	}
}
