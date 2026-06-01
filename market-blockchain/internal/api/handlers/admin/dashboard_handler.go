package admin

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"market-blockchain/internal/repository"
)

type DashboardHandler struct {
	subscriptionRepo repository.SubscriptionRepository
	chargeRepo       repository.ChargeRepository
	eventRepo        repository.EventRepository
}

func NewDashboardHandler(
	subscriptionRepo repository.SubscriptionRepository,
	chargeRepo repository.ChargeRepository,
	eventRepo repository.EventRepository,
) *DashboardHandler {
	return &DashboardHandler{
		subscriptionRepo: subscriptionRepo,
		chargeRepo:       chargeRepo,
		eventRepo:        eventRepo,
	}
}

type MetricsResponse struct {
	ActiveSubscriptions  int     `json:"active_subscriptions"`
	Revenue30d           float64 `json:"revenue_30d"`
	PendingChargesCount  int     `json:"pending_charges_count"`
	PendingChargesAmount float64 `json:"pending_charges_amount"`
	FailedChargesCount   int     `json:"failed_charges_count"`
	FailedChargesAmount  float64 `json:"failed_charges_amount"`
}

func (h *DashboardHandler) GetMetrics(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	activeCount, _ := h.subscriptionRepo.CountByStatus(ctx, "active")

	now := time.Now().UnixMilli()
	thirtyDaysAgo := now - (30 * 24 * 60 * 60 * 1000)
	revenue30d, _ := h.chargeRepo.SumCompletedCharges(ctx, thirtyDaysAgo, now)

	pendingCount, pendingAmount, _ := h.chargeRepo.CountAndSumByStatus(ctx, "pending")
	failedCount, failedAmount, _ := h.chargeRepo.CountAndSumByStatus(ctx, "failed")

	response := MetricsResponse{
		ActiveSubscriptions:  activeCount,
		Revenue30d:           float64(revenue30d) / 1000000,
		PendingChargesCount:  pendingCount,
		PendingChargesAmount: float64(pendingAmount) / 1000000,
		FailedChargesCount:   failedCount,
		FailedChargesAmount:  float64(failedAmount) / 1000000,
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)
}

func (h *DashboardHandler) GetRevenueTrend(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{"data": []interface{}{}})
}

func (h *DashboardHandler) GetSubscriptionDistribution(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	activeCount, _ := h.subscriptionRepo.CountByStatus(ctx, "active")
	cancelledCount, _ := h.subscriptionRepo.CountByStatus(ctx, "cancelled")
	expiredCount, _ := h.subscriptionRepo.CountByStatus(ctx, "expired")

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"active":    activeCount,
		"cancelled": cancelledCount,
		"expired":   expiredCount,
	})
}

func (h *DashboardHandler) GetRecentEvents(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	limit := 10
	if limitParam := r.URL.Query().Get("limit"); limitParam != "" {
		fmt.Sscanf(limitParam, "%d", &limit)
	}

	events, _ := h.eventRepo.ListRecent(ctx, limit)

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"events": events,
	})
}
