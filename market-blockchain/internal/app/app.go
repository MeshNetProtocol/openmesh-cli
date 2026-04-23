package app

import (
	"context"
	"database/sql"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	_ "github.com/lib/pq"

	"market-blockchain/internal/api"
	"market-blockchain/internal/api/handlers"
	"market-blockchain/internal/blockchain"
	"market-blockchain/internal/config"
	"market-blockchain/internal/service"
	"market-blockchain/internal/store/postgres"
)

type App struct {
	config *config.Config
	db     *sql.DB
	server *http.Server
}

func New() (*App, error) {
	cfg, err := config.Load()
	if err != nil {
		return nil, fmt.Errorf("load config: %w", err)
	}

	db, err := sql.Open("postgres", cfg.DatabaseURL)
	if err != nil {
		return nil, fmt.Errorf("open database: %w", err)
	}

	if err := db.Ping(); err != nil {
		return nil, fmt.Errorf("ping database: %w", err)
	}

	store := postgres.New(db)

	planRepo := postgres.NewPlanRepository(store)
	subscriptionRepo := postgres.NewSubscriptionRepository(store)
	authorizationRepo := postgres.NewAuthorizationRepository(store)
	chargeRepo := postgres.NewChargeRepository(store)
	eventRepo := postgres.NewEventRepository(store)

	var contractClient *blockchain.ContractClient
	if cfg.BlockchainRPCURL != "" && cfg.ContractAddress != "" {
		contractClient, err = blockchain.NewContractClient(
			cfg.BlockchainRPCURL,
			cfg.ContractAddress,
			cfg.PrivateKey,
		)
		if err != nil {
			log.Printf("warning: failed to initialize contract client: %v", err)
		}
	}

	chainService := service.NewChainService(
		contractClient,
		subscriptionRepo,
		authorizationRepo,
		chargeRepo,
		eventRepo,
	)

	subscriptionService := service.NewSubscriptionService(
		planRepo,
		subscriptionRepo,
		authorizationRepo,
		chargeRepo,
	)

	subscriptionManagementService := service.NewSubscriptionManagementService(
		subscriptionRepo,
		eventRepo,
	)

	renewalService := service.NewRenewalService(
		subscriptionRepo,
		authorizationRepo,
		chargeRepo,
		eventRepo,
		planRepo,
		chainService,
	)

	_ = renewalService

	subscriptionHandler := handlers.NewSubscriptionHandler(
		subscriptionService,
		subscriptionManagementService,
	)

	planHandler := handlers.NewPlanHandler(planRepo)
	healthHandler := handlers.NewHealthHandler(db)

	router := api.NewRouter(healthHandler, planHandler, subscriptionHandler)

	server := &http.Server{
		Addr:    ":" + cfg.ServerPort,
		Handler: router,
	}

	return &App{
		config: cfg,
		db:     db,
		server: server,
	}, nil
}

func (a *App) Run() error {
	log.Printf("Starting market-blockchain server on port %s", a.config.ServerPort)

	errChan := make(chan error, 1)
	go func() {
		if err := a.server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			errChan <- err
		}
	}()

	sigChan := make(chan os.Signal, 1)
	signal.Notify(sigChan, os.Interrupt, syscall.SIGTERM)

	select {
	case err := <-errChan:
		return fmt.Errorf("server error: %w", err)
	case sig := <-sigChan:
		log.Printf("Received signal %v, shutting down gracefully", sig)
		return a.Shutdown()
	}
}

func (a *App) Shutdown() error {
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	if err := a.server.Shutdown(ctx); err != nil {
		log.Printf("Server shutdown error: %v", err)
	}

	if err := a.db.Close(); err != nil {
		log.Printf("Database close error: %v", err)
	}

	log.Println("Server stopped")
	return nil
}
