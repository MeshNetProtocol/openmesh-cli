package service

import (
	"context"
	"errors"
	"testing"

	"market-blockchain/internal/domain"
)

type testPlanRepo struct {
	plan *domain.Plan
	err  error
}

func (r *testPlanRepo) Create(plan *domain.Plan) error { return nil }
func (r *testPlanRepo) Update(plan *domain.Plan) error { return nil }
func (r *testPlanRepo) GetByPlanID(planID string) (*domain.Plan, error) {
	if r.err != nil {
		return nil, r.err
	}
	if r.plan != nil && r.plan.PlanID == planID {
		return r.plan, nil
	}
	return nil, nil
}
func (r *testPlanRepo) ListActive() ([]*domain.Plan, error) { return nil, nil }
func (r *testPlanRepo) ListAll(ctx context.Context) ([]*domain.Plan, error) { return nil, nil }

type testSubscriptionRepo struct {
	byIdentityPlan *domain.Subscription
	err            error
}

func (r *testSubscriptionRepo) Create(subscription *domain.Subscription) error { return nil }
func (r *testSubscriptionRepo) Update(subscription *domain.Subscription) error { return nil }
func (r *testSubscriptionRepo) GetByID(id string) (*domain.Subscription, error) { return nil, nil }
func (r *testSubscriptionRepo) GetByIdentityAndPlan(identityAddress, planID string) (*domain.Subscription, error) {
	if r.err != nil {
		return nil, r.err
	}
	return r.byIdentityPlan, nil
}
func (r *testSubscriptionRepo) ListRenewable(now int64) ([]*domain.Subscription, error) {
	return nil, nil
}
func (r *testSubscriptionRepo) ListByStatus(ctx context.Context, status string, limit, offset int) ([]*domain.Subscription, error) {
	return nil, nil
}
func (r *testSubscriptionRepo) ListAll(ctx context.Context, limit, offset int) ([]*domain.Subscription, error) {
	return nil, nil
}
func (r *testSubscriptionRepo) CountByStatus(ctx context.Context, status string) (int, error) {
	return 0, nil
}
func (r *testSubscriptionRepo) CountAll(ctx context.Context) (int, error) { return 0, nil }
func (r *testSubscriptionRepo) CountByPlanAndStatus(ctx context.Context, planID, status string) (int, error) {
	return 0, nil
}
func (r *testSubscriptionRepo) SearchByAddress(ctx context.Context, address string) ([]*domain.Subscription, error) {
	return nil, nil
}

type testAuthorizationRepo struct{}

func (r *testAuthorizationRepo) Create(authorization *domain.Authorization) error { return nil }
func (r *testAuthorizationRepo) Update(authorization *domain.Authorization) error { return nil }
func (r *testAuthorizationRepo) GetByIdentityAndPlan(identityAddress, planID string) (*domain.Authorization, error) {
	return nil, nil
}

type testChargeRepo struct{}

func (r *testChargeRepo) Create(charge *domain.Charge) error { return nil }
func (r *testChargeRepo) Update(charge *domain.Charge) error { return nil }
func (r *testChargeRepo) GetByChargeID(chargeID string) (*domain.Charge, error) { return nil, nil }
func (r *testChargeRepo) ListByIdentity(identityAddress string) ([]*domain.Charge, error) {
	return nil, nil
}
func (r *testChargeRepo) ListByStatusAndDateRange(ctx context.Context, status string, fromTime, toTime int64) ([]*domain.Charge, error) {
	return nil, nil
}
func (r *testChargeRepo) ListByDateRange(ctx context.Context, fromTime, toTime int64) ([]*domain.Charge, error) {
	return nil, nil
}
func (r *testChargeRepo) ListBySubscription(ctx context.Context, subscriptionID string) ([]*domain.Charge, error) {
	return nil, nil
}
func (r *testChargeRepo) SumCompletedCharges(ctx context.Context, fromTime, toTime int64) (int64, error) {
	return 0, nil
}
func (r *testChargeRepo) CountAndSumByStatus(ctx context.Context, status string) (int, int64, error) {
	return 0, 0, nil
}

