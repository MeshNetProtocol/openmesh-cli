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
	subscription, err := s.subscriptions.GetByID(subscriptionID)
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

func (s *SubscriptionManagementService) GetSubscription(subscriptionID string) (*domain.Subscription, error) {
	return s.subscriptions.GetByID(subscriptionID)
}

func (s *SubscriptionManagementService) GetSubscriptionByIdentityAndPlan(identityAddress, planID string) (*domain.Subscription, error) {
	return s.subscriptions.GetByIdentityAndPlan(identityAddress, planID)
}
