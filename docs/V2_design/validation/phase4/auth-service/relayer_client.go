package main

import (
	"context"
	"fmt"
	"math/big"
	"os"
	"strings"
	"time"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
)

const authorizeChargeWithPermitABI = `[
  {
    "inputs": [
      {"internalType": "address", "name": "user", "type": "address"},
      {"internalType": "address", "name": "identityAddress", "type": "address"},
      {"internalType": "uint256", "name": "expectedAllowance", "type": "uint256"},
      {"internalType": "uint256", "name": "targetAllowance", "type": "uint256"},
      {"internalType": "uint256", "name": "deadline", "type": "uint256"},
      {"internalType": "uint8", "name": "v", "type": "uint8"},
      {"internalType": "bytes32", "name": "r", "type": "bytes32"},
      {"internalType": "bytes32", "name": "s", "type": "bytes32"}
    ],
    "name": "authorizeChargeWithPermit",
    "outputs": [],
    "stateMutability": "nonpayable",
    "type": "function"
  }
]`

type RelayerClient struct {
	rpcURL          string
	privateKeyHex   string
	vaultAddress    common.Address
	chainID         *big.Int
	gasLimit        uint64
	client          *ethclient.Client
	contractABI     abi.ABI
}

type AuthorizePermitChainRequest struct {
	UserAddress       string
	IdentityAddress   string
	ExpectedAllowance int
	TargetAllowance   int
	Deadline          int64
	SignatureV        uint8
	SignatureR        string
	SignatureS        string
}

func NewRelayerClient() (*RelayerClient, error) {
	rpcURL := firstNonEmpty(
		os.Getenv("CHAIN_RPC_URL"),
		os.Getenv("BASE_RPC_URL"),
		os.Getenv("BASE_SEPOLIA_RPC_URL"),
	)
	if rpcURL == "" {
		return nil, fmt.Errorf("CHAIN_RPC_URL or BASE_SEPOLIA_RPC_URL is required")
	}

	privateKeyHex := firstNonEmpty(
		os.Getenv("RELAYER_PRIVATE_KEY"),
		os.Getenv("PRIVATE_KEY"),
	)
	if privateKeyHex == "" {
		return nil, fmt.Errorf("RELAYER_PRIVATE_KEY or PRIVATE_KEY is required")
	}

	vaultAddressHex := firstNonEmpty(
		os.Getenv("VAULT_CONTRACT_ADDRESS"),
		os.Getenv("VPN_SUBSCRIPTION_CONTRACT"),
	)
	if !common.IsHexAddress(vaultAddressHex) {
		return nil, fmt.Errorf("valid VAULT_CONTRACT_ADDRESS or VPN_SUBSCRIPTION_CONTRACT is required")
	}

	parsedABI, err := abi.JSON(strings.NewReader(authorizeChargeWithPermitABI))
	if err != nil {
		return nil, fmt.Errorf("parse authorize ABI: %w", err)
	}

	client, err := ethclient.Dial(rpcURL)
	if err != nil {
		return nil, fmt.Errorf("dial rpc: %w", err)
	}

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	chainID, err := client.ChainID(ctx)
	if err != nil {
		return nil, fmt.Errorf("read chain id: %w", err)
	}

	return &RelayerClient{
		rpcURL:        rpcURL,
		privateKeyHex: privateKeyHex,
		vaultAddress:  common.HexToAddress(vaultAddressHex),
		chainID:       chainID,
		gasLimit:      350000,
		client:        client,
		contractABI:   parsedABI,
	}, nil
}

func (c *RelayerClient) AuthorizeChargeWithPermit(req AuthorizePermitChainRequest) (string, error) {
	if !common.IsHexAddress(req.UserAddress) {
		return "", fmt.Errorf("invalid user address")
	}
	if !common.IsHexAddress(req.IdentityAddress) {
		return "", fmt.Errorf("invalid identity address")
	}
	if req.TargetAllowance <= 0 {
		return "", fmt.Errorf("target allowance must be greater than zero")
	}
	if req.Deadline <= 0 {
		return "", fmt.Errorf("deadline must be greater than zero")
	}

	rBytes, err := hexToBytes32(req.SignatureR)
	if err != nil {
		return "", fmt.Errorf("invalid signature_r: %w", err)
	}
	sBytes, err := hexToBytes32(req.SignatureS)
	if err != nil {
		return "", fmt.Errorf("invalid signature_s: %w", err)
	}
	if req.SignatureV < 27 {
		req.SignatureV += 27
	}

	data, err := c.contractABI.Pack(
		"authorizeChargeWithPermit",
		common.HexToAddress(req.UserAddress),
		common.HexToAddress(req.IdentityAddress),
		big.NewInt(int64(req.ExpectedAllowance)),
		big.NewInt(int64(req.TargetAllowance)),
		big.NewInt(req.Deadline),
		req.SignatureV,
		rBytes,
		sBytes,
	)
	if err != nil {
		return "", fmt.Errorf("pack authorize call: %w", err)
	}

	privateKey, err := crypto.HexToECDSA(strings.TrimPrefix(c.privateKeyHex, "0x"))
	if err != nil {
		return "", fmt.Errorf("parse relayer private key: %w", err)
	}
	signerAddress := crypto.PubkeyToAddress(privateKey.PublicKey)

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	nonce, err := c.client.PendingNonceAt(ctx, signerAddress)
	if err != nil {
		return "", fmt.Errorf("load nonce: %w", err)
	}

	gasPrice, err := c.client.SuggestGasPrice(ctx)
	if err != nil {
		return "", fmt.Errorf("suggest gas price: %w", err)
	}

	msg := ethereum.CallMsg{From: signerAddress, To: &c.vaultAddress, Data: data}
	gasLimit, err := c.client.EstimateGas(ctx, msg)
	if err != nil {
		gasLimit = c.gasLimit
	}

	tx := types.NewTransaction(nonce, c.vaultAddress, big.NewInt(0), gasLimit, gasPrice, data)
	signedTx, err := types.SignTx(tx, types.NewLondonSigner(c.chainID), privateKey)
	if err != nil {
		return "", fmt.Errorf("sign tx: %w", err)
	}

	if err := c.client.SendTransaction(ctx, signedTx); err != nil {
		return "", fmt.Errorf("send tx: %w", err)
	}

	return signedTx.Hash().Hex(), nil
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
}

func hexToBytes32(value string) ([32]byte, error) {
	var out [32]byte
	if !strings.HasPrefix(strings.ToLower(value), "0x") {
		return out, fmt.Errorf("must be hex")
	}
	bytes := common.FromHex(value)
	if len(bytes) != 32 {
		return out, fmt.Errorf("expected 32 bytes, got %d", len(bytes))
	}
	copy(out[:], bytes)
	return out, nil
}
