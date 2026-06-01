package service

import (
	"context"
	"fmt"
	"time"

	"market-blockchain/internal/domain"
	"market-blockchain/internal/repository"
	"market-blockchain/internal/xray"
)

type subscriptionLifecycleStore interface {
	CreateInitialState(ctx context.Context, subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, event *domain.Event) error
	CompleteFirstCharge(ctx context.Context, subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, event *domain.Event) error
	CompleteRenewal(ctx context.Context, subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, event *domain.Event) error
	ApplyImmediateUpgrade(ctx context.Context, subscription *domain.Subscription, charge *domain.Charge, event *domain.Event) error
	ScheduleDowngrade(ctx context.Context, subscription *domain.Subscription, event *domain.Event) error
}

type subscriptionXraySync interface {
	AddUser(ctx context.Context, email, uuid string) error
	RemoveUser(ctx context.Context, email string) error
}

type SubscriptionLifecycleService struct {
	subscriptions  repository.SubscriptionRepository
	authorizations repository.AuthorizationRepository
	charges        repository.ChargeRepository
	events         repository.EventRepository
	store          subscriptionLifecycleStore
	xraySync       subscriptionXraySync
}

func NewSubscriptionLifecycleService(
	subscriptions repository.SubscriptionRepository,
	authorizations repository.AuthorizationRepository,
	charges repository.ChargeRepository,
	events repository.EventRepository,
	store subscriptionLifecycleStore,
	xraySync subscriptionXraySync,
) *SubscriptionLifecycleService {
	return &SubscriptionLifecycleService{
		subscriptions:  subscriptions,
		authorizations: authorizations,
		charges:        charges,
		events:         events,
		store:          store,
		xraySync:       xraySync,
	}
}

type CreatePendingSubscriptionInput struct {
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
	Plan                *domain.Plan
}

type CreatePendingSubscriptionResult struct {
	Subscription  *domain.Subscription
	Authorization *domain.Authorization
	InitialCharge *domain.Charge
}

func (s *SubscriptionLifecycleService) CreatePendingSubscription(ctx context.Context, input CreatePendingSubscriptionInput) (*CreatePendingSubscriptionResult, error) {
	now := time.Now().UnixMilli()
	periodEnd := now + (input.Plan.PeriodSeconds * 1000)

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
		AuthorizationPeriods: input.Plan.AuthorizationPeriods,
		CreatedAt:            now,
		UpdatedAt:            now,
	}

	chargeAmount := input.InitialChargeAmount
	if chargeAmount <= 0 {
		chargeAmount = input.Plan.AmountUSDCBaseUnits
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
			`{"subscription_id":"%s","authorization_id":"%s","charge_record_id":"%s","status":"%s","lifecycle_action":"create_pending","xray_action":"none","xray_sync_status":"not_required"}`,
			input.SubscriptionID,
			input.AuthorizationID,
			input.ChargeRecordID,
			domain.SubscriptionPending,
		),
		CreatedAt: now,
	}

	if err := s.store.CreateInitialState(ctx, subscription, authorization, charge, event); err != nil {
		return nil, fmt.Errorf("persist subscription creation: %w", err)
	}

	return &CreatePendingSubscriptionResult{
		Subscription:  subscription,
		Authorization: authorization,
		InitialCharge: charge,
	}, nil
}

