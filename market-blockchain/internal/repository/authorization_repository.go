package repository

import "market-blockchain/internal/domain"

type AuthorizationRepository interface {
	Create(authorization *domain.Authorization) error
	Update(authorization *domain.Authorization) error
	GetByIdentityAndPlan(identityAddress, planID string) (*domain.Authorization, error)
}
