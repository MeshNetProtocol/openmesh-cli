package service

import (
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
}

func NewSubscriptionUpgradeService(
	subscriptions repository.SubscriptionRepository,
	authorizations repository.AuthorizationRepository,
	charges repository.ChargeRepository,
	plans repository.PlanRepository,
	events repository.EventRepository,
) *SubscriptionUpgradeService {
	return &SubscriptionUpgradeService{
		subscriptions:  subscriptions,
		authorizations: authorizations,
		charges:        charges,
		plans:          plans,
		events:         events,
	}
}

type UpgradeSubscriptionInput struct {
	SubscriptionID string
	NewPlanID      string
}

func (s *SubscriptionUpgradeService) UpgradeSubscription(input UpgradeSubscriptionInput) error {
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

	now := time.Now().UnixMilli()
	proratedCharge := s.calculateProratedCharge(subscription, oldPlan, newPlan, now)

	chargeID := fmt.Sprintf("chg_%d", now)
	charge := &domain.Charge{
		ID:              chargeID,
		ChargeID:        chargeID,
		SubscriptionID:  subscription.ID,
		AuthorizationID: subscription.CurrentAuthorizationID,
		Amount:          proratedCharge,
		Status:          domain.ChargePending,
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	if err := s.charges.Create(charge); err != nil {
		return fmt.Errorf("create charge: %w", err)
	}

	subscription.PlanID = newPlan.PlanID
	subscription.UpdatedAt = now
	if err := s.subscriptions.Update(subscription); err != nil {
		return fmt.Errorf("update subscription: %w", err)
	}

	s.events.Create(&domain.Event{
		ID:              fmt.Sprintf("evt_%d", now),
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    subscription.PayerAddress,
		PlanID:          newPlan.PlanID,
		ChargeID:        charge.ChargeID,
		Type:            domain.EventUpgrade,
		Description:     fmt.Sprintf("Upgraded from %s to %s", oldPlan.Name, newPlan.Name),
		Metadata:        fmt.Sprintf(`{"old_plan_id":"%s","new_plan_id":"%s","prorated_charge":%d}`, oldPlan.PlanID, newPlan.PlanID, proratedCharge),
		CreatedAt:       now,
	})

	return nil
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

func (s *SubscriptionUpgradeService) DowngradeSubscription(input DowngradeSubscriptionInput) error {
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

	now := time.Now().UnixMilli()

	subscription.PendingPlanID = newPlan.PlanID
	subscription.UpdatedAt = now
	if err := s.subscriptions.Update(subscription); err != nil {
		return fmt.Errorf("update subscription: %w", err)
	}

	s.events.Create(&domain.Event{
		ID:              fmt.Sprintf("evt_%d", now),
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    subscription.PayerAddress,
		PlanID:          subscription.PlanID,
		Type:            domain.EventDowngrade,
		Description:     fmt.Sprintf("Scheduled downgrade from %s to %s at period end", oldPlan.Name, newPlan.Name),
		Metadata:        fmt.Sprintf(`{"old_plan_id":"%s","new_plan_id":"%s","effective_at":%d}`, oldPlan.PlanID, newPlan.PlanID, subscription.CurrentPeriodEnd),
		CreatedAt:       now,
	})

	return nil
}
