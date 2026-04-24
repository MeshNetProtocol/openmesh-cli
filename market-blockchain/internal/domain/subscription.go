package domain

import (
	"errors"
	"fmt"
)

type SubscriptionStatus string

type SubscriptionSource string

const (
	SubscriptionPending   SubscriptionStatus = "pending"
	SubscriptionActive    SubscriptionStatus = "active"
	SubscriptionExpired   SubscriptionStatus = "expired"
	SubscriptionCancelled SubscriptionStatus = "cancelled"
)

const (
	SubscriptionSourceFirstSubscribe SubscriptionSource = "first_subscribe"
	SubscriptionSourceRenewal        SubscriptionSource = "renewal"
	SubscriptionSourceUpgrade        SubscriptionSource = "upgrade"
	SubscriptionSourceDowngrade      SubscriptionSource = "downgrade"
)

var ErrInvalidSubscriptionTransition = errors.New("invalid subscription transition")

type Subscription struct {
	ID                     string
	IdentityAddress        string
	PayerAddress           string
	PlanID                 string
	Status                 SubscriptionStatus
	AutoRenew              bool
	CurrentPeriodStart     int64
	CurrentPeriodEnd       int64
	NextPlanID             string
	PendingPlanID          string
	CurrentAuthorizationID string
	LastChargeID           string
	LastChargeAt           int64
	Source                 SubscriptionSource
	Uplink                 int64
	Downlink               int64
	TotalTraffic           int64
	CreatedAt              int64
	UpdatedAt              int64
}

func (s *Subscription) Activate(now int64) error {
	if s.Status != SubscriptionPending {
		return invalidSubscriptionTransition(s.Status, SubscriptionActive)
	}

	s.Status = SubscriptionActive
	s.UpdatedAt = now
	return nil
}

func (s *Subscription) Cancel(now int64) error {
	if s.Status != SubscriptionActive {
		return invalidSubscriptionTransition(s.Status, SubscriptionCancelled)
	}

	s.Status = SubscriptionCancelled
	s.AutoRenew = false
	s.UpdatedAt = now
	return nil
}

func (s *Subscription) Expire(now int64) error {
	if s.Status != SubscriptionActive {
		return invalidSubscriptionTransition(s.Status, SubscriptionExpired)
	}

	s.Status = SubscriptionExpired
	s.UpdatedAt = now
	return nil
}

func invalidSubscriptionTransition(current, next SubscriptionStatus) error {
	return fmt.Errorf("%w: %s -> %s", ErrInvalidSubscriptionTransition, current, next)
}
