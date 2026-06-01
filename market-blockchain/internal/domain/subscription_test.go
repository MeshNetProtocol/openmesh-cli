package domain

import (
	"errors"
	"testing"
)

func TestSubscriptionActivate(t *testing.T) {
	t.Run("pending to active succeeds", func(t *testing.T) {
		subscription := &Subscription{Status: SubscriptionPending, UpdatedAt: 10}
		now := int64(100)

		if err := subscription.Activate(now); err != nil {
			t.Fatalf("Activate returned error: %v", err)
		}
		if subscription.Status != SubscriptionActive {
			t.Fatalf("expected status %s, got %s", SubscriptionActive, subscription.Status)
		}
		if subscription.UpdatedAt != now {
			t.Fatalf("expected UpdatedAt %d, got %d", now, subscription.UpdatedAt)
		}
	})

	t.Run("active to active rejected", func(t *testing.T) {
		subscription := &Subscription{Status: SubscriptionActive, UpdatedAt: 10}

		err := subscription.Activate(100)
		if err == nil {
			t.Fatal("expected error")
		}
		if !errors.Is(err, ErrInvalidSubscriptionTransition) {
			t.Fatalf("expected ErrInvalidSubscriptionTransition, got %v", err)
		}
		if subscription.Status != SubscriptionActive {
			t.Fatalf("status changed unexpectedly: %s", subscription.Status)
		}
		if subscription.UpdatedAt != 10 {
			t.Fatalf("UpdatedAt changed unexpectedly: %d", subscription.UpdatedAt)
		}
	})

	t.Run("cancelled to active rejected", func(t *testing.T) {
		subscription := &Subscription{Status: SubscriptionCancelled, UpdatedAt: 10}

		err := subscription.Activate(100)
		if err == nil {
			t.Fatal("expected error")
		}
		if !errors.Is(err, ErrInvalidSubscriptionTransition) {
			t.Fatalf("expected ErrInvalidSubscriptionTransition, got %v", err)
		}
		if subscription.Status != SubscriptionCancelled {
			t.Fatalf("status changed unexpectedly: %s", subscription.Status)
		}
		if subscription.UpdatedAt != 10 {
			t.Fatalf("UpdatedAt changed unexpectedly: %d", subscription.UpdatedAt)
		}
	})
}

func TestSubscriptionCancel(t *testing.T) {
	t.Run("active to cancelled succeeds", func(t *testing.T) {
		subscription := &Subscription{Status: SubscriptionActive, AutoRenew: true, UpdatedAt: 10}
		now := int64(100)

		if err := subscription.Cancel(now); err != nil {
			t.Fatalf("Cancel returned error: %v", err)
		}
		if subscription.Status != SubscriptionCancelled {
			t.Fatalf("expected status %s, got %s", SubscriptionCancelled, subscription.Status)
		}
		if subscription.AutoRenew {
			t.Fatal("expected AutoRenew to be false")
		}
		if subscription.UpdatedAt != now {
			t.Fatalf("expected UpdatedAt %d, got %d", now, subscription.UpdatedAt)
		}
	})

	t.Run("pending to cancelled rejected", func(t *testing.T) {
		subscription := &Subscription{Status: SubscriptionPending, AutoRenew: true, UpdatedAt: 10}

		err := subscription.Cancel(100)
		if err == nil {
			t.Fatal("expected error")
		}
		if !errors.Is(err, ErrInvalidSubscriptionTransition) {
			t.Fatalf("expected ErrInvalidSubscriptionTransition, got %v", err)
		}
		if subscription.Status != SubscriptionPending {
			t.Fatalf("status changed unexpectedly: %s", subscription.Status)
		}
		if !subscription.AutoRenew {
			t.Fatal("AutoRenew changed unexpectedly")
		}
		if subscription.UpdatedAt != 10 {
			t.Fatalf("UpdatedAt changed unexpectedly: %d", subscription.UpdatedAt)
		}
	})

	t.Run("expired to cancelled rejected", func(t *testing.T) {
		subscription := &Subscription{Status: SubscriptionExpired, AutoRenew: true, UpdatedAt: 10}

		err := subscription.Cancel(100)
		if err == nil {
			t.Fatal("expected error")
		}
		if !errors.Is(err, ErrInvalidSubscriptionTransition) {
			t.Fatalf("expected ErrInvalidSubscriptionTransition, got %v", err)
		}
		if subscription.Status != SubscriptionExpired {
			t.Fatalf("status changed unexpectedly: %s", subscription.Status)
		}
		if !subscription.AutoRenew {
			t.Fatal("AutoRenew changed unexpectedly")
		}
		if subscription.UpdatedAt != 10 {
			t.Fatalf("UpdatedAt changed unexpectedly: %d", subscription.UpdatedAt)
		}
	})
}

func TestSubscriptionExpire(t *testing.T) {
	t.Run("active to expired succeeds", func(t *testing.T) {
		subscription := &Subscription{Status: SubscriptionActive, UpdatedAt: 10}
		now := int64(100)

		if err := subscription.Expire(now); err != nil {
			t.Fatalf("Expire returned error: %v", err)
		}
		if subscription.Status != SubscriptionExpired {
			t.Fatalf("expected status %s, got %s", SubscriptionExpired, subscription.Status)
		}
		if subscription.UpdatedAt != now {
			t.Fatalf("expected UpdatedAt %d, got %d", now, subscription.UpdatedAt)
		}
	})

	t.Run("pending to expired rejected", func(t *testing.T) {
		subscription := &Subscription{Status: SubscriptionPending, UpdatedAt: 10}

		err := subscription.Expire(100)
		if err == nil {
			t.Fatal("expected error")
		}
		if !errors.Is(err, ErrInvalidSubscriptionTransition) {
			t.Fatalf("expected ErrInvalidSubscriptionTransition, got %v", err)
		}
		if subscription.Status != SubscriptionPending {
			t.Fatalf("status changed unexpectedly: %s", subscription.Status)
		}
		if subscription.UpdatedAt != 10 {
			t.Fatalf("UpdatedAt changed unexpectedly: %d", subscription.UpdatedAt)
		}
	})

	t.Run("cancelled to expired rejected", func(t *testing.T) {
		subscription := &Subscription{Status: SubscriptionCancelled, UpdatedAt: 10}

		err := subscription.Expire(100)
		if err == nil {
			t.Fatal("expected error")
		}
		if !errors.Is(err, ErrInvalidSubscriptionTransition) {
			t.Fatalf("expected ErrInvalidSubscriptionTransition, got %v", err)
		}
		if subscription.Status != SubscriptionCancelled {
			t.Fatalf("status changed unexpectedly: %s", subscription.Status)
		}
		if subscription.UpdatedAt != 10 {
			t.Fatalf("UpdatedAt changed unexpectedly: %d", subscription.UpdatedAt)
		}
	})
}
