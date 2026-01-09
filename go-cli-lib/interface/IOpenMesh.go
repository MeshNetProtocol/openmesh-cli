package openmesh

import (
	"crypto/ecdsa"
	"encoding/hex"
	"errors"
	"fmt"

	"github.com/ethereum/go-ethereum/accounts/keystore"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/google/uuid"
	"github.com/tyler-smith/go-bip32"
	"github.com/tyler-smith/go-bip39"
)

type AppLib struct {
	config []byte
}

func NewLib() *AppLib {
	return &AppLib{}
}

func (a *AppLib) InitApp(config []byte) error {
	a.config = append([]byte(nil), config...)
	return nil
}

func (a *AppLib) GenerateMnemonic12() (string, error) {
	entropy, err := bip39.NewEntropy(128)
	if err != nil {
		return "", err
	}
	return bip39.NewMnemonic(entropy)
}

// DecryptEvmWallet decodes the encrypted wallet keystore and returns the private key
func (a *AppLib) DecryptEvmWallet(keystoreJSON string, password string) (*walletSecretsV1, error) {
	// Use go-ethereum's keystore to decrypt
	key, err := keystore.DecryptKey([]byte(keystoreJSON), password)
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt keystore: %w", err)
	}

	privKeyHex := hex.EncodeToString(crypto.FromECDSA(key.PrivateKey))
	address := crypto.PubkeyToAddress(key.PrivateKey.PublicKey).Hex()

	// Note: We can't return the original mnemonic from the keystore
	// The keystore only contains the encrypted private key
	return &walletSecretsV1{
		V:             1,
		PrivateKeyHex: privKeyHex,
		Address:       address,
	}, nil
}

const (
	evmDerivationPath = "m/44'/60'/0'/0/0"
)

// CreateEvmWallet:
// - 验证 mnemonic
// - 按 BIP44(m/44'/60'/0'/0/0) 导出 EVM 私钥与地址
// - 用 password 创建 keystore 加密的私钥，返回标准 keystore JSON
func (a *AppLib) CreateEvmWallet(mnemonic string, password string) (string, error) {
	if !bip39.IsMnemonicValid(mnemonic) {
		return "", errors.New("invalid mnemonic")
	}

	privKey, _, err := deriveEvmKeyFromMnemonic(mnemonic)
	if err != nil {
		return "", err
	}

	// Create the encrypted keystore directly
	key := &keystore.Key{
		PrivateKey: privKey,
		Address:    crypto.PubkeyToAddress(privKey.PublicKey),
		Id:         uuid.New(),
	}

	// Encrypt the key to keystore format
	keyJSON, err := keystore.EncryptKey(key, password, keystore.StandardScryptN, keystore.StandardScryptP)
	if err != nil {
		return "", err
	}

	return string(keyJSON), nil
}

// ---- internal structs ----

type walletSecretsV1 struct {
	V             int    `json:"v"`
	Mnemonic      string `json:"mnemonic"`      // Note: This will be empty in DecryptEvmWallet result
	PrivateKeyHex string `json:"privateKeyHex"` // Available in DecryptEvmWallet result
	Address       string `json:"address"`       // Available in DecryptEvmWallet result
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