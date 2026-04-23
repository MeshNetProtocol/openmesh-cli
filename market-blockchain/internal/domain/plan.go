package domain

type Plan struct {
	PlanID                   string
	Name                     string
	Description              string
	PeriodSeconds            int64
	AmountUSDCBaseUnits      int64
	AmountUSDCDisplay        string
	AuthorizationPeriods     int32
	TotalAuthorizationAmount int64
	Active                   bool
	CreatedAt                int64
	UpdatedAt                int64
}
