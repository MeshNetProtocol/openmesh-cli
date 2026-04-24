package repository

import (
	"context"
	"market-blockchain/internal/domain"
)

type AuthorizationRepository interface {
	Create(authorization *domain.Authorization) error
	Update(authorization *domain.Authorization) error
	GetByID(ctx context.Context, id string) (*domain.Authorization, error)
	GetByIdentityAndPlan(ctx context.Context, identityAddress, planID string) (*domain.Authorization, error)
}
