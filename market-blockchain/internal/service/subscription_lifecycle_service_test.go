package service

import (
	"context"
	"errors"
	"strings"
	"testing"

	"market-blockchain/internal/domain"
)

type lifecycleTestSubscriptionRepo struct {
	updated     *domain.Subscription
	updateCalls int
	err         error
}

func (r *lifecycleTestSubscriptionRepo) Create(subscription *domain.Subscription) error { return nil }
func (r *lifecycleTestSubscriptionRepo) Update(subscription *domain.Subscription) error {
	if r.err != nil {
		return r.err
	}
	r.updateCalls++
	copy := *subscription
	r.updated = &copy
	return nil
}
func (r *lifecycleTestSubscriptionRepo) GetByID(id string) (*domain.Subscription, error) {
	return nil, nil
}
func (r *lifecycleTestSubscriptionRepo) GetByIdentityAndPlan(identityAddress, planID string) (*domain.Subscription, error) {
	return nil, nil
}
func (r *lifecycleTestSubscriptionRepo) ListRenewable(now int64) ([]*domain.Subscription, error) {
	return nil, nil
}
func (r *lifecycleTestSubscriptionRepo) ListByStatus(ctx context.Context, status string, limit, offset int) ([]*domain.Subscription, error) {
	return nil, nil
}
func (r *lifecycleTestSubscriptionRepo) ListAll(ctx context.Context, limit, offset int) ([]*domain.Subscription, error) {
	return nil, nil
}
func (r *lifecycleTestSubscriptionRepo) CountByStatus(ctx context.Context, status string) (int, error) {
	return 0, nil
}
func (r *lifecycleTestSubscriptionRepo) CountAll(ctx context.Context) (int, error) { return 0, nil }
func (r *lifecycleTestSubscriptionRepo) CountByPlanAndStatus(ctx context.Context, planID, status string) (int, error) {
	return 0, nil
}
func (r *lifecycleTestSubscriptionRepo) SearchByAddress(ctx context.Context, address string) ([]*domain.Subscription, error) {
	return nil, nil
}

type lifecycleTestAuthorizationRepo struct {
	updated     *domain.Authorization
	updateCalls int
	err         error
}

func (r *lifecycleTestAuthorizationRepo) Create(authorization *domain.Authorization) error { return nil }
func (r *lifecycleTestAuthorizationRepo) Update(authorization *domain.Authorization) error {
	if r.err != nil {
		return r.err
	}
	r.updateCalls++
	copy := *authorization
	r.updated = &copy
	return nil
}
func (r *lifecycleTestAuthorizationRepo) GetByID(id string) (*domain.Authorization, error) {
	return nil, nil
}
func (r *lifecycleTestAuthorizationRepo) GetByIdentityAndPlan(identityAddress, planID string) (*domain.Authorization, error) {
	return nil, nil
}

type lifecycleTestChargeRepo struct {
	created     []*domain.Charge
	createCalls int
	err         error
}

func (r *lifecycleTestChargeRepo) Create(charge *domain.Charge) error {
	if r.err != nil {
		return r.err
	}
	r.createCalls++
	copy := *charge
	r.created = append(r.created, &copy)
	return nil
}
func (r *lifecycleTestChargeRepo) Update(charge *domain.Charge) error { return nil }
func (r *lifecycleTestChargeRepo) GetByID(id string) (*domain.Charge, error) { return nil, nil }
func (r *lifecycleTestChargeRepo) GetByChargeID(chargeID string) (*domain.Charge, error) { return nil, nil }
func (r *lifecycleTestChargeRepo) ListByIdentity(identityAddress string) ([]*domain.Charge, error) {
	return nil, nil
}
func (r *lifecycleTestChargeRepo) ListByStatusAndDateRange(ctx context.Context, status string, fromTime, toTime int64) ([]*domain.Charge, error) {
	return nil, nil
}
func (r *lifecycleTestChargeRepo) ListByDateRange(ctx context.Context, fromTime, toTime int64) ([]*domain.Charge, error) {
	return nil, nil
}
func (r *lifecycleTestChargeRepo) ListBySubscription(ctx context.Context, subscriptionID string) ([]*domain.Charge, error) {
	return nil, nil
}
func (r *lifecycleTestChargeRepo) SumCompletedCharges(ctx context.Context, fromTime, toTime int64) (int64, error) {
	return 0, nil
}
func (r *lifecycleTestChargeRepo) CountAndSumByStatus(ctx context.Context, status string) (int, int64, error) {
	return 0, 0, nil
}

