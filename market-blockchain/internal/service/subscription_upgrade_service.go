package service

import (
	"context"
	"fmt"
	"time"

	"market-blockchain/internal/domain"
	"market-blockchain/internal/repository"
)

type SubscriptionUpgradeService struct {
	subscriptions  repository.SubscriptionRepository
	authorizations repository.AuthorizationRepository
	charges        repository.ChargeRepository
	plans          repository.PlanRepository
	events         repository.EventRepository
	lifecycle      *SubscriptionLifecycleService
}

func NewSubscriptionUpgradeService(
	subscriptions repository.SubscriptionRepository,
	authorizations repository.AuthorizationRepository,
	charges repository.ChargeRepository,
	plans repository.PlanRepository,
	events repository.EventRepository,
	lifecycle *SubscriptionLifecycleService,
) *SubscriptionUpgradeService {
	return &SubscriptionUpgradeService{
		subscriptions:  subscriptions,
		authorizations: authorizations,
		charges:        charges,
		plans:          plans,
		events:         events,
		lifecycle:      lifecycle,
	}
}

type UpgradeSubscriptionInput struct {
	SubscriptionID string
	NewPlanID      string
}

func (s *SubscriptionUpgradeService) UpgradeSubscription(ctx context.Context, input UpgradeSubscriptionInput) error {
	subscription, err := s.subscriptions.GetByID(input.SubscriptionID)
	if err != nil {
		return fmt.Errorf("get subscription: %w", err)
	}
	if subscription == nil {
		return fmt.Errorf("subscription not found")
	}

	if subscription.Status != domain.SubscriptionActive {
		return fmt.Errorf("can only upgrade active subscriptions")
	}

	newPlan, err := s.plans.GetByPlanID(input.NewPlanID)
	if err != nil {
		return fmt.Errorf("get new plan: %w", err)
	}
	if newPlan == nil {
		return fmt.Errorf("new plan not found")
	}

	oldPlan, err := s.plans.GetByPlanID(subscription.PlanID)
	if err != nil {
		return fmt.Errorf("get old plan: %w", err)
	}
	if oldPlan == nil {
		return fmt.Errorf("old plan not found")
	}

	if newPlan.AmountUSDCBaseUnits <= oldPlan.AmountUSDCBaseUnits {
		return fmt.Errorf("new plan must be more expensive than current plan")
	}

	proratedCharge := s.calculateProratedCharge(subscription, oldPlan, newPlan, time.Now().UnixMilli())
	return s.lifecycle.ApplyImmediateUpgrade(ctx, subscription, oldPlan, newPlan, proratedCharge)
}

func (s *SubscriptionUpgradeService) calculateProratedCharge(
	subscription *domain.Subscription,
	oldPlan *domain.Plan,
	newPlan *domain.Plan,
	now int64,
) int64 {
	if subscription.CurrentPeriodEnd <= now {
		return newPlan.AmountUSDCBaseUnits
	}

	remainingTime := subscription.CurrentPeriodEnd - now
	totalPeriod := oldPlan.PeriodSeconds * 1000

	if totalPeriod == 0 {
		return newPlan.AmountUSDCBaseUnits
	}

	unusedCredit := (oldPlan.AmountUSDCBaseUnits * remainingTime) / totalPeriod
	proratedCharge := newPlan.AmountUSDCBaseUnits - unusedCredit

	if proratedCharge < 0 {
		return 0
	}

	return proratedCharge
}

type DowngradeSubscriptionInput struct {
	SubscriptionID string
	NewPlanID      string
}

func (s *SubscriptionUpgradeService) DowngradeSubscription(ctx context.Context, input DowngradeSubscriptionInput) error {
	subscription, err := s.subscriptions.GetByID(input.SubscriptionID)
	if err != nil {
		return fmt.Errorf("get subscription: %w", err)
	}
	if subscription == nil {
		return fmt.Errorf("subscription not found")
	}

	if subscription.Status != domain.SubscriptionActive {
		return fmt.Errorf("can only downgrade active subscriptions")
	}

	newPlan, err := s.plans.GetByPlanID(input.NewPlanID)
	if err != nil {
		return fmt.Errorf("get new plan: %w", err)
	}
	if newPlan == nil {
		return fmt.Errorf("new plan not found")
	}

	oldPlan, err := s.plans.GetByPlanID(subscription.PlanID)
	if err != nil {
		return fmt.Errorf("get old plan: %w", err)
	}
	if oldPlan == nil {
		return fmt.Errorf("old plan not found")
	}

	if newPlan.AmountUSDCBaseUnits >= oldPlan.AmountUSDCBaseUnits {
		return fmt.Errorf("new plan must be less expensive than current plan")
	}

	_ = s.authorizations
	_ = s.charges
	_ = s.events

	return s.lifecycle.ScheduleDowngrade(ctx, subscription, oldPlan, newPlan)
}
