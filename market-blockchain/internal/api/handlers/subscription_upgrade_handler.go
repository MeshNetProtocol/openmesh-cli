package handlers

import (
	"encoding/json"
	"net/http"

	"market-blockchain/internal/service"
)

type SubscriptionUpgradeHandler struct {
	upgradeService *service.SubscriptionUpgradeService
}

func NewSubscriptionUpgradeHandler(upgradeService *service.SubscriptionUpgradeService) *SubscriptionUpgradeHandler {
	return &SubscriptionUpgradeHandler{
		upgradeService: upgradeService,
	}
}

type UpgradeSubscriptionRequest struct {
	NewPlanID string `json:"new_plan_id"`
}

func (h *SubscriptionUpgradeHandler) UpgradeSubscription(w http.ResponseWriter, r *http.Request) {
	subscriptionID := r.PathValue("id")
	if subscriptionID == "" {
		respondError(w, http.StatusBadRequest, "subscription_id is required")
		return
	}

	var req UpgradeSubscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.NewPlanID == "" {
		respondError(w, http.StatusBadRequest, "new_plan_id is required")
		return
	}

	input := service.UpgradeSubscriptionInput{
		SubscriptionID: subscriptionID,
		NewPlanID:      req.NewPlanID,
	}

	if err := h.upgradeService.UpgradeSubscription(input); err != nil {
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"message": "subscription upgraded successfully",
	})
}

type DowngradeSubscriptionRequest struct {
	NewPlanID string `json:"new_plan_id"`
}

func (h *SubscriptionUpgradeHandler) DowngradeSubscription(w http.ResponseWriter, r *http.Request) {
	subscriptionID := r.PathValue("id")
	if subscriptionID == "" {
		respondError(w, http.StatusBadRequest, "subscription_id is required")
		return
	}

	var req DowngradeSubscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	if req.NewPlanID == "" {
		respondError(w, http.StatusBadRequest, "new_plan_id is required")
		return
	}

	input := service.DowngradeSubscriptionInput{
		SubscriptionID: subscriptionID,
		NewPlanID:      req.NewPlanID,
	}

	if err := h.upgradeService.DowngradeSubscription(input); err != nil {
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{
		"message": "subscription downgrade scheduled for period end",
	})
}
