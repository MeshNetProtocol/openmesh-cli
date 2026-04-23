package repository

import "market-blockchain/internal/domain"

type ChargeRepository interface {
	Create(charge *domain.Charge) error
	Update(charge *domain.Charge) error
	GetByChargeID(chargeID string) (*domain.Charge, error)
	ListByIdentity(identityAddress string) ([]*domain.Charge, error)
}
