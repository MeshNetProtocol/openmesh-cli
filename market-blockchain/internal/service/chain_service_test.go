package service

import (
	"context"
	"errors"
	"math/big"
	"strings"
	"testing"

	"github.com/ethereum/go-ethereum/common"

	"market-blockchain/internal/blockchain"
	"market-blockchain/internal/domain"
)

type testChainContract struct {
	authorizeTxHash string
	chargeTxHash    string
	authorizeErr    error
	chargeErr       error
}

func (c *testChainContract) AuthorizeChargeWithPermit(ctx context.Context, identity common.Address, payer common.Address, expectedAllowance *big.Int, targetAllowance *big.Int, deadline *big.Int, sig blockchain.PermitSignature) (string, error) {
	if c.authorizeErr != nil {
		return "", c.authorizeErr
	}
	return c.authorizeTxHash, nil
}

func (c *testChainContract) Charge(ctx context.Context, chargeID [32]byte, identity common.Address, amount *big.Int) (string, error) {
	if c.chargeErr != nil {
		return "", c.chargeErr
	}
	return c.chargeTxHash, nil
}

type testActivationSubscriptionRepo struct {
	subscription *domain.Subscription
	err          error
}

func (r *testActivationSubscriptionRepo) Create(subscription *domain.Subscription) error { return nil }
func (r *testActivationSubscriptionRepo) Update(subscription *domain.Subscription) error { return nil }
func (r *testActivationSubscriptionRepo) GetByID(id string) (*domain.Subscription, error) {
	if r.err != nil {
		return nil, r.err
	}
	if r.subscription != nil && r.subscription.ID == id {
		return r.subscription, nil
	}
	return nil, nil
}
func (r *testActivationSubscriptionRepo) GetByIdentityAndPlan(identityAddress, planID string) (*domain.Subscription, error) {
	return nil, nil
}
func (r *testActivationSubscriptionRepo) ListRenewable(now int64) ([]*domain.Subscription, error) {
	return nil, nil
}
func (r *testActivationSubscriptionRepo) ListByStatus(ctx context.Context, status string, limit, offset int) ([]*domain.Subscription, error) {
	return nil, nil
}
func (r *testActivationSubscriptionRepo) ListAll(ctx context.Context, limit, offset int) ([]*domain.Subscription, error) {
	return nil, nil
}
func (r *testActivationSubscriptionRepo) CountByStatus(ctx context.Context, status string) (int, error) {
	return 0, nil
}
func (r *testActivationSubscriptionRepo) CountAll(ctx context.Context) (int, error) { return 0, nil }
func (r *testActivationSubscriptionRepo) CountByPlanAndStatus(ctx context.Context, planID, status string) (int, error) {
	return 0, nil
}
func (r *testActivationSubscriptionRepo) SearchByAddress(ctx context.Context, address string) ([]*domain.Subscription, error) {
	return nil, nil
}

type testActivationAuthorizationRepo struct {
	authorization *domain.Authorization
	updated       *domain.Authorization
	getErr        error
	updateErr     error
}

func (r *testActivationAuthorizationRepo) Create(authorization *domain.Authorization) error { return nil }
func (r *testActivationAuthorizationRepo) Update(authorization *domain.Authorization) error {
	if r.updateErr != nil {
		return r.updateErr
	}
	r.updated = authorization
	return nil
}
func (r *testActivationAuthorizationRepo) GetByID(id string) (*domain.Authorization, error) {
	if r.getErr != nil {
		return nil, r.getErr
	}
	if r.authorization != nil && r.authorization.ID == id {
		return r.authorization, nil
	}
	return nil, nil
}
func (r *testActivationAuthorizationRepo) GetByIdentityAndPlan(identityAddress, planID string) (*domain.Authorization, error) {
	return nil, nil
}

type testActivationChargeRepo struct {
	charge    *domain.Charge
	updated   *domain.Charge
	getErr    error
	updateErr error
}

func (r *testActivationChargeRepo) Create(charge *domain.Charge) error { return nil }
func (r *testActivationChargeRepo) Update(charge *domain.Charge) error {
	if r.updateErr != nil {
		return r.updateErr
	}
	r.updated = charge
	return nil
}
func (r *testActivationChargeRepo) GetByID(id string) (*domain.Charge, error) {
	if r.getErr != nil {
		return nil, r.getErr
	}
	if r.charge != nil && r.charge.ID == id {
		return r.charge, nil
	}
	return nil, nil
}
func (r *testActivationChargeRepo) GetByChargeID(chargeID string) (*domain.Charge, error) { return nil, nil }
func (r *testActivationChargeRepo) ListByIdentity(identityAddress string) ([]*domain.Charge, error) {
	return nil, nil
}
func (r *testActivationChargeRepo) ListByStatusAndDateRange(ctx context.Context, status string, fromTime, toTime int64) ([]*domain.Charge, error) {
	return nil, nil
}
func (r *testActivationChargeRepo) ListByDateRange(ctx context.Context, fromTime, toTime int64) ([]*domain.Charge, error) {
	return nil, nil
}
func (r *testActivationChargeRepo) ListBySubscription(ctx context.Context, subscriptionID string) ([]*domain.Charge, error) {
	return nil, nil
}
func (r *testActivationChargeRepo) SumCompletedCharges(ctx context.Context, fromTime, toTime int64) (int64, error) {
	return 0, nil
}
func (r *testActivationChargeRepo) CountAndSumByStatus(ctx context.Context, status string) (int, int64, error) {
	return 0, 0, nil
}

