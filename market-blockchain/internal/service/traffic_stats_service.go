package service

import (
	"context"
	"fmt"
	"log"
	"time"

	"market-blockchain/internal/repository"
	"market-blockchain/internal/xray"
)

type TrafficStatsService struct {
	xrayClient       *xray.Client
	subscriptionRepo repository.SubscriptionRepository
	updateInterval   time.Duration
}

func NewTrafficStatsService(
	xrayClient *xray.Client,
	subscriptionRepo repository.SubscriptionRepository,
	updateInterval time.Duration,
) *TrafficStatsService {
	if updateInterval == 0 {
		updateInterval = 10 * time.Second
	}

	return &TrafficStatsService{
		xrayClient:       xrayClient,
		subscriptionRepo: subscriptionRepo,
		updateInterval:   updateInterval,
	}
}

func (s *TrafficStatsService) Start(ctx context.Context) {
	ticker := time.NewTicker(s.updateInterval)
	defer ticker.Stop()

	log.Printf("Traffic stats service started (interval: %v)", s.updateInterval)

	if err := s.UpdateAllTrafficStats(ctx); err != nil {
		log.Printf("Failed to update traffic stats: %v", err)
	}

	for {
		select {
		case <-ctx.Done():
			log.Println("Traffic stats service stopped")
			return
		case <-ticker.C:
			if err := s.UpdateAllTrafficStats(ctx); err != nil {
				log.Printf("Failed to update traffic stats: %v", err)
			}
		}
	}
}

func (s *TrafficStatsService) UpdateAllTrafficStats(ctx context.Context) error {
	trafficList, err := s.xrayClient.QueryAllUsersTraffic(ctx)
	if err != nil {
		return fmt.Errorf("failed to query traffic from Xray: %w", err)
	}

	log.Printf("Updating traffic stats for %d users", len(trafficList))

	for _, traffic := range trafficList {
		subscription, err := s.subscriptionRepo.GetByIdentityAndPlan(traffic.Email, "")
		if err != nil || subscription == nil {
			continue
		}

		subscription.Uplink = traffic.Uplink
		subscription.Downlink = traffic.Downlink
		subscription.TotalTraffic = traffic.Uplink + traffic.Downlink

		if err := s.subscriptionRepo.Update(subscription); err != nil {
			log.Printf("Failed to update traffic stats for user %s: %v", traffic.Email, err)
			continue
		}

		log.Printf("User %s: uplink=%s, downlink=%s, total=%s",
			traffic.Email,
			formatBytes(traffic.Uplink),
			formatBytes(traffic.Downlink),
			formatBytes(subscription.TotalTraffic),
		)
	}

	return nil
}

func formatBytes(bytes int64) string {
	const unit = 1024
	if bytes < unit {
		return fmt.Sprintf("%d B", bytes)
	}
	div, exp := int64(unit), 0
	for n := bytes / unit; n >= unit; n /= unit {
		div *= unit
		exp++
	}
	return fmt.Sprintf("%.1f %cB", float64(bytes)/float64(div), "KMGTPE"[exp])
}
