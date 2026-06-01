package handlers

import (
	"encoding/json"
	"net/http"

	"market-blockchain/internal/domain"
)

// Shared response types
type PlanResponse struct {
	PlanID                   string `json:"plan_id"`
	Name                     string `json:"name"`
	Description              string `json:"description"`
	PeriodSeconds            int64  `json:"period_seconds"`
	AmountUSDCBaseUnits      int64  `json:"amount_usdc_base_units"`
	AmountUSDCDisplay        string `json:"amount_usdc_display"`
	AuthorizationPeriods     int32  `json:"authorization_periods"`
	TotalAuthorizationAmount int64  `json:"total_authorization_amount"`
	Active                   bool   `json:"active"`
}

type SubscriptionResponse struct {
	ID                 string `json:"id"`
	IdentityAddress    string `json:"identity_address"`
	PayerAddress       string `json:"payer_address"`
	PlanID             string `json:"plan_id"`
	Status             string `json:"status"`
	AutoRenew          bool   `json:"auto_renew"`
	CurrentPeriodStart int64  `json:"current_period_start"`
	CurrentPeriodEnd   int64  `json:"current_period_end"`
	NextPlanID         string `json:"next_plan_id,omitempty"`
	LastChargeID       string `json:"last_charge_id"`
	LastChargeAt       int64  `json:"last_charge_at"`
	Source             string `json:"source"`
}

type AuthorizationResponse struct {
	ID                   string `json:"id"`
	IdentityAddress      string `json:"identity_address"`
	PayerAddress         string `json:"payer_address"`
	PlanID               string `json:"plan_id"`
	ExpectedAllowance    int64  `json:"expected_allowance"`
	TargetAllowance      int64  `json:"target_allowance"`
	AuthorizedAllowance  int64  `json:"authorized_allowance"`
	RemainingAllowance   int64  `json:"remaining_allowance"`
	PermitStatus         string `json:"permit_status"`
	PermitTxHash         string `json:"permit_tx_hash,omitempty"`
	PermitDeadline       int64  `json:"permit_deadline"`
	AuthorizationPeriods int32  `json:"authorization_periods"`
}

type ChargeResponse struct {
	ID              string `json:"id"`
	ChargeID        string `json:"charge_id"`
	IdentityAddress string `json:"identity_address"`
	PayerAddress    string `json:"payer_address"`
	PlanID          string `json:"plan_id"`
	Amount          int64  `json:"amount"`
	Status          string `json:"status"`
	TxHash          string `json:"tx_hash,omitempty"`
	Reason          string `json:"reason"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}

// Shared mapper functions
func mapPlanToResponse(plan *domain.Plan) PlanResponse {
	return PlanResponse{
		PlanID:                   plan.PlanID,
		Name:                     plan.Name,
		Description:              plan.Description,
		PeriodSeconds:            plan.PeriodSeconds,
		AmountUSDCBaseUnits:      plan.AmountUSDCBaseUnits,
		AmountUSDCDisplay:        plan.AmountUSDCDisplay,
		AuthorizationPeriods:     plan.AuthorizationPeriods,
		TotalAuthorizationAmount: plan.TotalAuthorizationAmount,
		Active:                   plan.Active,
	}
}

func mapSubscriptionToResponse(sub *domain.Subscription) SubscriptionResponse {
	return SubscriptionResponse{
		ID:                 sub.ID,
		IdentityAddress:    sub.IdentityAddress,
		PayerAddress:       sub.PayerAddress,
		PlanID:             sub.PlanID,
		Status:             string(sub.Status),
		AutoRenew:          sub.AutoRenew,
		CurrentPeriodStart: sub.CurrentPeriodStart,
		CurrentPeriodEnd:   sub.CurrentPeriodEnd,
		NextPlanID:         sub.NextPlanID,
		LastChargeID:       sub.LastChargeID,
		LastChargeAt:       sub.LastChargeAt,
		Source:             string(sub.Source),
	}
}

func mapAuthorizationToResponse(auth *domain.Authorization) AuthorizationResponse {
	return AuthorizationResponse{
		ID:                   auth.ID,
		IdentityAddress:      auth.IdentityAddress,
		PayerAddress:         auth.PayerAddress,
		PlanID:               auth.PlanID,
		ExpectedAllowance:    auth.ExpectedAllowance,
		TargetAllowance:      auth.TargetAllowance,
		AuthorizedAllowance:  auth.AuthorizedAllowance,
		RemainingAllowance:   auth.RemainingAllowance,
		PermitStatus:         string(auth.PermitStatus),
		PermitTxHash:         auth.PermitTxHash,
		PermitDeadline:       auth.PermitDeadline,
		AuthorizationPeriods: auth.AuthorizationPeriods,
	}
}

func mapChargeToResponse(charge *domain.Charge) ChargeResponse {
	return ChargeResponse{
		ID:              charge.ID,
		ChargeID:        charge.ChargeID,
		IdentityAddress: charge.IdentityAddress,
		PayerAddress:    charge.PayerAddress,
		PlanID:          charge.PlanID,
		Amount:          charge.Amount,
		Status:          string(charge.Status),
		TxHash:          charge.TxHash,
		Reason:          charge.Reason,
	}
}

// Shared response helpers
func respondJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

func respondError(w http.ResponseWriter, status int, message string) {
	respondJSON(w, status, ErrorResponse{Error: message})
}