type captureCreator struct {
	subscription  *domain.Subscription
	authorization *domain.Authorization
	charge        *domain.Charge
	event         *domain.Event
	err           error
}

func (c *captureCreator) CreateInitialState(subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, event *domain.Event) error {
	if c.err != nil {
		return c.err
	}
	c.subscription = subscription
	c.authorization = authorization
	c.charge = charge
	c.event = event
	return nil
}

func TestCreateSubscriptionPersistsInitialState(t *testing.T) {
	plan := &domain.Plan{
		PlanID:                   "basic-monthly",
		PeriodSeconds:            3600,
		AmountUSDCBaseUnits:      100,
		AuthorizationPeriods:     3,
		TotalAuthorizationAmount: 300,
		Active:                   true,
	}
	creator := &captureCreator{}
	service := NewSubscriptionService(
		&testPlanRepo{plan: plan},
		&testSubscriptionRepo{},
		&testAuthorizationRepo{},
		&testChargeRepo{},
		creator,
	)

	result, err := service.CreateSubscription(CreateSubscriptionInput{
		SubscriptionID:    "sub_1",
		AuthorizationID:   "auth_1",
		ChargeRecordID:    "charge_record_1",
		IdentityAddress:   "identity_1",
		PayerAddress:      "payer_1",
		PlanID:            "basic-monthly",
		ExpectedAllowance: 1000,
		TargetAllowance:   2000,
		PermitDeadline:    123456,
		InitialChargeID:   "charge_1",
	})
	if err != nil {
		t.Fatalf("CreateSubscription returned error: %v", err)
	}
	if result == nil {
		t.Fatal("expected result")
	}
	if creator.subscription == nil || creator.authorization == nil || creator.charge == nil || creator.event == nil {
		t.Fatal("expected all records to be persisted")
	}
	if creator.subscription.ID != "sub_1" {
		t.Fatalf("unexpected subscription id: %s", creator.subscription.ID)
	}
	if creator.subscription.CurrentAuthorizationID != "auth_1" {
		t.Fatalf("unexpected current authorization id: %s", creator.subscription.CurrentAuthorizationID)
	}
	if creator.subscription.Status != domain.SubscriptionPending {
		t.Fatalf("unexpected subscription status: %s", creator.subscription.Status)
	}
	if creator.charge.SubscriptionID != "sub_1" || creator.charge.AuthorizationID != "auth_1" {
		t.Fatalf("charge not linked to subscription/auth: %+v", creator.charge)
	}
	if creator.event.Type != domain.EventFirstSubscribe {
		t.Fatalf("unexpected event type: %s", creator.event.Type)
	}
	if creator.event.Metadata == "" {
		t.Fatal("expected event metadata")
	}
	if result.Subscription.ID != creator.subscription.ID || result.Authorization.ID != creator.authorization.ID || result.InitialCharge.ID != creator.charge.ID {
		t.Fatal("returned objects do not match persisted objects")
	}
}

func TestCreateSubscriptionRollsUpPersistenceError(t *testing.T) {
	service := NewSubscriptionService(
		&testPlanRepo{plan: &domain.Plan{PlanID: "basic", PeriodSeconds: 60, AmountUSDCBaseUnits: 100, AuthorizationPeriods: 1, Active: true}},
		&testSubscriptionRepo{},
		&testAuthorizationRepo{},
		&testChargeRepo{},
		&captureCreator{err: errors.New("boom")},
	)

	_, err := service.CreateSubscription(CreateSubscriptionInput{
		SubscriptionID:    "sub_1",
		AuthorizationID:   "auth_1",
		ChargeRecordID:    "charge_record_1",
		IdentityAddress:   "identity_1",
		PayerAddress:      "payer_1",
		PlanID:            "basic",
		ExpectedAllowance: 100,
		TargetAllowance:   100,
		PermitDeadline:    123,
		InitialChargeID:   "charge_1",
	})
	if err == nil {
		t.Fatal("expected error")
	}
	if got := err.Error(); got != "persist subscription creation: boom" {
		t.Fatalf("unexpected error: %s", got)
	}
}
