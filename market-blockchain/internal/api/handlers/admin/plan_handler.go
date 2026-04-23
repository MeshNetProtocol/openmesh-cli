package admin

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"market-blockchain/internal/domain"
	"market-blockchain/internal/repository"
)

type AdminPlanHandler struct {
	planRepo         repository.PlanRepository
	subscriptionRepo repository.SubscriptionRepository
}

func NewAdminPlanHandler(
	planRepo repository.PlanRepository,
	subscriptionRepo repository.SubscriptionRepository,
) *AdminPlanHandler {
	return &AdminPlanHandler{
		planRepo:         planRepo,
		subscriptionRepo: subscriptionRepo,
	}
}

type PlanWithStats struct {
	domain.Plan
	ActiveSubscribers int `json:"active_subscribers"`
}

func (h *AdminPlanHandler) ListPlans(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	plans, err := h.planRepo.ListAll(ctx)
	if err != nil {
		http.Error(w, "failed to list plans", http.StatusInternalServerError)
		return
	}

	plansWithStats := make([]PlanWithStats, 0, len(plans))
	for _, plan := range plans {
		count, _ := h.subscriptionRepo.CountByPlanAndStatus(ctx, plan.PlanID, "active")
		plansWithStats = append(plansWithStats, PlanWithStats{
			Plan:              *plan,
			ActiveSubscribers: count,
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"plans": plansWithStats,
	})
}

type CreatePlanRequest struct {
	PlanID               string `json:"plan_id"`
	Name                 string `json:"name"`
	Description          string `json:"description"`
	PeriodSeconds        int64  `json:"period_seconds"`
	AmountUSDCBaseUnits  int64  `json:"amount_usdc_base_units"`
	AuthorizationPeriods int32  `json:"authorization_periods"`
	Active               bool   `json:"active"`
}

func (h *AdminPlanHandler) CreatePlan(w http.ResponseWriter, r *http.Request) {
	var req CreatePlanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	if req.PlanID == "" || req.Name == "" || req.PeriodSeconds <= 0 || req.AmountUSDCBaseUnits <= 0 || req.AuthorizationPeriods < 1 {
		http.Error(w, "invalid plan parameters", http.StatusBadRequest)
		return
	}

	now := time.Now().UnixMilli()
	plan := &domain.Plan{
		PlanID:                   req.PlanID,
		Name:                     req.Name,
		Description:              req.Description,
		PeriodSeconds:            req.PeriodSeconds,
		AmountUSDCBaseUnits:      req.AmountUSDCBaseUnits,
		AmountUSDCDisplay:        formatUSDC(req.AmountUSDCBaseUnits),
		AuthorizationPeriods:     req.AuthorizationPeriods,
		TotalAuthorizationAmount: req.AmountUSDCBaseUnits * int64(req.AuthorizationPeriods),
		Active:                   req.Active,
		CreatedAt:                now,
		UpdatedAt:                now,
	}

	if err := h.planRepo.Create(plan); err != nil {
		http.Error(w, "failed to create plan", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]interface{}{
		"plan": plan,
	})
}

type UpdatePlanRequest struct {
	Name   string `json:"name"`
	Active *bool  `json:"active"`
}

func (h *AdminPlanHandler) UpdatePlan(w http.ResponseWriter, r *http.Request) {
	planID := r.PathValue("id")

	var req UpdatePlanRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, "invalid request body", http.StatusBadRequest)
		return
	}

	plan, err := h.planRepo.GetByPlanID(planID)
	if err != nil {
		http.Error(w, "plan not found", http.StatusNotFound)
		return
	}

	if req.Name != "" {
		plan.Name = req.Name
	}
	if req.Active != nil {
		plan.Active = *req.Active
	}
	plan.UpdatedAt = time.Now().UnixMilli()

	if err := h.planRepo.Update(plan); err != nil {
		http.Error(w, "failed to update plan", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"plan": plan,
	})
}

func formatUSDC(baseUnits int64) string {
	dollars := float64(baseUnits) / 1000000
	return fmt.Sprintf("%.2f USDC", dollars)
}
