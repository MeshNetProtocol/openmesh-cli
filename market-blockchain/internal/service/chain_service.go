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

type ChainService struct {
	contractClient     *blockchain.ContractClient
	subscriptions      repository.SubscriptionRepository
	authorizations     repository.AuthorizationRepository
	charges            repository.ChargeRepository
	events             repository.EventRepository
}

func NewChainService(
	contractClient *blockchain.ContractClient,
	subscriptions repository.SubscriptionRepository,
	authorizations repository.AuthorizationRepository,
	charges repository.ChargeRepository,
	events repository.EventRepository,
) *ChainService {
	return &ChainService{
		contractClient: contractClient,
		subscriptions:  subscriptions,
		authorizations: authorizations,
		charges:        charges,
		events:         events,
	}
}

type ExecuteFirstChargeInput struct {
	SubscriptionID  string
	AuthorizationID string
	ChargeRecordID  string
	PermitSignature blockchain.PermitSignature
}

func (s *ChainService) ExecuteFirstCharge(ctx context.Context, input ExecuteFirstChargeInput) error {
	authorization, err := s.authorizations.GetByIdentityAndPlan("", "")
	if err != nil {
		return fmt.Errorf("get authorization: %w", err)
	}
	if authorization == nil || authorization.ID != input.AuthorizationID {
		return fmt.Errorf("authorization not found")
	}

	charge, err := s.charges.GetByChargeID("")
	if err != nil {
		return fmt.Errorf("get charge: %w", err)
	}
	if charge == nil || charge.ID != input.ChargeRecordID {
		return fmt.Errorf("charge not found")
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
		s.authorizations.Update(authorization)
		return fmt.Errorf("authorize charge with permit: %w", err)
	}

	authorization.PermitStatus = domain.AuthorizationCompleted
	authorization.PermitTxHash = permitTxHash
	authorization.AuthorizedAllowance = authorization.TargetAllowance
	authorization.UpdatedAt = time.Now().UnixMilli()
	if err := s.authorizations.Update(authorization); err != nil {
		return fmt.Errorf("update authorization: %w", err)
	}

	var chargeID [32]byte
	copy(chargeID[:], []byte(charge.ChargeID))
	amount := big.NewInt(charge.Amount)

	chargeTxHash, err := s.contractClient.Charge(ctx, chargeID, identity, amount)
	if err != nil {
		charge.Status = domain.ChargeFailed
		charge.UpdatedAt = time.Now().UnixMilli()
		s.charges.Update(charge)
		return fmt.Errorf("charge: %w", err)
	}

	charge.Status = domain.ChargeCompleted
	charge.TxHash = chargeTxHash
	charge.UpdatedAt = time.Now().UnixMilli()
	if err := s.charges.Update(charge); err != nil {
		return fmt.Errorf("update charge: %w", err)
	}

	authorization.RemainingAllowance -= charge.Amount
	authorization.UpdatedAt = time.Now().UnixMilli()
	if err := s.authorizations.Update(authorization); err != nil {
		return fmt.Errorf("update remaining allowance: %w", err)
	}

	subscription, err := s.subscriptions.GetByID(input.SubscriptionID)
	if err != nil {
		return fmt.Errorf("get subscription: %w", err)
	}
	if subscription == nil {
		return fmt.Errorf("subscription not found")
	}

	subscription.Status = domain.SubscriptionActive
	subscription.UpdatedAt = time.Now().UnixMilli()
	if err := s.subscriptions.Update(subscription); err != nil {
		return fmt.Errorf("update subscription: %w", err)
	}

	now := time.Now().UnixMilli()
	s.events.Create(&domain.Event{
		ID:              fmt.Sprintf("evt_%d", now),
		IdentityAddress: subscription.IdentityAddress,
		PayerAddress:    subscription.PayerAddress,
		PlanID:          subscription.PlanID,
		ChargeID:        charge.ChargeID,
		Type:            domain.EventFirstSubscribe,
		Description:     "First subscription charge completed",
		Metadata:        fmt.Sprintf(`{"tx_hash":"%s"}`, chargeTxHash),
		CreatedAt:       now,
	})

	return nil
}
