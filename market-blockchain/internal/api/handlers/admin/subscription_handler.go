package admin

import (
	"encoding/json"
	"net/http"
	"strconv"

	"market-blockchain/internal/repository"
)

type AdminSubscriptionHandler struct {
	subscriptionRepo repository.SubscriptionRepository
}

func NewAdminSubscriptionHandler(subscriptionRepo repository.SubscriptionRepository) *AdminSubscriptionHandler {
	return &AdminSubscriptionHandler{
		subscriptionRepo: subscriptionRepo,
	}
}

func (h *AdminSubscriptionHandler) ListSubscriptions(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	status := r.URL.Query().Get("status")
	page, _ := strconv.Atoi(r.URL.Query().Get("page"))
	if page < 1 {
		page = 1
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	if limit < 1 || limit > 100 {
		limit = 50
	}

	offset := (page - 1) * limit

	var subscriptions interface{}
	var total int
	var err error

	if status != "" && status != "all" {
		subscriptions, err = h.subscriptionRepo.ListByStatus(ctx, status, limit, offset)
		if err == nil {
			total, _ = h.subscriptionRepo.CountByStatus(ctx, status)
		}
	} else {
		subscriptions, err = h.subscriptionRepo.ListAll(ctx, limit, offset)
		if err == nil {
			total, _ = h.subscriptionRepo.CountAll(ctx)
		}
	}

	if err != nil {
		http.Error(w, "failed to list subscriptions", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]interface{}{
		"subscriptions": subscriptions,
		"total":         total,
		"page":          page,
		"limit":         limit,
	})
}