type lifecycleTestEventRepo struct {
	events      []*domain.Event
	createCalls int
	err         error
}

func (r *lifecycleTestEventRepo) Create(event *domain.Event) error {
	if r.err != nil {
		return r.err
	}
	r.createCalls++
	copy := *event
	r.events = append(r.events, &copy)
	return nil
}
func (r *lifecycleTestEventRepo) ListByIdentity(identityAddress string) ([]*domain.Event, error) { return nil, nil }
func (r *lifecycleTestEventRepo) ListByTypeAndDateRange(ctx context.Context, eventType string, fromTime, toTime int64) ([]*domain.Event, error) {
	return nil, nil
}
func (r *lifecycleTestEventRepo) ListByDateRange(ctx context.Context, fromTime, toTime int64) ([]*domain.Event, error) {
	return nil, nil
}
func (r *lifecycleTestEventRepo) ListBySubscription(ctx context.Context, subscriptionID string, limit int) ([]*domain.Event, error) {
	return nil, nil
}
func (r *lifecycleTestEventRepo) ListRecent(ctx context.Context, limit int) ([]*domain.Event, error) { return nil, nil }
func (r *lifecycleTestEventRepo) GetByID(ctx context.Context, id string) (*domain.Event, error) { return nil, nil }

type lifecycleTestStore struct {
	completedFirstChargeCalls int
	completeRenewalCalls      int
	applyUpgradeCalls         int
	scheduleDowngradeCalls    int

	completed struct {
		subscription  *domain.Subscription
		authorization *domain.Authorization
		charge        *domain.Charge
		event         *domain.Event
	}
	renewal struct {
		subscription  *domain.Subscription
		authorization *domain.Authorization
		charge        *domain.Charge
		event         *domain.Event
	}
	upgrade struct {
		subscription *domain.Subscription
		charge       *domain.Charge
		event        *domain.Event
	}
	downgrade struct {
		subscription *domain.Subscription
		event        *domain.Event
	}

	firstChargeErr error
	renewalErr     error
	upgradeErr     error
	downgradeErr   error
}

func (s *lifecycleTestStore) CreateInitialState(subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, event *domain.Event) error {
	return nil
}

func (s *lifecycleTestStore) CompleteFirstCharge(subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, event *domain.Event) error {
	if s.firstChargeErr != nil {
		return s.firstChargeErr
	}
	s.completedFirstChargeCalls++
	subCopy := *subscription
	authCopy := *authorization
	chargeCopy := *charge
	eventCopy := *event
	s.completed.subscription = &subCopy
	s.completed.authorization = &authCopy
	s.completed.charge = &chargeCopy
	s.completed.event = &eventCopy
	return nil
}

func (s *lifecycleTestStore) CompleteRenewal(subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, event *domain.Event) error {
	if s.renewalErr != nil {
		return s.renewalErr
	}
	s.completeRenewalCalls++
	subCopy := *subscription
	authCopy := *authorization
	chargeCopy := *charge
	eventCopy := *event
	s.renewal.subscription = &subCopy
	s.renewal.authorization = &authCopy
	s.renewal.charge = &chargeCopy
	s.renewal.event = &eventCopy
	return nil
}

func (s *lifecycleTestStore) ApplyImmediateUpgrade(subscription *domain.Subscription, charge *domain.Charge, event *domain.Event) error {
	if s.upgradeErr != nil {
		return s.upgradeErr
	}
	s.applyUpgradeCalls++
	subCopy := *subscription
	chargeCopy := *charge
	eventCopy := *event
	s.upgrade.subscription = &subCopy
	s.upgrade.charge = &chargeCopy
	s.upgrade.event = &eventCopy
	return nil
}

func (s *lifecycleTestStore) ScheduleDowngrade(subscription *domain.Subscription, event *domain.Event) error {
	if s.downgradeErr != nil {
		return s.downgradeErr
	}
	s.scheduleDowngradeCalls++
	subCopy := *subscription
	eventCopy := *event
	s.downgrade.subscription = &subCopy
	s.downgrade.event = &eventCopy
	return nil
}

type lifecycleTestXray struct {
	addCalls    int
	removeCalls int
	addErr      error
	removeErr   error
}

