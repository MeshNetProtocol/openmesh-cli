package postgres

import (
	"database/sql"
	"market-blockchain/internal/domain"
)

type Store struct {
	DB *sql.DB
}

func New(db *sql.DB) *Store {
	return &Store{DB: db}
}

func (s *Store) CreateInitialState(subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, event *domain.Event) error {
	tx, err := s.DB.Begin()
	if err != nil {
		return err
	}

	defer func() {
		if err != nil {
			_ = tx.Rollback()
		}
	}()

	if _, err = tx.Exec(`
		INSERT INTO subscriptions (
			id, identity_address, payer_address, plan_id, status, auto_renew,
			current_period_start, current_period_end, next_plan_id, pending_plan_id,
			current_authorization_id, last_charge_id, last_charge_at, source,
			uplink, downlink, total_traffic, created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
	`,
		subscription.ID, subscription.IdentityAddress, subscription.PayerAddress, subscription.PlanID, subscription.Status,
		subscription.AutoRenew, subscription.CurrentPeriodStart, subscription.CurrentPeriodEnd, subscription.NextPlanID,
		subscription.PendingPlanID, subscription.CurrentAuthorizationID, subscription.LastChargeID, subscription.LastChargeAt,
		subscription.Source, subscription.Uplink, subscription.Downlink, subscription.TotalTraffic, subscription.CreatedAt, subscription.UpdatedAt,
	); err != nil {
		return err
	}

	if _, err = tx.Exec(`
		INSERT INTO authorizations (
			id, identity_address, payer_address, plan_id, expected_allowance,
			target_allowance, authorized_allowance, remaining_allowance,
			permit_status, permit_tx_hash, permit_deadline, authorization_periods,
			created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
	`,
		authorization.ID, authorization.IdentityAddress, authorization.PayerAddress, authorization.PlanID,
		authorization.ExpectedAllowance, authorization.TargetAllowance, authorization.AuthorizedAllowance,
		authorization.RemainingAllowance, authorization.PermitStatus, authorization.PermitTxHash,
		authorization.PermitDeadline, authorization.AuthorizationPeriods, authorization.CreatedAt, authorization.UpdatedAt,
	); err != nil {
		return err
	}

	if _, err = tx.Exec(`
		INSERT INTO charges (
			id, charge_id, subscription_id, authorization_id, identity_address, payer_address, plan_id,
			amount, status, tx_hash, reason, created_at, updated_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13)
	`,
		charge.ID, charge.ChargeID, charge.SubscriptionID, charge.AuthorizationID,
		charge.IdentityAddress, charge.PayerAddress, charge.PlanID, charge.Amount,
		charge.Status, charge.TxHash, charge.Reason, charge.CreatedAt, charge.UpdatedAt,
	); err != nil {
		return err
	}

	if _, err = tx.Exec(`
		INSERT INTO events (
			id, identity_address, payer_address, plan_id, charge_id,
			type, description, metadata, created_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`,
		event.ID, event.IdentityAddress, event.PayerAddress, event.PlanID,
		event.ChargeID, event.Type, event.Description, event.Metadata, event.CreatedAt,
	); err != nil {
		return err
	}

	if err = tx.Commit(); err != nil {
		return err
	}

	return nil
}
