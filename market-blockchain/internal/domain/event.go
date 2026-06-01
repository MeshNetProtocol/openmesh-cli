package domain

type EventType string

const (
	EventFirstSubscribe EventType = "first_subscribe"
	EventChargeSuccess  EventType = "charge_success"
	EventChargeFailed   EventType = "charge_failed"
	EventExpired        EventType = "expired"
	EventReauthorize    EventType = "reauthorize"
	EventCancel         EventType = "cancel"
	EventUpgrade        EventType = "upgrade"
	EventDowngrade      EventType = "downgrade"
	EventRenew          EventType = "renew"
)

type Event struct {
	ID              string
	IdentityAddress string
	PayerAddress    string
	PlanID          string
	ChargeID        string
	Type            EventType
	Description     string
	Metadata        string
	CreatedAt       int64
}