func (x *lifecycleTestXray) AddUser(ctx context.Context, email, uuid string) error {
	x.addCalls++
	return x.addErr
}

func (x *lifecycleTestXray) RemoveUser(ctx context.Context, email string) error {
	x.removeCalls++
	return x.removeErr
}

func TestSubscriptionLifecycleServiceCancelSubscription(t *testing.T) {
	t.Run("active subscription cancels and writes event", func(t *testing.T) {
		subscriptions := &lifecycleTestSubscriptionRepo{}
		events := &lifecycleTestEventRepo{}
		xraySync := &lifecycleTestXray{}
		service := NewSubscriptionLifecycleService(
			subscriptions,
			&lifecycleTestAuthorizationRepo{},
			&lifecycleTestChargeRepo{},
			events,
			&lifecycleTestStore{},
			xraySync,
		)

		subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Status: domain.SubscriptionActive, AutoRenew: true}
		if err := service.CancelSubscription(subscription); err != nil {
			t.Fatalf("CancelSubscription returned error: %v", err)
		}
		if subscriptions.updateCalls != 1 {
			t.Fatalf("expected one update, got %d", subscriptions.updateCalls)
		}
		if subscriptions.updated == nil || subscriptions.updated.Status != domain.SubscriptionCancelled {
			t.Fatalf("expected cancelled subscription, got %+v", subscriptions.updated)
		}
		if subscriptions.updated.AutoRenew {
			t.Fatal("expected AutoRenew to be false")
		}
		if events.createCalls != 2 {
			t.Fatalf("expected two events, got %d", events.createCalls)
		}
		if xraySync.removeCalls != 1 {
			t.Fatalf("expected one Xray remove, got %d", xraySync.removeCalls)
		}
		if !strings.Contains(events.events[0].Metadata, `"subscription_id":"sub_1"`) || !strings.Contains(events.events[0].Metadata, `"status":"cancelled"`) || !strings.Contains(events.events[0].Metadata, `"lifecycle_action":"cancel"`) {
			t.Fatalf("unexpected metadata: %s", events.events[0].Metadata)
		}
	})

	t.Run("non-active subscription is rejected without writes", func(t *testing.T) {
		subscriptions := &lifecycleTestSubscriptionRepo{}
		events := &lifecycleTestEventRepo{}
		xraySync := &lifecycleTestXray{}
		service := NewSubscriptionLifecycleService(
			subscriptions,
			&lifecycleTestAuthorizationRepo{},
			&lifecycleTestChargeRepo{},
			events,
			&lifecycleTestStore{},
			xraySync,
		)

		subscription := &domain.Subscription{ID: "sub_1", Status: domain.SubscriptionPending, AutoRenew: true}
		err := service.CancelSubscription(subscription)
		if err == nil || !strings.Contains(err.Error(), "invalid subscription transition") {
			t.Fatalf("unexpected error: %v", err)
		}
		if subscriptions.updateCalls != 0 {
			t.Fatalf("expected no updates, got %d", subscriptions.updateCalls)
		}
		if events.createCalls != 0 {
			t.Fatalf("expected no events, got %d", events.createCalls)
		}
		if xraySync.removeCalls != 0 {
			t.Fatalf("expected no Xray calls, got %d", xraySync.removeCalls)
		}
	})
}

