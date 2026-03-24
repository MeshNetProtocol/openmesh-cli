package main

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"sync"
	"time"
)

// Traffic 流量数据
type Traffic struct {
	Tx uint64 `json:"tx"`
	Rx uint64 `json:"rx"`
}

// NodeTraffic 节点流量数据
type NodeTraffic struct {
	NodeID  string
	Traffic map[string]Traffic
	Error   error
}

// Collector 流量采集器
type Collector struct {
	db     *Database
	client *http.Client
}

// NewCollector 创建流量采集器
func NewCollector(db *Database) *Collector {
	return &Collector{
		db: db,
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

// CollectAll 并发采集所有节点的流量
func (c *Collector) CollectAll() (map[string]Traffic, []error) {
	nodes, err := c.db.GetNodes()
	if err != nil {
		return nil, []error{fmt.Errorf("failed to get nodes: %w", err)}
	}

	if len(nodes) == 0 {
		return make(map[string]Traffic), nil
	}

	// 并发采集
	results := make(chan NodeTraffic, len(nodes))
	var wg sync.WaitGroup

	for _, node := range nodes {
		wg.Add(1)
		go func(n Node) {
			defer wg.Done()

			traffic, err := c.fetchNodeTraffic(n)
			results <- NodeTraffic{
				NodeID:  n.NodeID,
				Traffic: traffic,
				Error:   err,
			}
		}(node)
	}

	// 等待所有采集完成
	go func() {
		wg.Wait()
		close(results)
	}()

	// 汇总结果
	aggregated := make(map[string]Traffic)
	var errors []error

	for result := range results {
		if result.Error != nil {
			log.Printf("Failed to collect from node %s: %v", result.NodeID, result.Error)
			errors = append(errors, fmt.Errorf("node %s: %w", result.NodeID, result.Error))
			continue
		}

		// 记录每个节点的流量日志
		for userID, traffic := range result.Traffic {
			if err := c.db.LogTraffic(userID, result.NodeID, int64(traffic.Tx), int64(traffic.Rx)); err != nil {
				log.Printf("Failed to log traffic for user %s on node %s: %v",
					userID, result.NodeID, err)
			}

			// 汇总流量
			current := aggregated[userID]
			current.Tx += traffic.Tx
			current.Rx += traffic.Rx
			aggregated[userID] = current
		}
	}

	return aggregated, errors
}

// SaveTraffic 保存流量到数据库
func (c *Collector) SaveTraffic(traffic map[string]Traffic) error {
	for userID, t := range traffic {
		total := int64(t.Tx + t.Rx)
		if total == 0 {
			continue
		}

		if err := c.db.IncrementTraffic(userID, int64(t.Tx), int64(t.Rx)); err != nil {
			log.Printf("Failed to increment traffic for user %s: %v", userID, err)
			return err
		}

		log.Printf("Updated traffic for user %s: tx=%d, rx=%d, total=%d",
			userID, t.Tx, t.Rx, total)
	}

	return nil
}
