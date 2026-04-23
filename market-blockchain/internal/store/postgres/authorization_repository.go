package postgres

import (
	"database/sql"
	"market-blockchain/internal/domain"
)

type AuthorizationRepository struct {
	store *Store
}

func NewAuthorizationRepository(store *Store) *AuthorizationRepository {
	return &AuthorizationRepository{store: store}
}

func (r *AuthorizationRepository) Create(auth *domain.Authorization) error {
	query := `
		INSERT INTO authorizations (
			id, identity_address, payer_address, plan_id, expected_allowance,
			target_allowance, authorized_allowance, remaining_allowance,
			permit_status, permit_tx_hash, permit_deadline, authorization_periods,
			created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
	`
	_, err := r.store.DB.Exec(query,
		auth.ID, auth.IdentityAddress, auth.PayerAddress, auth.PlanID,
		auth.ExpectedAllowance, auth.TargetAllowance, auth.AuthorizedAllowance,
		auth.RemainingAllowance, auth.PermitStatus, auth.PermitTxHash,
		auth.PermitDeadline, auth.AuthorizationPeriods, auth.CreatedAt, auth.UpdatedAt,
	)
	return err
}

func (r *AuthorizationRepository) Update(auth *domain.Authorization) error {
	query := `
		UPDATE authorizations SET
			payer_address = $2, expected_allowance = $3, target_allowance = $4,
			authorized_allowance = $5, remaining_allowance = $6, permit_status = $7,
			permit_tx_hash = $8, permit_deadline = $9, authorization_periods = $10,
			updated_at = $11
		WHERE id = $1
	`
	_, err := r.store.DB.Exec(query,
		auth.ID, auth.PayerAddress, auth.ExpectedAllowance, auth.TargetAllowance,
		auth.AuthorizedAllowance, auth.RemainingAllowance, auth.PermitStatus,
		auth.PermitTxHash, auth.PermitDeadline, auth.AuthorizationPeriods, auth.UpdatedAt,
	)
	return err
}

func (r *AuthorizationRepository) GetByIdentityAndPlan(identityAddress, planID string) (*domain.Authorization, error) {
	query := `
		SELECT id, identity_address, payer_address, plan_id, expected_allowance,
			target_allowance, authorized_allowance, remaining_allowance,
			permit_status, permit_tx_hash, permit_deadline, authorization_periods,
			created_at, updated_at
		FROM authorizations
		WHERE identity_address = $1 AND plan_id = $2
	`
	auth := &domain.Authorization{}
	err := r.store.DB.QueryRow(query, identityAddress, planID).Scan(
		&auth.ID, &auth.IdentityAddress, &auth.PayerAddress, &auth.PlanID,
		&auth.ExpectedAllowance, &auth.TargetAllowance, &auth.AuthorizedAllowance,
		&auth.RemainingAllowance, &auth.PermitStatus, &auth.PermitTxHash,
		&auth.PermitDeadline, &auth.AuthorizationPeriods, &auth.CreatedAt, &auth.UpdatedAt,
	)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return auth, nil
}
