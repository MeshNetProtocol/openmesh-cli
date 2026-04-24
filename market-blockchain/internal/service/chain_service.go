package service

import (
	"context"
	"fmt"
	"math/big"
	"time"

	"github.com/ethereum/go-ethereum/common"

	"market-blockchain/internal/blockchain"
	"market-blockchain/internal/domain"
	"market-blockchain/internal/repository"
)

type chainContract interface {
	AuthorizeChargeWithPermit(ctx context.Context, identity common.Address, payer common.Address, expectedAllowance *big.Int, targetAllowance *big.Int, deadline *big.Int, sig blockchain.PermitSignature) (string, error)
	Charge(ctx context.Context, chargeID [32]byte, identity common.Address, amount *big.Int) (string, error)
}

type firstChargeLifecycle interface {
	CompleteFirstCharge(ctx context.Context, subscription *domain.Subscription, authorization *domain.Authorization, charge *domain.Charge, permitTxHash, chargeTxHash string) error
}

type ChainService struct {
	contractClient chainContract
	subscriptions  repository.SubscriptionRepository
	authorizations repository.AuthorizationRepository
	charges        repository.ChargeRepository
	events         repository.EventRepository
	lifecycle      firstChargeLifecycle
}

func NewChainService(
	contractClient chainContract,
	subscriptions repository.SubscriptionRepository,
	authorizations repository.AuthorizationRepository,
	charges repository.ChargeRepository,
	events repository.EventRepository,
	lifecycle firstChargeLifecycle,
) *ChainService {
	return &ChainService{
		contractClient: contractClient,
		subscriptions:  subscriptions,
		authorizations: authorizations,
		charges:        charges,
		events:         events,
		lifecycle:      lifecycle,
	}
}

type ExecuteFirstChargeInput struct {
	SubscriptionID  string
	AuthorizationID string
	ChargeRecordID  string
	PermitSignature blockchain.PermitSignature
}

func (s *ChainService) ExecuteFirstCharge(ctx context.Context, input ExecuteFirstChargeInput) error {
	authorization, err := s.authorizations.GetByID(input.AuthorizationID)
	if err != nil {
		return fmt.Errorf("get authorization by id: %w", err)
	}
	if authorization == nil {
		return fmt.Errorf("authorization not found")
	}

	charge, err := s.charges.GetByID(input.ChargeRecordID)
	if err != nil {
		return fmt.Errorf("get charge by id: %w", err)
	}
	if charge == nil {
		return fmt.Errorf("charge not found")
	}
	if charge.AuthorizationID != authorization.ID {
		return fmt.Errorf("charge does not belong to authorization")
	}
	if charge.SubscriptionID != input.SubscriptionID {
		return fmt.Errorf("charge does not belong to subscription")
	}

	subscription, err := s.subscriptions.GetByID(input.SubscriptionID)
	if err != nil {
		return fmt.Errorf("get subscription: %w", err)
	}
	if subscription == nil {
		return fmt.Errorf("subscription not found")
	}
	if subscription.CurrentAuthorizationID != "" && subscription.CurrentAuthorizationID != authorization.ID {
		return fmt.Errorf("authorization does not belong to subscription")
	}
	if subscription.LastChargeID != "" && subscription.LastChargeID != charge.ChargeID {
		return fmt.Errorf("charge does not match subscription")
	}
	if subscription.Status != domain.SubscriptionPending {
		return fmt.Errorf("invalid subscription status for first charge: %s", subscription.Status)
	}
	if charge.Status != domain.ChargePending {
		return fmt.Errorf("invalid charge status for first charge: %s", charge.Status)
	}
	if authorization.PermitStatus != domain.AuthorizationPending {
		return fmt.Errorf("invalid authorization status for first charge: %s", authorization.PermitStatus)
	}

	identity := common.HexToAddress(authorization.IdentityAddress)
	payer := common.HexToAddress(authorization.PayerAddress)
	expectedAllowance := big.NewInt(authorization.ExpectedAllowance)
	targetAllowance := big.NewInt(authorization.TargetAllowance)
	deadline := big.NewInt(authorization.PermitDeadline)

	permitTxHash, err := s.contractClient.AuthorizeChargeWithPermit(
		ctx,
		identity,
		payer,
		expectedAllowance,
		targetAllowance,
		deadline,
		input.PermitSignature,
	)
	if err != nil {
		authorization.PermitStatus = domain.AuthorizationFailed
		authorization.UpdatedAt = time.Now().UnixMilli()
		if updateErr := s.authorizations.Update(authorization); updateErr != nil {
			return fmt.Errorf("authorize charge with permit: %w (also failed to persist authorization failure: %v)", err, updateErr)
		}
		return fmt.Errorf("authorize charge with permit: %w", err)
	}

	var chargeID [32]byte
	copy(chargeID[:], []byte(charge.ChargeID))
	amount := big.NewInt(charge.Amount)

	chargeTxHash, err := s.contractClient.Charge(ctx, chargeID, identity, amount)
	if err != nil {
		now := time.Now().UnixMilli()
		authorization.PermitStatus = domain.AuthorizationCompleted
		authorization.PermitTxHash = permitTxHash
		authorization.AuthorizedAllowance = authorization.TargetAllowance
		authorization.UpdatedAt = now
		charge.Status = domain.ChargeFailed
		charge.UpdatedAt = now
		if updateErr := s.authorizations.Update(authorization); updateErr != nil {
			return fmt.Errorf("charge: %w (also failed to persist authorization success: %v)", err, updateErr)
		}
		if updateErr := s.charges.Update(charge); updateErr != nil {
			return fmt.Errorf("charge: %w (authorization success persisted, but failed to persist charge failure: %v)", err, updateErr)
		}
		return fmt.Errorf("charge: %w", err)
	}

	if err := s.lifecycle.CompleteFirstCharge(ctx, subscription, authorization, charge, permitTxHash, chargeTxHash); err != nil {
		return err
	}

	return nil
}