func (s *SubscriptionLifecycleService) CompleteFirstCharge(ctx context.Context, subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, permitTxHash, chargeTxHash string) error {
	now := time.Now().UnixMilli()

	authorization.PermitStatus = domain.AuthorizationCompleted
	authorization.PermitTxHash = permitTxHash
	authorization.AuthorizedAllowance = authorization.TargetAllowance
	authorization.RemainingAllowance = authorization.TargetAllowance - charge.Amount
	authorization.UpdatedAt = now

	charge.Status = domain.ChargeCompleted
	charge.TxHash = chargeTxHash
	charge.UpdatedAt = now

	if err := subscription.Activate(now); err != nil {
		return err
	}
	subscription.CurrentAuthorizationID = authorization.ID
	subscription.LastChargeID = charge.ChargeID
	subscription.LastChargeAt = now

	event := &domain.Event{
		ID:              fmt.Sprintf("evt_%s_first_charge", subscription.ID),
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    subscription.PayerAddress,
		PlanID:          subscription.PlanID,
		ChargeID:        charge.ChargeID,
		Type:            domain.EventChargeSuccess,
		Description:     "First subscription charge completed and activated",
		Metadata: fmt.Sprintf(
			`{"subscription_id":"%s","authorization_id":"%s","charge_record_id":"%s","subscription_status":"%s","authorization_status":"%s","charge_status":"%s","permit_tx_hash":"%s","charge_tx_hash":"%s","lifecycle_action":"activate_first_charge","xray_action":"add_user","xray_sync_status":"pending"}`,
			subscription.ID,
			authorization.ID,
			charge.ID,
			subscription.Status,
			authorization.PermitStatus,
			charge.Status,
			permitTxHash,
			chargeTxHash,
		),
		CreatedAt: now,
	}

	if err := s.store.CompleteFirstCharge(ctx, subscription, authorization, charge, event); err != nil {
		return fmt.Errorf("persist first charge completion: %w", err)
	}

	if err := s.syncActiveSubscription(ctx, subscription, "activate_first_charge", domain.EventChargeSuccess, "Subscription synced to Xray as active"); err != nil {
		return err
	}

	return nil
}

func (s *SubscriptionLifecycleService) CancelSubscription(ctx context.Context, subscription *domain.Subscription) error {
	now := time.Now().UnixMilli()
	if err := subscription.Cancel(now); err != nil {
		return err
	}

	if err := s.subscriptions.Update(subscription); err != nil {
		return fmt.Errorf("update subscription: %w", err)
	}

	if err := s.events.Create(&domain.Event{
		ID:              fmt.Sprintf("evt_%d", now),
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    subscription.PayerAddress,
		PlanID:          subscription.PlanID,
		ChargeID:        "",
		Type:            domain.EventCancel,
		Description:     "Subscription cancelled by user",
		Metadata:        fmt.Sprintf(`{"subscription_id":"%s","status":"%s","lifecycle_action":"cancel","xray_action":"remove_user","xray_sync_status":"pending"}`, subscription.ID, subscription.Status),
		CreatedAt:       now,
	}); err != nil {
		return fmt.Errorf("create cancel event: %w", err)
	}

	if err := s.syncInactiveSubscription(ctx, subscription, "cancel", domain.EventCancel, "Subscription removed from Xray after cancellation"); err != nil {
		return err
	}

	return nil
}

func (s *SubscriptionLifecycleService) ExpireSubscription(ctx context.Context, subscription *domain.Subscription, reason string) error {
	now := time.Now().UnixMilli()
	if err := subscription.Expire(now); err != nil {
		return err
	}

	if err := s.subscriptions.Update(subscription); err != nil {
		return fmt.Errorf("update subscription: %w", err)
	}

	if err := s.events.Create(&domain.Event{
		ID:              fmt.Sprintf("evt_%d", now),
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    subscription.PayerAddress,
		PlanID:          subscription.PlanID,
		ChargeID:        "",
		Type:            domain.EventExpired,
		Description:     reason,
		Metadata:        fmt.Sprintf(`{"subscription_id":"%s","status":"%s","lifecycle_action":"expire","xray_action":"remove_user","xray_sync_status":"pending"}`, subscription.ID, subscription.Status),
		CreatedAt:       now,
	}); err != nil {
		return fmt.Errorf("create expiration event: %w", err)
	}

	if err := s.syncInactiveSubscription(ctx, subscription, "expire", domain.EventExpired, "Subscription removed from Xray after expiration"); err != nil {
		return err
	}

	return nil
}

