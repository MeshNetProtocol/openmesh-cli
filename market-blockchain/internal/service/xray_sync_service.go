package service

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"log"

	"market-blockchain/internal/domain"
	"market-blockchain/internal/repository"
	"market-blockchain/internal/xray"
)

type XraySyncService struct {
	xrayClient       *xray.Client
	subscriptionRepo repository.SubscriptionRepository
	eventRepo        repository.EventRepository
	inboundTag       string
}

func NewXraySyncService(
	xrayClient *xray.Client,
	subscriptionRepo repository.SubscriptionRepository,
	eventRepo repository.EventRepository,
	inboundTag string,
) *XraySyncService {
	return &XraySyncService{
		xrayClient:       xrayClient,
		subscriptionRepo: subscriptionRepo,
		eventRepo:        eventRepo,
		inboundTag:       inboundTag,
	}
}

func (s *XraySyncService) SyncSubscriptionToXray(ctx context.Context, subscription *domain.Subscription) error {
	email := subscription.IdentityAddress
	uuid := generateUUIDFromAddress(subscription.IdentityAddress)

	if subscription.Status == "active" {
		if err := s.xrayClient.AddUser(ctx, email, uuid); err != nil {
			log.Printf("Failed to add user %s to Xray: %v", email, err)
			return fmt.Errorf("failed to add user to Xray: %w", err)
		}
		log.Printf("Added user %s to Xray", email)
		return nil
	}

	if subscription.Status == "cancelled" || subscription.Status == "expired" {
		if err := s.xrayClient.RemoveUser(ctx, email); err != nil {
			log.Printf("Failed to remove user %s from Xray: %v", email, err)
			return fmt.Errorf("failed to remove user from Xray: %w", err)
		}
		log.Printf("Removed user %s from Xray", email)
		return nil
	}

	return nil
}

func (s *XraySyncService) SyncAllActiveSubscriptions(ctx context.Context) error {
	subscriptions, err := s.subscriptionRepo.ListByStatus(ctx, "active", 1000, 0)
	if err != nil {
		return fmt.Errorf("failed to list active subscriptions: %w", err)
	}

	log.Printf("Syncing %d active subscriptions to Xray", len(subscriptions))

	for _, sub := range subscriptions {
		if err := s.SyncSubscriptionToXray(ctx, sub); err != nil {
			log.Printf("Failed to sync subscription %s: %v", sub.ID, err)
		}
	}

	return nil
}

func generateUUIDFromAddress(address string) string {
	hash := sha256.Sum256([]byte(address))
	hashHex := hex.EncodeToString(hash[:])
	return fmt.Sprintf("%s-%s-%s-%s-%s",
		hashHex[0:8],
		hashHex[8:12],
		hashHex[12:16],
		hashHex[16:20],
		hashHex[20:32],
	)
}

func GetUserUUID(identityAddress string) string {
	return generateUUIDFromAddress(identityAddress)
}
