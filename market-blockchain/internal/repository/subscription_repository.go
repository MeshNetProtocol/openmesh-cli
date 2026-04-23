package repository

import (
	"context"
	"market-blockchain/internal/domain"
)

type SubscriptionRepository interface {
	Create(subscription *domain.Subscription) error
	Update(subscription *domain.Subscription) error
	GetByID(id string) (*domain.Subscription, error)
	GetByIdentityAndPlan(identityAddress, planID string) (*domain.Subscription, error)
	ListRenewable(now int64) ([]*domain.Subscription, error)

	// Admin methods
	ListByStatus(ctx context.Context, status string, limit, offset int) ([]*domain.Subscription, error)
	ListAll(ctx context.Context, limit, offset int) ([]*domain.Subscription, error)
	CountByStatus(ctx context.Context, status string) (int, error)
	CountAll(ctx context.Context) (int, error)
	CountByPlanAndStatus(ctx context.Context, planID, status string) (int, error)
	SearchByAddress(ctx context.Context, address string) ([]*domain.Subscription, error)
}
