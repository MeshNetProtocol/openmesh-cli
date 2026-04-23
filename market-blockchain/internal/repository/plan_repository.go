package repository

import (
	"context"
	"market-blockchain/internal/domain"
)

type PlanRepository interface {
	Create(plan *domain.Plan) error
	Update(plan *domain.Plan) error
	GetByPlanID(planID string) (*domain.Plan, error)
	ListActive() ([]*domain.Plan, error)

	// Admin methods
	ListAll(ctx context.Context) ([]*domain.Plan, error)
}
