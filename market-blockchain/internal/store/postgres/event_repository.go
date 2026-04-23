package postgres

import (
	"context"
	"database/sql"
	"market-blockchain/internal/domain"
)

type EventRepository struct {
	store *Store
}

func NewEventRepository(store *Store) *EventRepository {
	return &EventRepository{store: store}
}

func (r *EventRepository) Create(event *domain.Event) error {
	query := `
		INSERT INTO events (
			id, identity_address, payer_address, plan_id, charge_id,
			type, description, metadata, created_at
		) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
	`
	_, err := r.store.DB.Exec(query,
		event.ID, event.IdentityAddress, event.PayerAddress, event.PlanID,
		event.ChargeID, event.Type, event.Description, event.Metadata, event.CreatedAt,
	)
	return err
}

func (r *EventRepository) ListByIdentity(identityAddress string) ([]*domain.Event, error) {
	query := `
		SELECT id, identity_address, payer_address, plan_id, charge_id,
			type, description, metadata, created_at
		FROM events WHERE identity_address = $1
		ORDER BY created_at DESC
	`
	rows, err := r.store.DB.Query(query, identityAddress)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []*domain.Event
	for rows.Next() {
		event := &domain.Event{}
		err := rows.Scan(
			&event.ID, &event.IdentityAddress, &event.PayerAddress, &event.PlanID,
			&event.ChargeID, &event.Type, &event.Description, &event.Metadata, &event.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		events = append(events, event)
	}
	return events, rows.Err()
}

func (r *EventRepository) ListByTypeAndDateRange(ctx context.Context, eventType string, fromTime, toTime int64) ([]*domain.Event, error) {
	query := `
		SELECT id, identity_address, payer_address, plan_id, charge_id,
			type, description, metadata, created_at
		FROM events
		WHERE type = $1 AND created_at >= $2 AND created_at <= $3
		ORDER BY created_at DESC
	`
	rows, err := r.store.DB.QueryContext(ctx, query, eventType, fromTime, toTime)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []*domain.Event
	for rows.Next() {
		event := &domain.Event{}
		err := rows.Scan(
			&event.ID, &event.IdentityAddress, &event.PayerAddress, &event.PlanID,
			&event.ChargeID, &event.Type, &event.Description, &event.Metadata, &event.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		events = append(events, event)
	}
	return events, rows.Err()
}

func (r *EventRepository) ListByDateRange(ctx context.Context, fromTime, toTime int64) ([]*domain.Event, error) {
	query := `
		SELECT id, identity_address, payer_address, plan_id, charge_id,
			type, description, metadata, created_at
		FROM events
		WHERE created_at >= $1 AND created_at <= $2
		ORDER BY created_at DESC
	`
	rows, err := r.store.DB.QueryContext(ctx, query, fromTime, toTime)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []*domain.Event
	for rows.Next() {
		event := &domain.Event{}
		err := rows.Scan(
			&event.ID, &event.IdentityAddress, &event.PayerAddress, &event.PlanID,
			&event.ChargeID, &event.Type, &event.Description, &event.Metadata, &event.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		events = append(events, event)
	}
	return events, rows.Err()
}

func (r *EventRepository) ListBySubscription(ctx context.Context, subscriptionID string, limit int) ([]*domain.Event, error) {
	query := `
		SELECT id, identity_address, payer_address, plan_id, charge_id,
			type, description, metadata, created_at
		FROM events
		WHERE metadata LIKE $1
		ORDER BY created_at DESC
		LIMIT $2
	`
	searchPattern := "%\"subscription_id\":\"" + subscriptionID + "\"%"
	rows, err := r.store.DB.QueryContext(ctx, query, searchPattern, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []*domain.Event
	for rows.Next() {
		event := &domain.Event{}
		err := rows.Scan(
			&event.ID, &event.IdentityAddress, &event.PayerAddress, &event.PlanID,
			&event.ChargeID, &event.Type, &event.Description, &event.Metadata, &event.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		events = append(events, event)
	}
	return events, rows.Err()
}

func (r *EventRepository) ListRecent(ctx context.Context, limit int) ([]*domain.Event, error) {
	query := `
		SELECT id, identity_address, payer_address, plan_id, charge_id,
			type, description, metadata, created_at
		FROM events
		ORDER BY created_at DESC
		LIMIT $1
	`
	rows, err := r.store.DB.QueryContext(ctx, query, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var events []*domain.Event
	for rows.Next() {
		event := &domain.Event{}
		err := rows.Scan(
			&event.ID, &event.IdentityAddress, &event.PayerAddress, &event.PlanID,
			&event.ChargeID, &event.Type, &event.Description, &event.Metadata, &event.CreatedAt,
		)
		if err != nil {
			return nil, err
		}
		events = append(events, event)
	}
	return events, rows.Err()
}

func (r *EventRepository) GetByID(ctx context.Context, id string) (*domain.Event, error) {
	query := `
		SELECT id, identity_address, payer_address, plan_id, charge_id,
			type, description, metadata, created_at
		FROM events WHERE id = $1
	`
	event := &domain.Event{}
	err := r.store.DB.QueryRowContext(ctx, query, id).Scan(
		&event.ID, &event.IdentityAddress, &event.PayerAddress, &event.PlanID,
		&event.ChargeID, &event.Type, &event.Description, &event.Metadata, &event.CreatedAt,
	)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return event, nil
}