type noopEventRepo struct{}

func (r *noopEventRepo) Create(event *domain.Event) error { return nil }
func (r *noopEventRepo) ListByIdentity(identityAddress string) ([]*domain.Event, error) { return nil, nil }
func (r *noopEventRepo) ListByTypeAndDateRange(ctx context.Context, eventType string, fromTime, toTime int64) ([]*domain.Event, error) {
	return nil, nil
}
func (r *noopEventRepo) ListByDateRange(ctx context.Context, fromTime, toTime int64) ([]*domain.Event, error) {
	return nil, nil
}
func (r *noopEventRepo) ListBySubscription(ctx context.Context, subscriptionID string, limit int) ([]*domain.Event, error) {
	return nil, nil
}
func (r *noopEventRepo) ListRecent(ctx context.Context, limit int) ([]*domain.Event, error) { return nil, nil }
func (r *noopEventRepo) GetByID(ctx context.Context, id string) (*domain.Event, error) { return nil, nil }

type captureFirstChargeCompleter struct {
	subscription *domain.Subscription
	authorization *domain.Authorization
	charge       *domain.Charge
	event        *domain.Event
	err          error
}

func (c *captureFirstChargeCompleter) CompleteFirstCharge(subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, event *domain.Event) error {
	if c.err != nil {
		return c.err
	}
	c.subscription = subscription
	c.authorization = authorization
	c.charge = charge
	c.event = event
	return nil
}

func TestExecuteFirstChargeActivatesSubscription(t *testing.T) {
	subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "0x0000000000000000000000000000000000000001", PayerAddress: "0x0000000000000000000000000000000000000002", PlanID: "plan_1", Status: domain.SubscriptionPending, CurrentAuthorizationID: "auth_1", LastChargeID: "chain_charge_1"}
	authorization := &domain.Authorization{ID: "auth_1", IdentityAddress: subscription.IdentityAddress, PayerAddress: subscription.PayerAddress, PlanID: subscription.PlanID, ExpectedAllowance: 1000, TargetAllowance: 2000, RemainingAllowance: 2000, PermitDeadline: 1234}
	charge := &domain.Charge{ID: "charge_record_1", ChargeID: "chain_charge_1", SubscriptionID: "sub_1", AuthorizationID: "auth_1", IdentityAddress: subscription.IdentityAddress, PayerAddress: subscription.PayerAddress, PlanID: subscription.PlanID, Amount: 300, Status: domain.ChargePending}
	completer := &captureFirstChargeCompleter{}
	service := NewChainService(
		&testChainContract{authorizeTxHash: "0xpermit", chargeTxHash: "0xcharge"},
		&testActivationSubscriptionRepo{subscription: subscription},
		&testActivationAuthorizationRepo{authorization: authorization},
		&testActivationChargeRepo{charge: charge},
		&noopEventRepo{},
		completer,
	)

	err := service.ExecuteFirstCharge(context.Background(), ExecuteFirstChargeInput{SubscriptionID: "sub_1", AuthorizationID: "auth_1", ChargeRecordID: "charge_record_1"})
	if err != nil {
		t.Fatalf("ExecuteFirstCharge returned error: %v", err)
	}
	if completer.subscription == nil || completer.authorization == nil || completer.charge == nil || completer.event == nil {
		t.Fatal("expected completed state to be persisted")
	}
	if completer.subscription.Status != domain.SubscriptionActive {
		t.Fatalf("expected subscription active, got %s", completer.subscription.Status)
	}
	if completer.authorization.PermitStatus != domain.AuthorizationCompleted {
		t.Fatalf("expected authorization completed, got %s", completer.authorization.PermitStatus)
	}
	if completer.authorization.RemainingAllowance != 1700 {
		t.Fatalf("unexpected remaining allowance: %d", completer.authorization.RemainingAllowance)
	}
	if completer.charge.Status != domain.ChargeCompleted {
		t.Fatalf("expected charge completed, got %s", completer.charge.Status)
	}
	if completer.charge.TxHash != "0xcharge" {
		t.Fatalf("unexpected charge tx hash: %s", completer.charge.TxHash)
	}
	if completer.event.Type != domain.EventChargeSuccess {
		t.Fatalf("unexpected event type: %s", completer.event.Type)
	}
	if !strings.Contains(completer.event.Metadata, `"subscription_id":"sub_1"`) {
		t.Fatalf("event metadata missing subscription id: %s", completer.event.Metadata)
	}
}

