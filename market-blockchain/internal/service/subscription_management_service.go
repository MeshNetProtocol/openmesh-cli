package service

import (
	"fmt"
	"time"

	"market-blockchain/internal/domain"
	"market-blockchain/internal/repository"
)

type SubscriptionManagementService struct {
	subscriptions repository.SubscriptionRepository
	events        repository.EventRepository
}

func NewSubscriptionManagementService(
	subscriptions repository.SubscriptionRepository,
	events repository.EventRepository,
) *SubscriptionManagementService {
	return &SubscriptionManagementService{
		subscriptions: subscriptions,
		events:        events,
	}
}

func (s *SubscriptionManagementService) CancelSubscription(subscriptionID string) error {
	subscription, err := s.subscriptions.GetByID(subscriptionID)
	if err != nil {
		return fmt.Errorf("get subscription: %w", err)
	}
	if subscription == nil {
		return fmt.Errorf("subscription not found")
	}

	if subscription.Status == domain.SubscriptionCancelled {
		return fmt.Errorf("subscription already cancelled")
	}

	now := time.Now().UnixMilli()
	subscription.Status = domain.SubscriptionCancelled
	subscription.AutoRenew = false
	subscription.UpdatedAt = now

	if err := s.subscriptions.Update(subscription); err != nil {
		return fmt.Errorf("update subscription: %w", err)
	}

	s.events.Create(&domain.Event{
		ID:              fmt.Sprintf("evt_%d", now),
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    subscription.PayerAddress,
		PlanID:          subscription.PlanID,
		ChargeID:        "",
		Type:            domain.EventCancel,
		Description:     "Subscription cancelled by user",
		Metadata:        "",
		CreatedAt:       now,
	})

	return nil
}

func (s *SubscriptionManagementService) GetSubscription(subscriptionID string) (*domain.Subscription, error) {
	return s.subscriptions.GetByID(subscriptionID)
}

func (s *SubscriptionManagementService) GetSubscriptionByIdentityAndPlan(identityAddress, planID string) (*domain.Subscription, error) {
	return s.subscriptions.GetByIdentityAndPlan(identityAddress, planID)
}