func TestSubscriptionLifecycleServiceExpireSubscription(t *testing.T) {
	t.Run("active subscription expires and writes event", func(t *testing.T) {
		subscriptions := &lifecycleTestSubscriptionRepo{}
		events := &lifecycleTestEventRepo{}
		xraySync := &lifecycleTestXray{}
		service := NewSubscriptionLifecycleService(
			subscriptions,
			&lifecycleTestAuthorizationRepo{},
			&lifecycleTestChargeRepo{},
			events,
			&lifecycleTestStore{},
			xraySync,
		)

		subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Status: domain.SubscriptionActive}
		if err := service.ExpireSubscription(subscription, "expired for test"); err != nil {
			t.Fatalf("ExpireSubscription returned error: %v", err)
		}
		if subscriptions.updateCalls != 1 {
			t.Fatalf("expected one update, got %d", subscriptions.updateCalls)
		}
		if subscriptions.updated == nil || subscriptions.updated.Status != domain.SubscriptionExpired {
			t.Fatalf("expected expired subscription, got %+v", subscriptions.updated)
		}
		if events.createCalls != 2 {
			t.Fatalf("expected two events, got %d", events.createCalls)
		}
		if xraySync.removeCalls != 1 {
			t.Fatalf("expected one Xray remove, got %d", xraySync.removeCalls)
		}
		if !strings.Contains(events.events[0].Metadata, `"subscription_id":"sub_1"`) || !strings.Contains(events.events[0].Metadata, `"status":"expired"`) || !strings.Contains(events.events[0].Metadata, `"lifecycle_action":"expire"`) {
			t.Fatalf("unexpected metadata: %s", events.events[0].Metadata)
		}
	})

	t.Run("non-active subscription is rejected without writes", func(t *testing.T) {
		subscriptions := &lifecycleTestSubscriptionRepo{}
		events := &lifecycleTestEventRepo{}
		xraySync := &lifecycleTestXray{}
		service := NewSubscriptionLifecycleService(
			subscriptions,
			&lifecycleTestAuthorizationRepo{},
			&lifecycleTestChargeRepo{},
			events,
			&lifecycleTestStore{},
			xraySync,
		)

		subscription := &domain.Subscription{ID: "sub_1", Status: domain.SubscriptionPending}
		err := service.ExpireSubscription(subscription, "already pending")
		if err == nil || !strings.Contains(err.Error(), "invalid subscription transition") {
			t.Fatalf("unexpected error: %v", err)
		}
		if subscriptions.updateCalls != 0 {
			t.Fatalf("expected no updates, got %d", subscriptions.updateCalls)
		}
		if events.createCalls != 0 {
			t.Fatalf("expected no events, got %d", events.createCalls)
		}
		if xraySync.removeCalls != 0 {
			t.Fatalf("expected no Xray calls, got %d", xraySync.removeCalls)
		}
	})
}

func TestSubscriptionLifecycleServiceApplyRenewalSuccess(t *testing.T) {
	t.Run("active renewal calls transaction method then xray", func(t *testing.T) {
		store := &lifecycleTestStore{}
		xraySync := &lifecycleTestXray{}
		service := NewSubscriptionLifecycleService(
			&lifecycleTestSubscriptionRepo{},
			&lifecycleTestAuthorizationRepo{},
			&lifecycleTestChargeRepo{},
			&lifecycleTestEventRepo{},
			store,
			xraySync,
		)

		subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_old", Status: domain.SubscriptionActive, CurrentAuthorizationID: "auth_1", CurrentPeriodStart: 1000, CurrentPeriodEnd: 2000}
		authorization := &domain.Authorization{ID: "auth_1", RemainingAllowance: 5000}
		plan := &domain.Plan{PlanID: "plan_old", Name: "Basic", PeriodSeconds: 3600, AmountUSDCBaseUnits: 300}

		if err := service.ApplyRenewalSuccess(subscription, authorization, plan, "charge_record_1", "charge_1"); err != nil {
			t.Fatalf("ApplyRenewalSuccess returned error: %v", err)
		}
		if store.completeRenewalCalls != 1 {
			t.Fatalf("expected one renewal transaction call, got %d", store.completeRenewalCalls)
		}
		if store.renewal.subscription == nil || store.renewal.authorization == nil || store.renewal.charge == nil || store.renewal.event == nil {
			t.Fatal("expected renewal transaction payloads")
		}
		if store.renewal.subscription.LastChargeID != "charge_1" {
			t.Fatalf("unexpected last charge id: %s", store.renewal.subscription.LastChargeID)
		}
		if store.renewal.authorization.RemainingAllowance != 4700 {
			t.Fatalf("unexpected remaining allowance: %d", store.renewal.authorization.RemainingAllowance)
		}
		if !strings.Contains(store.renewal.event.Metadata, `"subscription_id":"sub_1"`) || !strings.Contains(store.renewal.event.Metadata, `"charge_record_id":"charge_record_1"`) || !strings.Contains(store.renewal.event.Metadata, `"lifecycle_action":"renewal_success"`) || !strings.Contains(store.renewal.event.Metadata, `"previous_plan_id":"plan_old"`) || !strings.Contains(store.renewal.event.Metadata, `"plan_id":"plan_old"`) {
			t.Fatalf("unexpected renewal metadata: %s", store.renewal.event.Metadata)
		}
		if xraySync.addCalls != 1 {
			t.Fatalf("expected one Xray add, got %d", xraySync.addCalls)
		}
	})

	t.Run("transaction failure does not trigger xray", func(t *testing.T) {
		store := &lifecycleTestStore{renewalErr: errors.New("tx failed")}
		xraySync := &lifecycleTestXray{}
		service := NewSubscriptionLifecycleService(
			&lifecycleTestSubscriptionRepo{},
			&lifecycleTestAuthorizationRepo{},
			&lifecycleTestChargeRepo{},
			&lifecycleTestEventRepo{},
			store,
			xraySync,
		)

		subscription := &domain.Subscription{ID: "sub_1", Status: domain.SubscriptionActive, CurrentPeriodEnd: 2000}
		authorization := &domain.Authorization{ID: "auth_1", RemainingAllowance: 5000}
		plan := &domain.Plan{PlanID: "plan_old", Name: "Basic", PeriodSeconds: 3600, AmountUSDCBaseUnits: 300}

		err := service.ApplyRenewalSuccess(subscription, authorization, plan, "charge_record_1", "charge_1")
		if err == nil || !strings.Contains(err.Error(), "persist renewal success") {
			t.Fatalf("unexpected error: %v", err)
		}
		if xraySync.addCalls != 0 {
			t.Fatalf("expected no Xray add, got %d", xraySync.addCalls)
		}
	})

	t.Run("non-active subscription is rejected", func(t *testing.T) {
		service := NewSubscriptionLifecycleService(
			&lifecycleTestSubscriptionRepo{},
			&lifecycleTestAuthorizationRepo{},
			&lifecycleTestChargeRepo{},
			&lifecycleTestEventRepo{},
			&lifecycleTestStore{},
			&lifecycleTestXray{},
		)

		subscription := &domain.Subscription{ID: "sub_1", Status: domain.SubscriptionPending}
		authorization := &domain.Authorization{ID: "auth_1", RemainingAllowance: 5000}
		plan := &domain.Plan{PlanID: "plan_old", Name: "Basic", PeriodSeconds: 3600, AmountUSDCBaseUnits: 300}

		err := service.ApplyRenewalSuccess(subscription, authorization, plan, "charge_record_1", "charge_1")
		if err == nil || !strings.Contains(err.Error(), "renewal requires active subscription") {
			t.Fatalf("unexpected error: %v", err)
		}
	})
}