func (s *SubscriptionLifecycleService) ApplyRenewalSuccess(ctx context.Context, subscription *domain.Subscription, authorization *domain.Authorization, plan *domain.Plan, chargeRecordID, chargeID string) error {
	if subscription.Status != domain.SubscriptionActive {
		return fmt.Errorf("renewal requires active subscription, got %s", subscription.Status)
	}

	now := time.Now().UnixMilli()
	eventType := domain.EventRenew
	eventDescription := "Renewal charge completed"
	source := domain.SubscriptionSourceRenewal
	previousPlanID := subscription.PlanID
	targetPlanID := subscription.PlanID
	lifecycleAction := "renewal_success"
	if subscription.PendingPlanID != "" {
		targetPlanID = subscription.PendingPlanID
		eventType = domain.EventDowngrade
		eventDescription = fmt.Sprintf("Downgraded to %s during renewal", plan.Name)
		source = domain.SubscriptionSourceDowngrade
	}

	charge := &domain.Charge{
		ID:              chargeRecordID,
		ChargeID:        chargeID,
		SubscriptionID:  subscription.ID,
		AuthorizationID: subscription.CurrentAuthorizationID,
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    subscription.PayerAddress,
		PlanID:          targetPlanID,
		Amount:          plan.AmountUSDCBaseUnits,
		Status:          domain.ChargePending,
		TxHash:          "",
		Reason:          string(eventType),
		CreatedAt:       now,
		UpdatedAt:       now,
	}

	subscription.PlanID = targetPlanID
	subscription.PendingPlanID = ""
	subscription.CurrentPeriodStart = subscription.CurrentPeriodEnd
	subscription.CurrentPeriodEnd = subscription.CurrentPeriodEnd + (plan.PeriodSeconds * 1000)
	subscription.LastChargeID = chargeID
	subscription.LastChargeAt = now
	subscription.Source = source
	subscription.UpdatedAt = now

	authorization.RemainingAllowance -= plan.AmountUSDCBaseUnits
	authorization.UpdatedAt = now

	event := &domain.Event{
		ID:              fmt.Sprintf("evt_%d", now),
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    subscription.PayerAddress,
		PlanID:          targetPlanID,
		ChargeID:        chargeID,
		Type:            eventType,
		Description:     eventDescription,
		Metadata:        fmt.Sprintf(`{"subscription_id":"%s","previous_plan_id":"%s","plan_id":"%s","charge_record_id":"%s","lifecycle_action":"%s","xray_action":"add_user","xray_sync_status":"pending"}`, subscription.ID, previousPlanID, targetPlanID, chargeRecordID, lifecycleAction),
		CreatedAt:       now,
	}

	if err := s.store.CompleteRenewal(ctx, subscription, authorization, charge, event); err != nil {
		return fmt.Errorf("persist renewal success: %w", err)
	}

	if err := s.syncActiveSubscription(ctx, subscription, lifecycleAction, eventType, "Subscription synced to Xray after renewal"); err != nil {
		return err
	}

	return nil
}

func (s *SubscriptionLifecycleService) ApplyImmediateUpgrade(ctx context.Context, subscription *domain.Subscription, oldPlan *domain.Plan, newPlan *domain.Plan, proratedCharge int64) error {
	if subscription.Status != domain.SubscriptionActive {
		return fmt.Errorf("can only upgrade active subscriptions")
	}

	now := time.Now().UnixMilli()
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

	subscription.PlanID = newPlan.PlanID
	subscription.Source = domain.SubscriptionSourceUpgrade
	subscription.UpdatedAt = now

	event := &domain.Event{
		ID:              fmt.Sprintf("evt_%d", now),
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    subscription.PayerAddress,
		PlanID:          newPlan.PlanID,
		ChargeID:        charge.ChargeID,
		Type:            domain.EventUpgrade,
		Description:     fmt.Sprintf("Upgraded from %s to %s", oldPlan.Name, newPlan.Name),
		Metadata:        fmt.Sprintf(`{"subscription_id":"%s","old_plan_id":"%s","new_plan_id":"%s","prorated_charge":%d,"lifecycle_action":"upgrade","xray_action":"none","xray_sync_status":"intentional_noop"}`, subscription.ID, oldPlan.PlanID, newPlan.PlanID, proratedCharge),
		CreatedAt:       now,
	}

	if err := s.store.ApplyImmediateUpgrade(ctx, subscription, charge, event); err != nil {
		return fmt.Errorf("persist immediate upgrade: %w", err)
	}

	return nil
}

