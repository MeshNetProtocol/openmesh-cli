package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"
)

func main() {
	// 命令行参数
	dataFile := flag.String("data", "../data/traffic.json", "Data file path")
	interval := flag.Duration("interval", 10*time.Second, "Collection interval")
	flag.Parse()

	// 创建存储
	storage, err := NewFileStorage(*dataFile)
	if err != nil {
		log.Fatalf("Failed to create storage: %v", err)
	}

	// 配置节点
	nodes := []Node{
		{
			NodeID:        "node1",
			TrafficAPIURL: "http://127.0.0.1:9443",
			Secret:        "stats_secret_node1",
		},
		{
			NodeID:        "node2",
			TrafficAPIURL: "http://127.0.0.1:9444",
			Secret:        "stats_secret_node2",
		},
	}

	// 创建采集器
	collector := NewCollector(storage, nodes)

	log.Printf("Traffic collector started")
	log.Printf("Data file: %s", *dataFile)
	log.Printf("Collection interval: %v", *interval)
	log.Printf("Monitoring nodes:")
	for _, node := range nodes {
		log.Printf("  - %s: %s", node.NodeID, node.TrafficAPIURL)
	}
	log.Println()

	// 处理信号
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	// 定时采集
	ticker := time.NewTicker(*interval)
	defer ticker.Stop()

	// 立即执行一次采集
	if err := collector.CollectAll(); err != nil {
		log.Printf("Collection error: %v", err)
	}

	// 定时循环
	for {
		select {
		case <-ticker.C:
			if err := collector.CollectAll(); err != nil {
				log.Printf("Collection error: %v", err)
			}
		case <-sigCh:
			log.Println("Received shutdown signal")
			log.Println("Traffic collector stopped")
			return
		}
	}
}
