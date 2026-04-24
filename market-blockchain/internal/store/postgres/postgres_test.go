package postgres

import (
	"regexp"
	"testing"

	"github.com/DATA-DOG/go-sqlmock"

	"market-blockchain/internal/domain"
)

func TestStoreCreateInitialStateCommitsAllRecords(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	defer db.Close()

	store := New(db)
	subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Status: domain.SubscriptionPending, AutoRenew: true, CurrentPeriodStart: 1, CurrentPeriodEnd: 2, NextPlanID: "", PendingPlanID: "", CurrentAuthorizationID: "auth_1", LastChargeID: "charge_1", LastChargeAt: 3, Source: domain.SubscriptionSourceFirstSubscribe, Uplink: 0, Downlink: 0, TotalTraffic: 0, CreatedAt: 4, UpdatedAt: 5}
	authorization := &domain.Authorization{ID: "auth_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", ExpectedAllowance: 10, TargetAllowance: 20, AuthorizedAllowance: 0, RemainingAllowance: 20, PermitStatus: domain.AuthorizationPending, PermitTxHash: "", PermitDeadline: 6, AuthorizationPeriods: 2, CreatedAt: 4, UpdatedAt: 5}
	charge := &domain.Charge{ID: "charge_record_1", ChargeID: "charge_1", SubscriptionID: "sub_1", AuthorizationID: "auth_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Amount: 100, Status: domain.ChargePending, TxHash: "", Reason: "first_subscribe", CreatedAt: 4, UpdatedAt: 5}
	event := &domain.Event{ID: "evt_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", ChargeID: "charge_1", Type: domain.EventFirstSubscribe, Description: "created", Metadata: "{}", CreatedAt: 4}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO subscriptions (")).WithArgs(
		subscription.ID, subscription.IdentityAddress, subscription.PayerAddress, subscription.PlanID, subscription.Status,
		subscription.AutoRenew, subscription.CurrentPeriodStart, subscription.CurrentPeriodEnd, subscription.NextPlanID,
		subscription.PendingPlanID, subscription.CurrentAuthorizationID, subscription.LastChargeID, subscription.LastChargeAt,
		subscription.Source, subscription.Uplink, subscription.Downlink, subscription.TotalTraffic, subscription.CreatedAt, subscription.UpdatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO authorizations (")).WithArgs(
		authorization.ID, authorization.IdentityAddress, authorization.PayerAddress, authorization.PlanID,
		authorization.ExpectedAllowance, authorization.TargetAllowance, authorization.AuthorizedAllowance,
		authorization.RemainingAllowance, authorization.PermitStatus, authorization.PermitTxHash,
		authorization.PermitDeadline, authorization.AuthorizationPeriods, authorization.CreatedAt, authorization.UpdatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO charges (")).WithArgs(
		charge.ID, charge.ChargeID, charge.SubscriptionID, charge.AuthorizationID,
		charge.IdentityAddress, charge.PayerAddress, charge.PlanID, charge.Amount,
		charge.Status, charge.TxHash, charge.Reason, charge.CreatedAt, charge.UpdatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO events (")).WithArgs(
		event.ID, event.IdentityAddress, event.PayerAddress, event.PlanID,
		event.ChargeID, event.Type, event.Description, event.Metadata, event.CreatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	if err := store.CreateInitialState(subscription, authorization, charge, event); err != nil {
		t.Fatalf("CreateInitialState returned error: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}

func TestStoreCreateInitialStateRollsBackOnFailure(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	defer db.Close()

	store := New(db)
	subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Status: domain.SubscriptionPending, AutoRenew: true, CurrentPeriodStart: 1, CurrentPeriodEnd: 2, NextPlanID: "", PendingPlanID: "", CurrentAuthorizationID: "auth_1", LastChargeID: "charge_1", LastChargeAt: 3, Source: domain.SubscriptionSourceFirstSubscribe, Uplink: 0, Downlink: 0, TotalTraffic: 0, CreatedAt: 4, UpdatedAt: 5}
	authorization := &domain.Authorization{ID: "auth_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", ExpectedAllowance: 10, TargetAllowance: 20, AuthorizedAllowance: 0, RemainingAllowance: 20, PermitStatus: domain.AuthorizationPending, PermitTxHash: "", PermitDeadline: 6, AuthorizationPeriods: 2, CreatedAt: 4, UpdatedAt: 5}
	charge := &domain.Charge{ID: "charge_record_1", ChargeID: "charge_1", SubscriptionID: "sub_1", AuthorizationID: "auth_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Amount: 100, Status: domain.ChargePending, TxHash: "", Reason: "first_subscribe", CreatedAt: 4, UpdatedAt: 5}
	event := &domain.Event{ID: "evt_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", ChargeID: "charge_1", Type: domain.EventFirstSubscribe, Description: "created", Metadata: "{}", CreatedAt: 4}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO subscriptions (")).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO authorizations (")).WillReturnError(assertiveErr{})
	mock.ExpectRollback()

	err = store.CreateInitialState(subscription, authorization, charge, event)
	if err == nil {
		t.Fatal("expected error")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}

type assertiveErr struct{}

func (assertiveErr) Error() string { return "insert authorization failed" }
