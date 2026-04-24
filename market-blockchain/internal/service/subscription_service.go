package service

import (
	"errors"
	"fmt"

	"market-blockchain/internal/domain"
	"market-blockchain/internal/repository"
)

var (
	ErrPlanNotFound             = errors.New("plan not found")
	ErrSubscriptionExists       = errors.New("subscription already exists")
	ErrInvalidAddresses         = errors.New("identity address and payer address are required")
	ErrInvalidExpectedAllowance = errors.New("expected allowance must be positive")
)

type CreateSubscriptionInput struct {
	SubscriptionID      string
	AuthorizationID     string
	ChargeRecordID      string
	IdentityAddress     string
	PayerAddress        string
	PlanID              string
	ExpectedAllowance   int64
	TargetAllowance     int64
	PermitDeadline      int64
	InitialChargeID     string
	InitialChargeAmount int64
}

type CreateSubscriptionResult struct {
	Plan          *domain.Plan
	Subscription  *domain.Subscription
	Authorization *domain.Authorization
	InitialCharge *domain.Charge
}

type subscriptionLifecycleCreator interface {
	CreatePendingSubscription(input CreatePendingSubscriptionInput) (*CreatePendingSubscriptionResult, error)
}

type SubscriptionService struct {
	plans         repository.PlanRepository
	subscriptions repository.SubscriptionRepository
	lifecycle     subscriptionLifecycleCreator
}

func NewSubscriptionService(
	plans repository.PlanRepository,
	subscriptions repository.SubscriptionRepository,
	lifecycle subscriptionLifecycleCreator,
) *SubscriptionService {
	return &SubscriptionService{
		plans:         plans,
		subscriptions: subscriptions,
		lifecycle:     lifecycle,
	}
}

func (s *SubscriptionService) CreateSubscription(input CreateSubscriptionInput) (*CreateSubscriptionResult, error) {
	if input.IdentityAddress == "" || input.PayerAddress == "" {
		return nil, ErrInvalidAddresses
	}
	if input.ExpectedAllowance <= 0 || input.TargetAllowance <= 0 {
		return nil, ErrInvalidExpectedAllowance
	}

	plan, err := s.plans.GetByPlanID(input.PlanID)
	if err != nil {
		return nil, fmt.Errorf("get plan: %w", err)
	}
	if plan == nil || !plan.Active {
		return nil, ErrPlanNotFound
	}

	existing, err := s.subscriptions.GetByIdentityAndPlan(input.IdentityAddress, input.PlanID)
	if err != nil {
		return nil, fmt.Errorf("get subscription: %w", err)
	}
	if existing != nil {
		return nil, ErrSubscriptionExists
	}

	result, err := s.lifecycle.CreatePendingSubscription(CreatePendingSubscriptionInput{
		SubscriptionID:      input.SubscriptionID,
		AuthorizationID:     input.AuthorizationID,
		ChargeRecordID:      input.ChargeRecordID,
		IdentityAddress:     input.IdentityAddress,
		PayerAddress:        input.PayerAddress,
		PlanID:              input.PlanID,
		ExpectedAllowance:   input.ExpectedAllowance,
		TargetAllowance:     input.TargetAllowance,
		PermitDeadline:      input.PermitDeadline,
		InitialChargeID:     input.InitialChargeID,
		InitialChargeAmount: input.InitialChargeAmount,
		Plan:                plan,
	})
	if err != nil {
		return nil, err
	}

	return &CreateSubscriptionResult{
		Plan:          plan,
		Subscription:  result.Subscription,
		Authorization: result.Authorization,
		InitialCharge: result.InitialCharge,
	}, nil
}