func TestSubscriptionLifecycleServiceApplyImmediateUpgrade(t *testing.T) {
	t.Run("active upgrade uses transaction method and no xray side effect", func(t *testing.T) {
		store := &lifecycleTestStore{}
		xraySync := &lifecycleTestXray{}
		service := NewSubscriptionLifecycleService(
			&lifecycleTestSubscriptionRepo{},
			&lifecycleTestAuthorizationRepo{},
			&lifecycleTestChargeRepo{},
			&lifecycleTestEventRepo{},
			store,
			xraySync,
		)

		subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "old_plan", Status: domain.SubscriptionActive, CurrentAuthorizationID: "auth_1"}
		oldPlan := &domain.Plan{PlanID: "old_plan", Name: "Old"}
		newPlan := &domain.Plan{PlanID: "new_plan", Name: "New"}

		if err := service.ApplyImmediateUpgrade(subscription, oldPlan, newPlan, 123); err != nil {
			t.Fatalf("ApplyImmediateUpgrade returned error: %v", err)
		}
		if store.applyUpgradeCalls != 1 {
			t.Fatalf("expected one upgrade transaction call, got %d", store.applyUpgradeCalls)
		}
		if store.upgrade.subscription == nil || store.upgrade.charge == nil || store.upgrade.event == nil {
			t.Fatal("expected upgrade transaction payloads")
		}
		if store.upgrade.subscription.PlanID != "new_plan" {
			t.Fatalf("unexpected updated plan: %s", store.upgrade.subscription.PlanID)
		}
		if !strings.Contains(store.upgrade.event.Metadata, `"subscription_id":"sub_1"`) || !strings.Contains(store.upgrade.event.Metadata, `"old_plan_id":"old_plan"`) || !strings.Contains(store.upgrade.event.Metadata, `"new_plan_id":"new_plan"`) || !strings.Contains(store.upgrade.event.Metadata, `"lifecycle_action":"upgrade"`) {
			t.Fatalf("unexpected upgrade metadata: %s", store.upgrade.event.Metadata)
		}
		if xraySync.addCalls != 0 && xraySync.removeCalls != 0 {
			t.Fatal("expected no Xray calls for upgrade")
		}
	})

	t.Run("transaction failure does not produce xray side effect", func(t *testing.T) {
		store := &lifecycleTestStore{upgradeErr: errors.New("tx failed")}
		xraySync := &lifecycleTestXray{}
		service := NewSubscriptionLifecycleService(
			&lifecycleTestSubscriptionRepo{},
			&lifecycleTestAuthorizationRepo{},
			&lifecycleTestChargeRepo{},
			&lifecycleTestEventRepo{},
			store,
			xraySync,
		)

		err := service.ApplyImmediateUpgrade(&domain.Subscription{ID: "sub_1", Status: domain.SubscriptionActive}, &domain.Plan{PlanID: "old_plan"}, &domain.Plan{PlanID: "new_plan"}, 100)
		if err == nil || !strings.Contains(err.Error(), "persist immediate upgrade") {
			t.Fatalf("unexpected error: %v", err)
		}
		if xraySync.addCalls != 0 || xraySync.removeCalls != 0 {
			t.Fatal("expected no Xray calls")
		}
	})
}

