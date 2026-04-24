package service

import (
	"errors"
	"fmt"
	"time"

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

type subscriptionCreationStore interface {
	CreateInitialState(subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, event *domain.Event) error
}

type SubscriptionService struct {
	plans          repository.PlanRepository
	subscriptions  repository.SubscriptionRepository
	authorizations repository.AuthorizationRepository
	charges        repository.ChargeRepository
	creator        subscriptionCreationStore
}

func NewSubscriptionService(
	plans repository.PlanRepository,
	subscriptions repository.SubscriptionRepository,
	authorizations repository.AuthorizationRepository,
	charges repository.ChargeRepository,
	creator subscriptionCreationStore,
) *SubscriptionService {
	return &SubscriptionService{
		plans:          plans,
		subscriptions:  subscriptions,
		authorizations: authorizations,
		charges:        charges,
		creator:        creator,
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

	now := time.Now().UnixMilli()
	periodEnd := now + (plan.PeriodSeconds * 1000)

	subscription := &domain.Subscription{
		ID:                     input.SubscriptionID,
		IdentityAddress:        input.IdentityAddress,
		PayerAddress:           input.PayerAddress,
		PlanID:                 input.PlanID,
		Status:                 domain.SubscriptionPending,
		AutoRenew:              true,
		CurrentPeriodStart:     now,
		CurrentPeriodEnd:       periodEnd,
		NextPlanID:             "",
		CurrentAuthorizationID: input.AuthorizationID,
		LastChargeID:           input.InitialChargeID,
		LastChargeAt:           now,
		Source:                 domain.SubscriptionSourceFirstSubscribe,
		CreatedAt:              now,
		UpdatedAt:              now,
	}

	authorization := &domain.Authorization{
		ID:                   input.AuthorizationID,
		IdentityAddress:      input.IdentityAddress,
		PayerAddress:         input.PayerAddress,
		PlanID:               input.PlanID,
		ExpectedAllowance:    input.ExpectedAllowance,
		TargetAllowance:      input.TargetAllowance,
		AuthorizedAllowance:  0,
		RemainingAllowance:   input.TargetAllowance,
		PermitStatus:         domain.AuthorizationPending,
		PermitTxHash:         "",
		PermitDeadline:       input.PermitDeadline,
		AuthorizationPeriods: plan.AuthorizationPeriods,
		CreatedAt:            now,
		UpdatedAt:            now,
	}

	chargeAmount := input.InitialChargeAmount
	if chargeAmount <= 0 {
		chargeAmount = plan.AmountUSDCBaseUnits
	}

	charge := &domain.Charge{
		ID:              input.ChargeRecordID,
		ChargeID:        input.InitialChargeID,
		SubscriptionID:  input.SubscriptionID,
		AuthorizationID: input.AuthorizationID,
		IdentityAddress: input.IdentityAddress,
		PayerAddress:    input.PayerAddress,
		PlanID:          input.PlanID,
		Amount:          chargeAmount,
		Status:          domain.ChargePending,
		TxHash:          "",
		Reason:          string(domain.EventFirstSubscribe),
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	event := &domain.Event{
		ID:              fmt.Sprintf("evt_%s_create", input.SubscriptionID),
		IdentityAddress: input.IdentityAddress,
		PayerAddress:    input.PayerAddress,
		PlanID:          input.PlanID,
		ChargeID:        input.InitialChargeID,
		Type:            domain.EventFirstSubscribe,
		Description:     "Subscription created and pending first charge",
		Metadata: fmt.Sprintf(
			`{"subscription_id":"%s","authorization_id":"%s","charge_record_id":"%s","status":"%s"}`,
			input.SubscriptionID,
			input.AuthorizationID,
			input.ChargeRecordID,
			domain.SubscriptionPending,
		),
		CreatedAt: now,
	}

	if err := s.creator.CreateInitialState(subscription, authorization, charge, event); err != nil {
		return nil, fmt.Errorf("persist subscription creation: %w", err)
	}

	return &CreateSubscriptionResult{
		Plan:          plan,
		Subscription:  subscription,
		Authorization: authorization,
		InitialCharge: charge,
	}, nil
}
