package blockchain

import (
	"context"
	"crypto/ecdsa"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/accounts/abi/bind"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

type ContractClient struct {
	client       *ethclient.Client
	contractAddr common.Address
	privateKey   *ecdsa.PrivateKey
	vault        *VPNCreditVault
}

func NewContractClient(rpcURL, contractAddress, privateKeyHex string) (*ContractClient, error) {
	client, err := ethclient.Dial(rpcURL)
	if err != nil {
		return nil, fmt.Errorf("dial rpc: %w", err)
	}

	contractAddr := common.HexToAddress(contractAddress)
	vault, err := NewVPNCreditVault(contractAddr, client)
	if err != nil {
		return nil, fmt.Errorf("bind contract: %w", err)
	}

	var privateKey *ecdsa.PrivateKey
	if privateKeyHex != "" {
		privateKey, err = crypto.HexToECDSA(privateKeyHex)
		if err != nil {
			return nil, fmt.Errorf("parse private key: %w", err)
		}
	}

	return &ContractClient{
		client:       client,
		contractAddr: contractAddr,
		privateKey:   privateKey,
		vault:        vault,
	}, nil
}

type PermitSignature struct {
	V uint8
	R [32]byte
	S [32]byte
}

func (c *ContractClient) AuthorizeChargeWithPermit(
	ctx context.Context,
	identity common.Address,
	payer common.Address,
	expectedAllowance *big.Int,
	targetAllowance *big.Int,
	deadline *big.Int,
	sig PermitSignature,
) (string, error) {
	if c.privateKey == nil {
		return "", fmt.Errorf("private key not configured")
	}

	chainID, err := c.client.ChainID(ctx)
	if err != nil {
		return "", fmt.Errorf("get chain id: %w", err)
	}

	auth, err := bind.NewKeyedTransactorWithChainID(c.privateKey, chainID)
	if err != nil {
		return "", fmt.Errorf("create transactor: %w", err)
	}

	tx, err := c.vault.AuthorizeChargeWithPermit(
		auth,
		payer,
		identity,
		expectedAllowance,
		targetAllowance,
		deadline,
		sig.V,
		sig.R,
		sig.S,
	)
	if err != nil {
		return "", fmt.Errorf("authorize charge with permit: %w", err)
	}

	return tx.Hash().Hex(), nil
}

func (c *ContractClient) Charge(
	ctx context.Context,
	chargeID [32]byte,
	identity common.Address,
	amount *big.Int,
) (string, error) {
	if c.privateKey == nil {
		return "", fmt.Errorf("private key not configured")
	}

	chainID, err := c.client.ChainID(ctx)
	if err != nil {
		return "", fmt.Errorf("get chain id: %w", err)
	}

	auth, err := bind.NewKeyedTransactorWithChainID(c.privateKey, chainID)
	if err != nil {
		return "", fmt.Errorf("create transactor: %w", err)
	}

	tx, err := c.vault.Charge(auth, chargeID, identity, amount)
	if err != nil {
		return "", fmt.Errorf("charge: %w", err)
	}

	return tx.Hash().Hex(), nil
}

func (c *ContractClient) GetAuthorizedAllowance(
	ctx context.Context,
	payer common.Address,
	identity common.Address,
) (*big.Int, error) {
	allowance, err := c.vault.GetAuthorizedAllowance(&bind.CallOpts{Context: ctx}, payer, identity)
	if err != nil {
		return nil, fmt.Errorf("get authorized allowance: %w", err)
	}
	return allowance, nil
}

func (c *ContractClient) GetIdentityPayer(
	ctx context.Context,
	identity common.Address,
) (common.Address, error) {
	payer, err := c.vault.GetIdentityPayer(&bind.CallOpts{Context: ctx}, identity)
	if err != nil {
		return common.Address{}, fmt.Errorf("get identity payer: %w", err)
	}
	return payer, nil
}

func (c *ContractClient) Close() {
	if c.client != nil {
		c.client.Close()
	}
}
