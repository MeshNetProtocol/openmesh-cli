package repository

import "market-blockchain/internal/domain"

type EventRepository interface {
	Create(event *domain.Event) error
	ListByIdentity(identityAddress string) ([]*domain.Event, error)
}