func TestExecuteFirstChargeFailsWhenAuthorizationMissing(t *testing.T) {
	service := NewChainService(
		&testChainContract{},
		&testActivationSubscriptionRepo{},
		&testActivationAuthorizationRepo{},
		&testActivationChargeRepo{},
		&noopEventRepo{},
		&captureFirstChargeCompleter{},
	)

	err := service.ExecuteFirstCharge(context.Background(), ExecuteFirstChargeInput{SubscriptionID: "sub_1", AuthorizationID: "missing", ChargeRecordID: "charge_record_1"})
	if err == nil || err.Error() != "authorization not found" {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestExecuteFirstChargeFailsWhenChargeMissing(t *testing.T) {
	service := NewChainService(
		&testChainContract{},
		&testActivationSubscriptionRepo{subscription: &domain.Subscription{ID: "sub_1"}},
		&testActivationAuthorizationRepo{authorization: &domain.Authorization{ID: "auth_1"}},
		&testActivationChargeRepo{},
		&noopEventRepo{},
		&captureFirstChargeCompleter{},
	)

	err := service.ExecuteFirstCharge(context.Background(), ExecuteFirstChargeInput{SubscriptionID: "sub_1", AuthorizationID: "auth_1", ChargeRecordID: "missing"})
	if err == nil || err.Error() != "charge not found" {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestExecuteFirstChargeReturnsPersistenceError(t *testing.T) {
	subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "0x0000000000000000000000000000000000000001", PayerAddress: "0x0000000000000000000000000000000000000002", PlanID: "plan_1", Status: domain.SubscriptionPending, CurrentAuthorizationID: "auth_1", LastChargeID: "chain_charge_1"}
	authorization := &domain.Authorization{ID: "auth_1", IdentityAddress: subscription.IdentityAddress, PayerAddress: subscription.PayerAddress, PlanID: subscription.PlanID, ExpectedAllowance: 1000, TargetAllowance: 2000, RemainingAllowance: 2000, PermitDeadline: 1234}
	charge := &domain.Charge{ID: "charge_record_1", ChargeID: "chain_charge_1", SubscriptionID: "sub_1", AuthorizationID: "auth_1", IdentityAddress: subscription.IdentityAddress, PayerAddress: subscription.PayerAddress, PlanID: subscription.PlanID, Amount: 300, Status: domain.ChargePending}
	service := NewChainService(
		&testChainContract{authorizeTxHash: "0xpermit", chargeTxHash: "0xcharge"},
		&testActivationSubscriptionRepo{subscription: subscription},
		&testActivationAuthorizationRepo{authorization: authorization},
		&testActivationChargeRepo{charge: charge},
		&noopEventRepo{},
		&captureFirstChargeCompleter{err: errors.New("persist failed")},
	)

	err := service.ExecuteFirstCharge(context.Background(), ExecuteFirstChargeInput{SubscriptionID: "sub_1", AuthorizationID: "auth_1", ChargeRecordID: "charge_record_1"})
	if err == nil || err.Error() != "persist first charge completion: persist failed" {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestExecuteFirstChargeMarksChargeFailedWhenChainChargeFails(t *testing.T) {
	chargeRepo := &testActivationChargeRepo{charge: &domain.Charge{ID: "charge_record_1", ChargeID: "chain_charge_1", SubscriptionID: "sub_1", AuthorizationID: "auth_1", Amount: 300, Status: domain.ChargePending}}
	service := NewChainService(
		&testChainContract{authorizeTxHash: "0xpermit", chargeErr: errors.New("chain down")},
		&testActivationSubscriptionRepo{subscription: &domain.Subscription{ID: "sub_1", IdentityAddress: "0x0000000000000000000000000000000000000001", PayerAddress: "0x0000000000000000000000000000000000000002", PlanID: "plan_1", CurrentAuthorizationID: "auth_1", LastChargeID: "chain_charge_1"}},
		&testActivationAuthorizationRepo{authorization: &domain.Authorization{ID: "auth_1", IdentityAddress: "0x0000000000000000000000000000000000000001", PayerAddress: "0x0000000000000000000000000000000000000002", PlanID: "plan_1", ExpectedAllowance: 1000, TargetAllowance: 2000, RemainingAllowance: 2000, PermitDeadline: 1234}},
		chargeRepo,
		&noopEventRepo{},
		&captureFirstChargeCompleter{},
	)

	err := service.ExecuteFirstCharge(context.Background(), ExecuteFirstChargeInput{SubscriptionID: "sub_1", AuthorizationID: "auth_1", ChargeRecordID: "charge_record_1"})
	if err == nil || !strings.Contains(err.Error(), "charge: chain down") {
		t.Fatalf("unexpected error: %v", err)
	}
	if chargeRepo.updated == nil {
		t.Fatal("expected failed charge to be persisted")
	}
	if chargeRepo.updated.Status != domain.ChargeFailed {
		t.Fatalf("expected charge failed, got %s", chargeRepo.updated.Status)
	}
}