func (s *SubscriptionLifecycleService) ScheduleDowngrade(ctx context.Context, subscription *domain.Subscription, oldPlan *domain.Plan, newPlan *domain.Plan) error {
	if subscription.Status != domain.SubscriptionActive {
		return fmt.Errorf("can only downgrade active subscriptions")
	}

	now := time.Now().UnixMilli()
	subscription.PendingPlanID = newPlan.PlanID
	subscription.Source = domain.SubscriptionSourceDowngrade
	subscription.UpdatedAt = now

	event := &domain.Event{
		ID:              fmt.Sprintf("evt_%d", now),
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    subscription.PayerAddress,
		PlanID:          subscription.PlanID,
		Type:            domain.EventDowngrade,
		Description:     fmt.Sprintf("Scheduled downgrade from %s to %s at period end", oldPlan.Name, newPlan.Name),
		Metadata:        fmt.Sprintf(`{"subscription_id":"%s","old_plan_id":"%s","new_plan_id":"%s","effective_at":%d,"lifecycle_action":"schedule_downgrade","xray_action":"none","xray_sync_status":"intentional_noop"}`, subscription.ID, oldPlan.PlanID, newPlan.PlanID, subscription.CurrentPeriodEnd),
		CreatedAt:       now,
	}

	if err := s.store.ScheduleDowngrade(ctx, subscription, event); err != nil {
		return fmt.Errorf("persist scheduled downgrade: %w", err)
	}

	return nil
}

func (s *SubscriptionLifecycleService) syncActiveSubscription(ctx context.Context, subscription *domain.Subscription, lifecycleAction string, eventType domain.EventType, description string) error {
	if s.xraySync == nil {
		return nil
	}

	if err := s.xraySync.AddUser(ctx, subscription.IdentityAddress, xray.GetUserUUID(subscription.IdentityAddress)); err != nil {
		return s.recordXraySyncFailure(subscription, lifecycleAction, "add_user", err)
	}

	if err := s.recordXraySyncEvent(subscription, lifecycleAction, "add_user", "succeeded", "", eventType, description); err != nil {
		return fmt.Errorf("record xray sync success: %w", err)
	}

	return nil
}

func (s *SubscriptionLifecycleService) syncInactiveSubscription(ctx context.Context, subscription *domain.Subscription, lifecycleAction string, eventType domain.EventType, description string) error {
	if s.xraySync == nil {
		return nil
	}

	if err := s.xraySync.RemoveUser(ctx, subscription.IdentityAddress); err != nil {
		return s.recordXraySyncFailure(subscription, lifecycleAction, "remove_user", err)
	}

	if err := s.recordXraySyncEvent(subscription, lifecycleAction, "remove_user", "succeeded", "", eventType, description); err != nil {
		return fmt.Errorf("record xray sync success: %w", err)
	}

	return nil
}

func (s *SubscriptionLifecycleService) recordXraySyncFailure(subscription *domain.Subscription, lifecycleAction, action string, syncErr error) error {
	if err := s.recordXraySyncEvent(subscription, lifecycleAction, action, "failed", syncErr.Error(), domain.EventChargeFailed, "Xray sync failed after lifecycle state change"); err != nil {
		return fmt.Errorf("xray sync failed after lifecycle state change: %v (also failed to write sync failure event: %w)", syncErr, err)
	}
	return fmt.Errorf("xray sync failed after lifecycle state change: %w", syncErr)
}

func (s *SubscriptionLifecycleService) recordXraySyncEvent(subscription *domain.Subscription, lifecycleAction, action, syncStatus, syncError string, eventType domain.EventType, description string) error {
	now := time.Now().UnixMilli()
	metadata := fmt.Sprintf(
		`{"subscription_id":"%s","status":"%s","lifecycle_action":"%s","xray_action":"%s","xray_sync_status":"%s","xray_error":"%s"}`,
		subscription.ID,
		subscription.Status,
		lifecycleAction,
		action,
		syncStatus,
		syncError,
	)

	return s.events.Create(&domain.Event{
		ID:              fmt.Sprintf("evt_%s_xray_%d", subscription.ID, now),
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    subscription.PayerAddress,
		PlanID:          subscription.PlanID,
		ChargeID:        subscription.LastChargeID,
		Type:            eventType,
		Description:     description,
		Metadata:        metadata,
		CreatedAt:       now,
	})
}
