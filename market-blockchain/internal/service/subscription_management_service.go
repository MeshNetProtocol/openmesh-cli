package service

import (
	"context"
	"fmt"

	"market-blockchain/internal/domain"
	"market-blockchain/internal/repository"
)

type SubscriptionManagementService struct {
	subscriptions repository.SubscriptionRepository
	lifecycle     *SubscriptionLifecycleService
}

func NewSubscriptionManagementService(
	subscriptions repository.SubscriptionRepository,
	lifecycle *SubscriptionLifecycleService,
) *SubscriptionManagementService {
	return &SubscriptionManagementService{
		subscriptions: subscriptions,
		lifecycle:     lifecycle,
	}
}

func (s *SubscriptionManagementService) CancelSubscription(ctx context.Context, subscriptionID string) error {
	subscription, err := s.subscriptions.GetByID(ctx, subscriptionID)
	if err != nil {
		return fmt.Errorf("get subscription: %w", err)
	}
	if subscription == nil {
		return fmt.Errorf("subscription not found")
	}

	if err := s.lifecycle.CancelSubscription(ctx, subscription); err != nil {
		return err
	}

	return nil
}

func (s *SubscriptionManagementService) GetSubscription(ctx context.Context, subscriptionID string) (*domain.Subscription, error) {
	return s.subscriptions.GetByID(ctx, subscriptionID)
}

func (s *SubscriptionManagementService) GetSubscriptionByIdentityAndPlan(ctx context.Context, identityAddress, planID string) (*domain.Subscription, error) {
	return s.subscriptions.GetByIdentityAndPlan(ctx, identityAddress, planID)
}
