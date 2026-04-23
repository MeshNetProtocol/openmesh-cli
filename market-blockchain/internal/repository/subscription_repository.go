package repository

import "market-blockchain/internal/domain"

type SubscriptionRepository interface {
	Create(subscription *domain.Subscription) error
	Update(subscription *domain.Subscription) error
	GetByID(id string) (*domain.Subscription, error)
	GetByIdentityAndPlan(identityAddress, planID string) (*domain.Subscription, error)
	ListRenewable(now int64) ([]*domain.Subscription, error)
}
