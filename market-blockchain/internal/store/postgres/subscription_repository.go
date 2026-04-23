package postgres

import (
	"database/sql"
	"market-blockchain/internal/domain"
)

type SubscriptionRepository struct {
	store *Store
}

func NewSubscriptionRepository(store *Store) *SubscriptionRepository {
	return &SubscriptionRepository{store: store}
}

func (r *SubscriptionRepository) Create(sub *domain.Subscription) error {
	query := `
		INSERT INTO subscriptions (
			id, identity_address, payer_address, plan_id, status, auto_renew,
			current_period_start, current_period_end, next_plan_id, pending_plan_id,
			current_authorization_id, last_charge_id, last_charge_at, source, created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16)
	`
	_, err := r.store.DB.Exec(query,
		sub.ID, sub.IdentityAddress, sub.PayerAddress, sub.PlanID, sub.Status,
		sub.AutoRenew, sub.CurrentPeriodStart, sub.CurrentPeriodEnd, sub.NextPlanID,
		sub.PendingPlanID, sub.CurrentAuthorizationID, sub.LastChargeID, sub.LastChargeAt,
		sub.Source, sub.CreatedAt, sub.UpdatedAt,
	)
	return err
}

func (r *SubscriptionRepository) Update(sub *domain.Subscription) error {
	query := `
		UPDATE subscriptions SET
			payer_address = $2, plan_id = $3, status = $4, auto_renew = $5,
			current_period_start = $6, current_period_end = $7, next_plan_id = $8,
			pending_plan_id = $9, current_authorization_id = $10, last_charge_id = $11,
			last_charge_at = $12, source = $13, updated_at = $14
		WHERE id = $1
	`
	_, err := r.store.DB.Exec(query,
		sub.ID, sub.PayerAddress, sub.PlanID, sub.Status, sub.AutoRenew,
		sub.CurrentPeriodStart, sub.CurrentPeriodEnd, sub.NextPlanID,
		sub.PendingPlanID, sub.CurrentAuthorizationID, sub.LastChargeID,
		sub.LastChargeAt, sub.Source, sub.UpdatedAt,
	)
	return err
}

func (r *SubscriptionRepository) GetByID(id string) (*domain.Subscription, error) {
	query := `
		SELECT id, identity_address, payer_address, plan_id, status, auto_renew,
			current_period_start, current_period_end, next_plan_id, pending_plan_id,
			current_authorization_id, last_charge_id, last_charge_at, source, created_at, updated_at
		FROM subscriptions WHERE id = $1
	`
	sub := &domain.Subscription{}
	err := r.store.DB.QueryRow(query, id).Scan(
		&sub.ID, &sub.IdentityAddress, &sub.PayerAddress, &sub.PlanID, &sub.Status,
		&sub.AutoRenew, &sub.CurrentPeriodStart, &sub.CurrentPeriodEnd, &sub.NextPlanID,
		&sub.PendingPlanID, &sub.CurrentAuthorizationID, &sub.LastChargeID, &sub.LastChargeAt,
		&sub.Source, &sub.CreatedAt, &sub.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return sub, nil
}

func (r *SubscriptionRepository) GetByIdentityAndPlan(identityAddress, planID string) (*domain.Subscription, error) {
	query := `
		SELECT id, identity_address, payer_address, plan_id, status, auto_renew,
			current_period_start, current_period_end, next_plan_id, pending_plan_id,
			current_authorization_id, last_charge_id, last_charge_at, source, created_at, updated_at
		FROM subscriptions
		WHERE identity_address = $1 AND plan_id = $2
		AND status IN ('pending', 'active')
	`
	sub := &domain.Subscription{}
	err := r.store.DB.QueryRow(query, identityAddress, planID).Scan(
		&sub.ID, &sub.IdentityAddress, &sub.PayerAddress, &sub.PlanID, &sub.Status,
		&sub.AutoRenew, &sub.CurrentPeriodStart, &sub.CurrentPeriodEnd, &sub.NextPlanID,
		&sub.PendingPlanID, &sub.CurrentAuthorizationID, &sub.LastChargeID, &sub.LastChargeAt,
		&sub.Source, &sub.CreatedAt, &sub.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return sub, nil
}

func (r *SubscriptionRepository) ListRenewable(now int64) ([]*domain.Subscription, error) {
	query := `
		SELECT id, identity_address, payer_address, plan_id, status, auto_renew,
			current_period_start, current_period_end, next_plan_id, pending_plan_id,
			current_authorization_id, last_charge_id, last_charge_at, source, created_at, updated_at
		FROM subscriptions
		WHERE status = 'active' AND auto_renew = true AND current_period_end <= $1
	`
	rows, err := r.store.DB.Query(query, now)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var subs []*domain.Subscription
	for rows.Next() {
		sub := &domain.Subscription{}
		err := rows.Scan(
			&sub.ID, &sub.IdentityAddress, &sub.PayerAddress, &sub.PlanID, &sub.Status,
			&sub.AutoRenew, &sub.CurrentPeriodStart, &sub.CurrentPeriodEnd, &sub.NextPlanID,
			&sub.PendingPlanID, &sub.CurrentAuthorizationID, &sub.LastChargeID, &sub.LastChargeAt,
			&sub.Source, &sub.CreatedAt, &sub.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		subs = append(subs, sub)
	}
	return subs, rows.Err()
}
