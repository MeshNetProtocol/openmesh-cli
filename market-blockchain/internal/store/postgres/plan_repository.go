package postgres

import (
	"context"
	"database/sql"
	"market-blockchain/internal/domain"
)

type PlanRepository struct {
	store *Store
}

func NewPlanRepository(store *Store) *PlanRepository {
	return &PlanRepository{store: store}
}

func (r *PlanRepository) Create(plan *domain.Plan) error {
	query := `
		INSERT INTO plans (
			plan_id, name, description, period_seconds, amount_usdc_base_units,
			amount_usdc_display, authorization_periods, total_authorization_amount,
			active, created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
	`
	_, err := r.store.DB.Exec(query,
		plan.PlanID, plan.Name, plan.Description, plan.PeriodSeconds,
		plan.AmountUSDCBaseUnits, plan.AmountUSDCDisplay, plan.AuthorizationPeriods,
		plan.TotalAuthorizationAmount, plan.Active, plan.CreatedAt, plan.UpdatedAt,
	)
	return err
}

func (r *PlanRepository) Update(plan *domain.Plan) error {
	query := `
		UPDATE plans SET
			name = $2, description = $3, period_seconds = $4,
			amount_usdc_base_units = $5, amount_usdc_display = $6,
			authorization_periods = $7, total_authorization_amount = $8,
			active = $9, updated_at = $10
		WHERE plan_id = $1
	`
	_, err := r.store.DB.Exec(query,
		plan.PlanID, plan.Name, plan.Description, plan.PeriodSeconds,
		plan.AmountUSDCBaseUnits, plan.AmountUSDCDisplay, plan.AuthorizationPeriods,
		plan.TotalAuthorizationAmount, plan.Active, plan.UpdatedAt,
	)
	return err
}

func (r *PlanRepository) GetByPlanID(planID string) (*domain.Plan, error) {
	query := `
		SELECT plan_id, name, description, period_seconds, amount_usdc_base_units,
			amount_usdc_display, authorization_periods, total_authorization_amount,
			active, created_at, updated_at
		FROM plans WHERE plan_id = $1
	`
	plan := &domain.Plan{}
	err := r.store.DB.QueryRow(query, planID).Scan(
		&plan.PlanID, &plan.Name, &plan.Description, &plan.PeriodSeconds,
		&plan.AmountUSDCBaseUnits, &plan.AmountUSDCDisplay, &plan.AuthorizationPeriods,
		&plan.TotalAuthorizationAmount, &plan.Active, &plan.CreatedAt, &plan.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return plan, nil
}

func (r *PlanRepository) ListActive() ([]*domain.Plan, error) {
	query := `
		SELECT plan_id, name, description, period_seconds, amount_usdc_base_units,
			amount_usdc_display, authorization_periods, total_authorization_amount,
			active, created_at, updated_at
		FROM plans WHERE active = true
	`
	rows, err := r.store.DB.Query(query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var plans []*domain.Plan
	for rows.Next() {
		plan := &domain.Plan{}
		err := rows.Scan(
			&plan.PlanID, &plan.Name, &plan.Description, &plan.PeriodSeconds,
			&plan.AmountUSDCBaseUnits, &plan.AmountUSDCDisplay, &plan.AuthorizationPeriods,
			&plan.TotalAuthorizationAmount, &plan.Active, &plan.CreatedAt, &plan.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		plans = append(plans, plan)
	}
	return plans, rows.Err()
}

func (r *PlanRepository) ListAll(ctx context.Context) ([]*domain.Plan, error) {
	query := `
		SELECT plan_id, name, description, period_seconds, amount_usdc_base_units,
			amount_usdc_display, authorization_periods, total_authorization_amount,
			active, created_at, updated_at
		FROM plans
		ORDER BY created_at DESC
	`
	rows, err := r.store.DB.QueryContext(ctx, query)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var plans []*domain.Plan
	for rows.Next() {
		plan := &domain.Plan{}
		err := rows.Scan(
			&plan.PlanID, &plan.Name, &plan.Description, &plan.PeriodSeconds,
			&plan.AmountUSDCBaseUnits, &plan.AmountUSDCDisplay, &plan.AuthorizationPeriods,
			&plan.TotalAuthorizationAmount, &plan.Active, &plan.CreatedAt, &plan.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		plans = append(plans, plan)
	}
	return plans, rows.Err()
}
