package scheduler

import (
	"context"
	"log"
	"time"

	"market-blockchain/internal/service"
)

type Scheduler struct {
	renewalService *service.RenewalService
	interval       time.Duration
	stopChan       chan struct{}
}

func NewScheduler(renewalService *service.RenewalService, interval time.Duration) *Scheduler {
	return &Scheduler{
		renewalService: renewalService,
		interval:       interval,
		stopChan:       make(chan struct{}),
	}
}

func (s *Scheduler) Start(ctx context.Context) {
	ticker := time.NewTicker(s.interval)
	defer ticker.Stop()

	log.Printf("Scheduler started with interval: %v", s.interval)

	for {
		select {
		case <-ticker.C:
			if err := s.renewalService.ProcessRenewals(ctx); err != nil {
				log.Printf("Renewal processing error: %v", err)
			}
		case <-s.stopChan:
			log.Println("Scheduler stopped")
			return
		case <-ctx.Done():
			log.Println("Scheduler context cancelled")
			return
		}
	}
}

func (s *Scheduler) Stop() {
	close(s.stopChan)
}
