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
	lifecycle      *SubscriptionLifecycleService
}

func NewRenewalService(
	subscriptions repository.SubscriptionRepository,
	authorizations repository.AuthorizationRepository,
	charges repository.ChargeRepository,
	events repository.EventRepository,
	plans repository.PlanRepository,
	chainService *ChainService,
	lifecycle *SubscriptionLifecycleService,
) *RenewalService {
	return &RenewalService{
		subscriptions:  subscriptions,
		authorizations: authorizations,
		charges:        charges,
		events:         events,
		plans:          plans,
		chainService:   chainService,
		lifecycle:      lifecycle,
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
		if err := s.lifecycle.ExpireSubscription(sub, "Subscription expired due to insufficient allowance"); err != nil {
			return fmt.Errorf("expire subscription: %w", err)
		}
		return fmt.Errorf("insufficient allowance")
	}

	chargeID := uuid.New().String()
	chargeRecordID := uuid.New().String()

	if err := s.lifecycle.ApplyRenewalSuccess(sub, auth, plan, chargeRecordID, chargeID); err != nil {
		return err
	}

	return nil
}
