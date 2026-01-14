package openmesh

import (
	"crypto/ecdsa"
	"fmt"

	"github.com/ethereum/go-ethereum/crypto"
	"github.com/tyler-smith/go-bip32"
	"github.com/tyler-smith/go-bip39"
)

// WalletSecretsV1 is the struct to hold wallet information
type WalletSecretsV1 struct {
	V             int    `json:"v"`
	PrivateKeyHex string `json:"privateKeyHex"` // Available in DecryptWallet result
	Address       string `json:"address"`       // Available in DecryptWallet result
}

// Network represents blockchain network information
type Network struct {
	Name          string            `json:"name"`
	RPCUrl        string            `json:"rpcUrl"`
	ChainID       int64             `json:"chainId"`
	USDCAddresses map[string]string `json:"usdcAddresses"`
}

// Networks Predefined networks
var Networks = map[string]Network{
	"base-mainnet": {
		Name:    "Base Mainnet",
		RPCUrl:  "https://mainnet.base.org",
		ChainID: 8453,
		USDCAddresses: map[string]string{
			"USDC": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913", // Base official USDC
		},
	},
	"base-testnet": {
		Name:    "Base Testnet",
		RPCUrl:  "https://sepolia.base.org",
		ChainID: 84532,
		USDCAddresses: map[string]string{
			"USDC": "0x036CbD53842c5426634e7929541eC2318f3dCF7e", // USDC on Base Sepolia Testnet
		},
	},
}

// BIP44: m/44'/60'/0'/0/0
func deriveEvmKeyFromMnemonic(mnemonic string) (*ecdsa.PrivateKey, string, error) {
	seed := bip39.NewSeed(mnemonic, "")
	master, err := bip32.NewMasterKey(seed)
	if err != nil {
		return nil, "", err
	}

	path := []uint32{
		44 + bip32.FirstHardenedChild,
		60 + bip32.FirstHardenedChild,
		0 + bip32.FirstHardenedChild,
		0,
		0,
	}

	k := master
	for i, child := range path {
		k, err = k.NewChildKey(child)
		if err != nil {
			return nil, "", fmt.Errorf("derive step %d failed: %w", i, err)
		}
	}

	// go-bip32 private key: 33 bytes, first byte 0x00
	privBytes := k.Key
	if len(privBytes) == 33 && privBytes[0] == 0x00 {
		privBytes = privBytes[1:]
	}
	if len(privBytes) != 32 {
		return nil, "", fmt.Errorf("unexpected private key length: %d", len(privBytes))
	}

	ecdsaPriv, err := crypto.ToECDSA(privBytes)
	if err != nil {
		return nil, "", err
	}

	addr := crypto.PubkeyToAddress(ecdsaPriv.PublicKey).Hex()
	return ecdsaPriv, addr, nil
}
