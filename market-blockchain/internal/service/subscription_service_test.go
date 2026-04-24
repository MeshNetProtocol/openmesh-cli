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
func (r *testPlanRepo) GetByPlanID(ctx context.Context, planID string) (*domain.Plan, error) {
	if r.err != nil {
		return nil, r.err
	}
	if r.plan != nil && r.plan.PlanID == planID {
		return r.plan, nil
	}
	return nil, nil
}
func (r *testPlanRepo) ListActive(ctx context.Context) ([]*domain.Plan, error) { return nil, nil }
func (r *testPlanRepo) ListAll(ctx context.Context) ([]*domain.Plan, error) { return nil, nil }

type testSubscriptionRepo struct {
	byIdentityPlan *domain.Subscription
	err            error
}

func (r *testSubscriptionRepo) Create(subscription *domain.Subscription) error { return nil }
func (r *testSubscriptionRepo) Update(subscription *domain.Subscription) error { return nil }
func (r *testSubscriptionRepo) GetByID(ctx context.Context, id string) (*domain.Subscription, error) { return nil, nil }
func (r *testSubscriptionRepo) GetByIdentityAndPlan(ctx context.Context, identityAddress, planID string) (*domain.Subscription, error) {
	if r.err != nil {
		return nil, r.err
	}
	return r.byIdentityPlan, nil
}
func (r *testSubscriptionRepo) ListRenewable(ctx context.Context, now int64) ([]*domain.Subscription, error) {
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
func (r *testAuthorizationRepo) GetByID(ctx context.Context, id string) (*domain.Authorization, error) {
	return nil, nil
}

func (r *testAuthorizationRepo) GetByIdentityAndPlan(ctx context.Context, identityAddress, planID string) (*domain.Authorization, error) {
	return nil, nil
}

type testChargeRepo struct{}

func (r *testChargeRepo) Create(charge *domain.Charge) error { return nil }
func (r *testChargeRepo) Update(charge *domain.Charge) error { return nil }
func (r *testChargeRepo) GetByID(ctx context.Context, id string) (*domain.Charge, error) { return nil, nil }
func (r *testChargeRepo) GetByChargeID(ctx context.Context, chargeID string) (*domain.Charge, error) { return nil, nil }
func (r *testChargeRepo) ListByIdentity(ctx context.Context, identityAddress string) ([]*domain.Charge, error) {
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
	result *CreatePendingSubscriptionResult
	err    error
}

func (c *captureCreator) CreatePendingSubscription(ctx context.Context, input CreatePendingSubscriptionInput) (*CreatePendingSubscriptionResult, error) {
	if c.err != nil {
		return nil, c.err
	}
	if c.result != nil {
		return c.result, nil
	}
	return &CreatePendingSubscriptionResult{
		Subscription: &domain.Subscription{ID: input.SubscriptionID, CurrentAuthorizationID: input.AuthorizationID, Status: domain.SubscriptionPending},
		Authorization: &domain.Authorization{ID: input.AuthorizationID},
		InitialCharge: &domain.Charge{ID: input.ChargeRecordID, SubscriptionID: input.SubscriptionID, AuthorizationID: input.AuthorizationID},
	}, nil
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
	creator := &captureCreator{
		result: &CreatePendingSubscriptionResult{
			Subscription:  &domain.Subscription{ID: "sub_1", CurrentAuthorizationID: "auth_1", Status: domain.SubscriptionPending},
			Authorization: &domain.Authorization{ID: "auth_1"},
			InitialCharge: &domain.Charge{ID: "charge_record_1", SubscriptionID: "sub_1", AuthorizationID: "auth_1"},
		},
	}
	service := NewSubscriptionService(
		&testPlanRepo{plan: plan},
		&testSubscriptionRepo{},
		creator,
	)

	result, err := service.CreateSubscription(context.Background(), CreateSubscriptionInput{
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
	if result.Subscription == nil || result.Authorization == nil || result.InitialCharge == nil {
		t.Fatal("expected all records to be returned")
	}
	if result.Subscription.ID != "sub_1" {
		t.Fatalf("unexpected subscription id: %s", result.Subscription.ID)
	}
	if result.Subscription.CurrentAuthorizationID != "auth_1" {
		t.Fatalf("unexpected current authorization id: %s", result.Subscription.CurrentAuthorizationID)
	}
	if result.Subscription.Status != domain.SubscriptionPending {
		t.Fatalf("unexpected subscription status: %s", result.Subscription.Status)
	}
	if result.InitialCharge.SubscriptionID != "sub_1" || result.InitialCharge.AuthorizationID != "auth_1" {
		t.Fatalf("charge not linked to subscription/auth: %+v", result.InitialCharge)
	}
	if result.Subscription.ID != "sub_1" || result.Authorization.ID != "auth_1" || result.InitialCharge.ID != "charge_record_1" {
		t.Fatal("returned objects do not match expected lifecycle output")
	}
}

func TestCreateSubscriptionRollsUpPersistenceError(t *testing.T) {
	service := NewSubscriptionService(
		&testPlanRepo{plan: &domain.Plan{PlanID: "basic", PeriodSeconds: 60, AmountUSDCBaseUnits: 100, AuthorizationPeriods: 1, Active: true}},
		&testSubscriptionRepo{},
		&captureCreator{err: errors.New("boom")},
	)

	_, err := service.CreateSubscription(context.Background(), CreateSubscriptionInput{
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
	if got := err.Error(); got != "boom" {
		t.Fatalf("unexpected error: %s", got)
	}
}
