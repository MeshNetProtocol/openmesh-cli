package blockchain

import (
	"context"
	"fmt"
	"math/big"

	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/ethclient"
)

type ContractClient struct {
	client         *ethclient.Client
	contractAddr   common.Address
	privateKey     string
}

func NewContractClient(rpcURL, contractAddress, privateKey string) (*ContractClient, error) {
	client, err := ethclient.Dial(rpcURL)
	if err != nil {
		return nil, fmt.Errorf("dial rpc: %w", err)
	}

	return &ContractClient{
		client:       client,
		contractAddr: common.HexToAddress(contractAddress),
		privateKey:   privateKey,
	}, nil
}

type PermitSignature struct {
	V uint8
	R [32]byte
	S [32]byte
}

type AuthorizeChargeWithPermitParams struct {
	Identity        common.Address
	Payer           common.Address
	ExpectedAmount  *big.Int
	TargetAllowance *big.Int
	Deadline        *big.Int
	Signature       PermitSignature
}

type ChargeParams struct {
	Identity common.Address
	Payer    common.Address
	ChargeID *big.Int
	Amount   *big.Int
}

func (c *ContractClient) AuthorizeChargeWithPermit(ctx context.Context, params AuthorizeChargeWithPermitParams) (string, error) {
	return "", fmt.Errorf("not implemented: contract binding required")
}

func (c *ContractClient) Charge(ctx context.Context, params ChargeParams) (string, error) {
	return "", fmt.Errorf("not implemented: contract binding required")
}

func (c *ContractClient) GetAllowance(ctx context.Context, identity, payer common.Address) (*big.Int, error) {
	return nil, fmt.Errorf("not implemented: contract binding required")
}

func (c *ContractClient) Close() {
	if c.client != nil {
		c.client.Close()
	}
}
