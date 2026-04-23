package domain

type SubscriptionStatus string

type SubscriptionSource string

const (
	SubscriptionPending   SubscriptionStatus = "pending"
	SubscriptionActive    SubscriptionStatus = "active"
	SubscriptionExpired   SubscriptionStatus = "expired"
	SubscriptionCancelled SubscriptionStatus = "cancelled"
)

const (
	SubscriptionSourceFirstSubscribe SubscriptionSource = "first_subscribe"
	SubscriptionSourceRenewal        SubscriptionSource = "renewal"
	SubscriptionSourceUpgrade        SubscriptionSource = "upgrade"
	SubscriptionSourceDowngrade      SubscriptionSource = "downgrade"
)

type Subscription struct {
	ID                 string
	IdentityAddress    string
	PayerAddress       string
	PlanID             string
	Status             SubscriptionStatus
	AutoRenew          bool
	CurrentPeriodStart int64
	CurrentPeriodEnd   int64
	NextPlanID         string
	LastChargeID       string
	LastChargeAt       int64
	Source             SubscriptionSource
	CreatedAt          int64
	UpdatedAt          int64
}