func TestSubscriptionLifecycleServiceScheduleDowngrade(t *testing.T) {
	t.Run("active downgrade uses transaction method and keeps xray noop", func(t *testing.T) {
		store := &lifecycleTestStore{}
		xraySync := &lifecycleTestXray{}
		service := NewSubscriptionLifecycleService(
			&lifecycleTestSubscriptionRepo{},
			&lifecycleTestAuthorizationRepo{},
			&lifecycleTestChargeRepo{},
			&lifecycleTestEventRepo{},
			store,
			xraySync,
		)

		subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "old_plan", Status: domain.SubscriptionActive, CurrentPeriodEnd: 9000}
		oldPlan := &domain.Plan{PlanID: "old_plan", Name: "Old"}
		newPlan := &domain.Plan{PlanID: "new_plan", Name: "New"}

		if err := service.ScheduleDowngrade(subscription, oldPlan, newPlan); err != nil {
			t.Fatalf("ScheduleDowngrade returned error: %v", err)
		}
		if store.scheduleDowngradeCalls != 1 {
			t.Fatalf("expected one downgrade transaction call, got %d", store.scheduleDowngradeCalls)
		}
		if store.downgrade.subscription == nil || store.downgrade.subscription.PendingPlanID != "new_plan" {
			t.Fatalf("unexpected downgrade subscription payload: %+v", store.downgrade.subscription)
		}
		if !strings.Contains(store.downgrade.event.Metadata, `"subscription_id":"sub_1"`) || !strings.Contains(store.downgrade.event.Metadata, `"old_plan_id":"old_plan"`) || !strings.Contains(store.downgrade.event.Metadata, `"new_plan_id":"new_plan"`) || !strings.Contains(store.downgrade.event.Metadata, `"lifecycle_action":"schedule_downgrade"`) {
			t.Fatalf("unexpected downgrade metadata: %s", store.downgrade.event.Metadata)
		}
		if xraySync.addCalls != 0 || xraySync.removeCalls != 0 {
			t.Fatal("expected no Xray calls for scheduled downgrade")
		}
	})

	t.Run("transaction failure does not produce xray side effect", func(t *testing.T) {
		store := &lifecycleTestStore{downgradeErr: errors.New("tx failed")}
		xraySync := &lifecycleTestXray{}
		service := NewSubscriptionLifecycleService(
			&lifecycleTestSubscriptionRepo{},
			&lifecycleTestAuthorizationRepo{},
			&lifecycleTestChargeRepo{},
			&lifecycleTestEventRepo{},
			store,
			xraySync,
		)

		err := service.ScheduleDowngrade(&domain.Subscription{ID: "sub_1", Status: domain.SubscriptionActive}, &domain.Plan{PlanID: "old_plan"}, &domain.Plan{PlanID: "new_plan"})
		if err == nil || !strings.Contains(err.Error(), "persist scheduled downgrade") {
			t.Fatalf("unexpected error: %v", err)
		}
		if xraySync.addCalls != 0 || xraySync.removeCalls != 0 {
			t.Fatal("expected no Xray calls")
		}
	})
}
