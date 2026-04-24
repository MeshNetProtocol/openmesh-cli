package postgres

import (
	"context"
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

	if err := store.CreateInitialState(context.Background(), subscription, authorization, charge, event); err != nil {
		t.Fatalf("CreateInitialState returned error: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}

func TestStoreCreateInitialStateCanBeReadBackViaRepositories(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	defer db.Close()

	store := New(db)
	subscriptionRepo := NewSubscriptionRepository(store)
	authorizationRepo := NewAuthorizationRepository(store)
	chargeRepo := NewChargeRepository(store)
	eventRepo := NewEventRepository(store)

	subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Status: domain.SubscriptionPending, AutoRenew: true, CurrentPeriodStart: 1, CurrentPeriodEnd: 2, NextPlanID: "", PendingPlanID: "", CurrentAuthorizationID: "auth_1", LastChargeID: "charge_1", LastChargeAt: 3, Source: domain.SubscriptionSourceFirstSubscribe, Uplink: 0, Downlink: 0, TotalTraffic: 0, CreatedAt: 4, UpdatedAt: 5}
	authorization := &domain.Authorization{ID: "auth_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", ExpectedAllowance: 10, TargetAllowance: 20, AuthorizedAllowance: 0, RemainingAllowance: 20, PermitStatus: domain.AuthorizationPending, PermitTxHash: "", PermitDeadline: 6, AuthorizationPeriods: 2, CreatedAt: 4, UpdatedAt: 5}
	charge := &domain.Charge{ID: "charge_record_1", ChargeID: "charge_1", SubscriptionID: "sub_1", AuthorizationID: "auth_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Amount: 100, Status: domain.ChargePending, TxHash: "", Reason: "first_subscribe", CreatedAt: 4, UpdatedAt: 5}
	event := &domain.Event{ID: "evt_sub_1_create", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", ChargeID: "charge_1", Type: domain.EventFirstSubscribe, Description: "created", Metadata: `{"subscription_id":"sub_1","authorization_id":"auth_1","charge_record_id":"charge_record_1","status":"pending"}`, CreatedAt: 4}

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

	mock.ExpectQuery(regexp.QuoteMeta("SELECT id, identity_address, payer_address, plan_id, status, auto_renew,")).
		WithArgs(subscription.ID).
		WillReturnRows(sqlmock.NewRows([]string{"id", "identity_address", "payer_address", "plan_id", "status", "auto_renew", "current_period_start", "current_period_end", "next_plan_id", "pending_plan_id", "current_authorization_id", "last_charge_id", "last_charge_at", "source", "uplink", "downlink", "total_traffic", "created_at", "updated_at"}).
			AddRow(subscription.ID, subscription.IdentityAddress, subscription.PayerAddress, subscription.PlanID, subscription.Status, subscription.AutoRenew, subscription.CurrentPeriodStart, subscription.CurrentPeriodEnd, subscription.NextPlanID, subscription.PendingPlanID, subscription.CurrentAuthorizationID, subscription.LastChargeID, subscription.LastChargeAt, subscription.Source, subscription.Uplink, subscription.Downlink, subscription.TotalTraffic, subscription.CreatedAt, subscription.UpdatedAt))
	mock.ExpectQuery(regexp.QuoteMeta("SELECT id, identity_address, payer_address, plan_id, expected_allowance,")).
		WithArgs(authorization.ID).
		WillReturnRows(sqlmock.NewRows([]string{"id", "identity_address", "payer_address", "plan_id", "expected_allowance", "target_allowance", "authorized_allowance", "remaining_allowance", "permit_status", "permit_tx_hash", "permit_deadline", "authorization_periods", "created_at", "updated_at"}).
			AddRow(authorization.ID, authorization.IdentityAddress, authorization.PayerAddress, authorization.PlanID, authorization.ExpectedAllowance, authorization.TargetAllowance, authorization.AuthorizedAllowance, authorization.RemainingAllowance, authorization.PermitStatus, authorization.PermitTxHash, authorization.PermitDeadline, authorization.AuthorizationPeriods, authorization.CreatedAt, authorization.UpdatedAt))
	mock.ExpectQuery(regexp.QuoteMeta("SELECT id, charge_id, subscription_id, authorization_id, identity_address, payer_address, plan_id,")).
		WithArgs(charge.ID).
		WillReturnRows(sqlmock.NewRows([]string{"id", "charge_id", "subscription_id", "authorization_id", "identity_address", "payer_address", "plan_id", "amount", "status", "tx_hash", "reason", "created_at", "updated_at"}).
			AddRow(charge.ID, charge.ChargeID, charge.SubscriptionID, charge.AuthorizationID, charge.IdentityAddress, charge.PayerAddress, charge.PlanID, charge.Amount, charge.Status, charge.TxHash, charge.Reason, charge.CreatedAt, charge.UpdatedAt))
	mock.ExpectQuery(regexp.QuoteMeta("SELECT id, identity_address, payer_address, plan_id, charge_id,")).
		WithArgs("%\"subscription_id\":\"sub_1\"%", 10).
		WillReturnRows(sqlmock.NewRows([]string{"id", "identity_address", "payer_address", "plan_id", "charge_id", "type", "description", "metadata", "created_at"}).
			AddRow(event.ID, event.IdentityAddress, event.PayerAddress, event.PlanID, event.ChargeID, event.Type, event.Description, event.Metadata, event.CreatedAt))

	if err := store.CreateInitialState(context.Background(), subscription, authorization, charge, event); err != nil {
		t.Fatalf("CreateInitialState returned error: %v", err)
	}

	gotSubscription, err := subscriptionRepo.GetByID(subscription.ID)
	if err != nil {
		t.Fatalf("GetByID(subscription): %v", err)
	}
	if gotSubscription == nil {
		t.Fatal("expected subscription")
	}
	if gotSubscription.CurrentAuthorizationID != authorization.ID {
		t.Fatalf("unexpected current authorization id: %s", gotSubscription.CurrentAuthorizationID)
	}
	if gotSubscription.LastChargeID != charge.ChargeID {
		t.Fatalf("unexpected last charge id: %s", gotSubscription.LastChargeID)
	}

	gotAuthorization, err := authorizationRepo.GetByID(authorization.ID)
	if err != nil {
		t.Fatalf("GetByID(authorization): %v", err)
	}
	if gotAuthorization == nil {
		t.Fatal("expected authorization")
	}
	if gotAuthorization.PlanID != subscription.PlanID {
		t.Fatalf("unexpected authorization plan id: %s", gotAuthorization.PlanID)
	}

	gotCharge, err := chargeRepo.GetByID(charge.ID)
	if err != nil {
		t.Fatalf("GetByID(charge): %v", err)
	}
	if gotCharge == nil {
		t.Fatal("expected charge")
	}
	if gotCharge.SubscriptionID != subscription.ID || gotCharge.AuthorizationID != authorization.ID {
		t.Fatalf("charge linkage mismatch: %+v", gotCharge)
	}

	gotEvents, err := eventRepo.ListBySubscription(context.Background(), subscription.ID, 10)
	if err != nil {
		t.Fatalf("ListBySubscription(events): %v", err)
	}
	if len(gotEvents) != 1 {
		t.Fatalf("expected 1 event, got %d", len(gotEvents))
	}
	if gotEvents[0].ID != event.ID {
		t.Fatalf("unexpected event id: %s", gotEvents[0].ID)
	}
	if gotEvents[0].ChargeID != charge.ChargeID {
		t.Fatalf("unexpected event charge id: %s", gotEvents[0].ChargeID)
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

	err = store.CreateInitialState(context.Background(), subscription, authorization, charge, event)
	if err == nil {
		t.Fatal("expected error")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}

func TestStoreCompleteFirstChargeCommitsAllUpdates(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	defer db.Close()

	store := New(db)
	subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Status: domain.SubscriptionActive, AutoRenew: true, CurrentPeriodStart: 1, CurrentPeriodEnd: 2, NextPlanID: "", PendingPlanID: "", CurrentAuthorizationID: "auth_1", LastChargeID: "charge_1", LastChargeAt: 3, Source: domain.SubscriptionSourceFirstSubscribe, Uplink: 0, Downlink: 0, TotalTraffic: 0, CreatedAt: 4, UpdatedAt: 5}
	authorization := &domain.Authorization{ID: "auth_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", ExpectedAllowance: 10, TargetAllowance: 20, AuthorizedAllowance: 20, RemainingAllowance: 10, PermitStatus: domain.AuthorizationCompleted, PermitTxHash: "0xpermit", PermitDeadline: 6, AuthorizationPeriods: 2, CreatedAt: 4, UpdatedAt: 5}
	charge := &domain.Charge{ID: "charge_record_1", ChargeID: "charge_1", SubscriptionID: "sub_1", AuthorizationID: "auth_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Amount: 10, Status: domain.ChargeCompleted, TxHash: "0xcharge", Reason: "first_subscribe", CreatedAt: 4, UpdatedAt: 5}
	event := &domain.Event{ID: "evt_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", ChargeID: "charge_1", Type: domain.EventChargeSuccess, Description: "activated", Metadata: "{}", CreatedAt: 4}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta("UPDATE authorizations SET")).WithArgs(
		authorization.ID, authorization.PayerAddress, authorization.ExpectedAllowance, authorization.TargetAllowance,
		authorization.AuthorizedAllowance, authorization.RemainingAllowance, authorization.PermitStatus,
		authorization.PermitTxHash, authorization.PermitDeadline, authorization.AuthorizationPeriods, authorization.UpdatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("UPDATE charges SET")).WithArgs(
		charge.ID, charge.Status, charge.TxHash, charge.UpdatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("UPDATE subscriptions SET")).WithArgs(
		subscription.ID, subscription.PayerAddress, subscription.PlanID, subscription.Status, subscription.AutoRenew,
		subscription.CurrentPeriodStart, subscription.CurrentPeriodEnd, subscription.NextPlanID,
		subscription.PendingPlanID, subscription.CurrentAuthorizationID, subscription.LastChargeID,
		subscription.LastChargeAt, subscription.Source, subscription.Uplink, subscription.Downlink, subscription.TotalTraffic, subscription.UpdatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO events (")).WithArgs(
		event.ID, event.IdentityAddress, event.PayerAddress, event.PlanID,
		event.ChargeID, event.Type, event.Description, event.Metadata, event.CreatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	if err := store.CompleteFirstCharge(context.Background(), subscription, authorization, charge, event); err != nil {
		t.Fatalf("CompleteFirstCharge returned error: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}

func TestStoreCompleteFirstChargeRollsBackOnFailure(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	defer db.Close()

	store := New(db)
	subscription := &domain.Subscription{ID: "sub_1"}
	authorization := &domain.Authorization{ID: "auth_1"}
	charge := &domain.Charge{ID: "charge_record_1"}
	event := &domain.Event{ID: "evt_1"}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta("UPDATE authorizations SET")).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("UPDATE charges SET")).WillReturnError(assertiveErr{})
	mock.ExpectRollback()

	err = store.CompleteFirstCharge(context.Background(), subscription, authorization, charge, event)
	if err == nil {
		t.Fatal("expected error")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}

func TestStoreCompleteRenewalCommitsAllUpdates(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	defer db.Close()

	store := New(db)
	subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Status: domain.SubscriptionActive, AutoRenew: true, CurrentPeriodStart: 100, CurrentPeriodEnd: 200, NextPlanID: "", PendingPlanID: "", CurrentAuthorizationID: "auth_1", LastChargeID: "charge_2", LastChargeAt: 300, Source: domain.SubscriptionSourceRenewal, Uplink: 0, Downlink: 0, TotalTraffic: 0, CreatedAt: 4, UpdatedAt: 5}
	authorization := &domain.Authorization{ID: "auth_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", ExpectedAllowance: 10, TargetAllowance: 20, AuthorizedAllowance: 20, RemainingAllowance: 10, PermitStatus: domain.AuthorizationCompleted, PermitTxHash: "0xpermit", PermitDeadline: 6, AuthorizationPeriods: 2, CreatedAt: 4, UpdatedAt: 5}
	charge := &domain.Charge{ID: "charge_record_1", ChargeID: "charge_2", SubscriptionID: "sub_1", AuthorizationID: "auth_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Amount: 10, Status: domain.ChargePending, TxHash: "", Reason: "renew", CreatedAt: 4, UpdatedAt: 5}
	event := &domain.Event{ID: "evt_renew", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", ChargeID: "charge_2", Type: domain.EventRenew, Description: "renewed", Metadata: "{}", CreatedAt: 4}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO charges (")).WithArgs(
		charge.ID, charge.ChargeID, charge.SubscriptionID, charge.AuthorizationID,
		charge.IdentityAddress, charge.PayerAddress, charge.PlanID, charge.Amount,
		charge.Status, charge.TxHash, charge.Reason, charge.CreatedAt, charge.UpdatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("UPDATE subscriptions SET")).WithArgs(
		subscription.ID, subscription.PayerAddress, subscription.PlanID, subscription.Status, subscription.AutoRenew,
		subscription.CurrentPeriodStart, subscription.CurrentPeriodEnd, subscription.NextPlanID,
		subscription.PendingPlanID, subscription.CurrentAuthorizationID, subscription.LastChargeID,
		subscription.LastChargeAt, subscription.Source, subscription.Uplink, subscription.Downlink, subscription.TotalTraffic, subscription.UpdatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("UPDATE authorizations SET")).WithArgs(
		authorization.ID, authorization.PayerAddress, authorization.ExpectedAllowance, authorization.TargetAllowance,
		authorization.AuthorizedAllowance, authorization.RemainingAllowance, authorization.PermitStatus,
		authorization.PermitTxHash, authorization.PermitDeadline, authorization.AuthorizationPeriods, authorization.UpdatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO events (")).WithArgs(
		event.ID, event.IdentityAddress, event.PayerAddress, event.PlanID,
		event.ChargeID, event.Type, event.Description, event.Metadata, event.CreatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	if err := store.CompleteRenewal(context.Background(), subscription, authorization, charge, event); err != nil {
		t.Fatalf("CompleteRenewal returned error: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}

func TestStoreCompleteRenewalRollsBackOnFailure(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	defer db.Close()

	store := New(db)
	subscription := &domain.Subscription{ID: "sub_1"}
	authorization := &domain.Authorization{ID: "auth_1"}
	charge := &domain.Charge{ID: "charge_record_1"}
	event := &domain.Event{ID: "evt_renew"}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO charges (")).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("UPDATE subscriptions SET")).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("UPDATE authorizations SET")).WillReturnError(assertiveErr{})
	mock.ExpectRollback()

	err = store.CompleteRenewal(context.Background(), subscription, authorization, charge, event)
	if err == nil {
		t.Fatal("expected error")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}

func TestStoreApplyImmediateUpgradeCommitsAllUpdates(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	defer db.Close()

	store := New(db)
	subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_new", Status: domain.SubscriptionActive, AutoRenew: true, CurrentPeriodStart: 100, CurrentPeriodEnd: 200, NextPlanID: "", PendingPlanID: "", CurrentAuthorizationID: "auth_1", LastChargeID: "charge_1", LastChargeAt: 300, Source: domain.SubscriptionSourceUpgrade, Uplink: 0, Downlink: 0, TotalTraffic: 0, CreatedAt: 4, UpdatedAt: 5}
	charge := &domain.Charge{ID: "chg_1", ChargeID: "chg_1", SubscriptionID: "sub_1", AuthorizationID: "auth_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_new", Amount: 50, Status: domain.ChargePending, TxHash: "", Reason: "upgrade", CreatedAt: 4, UpdatedAt: 5}
	event := &domain.Event{ID: "evt_upgrade", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_new", ChargeID: "chg_1", Type: domain.EventUpgrade, Description: "upgraded", Metadata: "{}", CreatedAt: 4}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO charges (")).WithArgs(
		charge.ID, charge.ChargeID, charge.SubscriptionID, charge.AuthorizationID,
		charge.IdentityAddress, charge.PayerAddress, charge.PlanID, charge.Amount,
		charge.Status, charge.TxHash, charge.Reason, charge.CreatedAt, charge.UpdatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("UPDATE subscriptions SET")).WithArgs(
		subscription.ID, subscription.PayerAddress, subscription.PlanID, subscription.Status, subscription.AutoRenew,
		subscription.CurrentPeriodStart, subscription.CurrentPeriodEnd, subscription.NextPlanID,
		subscription.PendingPlanID, subscription.CurrentAuthorizationID, subscription.LastChargeID,
		subscription.LastChargeAt, subscription.Source, subscription.Uplink, subscription.Downlink, subscription.TotalTraffic, subscription.UpdatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO events (")).WithArgs(
		event.ID, event.IdentityAddress, event.PayerAddress, event.PlanID,
		event.ChargeID, event.Type, event.Description, event.Metadata, event.CreatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	if err := store.ApplyImmediateUpgrade(context.Background(), subscription, charge, event); err != nil {
		t.Fatalf("ApplyImmediateUpgrade returned error: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}

func TestStoreApplyImmediateUpgradeRollsBackOnFailure(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	defer db.Close()

	store := New(db)
	subscription := &domain.Subscription{ID: "sub_1"}
	charge := &domain.Charge{ID: "chg_1"}
	event := &domain.Event{ID: "evt_upgrade"}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO charges (")).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("UPDATE subscriptions SET")).WillReturnError(assertiveErr{})
	mock.ExpectRollback()

	err = store.ApplyImmediateUpgrade(context.Background(), subscription, charge, event)
	if err == nil {
		t.Fatal("expected error")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}

func TestStoreScheduleDowngradeCommitsAllUpdates(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	defer db.Close()

	store := New(db)
	subscription := &domain.Subscription{ID: "sub_1", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", Status: domain.SubscriptionActive, AutoRenew: true, CurrentPeriodStart: 100, CurrentPeriodEnd: 200, NextPlanID: "", PendingPlanID: "plan_new", CurrentAuthorizationID: "auth_1", LastChargeID: "charge_1", LastChargeAt: 300, Source: domain.SubscriptionSourceDowngrade, Uplink: 0, Downlink: 0, TotalTraffic: 0, CreatedAt: 4, UpdatedAt: 5}
	event := &domain.Event{ID: "evt_downgrade", IdentityAddress: "identity_1", PayerAddress: "payer_1", PlanID: "plan_1", ChargeID: "", Type: domain.EventDowngrade, Description: "downgraded", Metadata: "{}", CreatedAt: 4}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta("UPDATE subscriptions SET")).WithArgs(
		subscription.ID, subscription.PayerAddress, subscription.PlanID, subscription.Status, subscription.AutoRenew,
		subscription.CurrentPeriodStart, subscription.CurrentPeriodEnd, subscription.NextPlanID,
		subscription.PendingPlanID, subscription.CurrentAuthorizationID, subscription.LastChargeID,
		subscription.LastChargeAt, subscription.Source, subscription.Uplink, subscription.Downlink, subscription.TotalTraffic, subscription.UpdatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO events (")).WithArgs(
		event.ID, event.IdentityAddress, event.PayerAddress, event.PlanID,
		event.ChargeID, event.Type, event.Description, event.Metadata, event.CreatedAt,
	).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectCommit()

	if err := store.ScheduleDowngrade(context.Background(), subscription, event); err != nil {
		t.Fatalf("ScheduleDowngrade returned error: %v", err)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}

func TestStoreScheduleDowngradeRollsBackOnFailure(t *testing.T) {
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock.New: %v", err)
	}
	defer db.Close()

	store := New(db)
	subscription := &domain.Subscription{ID: "sub_1"}
	event := &domain.Event{ID: "evt_downgrade"}

	mock.ExpectBegin()
	mock.ExpectExec(regexp.QuoteMeta("UPDATE subscriptions SET")).WillReturnResult(sqlmock.NewResult(1, 1))
	mock.ExpectExec(regexp.QuoteMeta("INSERT INTO events (")).WillReturnError(assertiveErr{})
	mock.ExpectRollback()

	err = store.ScheduleDowngrade(context.Background(), subscription, event)
	if err == nil {
		t.Fatal("expected error")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Fatalf("unmet expectations: %v", err)
	}
}

type assertiveErr struct{}

func (assertiveErr) Error() string { return "insert authorization failed" }
