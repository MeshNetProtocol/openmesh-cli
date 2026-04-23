package postgres

import (
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
