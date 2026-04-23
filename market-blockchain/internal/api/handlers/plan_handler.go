package handlers

import (
	"net/http"

	"market-blockchain/internal/repository"
)

type PlanHandler struct {
	planRepo repository.PlanRepository
}

func NewPlanHandler(planRepo repository.PlanRepository) *PlanHandler {
	return &PlanHandler{
		planRepo: planRepo,
	}
}

func (h *PlanHandler) ListPlans(w http.ResponseWriter, r *http.Request) {
	plans, err := h.planRepo.ListActive()
	if err != nil {
		respondError(w, http.StatusInternalServerError, "failed to list plans")
		return
	}

	response := make([]PlanResponse, 0, len(plans))
	for _, plan := range plans {
		response = append(response, mapPlanToResponse(plan))
	}

	respondJSON(w, http.StatusOK, response)
}
