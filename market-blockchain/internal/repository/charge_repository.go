package repository

import (
	"context"
	"market-blockchain/internal/domain"
)

type ChargeRepository interface {
	Create(charge *domain.Charge) error
	Update(charge *domain.Charge) error
	GetByChargeID(chargeID string) (*domain.Charge, error)
	ListByIdentity(identityAddress string) ([]*domain.Charge, error)

	// Admin methods
	ListByStatusAndDateRange(ctx context.Context, status string, fromTime, toTime int64) ([]*domain.Charge, error)
	ListByDateRange(ctx context.Context, fromTime, toTime int64) ([]*domain.Charge, error)
	ListBySubscription(ctx context.Context, subscriptionID string) ([]*domain.Charge, error)
	SumCompletedCharges(ctx context.Context, fromTime, toTime int64) (int64, error)
	CountAndSumByStatus(ctx context.Context, status string) (int, int64, error)
}
