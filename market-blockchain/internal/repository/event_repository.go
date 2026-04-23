package repository

import (
	"context"
	"market-blockchain/internal/domain"
)

type EventRepository interface {
	Create(event *domain.Event) error
	ListByIdentity(identityAddress string) ([]*domain.Event, error)

	// Admin methods
	ListByTypeAndDateRange(ctx context.Context, eventType string, fromTime, toTime int64) ([]*domain.Event, error)
	ListByDateRange(ctx context.Context, fromTime, toTime int64) ([]*domain.Event, error)
	ListBySubscription(ctx context.Context, subscriptionID string, limit int) ([]*domain.Event, error)
	ListRecent(ctx context.Context, limit int) ([]*domain.Event, error)
	GetByID(ctx context.Context, id string) (*domain.Event, error)
}
