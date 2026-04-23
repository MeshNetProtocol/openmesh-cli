package handlers

import (
	"encoding/json"
	"net/http"

	"github.com/google/uuid"

	"market-blockchain/internal/service"
)

type SubscriptionHandler struct {
	subscriptionService           *service.SubscriptionService
	subscriptionManagementService *service.SubscriptionManagementService
}

func NewSubscriptionHandler(
	subscriptionService *service.SubscriptionService,
	subscriptionManagementService *service.SubscriptionManagementService,
) *SubscriptionHandler {
	return &SubscriptionHandler{
		subscriptionService:           subscriptionService,
		subscriptionManagementService: subscriptionManagementService,
	}
}

type CreateSubscriptionRequest struct {
	IdentityAddress     string `json:"identity_address"`
	PayerAddress        string `json:"payer_address"`
	PlanID              string `json:"plan_id"`
	ExpectedAllowance   int64  `json:"expected_allowance"`
	TargetAllowance     int64  `json:"target_allowance"`
	PermitDeadline      int64  `json:"permit_deadline"`
	InitialChargeAmount int64  `json:"initial_charge_amount,omitempty"`
}

type CreateSubscriptionResponse struct {
	SubscriptionID  string                `json:"subscription_id"`
	AuthorizationID string                `json:"authorization_id"`
	ChargeRecordID  string                `json:"charge_record_id"`
	Plan            PlanResponse          `json:"plan"`
	Subscription    SubscriptionResponse  `json:"subscription"`
	Authorization   AuthorizationResponse `json:"authorization"`
	InitialCharge   ChargeResponse        `json:"initial_charge"`
}

func (h *SubscriptionHandler) CreateSubscription(w http.ResponseWriter, r *http.Request) {
	var req CreateSubscriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		respondError(w, http.StatusBadRequest, "invalid request body")
		return
	}

	subscriptionID := uuid.New().String()
	authorizationID := uuid.New().String()
	chargeRecordID := uuid.New().String()
	initialChargeID := uuid.New().String()

	input := service.CreateSubscriptionInput{
		SubscriptionID:      subscriptionID,
		AuthorizationID:     authorizationID,
		ChargeRecordID:      chargeRecordID,
		IdentityAddress:     req.IdentityAddress,
		PayerAddress:        req.PayerAddress,
		PlanID:              req.PlanID,
		ExpectedAllowance:   req.ExpectedAllowance,
		TargetAllowance:     req.TargetAllowance,
		PermitDeadline:      req.PermitDeadline,
		InitialChargeID:     initialChargeID,
		InitialChargeAmount: req.InitialChargeAmount,
	}

	result, err := h.subscriptionService.CreateSubscription(input)
	if err != nil {
		switch err {
		case service.ErrPlanNotFound:
			respondError(w, http.StatusNotFound, "plan not found")
		case service.ErrSubscriptionExists:
			respondError(w, http.StatusConflict, "subscription already exists")
		case service.ErrInvalidAddresses, service.ErrInvalidExpectedAllowance:
			respondError(w, http.StatusBadRequest, err.Error())
		default:
			respondError(w, http.StatusInternalServerError, "internal server error")
		}
		return
	}

	resp := CreateSubscriptionResponse{
		SubscriptionID:  subscriptionID,
		AuthorizationID: authorizationID,
		ChargeRecordID:  chargeRecordID,
		Plan:            mapPlanToResponse(result.Plan),
		Subscription:    mapSubscriptionToResponse(result.Subscription),
		Authorization:   mapAuthorizationToResponse(result.Authorization),
		InitialCharge:   mapChargeToResponse(result.InitialCharge),
	}

	respondJSON(w, http.StatusCreated, resp)
}

func (h *SubscriptionHandler) CancelSubscription(w http.ResponseWriter, r *http.Request) {
	subscriptionID := r.PathValue("id")
	if subscriptionID == "" {
		respondError(w, http.StatusBadRequest, "subscription_id is required")
		return
	}

	if err := h.subscriptionManagementService.CancelSubscription(subscriptionID); err != nil {
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}

	respondJSON(w, http.StatusOK, map[string]string{"message": "subscription cancelled"})
}

func (h *SubscriptionHandler) GetSubscription(w http.ResponseWriter, r *http.Request) {
	subscriptionID := r.PathValue("id")
	if subscriptionID == "" {
		respondError(w, http.StatusBadRequest, "subscription_id is required")
		return
	}

	subscription, err := h.subscriptionManagementService.GetSubscription(subscriptionID)
	if err != nil {
		respondError(w, http.StatusInternalServerError, err.Error())
		return
	}
	if subscription == nil {
		respondError(w, http.StatusNotFound, "subscription not found")
		return
	}

	respondJSON(w, http.StatusOK, mapSubscriptionToResponse(subscription))
}
