package api

import (
	"net/http"

	"market-blockchain/internal/api/handlers"
	"market-blockchain/internal/api/handlers/admin"
	"market-blockchain/internal/api/middleware"
)

func NewRouter(
	healthHandler *handlers.HealthHandler,
	planHandler *handlers.PlanHandler,
	subscriptionHandler *handlers.SubscriptionHandler,
	upgradeHandler *handlers.SubscriptionUpgradeHandler,
	adminDashboardHandler *admin.DashboardHandler,
	adminPlanHandler *admin.AdminPlanHandler,
) http.Handler {
	mux := http.NewServeMux()

	// Public API endpoints
	mux.HandleFunc("GET /health", healthHandler.Health)
	mux.HandleFunc("GET /api/v1/plans", planHandler.ListPlans)
	mux.HandleFunc("POST /api/v1/subscriptions", subscriptionHandler.CreateSubscription)
	mux.HandleFunc("GET /api/v1/subscriptions/{id}", subscriptionHandler.GetSubscription)
	mux.HandleFunc("DELETE /api/v1/subscriptions/{id}", subscriptionHandler.CancelSubscription)
	mux.HandleFunc("POST /api/v1/subscriptions/{id}/upgrade", upgradeHandler.UpgradeSubscription)
	mux.HandleFunc("POST /api/v1/subscriptions/{id}/downgrade", upgradeHandler.DowngradeSubscription)

	// Admin API endpoints
	mux.HandleFunc("GET /admin/api/v1/dashboard/metrics", adminDashboardHandler.GetMetrics)
	mux.HandleFunc("GET /admin/api/v1/dashboard/revenue-trend", adminDashboardHandler.GetRevenueTrend)
	mux.HandleFunc("GET /admin/api/v1/dashboard/subscription-distribution", adminDashboardHandler.GetSubscriptionDistribution)
	mux.HandleFunc("GET /admin/api/v1/dashboard/recent-events", adminDashboardHandler.GetRecentEvents)
	mux.HandleFunc("GET /admin/api/v1/plans", adminPlanHandler.ListPlans)
	mux.HandleFunc("POST /admin/api/v1/plans", adminPlanHandler.CreatePlan)
	mux.HandleFunc("PUT /admin/api/v1/plans/{id}", adminPlanHandler.UpdatePlan)

	// Admin UI
	fs := http.FileServer(http.Dir("web/admin"))
	mux.Handle("GET /admin/", http.StripPrefix("/admin", fs))

	return middleware.Logger(mux)
}
