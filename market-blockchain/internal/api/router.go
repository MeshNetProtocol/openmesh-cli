package api

import (
	"net/http"

	"market-blockchain/internal/api/handlers"
	"market-blockchain/internal/api/middleware"
)

func NewRouter(
	healthHandler *handlers.HealthHandler,
	planHandler *handlers.PlanHandler,
	subscriptionHandler *handlers.SubscriptionHandler,
) http.Handler {
	mux := http.NewServeMux()

	mux.HandleFunc("GET /health", healthHandler.Health)
	mux.HandleFunc("GET /api/v1/plans", planHandler.ListPlans)
	mux.HandleFunc("POST /api/v1/subscriptions", subscriptionHandler.CreateSubscription)
	mux.HandleFunc("GET /api/v1/subscriptions/{id}", subscriptionHandler.GetSubscription)
	mux.HandleFunc("DELETE /api/v1/subscriptions/{id}", subscriptionHandler.CancelSubscription)

	return middleware.Logger(mux)
}
