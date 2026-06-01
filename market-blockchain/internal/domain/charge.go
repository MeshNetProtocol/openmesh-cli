package domain

type ChargeStatus string

const (
	ChargePending   ChargeStatus = "pending"
	ChargeCompleted ChargeStatus = "completed"
	ChargeFailed    ChargeStatus = "failed"
)

type Charge struct {
	ID              string
	ChargeID        string
	SubscriptionID  string
	AuthorizationID string
	IdentityAddress string
	PayerAddress    string
	PlanID          string
	Amount          int64
	Status          ChargeStatus
	TxHash          string
	Reason          string
	CreatedAt       int64
	UpdatedAt       int64
}
