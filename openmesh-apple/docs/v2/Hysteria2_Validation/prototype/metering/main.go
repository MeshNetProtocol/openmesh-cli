package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"
)

const (
	defaultDBPath      = "../../data/metering.db"
	defaultAuthAPIURL  = "http://127.0.0.1:8080"
	defaultInterval    = 10 * time.Second
)

// MeteringService 计费服务
type MeteringService struct {
	db           *Database
	collector    *Collector
	quotaChecker *QuotaChecker
	interval     time.Duration
	stopCh       chan struct{}
}

// NewMeteringService 创建计费服务
func NewMeteringService(dbPath, authAPIURL string, interval time.Duration) (*MeteringService, error) {
	// 初始化数据库
	db, err := NewDatabase(dbPath)
	if err != nil {
		return nil, err
	}

	if err := db.InitSchema(); err != nil {
		return nil, err
	}

	// 创建组件
	collector := NewCollector(db)
	quotaChecker := NewQuotaChecker(db, authAPIURL)

	return &MeteringService{
		db:           db,
		collector:    collector,
		quotaChecker: quotaChecker,
		interval:     interval,
		stopCh:       make(chan struct{}),
	}, nil
}

// Start 启动服务
func (s *MeteringService) Start() {
	log.Printf("Metering service started, collection interval: %v", s.interval)

	ticker := time.NewTicker(s.interval)
	defer ticker.Stop()

	// 立即执行一次采集
	s.runCollection()

	for {
		select {
		case <-ticker.C:
			s.runCollection()
		case <-s.stopCh:
			log.Println("Metering service stopped")
			return
		}
	}
}

// Stop 停止服务
func (s *MeteringService) Stop() {
	close(s.stopCh)
	s.db.Close()
}

// runCollection 执行一次完整的采集流程
func (s *MeteringService) runCollection() {
	log.Println("========================================")
	log.Println("Starting traffic collection cycle")
	log.Println("========================================")

	startTime := time.Now()

	// 1. 采集所有节点的流量
	traffic, errors := s.collector.CollectAll()
	if len(errors) > 0 {
		log.Printf("Collection completed with %d errors", len(errors))
		for _, err := range errors {
			log.Printf("  - %v", err)
		}
	}

	if len(traffic) == 0 {
		log.Println("No traffic data collected")
		log.Printf("Collection cycle completed in %v\n", time.Since(startTime))
		return
	}

	log.Printf("Collected traffic from %d users", len(traffic))

	// 2. 保存流量到数据库
	if err := s.collector.SaveTraffic(traffic); err != nil {
		log.Printf("Failed to save traffic: %v", err)
		return
	}

	// 3. 检查所有用户的配额
	log.Println("Checking user quotas...")
	if err := s.quotaChecker.CheckAll(); err != nil {
		log.Printf("Quota check error: %v", err)
	}

	// 4. 打印统计信息
	s.printStats()

	log.Printf("Collection cycle completed in %v\n", time.Since(startTime))
}

// printStats 打印统计信息
func (s *MeteringService) printStats() {
	users, err := s.db.GetAllUsers()
	if err != nil {
		log.Printf("Failed to get users: %v", err)
		return
	}

	log.Println("User statistics:")
	for _, user := range users {
		percentage := float64(user.Used) / float64(user.Quota) * 100
		log.Printf("  - %s: %d/%d bytes (%.1f%%) [%s]",
			user.UserID, user.Used, user.Quota, percentage, user.Status)
	}
}

func main() {
	// 命令行参数
	dbPath := flag.String("db", defaultDBPath, "Database file path")
	authAPIURL := flag.String("auth-api", defaultAuthAPIURL, "Auth API URL")
	interval := flag.Duration("interval", defaultInterval, "Collection interval")
	flag.Parse()

	// 创建服务
	service, err := NewMeteringService(*dbPath, *authAPIURL, *interval)
	if err != nil {
		log.Fatalf("Failed to create metering service: %v", err)
	}

	// 处理信号
	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)

	// 启动服务
	go service.Start()

	// 等待退出信号
	<-sigCh
	log.Println("Received shutdown signal")
	service.Stop()
}
