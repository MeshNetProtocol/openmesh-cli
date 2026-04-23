package postgres

import (
	"context"
	"database/sql"
	"market-blockchain/internal/domain"
)

type ChargeRepository struct {
	store *Store
}

func NewChargeRepository(store *Store) *ChargeRepository {
	return &ChargeRepository{store: store}
}

func (r *ChargeRepository) Create(charge *domain.Charge) error {
	query := `
		INSERT INTO charges (
			id, charge_id, subscription_id, authorization_id, identity_address, payer_address, plan_id,
			amount, status, tx_hash, reason, created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
	`
	_, err := r.store.DB.Exec(query,
		charge.ID, charge.ChargeID, charge.SubscriptionID, charge.AuthorizationID,
		charge.IdentityAddress, charge.PayerAddress, charge.PlanID, charge.Amount,
		charge.Status, charge.TxHash, charge.Reason, charge.CreatedAt, charge.UpdatedAt,
	)
	return err
}

func (r *ChargeRepository) Update(charge *domain.Charge) error {
	query := `
		UPDATE charges SET
			status = $2, tx_hash = $3, updated_at = $4
		WHERE id = $1
	`
	_, err := r.store.DB.Exec(query,
		charge.ID, charge.Status, charge.TxHash, charge.UpdatedAt,
	)
	return err
}

func (r *ChargeRepository) GetByChargeID(chargeID string) (*domain.Charge, error) {
	query := `
		SELECT id, charge_id, subscription_id, authorization_id, identity_address, payer_address, plan_id,
			amount, status, tx_hash, reason, created_at, updated_at
		FROM charges WHERE charge_id = $1
	`
	charge := &domain.Charge{}
	err := r.store.DB.QueryRow(query, chargeID).Scan(
		&charge.ID, &charge.ChargeID, &charge.SubscriptionID, &charge.AuthorizationID,
		&charge.IdentityAddress, &charge.PayerAddress, &charge.PlanID, &charge.Amount,
		&charge.Status, &charge.TxHash, &charge.Reason, &charge.CreatedAt, &charge.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return charge, nil
}

func (r *ChargeRepository) ListByIdentity(identityAddress string) ([]*domain.Charge, error) {
	query := `
		SELECT id, charge_id, subscription_id, authorization_id, identity_address, payer_address, plan_id,
			amount, status, tx_hash, reason, created_at, updated_at
		FROM charges WHERE identity_address = $1
		ORDER BY created_at DESC
	`
	rows, err := r.store.DB.Query(query, identityAddress)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var charges []*domain.Charge
	for rows.Next() {
		charge := &domain.Charge{}
		err := rows.Scan(
			&charge.ID, &charge.ChargeID, &charge.SubscriptionID, &charge.AuthorizationID,
			&charge.IdentityAddress, &charge.PayerAddress, &charge.PlanID, &charge.Amount,
			&charge.Status, &charge.TxHash, &charge.Reason, &charge.CreatedAt, &charge.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		charges = append(charges, charge)
	}
	return charges, rows.Err()
}

func (r *ChargeRepository) ListByStatusAndDateRange(ctx context.Context, status string, fromTime, toTime int64) ([]*domain.Charge, error) {
	query := `
		SELECT id, charge_id, subscription_id, authorization_id, identity_address, payer_address, plan_id,
			amount, status, tx_hash, reason, created_at, updated_at
		FROM charges
		WHERE status = $1 AND created_at >= $2 AND created_at <= $3
		ORDER BY created_at DESC
	`
	rows, err := r.store.DB.QueryContext(ctx, query, status, fromTime, toTime)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var charges []*domain.Charge
	for rows.Next() {
		charge := &domain.Charge{}
		err := rows.Scan(
			&charge.ID, &charge.ChargeID, &charge.SubscriptionID, &charge.AuthorizationID,
			&charge.IdentityAddress, &charge.PayerAddress, &charge.PlanID, &charge.Amount,
			&charge.Status, &charge.TxHash, &charge.Reason, &charge.CreatedAt, &charge.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		charges = append(charges, charge)
	}
	return charges, rows.Err()
}

func (r *ChargeRepository) ListByDateRange(ctx context.Context, fromTime, toTime int64) ([]*domain.Charge, error) {
	query := `
		SELECT id, charge_id, subscription_id, authorization_id, identity_address, payer_address, plan_id,
			amount, status, tx_hash, reason, created_at, updated_at
		FROM charges
		WHERE created_at >= $1 AND created_at <= $2
		ORDER BY created_at DESC
	`
	rows, err := r.store.DB.QueryContext(ctx, query, fromTime, toTime)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var charges []*domain.Charge
	for rows.Next() {
		charge := &domain.Charge{}
		err := rows.Scan(
			&charge.ID, &charge.ChargeID, &charge.SubscriptionID, &charge.AuthorizationID,
			&charge.IdentityAddress, &charge.PayerAddress, &charge.PlanID, &charge.Amount,
			&charge.Status, &charge.TxHash, &charge.Reason, &charge.CreatedAt, &charge.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		charges = append(charges, charge)
	}
	return charges, rows.Err()
}

func (r *ChargeRepository) ListBySubscription(ctx context.Context, subscriptionID string) ([]*domain.Charge, error) {
	query := `
		SELECT id, charge_id, subscription_id, authorization_id, identity_address, payer_address, plan_id,
			amount, status, tx_hash, reason, created_at, updated_at
		FROM charges
		WHERE subscription_id = $1
		ORDER BY created_at DESC
	`
	rows, err := r.store.DB.QueryContext(ctx, query, subscriptionID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var charges []*domain.Charge
	for rows.Next() {
		charge := &domain.Charge{}
		err := rows.Scan(
			&charge.ID, &charge.ChargeID, &charge.SubscriptionID, &charge.AuthorizationID,
			&charge.IdentityAddress, &charge.PayerAddress, &charge.PlanID, &charge.Amount,
			&charge.Status, &charge.TxHash, &charge.Reason, &charge.CreatedAt, &charge.UpdatedAt,
		)
		if err != nil {
			return nil, err
		}
		charges = append(charges, charge)
	}
	return charges, rows.Err()
}

func (r *ChargeRepository) SumCompletedCharges(ctx context.Context, fromTime, toTime int64) (int64, error) {
	query := `
		SELECT COALESCE(SUM(amount), 0)
		FROM charges
		WHERE status = 'completed' AND created_at >= $1 AND created_at <= $2
	`
	var sum int64
	err := r.store.DB.QueryRowContext(ctx, query, fromTime, toTime).Scan(&sum)
	return sum, err
}

func (r *ChargeRepository) CountAndSumByStatus(ctx context.Context, status string) (int, int64, error) {
	query := `
		SELECT COUNT(*), COALESCE(SUM(amount), 0)
		FROM charges
		WHERE status = $1
	`
	var count int
	var sum int64
	err := r.store.DB.QueryRowContext(ctx, query, status).Scan(&count, &sum)
	return count, sum, err
}
