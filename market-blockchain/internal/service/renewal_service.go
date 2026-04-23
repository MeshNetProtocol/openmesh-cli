package service

import (
	"context"
	"fmt"
	"time"

	"github.com/google/uuid"

	"market-blockchain/internal/domain"
	"market-blockchain/internal/repository"
)

type RenewalService struct {
	subscriptions  repository.SubscriptionRepository
	authorizations repository.AuthorizationRepository
	charges        repository.ChargeRepository
	events         repository.EventRepository
	plans          repository.PlanRepository
	chainService   *ChainService
}

func NewRenewalService(
	subscriptions repository.SubscriptionRepository,
	authorizations repository.AuthorizationRepository,
	charges repository.ChargeRepository,
	events repository.EventRepository,
	plans repository.PlanRepository,
	chainService *ChainService,
) *RenewalService {
	return &RenewalService{
		subscriptions:  subscriptions,
		authorizations: authorizations,
		charges:        charges,
		events:         events,
		plans:          plans,
		chainService:   chainService,
	}
}

func (s *RenewalService) ProcessRenewals(ctx context.Context) error {
	now := time.Now().UnixMilli()

	renewableSubscriptions, err := s.subscriptions.ListRenewable(now)
	if err != nil {
		return fmt.Errorf("list renewable subscriptions: %w", err)
	}

	for _, sub := range renewableSubscriptions {
		if err := s.processRenewal(ctx, sub); err != nil {
			s.events.Create(&domain.Event{
				ID:              uuid.New().String(),
				IdentityAddress: sub.IdentityAddress,
				PayerAddress:    sub.PayerAddress,
				PlanID:          sub.PlanID,
				ChargeID:        "",
				Type:            domain.EventChargeFailed,
				Description:     fmt.Sprintf("Renewal failed: %v", err),
				Metadata:        "",
				CreatedAt:       time.Now().UnixMilli(),
			})
			continue
		}
	}

	return nil
}

func (s *RenewalService) processRenewal(ctx context.Context, sub *domain.Subscription) error {
	targetPlanID := sub.PlanID
	if sub.PendingPlanID != "" {
		targetPlanID = sub.PendingPlanID
	}

	plan, err := s.plans.GetByPlanID(targetPlanID)
	if err != nil {
		return fmt.Errorf("get plan: %w", err)
	}
	if plan == nil || !plan.Active {
		return fmt.Errorf("plan not found or inactive")
	}

	auth, err := s.authorizations.GetByIdentityAndPlan(sub.IdentityAddress, sub.PlanID)
	if err != nil {
		return fmt.Errorf("get authorization: %w", err)
	}
	if auth == nil {
		return fmt.Errorf("authorization not found")
	}

	if auth.RemainingAllowance < plan.AmountUSDCBaseUnits {
		sub.Status = domain.SubscriptionExpired
		sub.UpdatedAt = time.Now().UnixMilli()
		s.subscriptions.Update(sub)

		s.events.Create(&domain.Event{
			ID:              uuid.New().String(),
			IdentityAddress: sub.IdentityAddress,
			PayerAddress:    sub.PayerAddress,
			PlanID:          sub.PlanID,
			ChargeID:        "",
			Type:            domain.EventExpired,
			Description:     "Subscription expired due to insufficient allowance",
			Metadata:        "",
			CreatedAt:       time.Now().UnixMilli(),
		})

		return fmt.Errorf("insufficient allowance")
	}

	chargeID := uuid.New().String()
	chargeRecordID := uuid.New().String()
	now := time.Now().UnixMilli()

	eventType := domain.EventRenew
	eventDescription := "Renewal charge completed"
	if sub.PendingPlanID != "" {
		eventType = domain.EventDowngrade
		eventDescription = fmt.Sprintf("Downgraded to %s during renewal", plan.Name)
	}

	charge := &domain.Charge{
		ID:              chargeRecordID,
		ChargeID:        chargeID,
		SubscriptionID:  sub.ID,
		AuthorizationID: sub.CurrentAuthorizationID,
		IdentityAddress: sub.IdentityAddress,
		PayerAddress:    sub.PayerAddress,
		PlanID:          targetPlanID,
		Amount:          plan.AmountUSDCBaseUnits,
		Status:          domain.ChargePending,
		TxHash:          "",
		Reason:          string(eventType),
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	if err := s.charges.Create(charge); err != nil {
		return fmt.Errorf("create charge: %w", err)
	}

	sub.PlanID = targetPlanID
	sub.PendingPlanID = ""
	sub.CurrentPeriodStart = sub.CurrentPeriodEnd
	sub.CurrentPeriodEnd = sub.CurrentPeriodEnd + (plan.PeriodSeconds * 1000)
	sub.LastChargeID = chargeID
	sub.LastChargeAt = now
	sub.UpdatedAt = now

	if err := s.subscriptions.Update(sub); err != nil {
		return fmt.Errorf("update subscription: %w", err)
	}

	auth.RemainingAllowance -= plan.AmountUSDCBaseUnits
	auth.UpdatedAt = now
	if err := s.authorizations.Update(auth); err != nil {
		return fmt.Errorf("update authorization: %w", err)
	}

	s.events.Create(&domain.Event{
		ID:              uuid.New().String(),
		IdentityAddress: sub.IdentityAddress,
		PayerAddress:    sub.PayerAddress,
		PlanID:          targetPlanID,
		ChargeID:        chargeID,
		Type:            eventType,
		Description:     eventDescription,
		Metadata:        "",
		CreatedAt:       now,
	})

	return nil
}
