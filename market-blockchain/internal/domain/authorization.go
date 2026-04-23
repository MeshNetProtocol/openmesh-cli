package domain

type AuthorizationStatus string

const (
	AuthorizationPending   AuthorizationStatus = "pending"
	AuthorizationCompleted AuthorizationStatus = "completed"
	AuthorizationFailed    AuthorizationStatus = "failed"
)

type Authorization struct {
	ID                   string
	IdentityAddress      string
	PayerAddress         string
	PlanID               string
	ExpectedAllowance    int64
	TargetAllowance      int64
	AuthorizedAllowance  int64
	RemainingAllowance   int64
	PermitStatus         AuthorizationStatus
	PermitTxHash         string
	PermitDeadline       int64
	AuthorizationPeriods int32
	CreatedAt            int64
	UpdatedAt            int64
}
