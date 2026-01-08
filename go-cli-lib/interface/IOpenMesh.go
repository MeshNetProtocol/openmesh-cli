package openmesh

import (
	"crypto/aes"
	"crypto/cipher"
	"crypto/ecdsa"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/tyler-smith/go-bip32"
	"github.com/tyler-smith/go-bip39"

	"github.com/ethereum/go-ethereum/crypto"
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

const (
	evmDerivationPath = "m/44'/60'/0'/0/0"
)

// CreateEvmWallet:
// - 验证 mnemonic
// - 按 BIP44(m/44'/60'/0'/0/0) 导出 EVM 私钥与地址
// - 用 pin 派生 key 加密 secrets（AES-GCM），返回 JSON（含 address/path/envelope）
func (a *AppLib) CreateEvmWallet(mnemonic string, pin string) (string, error) {
	if !bip39.IsMnemonicValid(mnemonic) {
		return "", errors.New("invalid mnemonic")
	}
	if err := validatePin6(pin); err != nil {
		return "", err
	}

	privKey, addressHex, err := deriveEvmKeyFromMnemonic(mnemonic)
	if err != nil {
		return "", err
	}

	// secrets：你也可以只存 privateKeyHex，不存 mnemonic（看你后续策略）
	secrets := walletSecretsV1{
		V:             1,
		Mnemonic:      mnemonic,
		PrivateKeyHex: hex.EncodeToString(crypto.FromECDSA(privKey)), // 32 bytes hex
	}
	plain, err := json.Marshal(secrets)
	if err != nil {
		return "", err
	}

	env, err := encryptWithPinEnvelopeV1(plain, pin)
	if err != nil {
		return "", err
	}
	env.Address = addressHex
	env.DerivationPath = evmDerivationPath

	out, err := json.Marshal(env)
	if err != nil {
		return "", err
	}
	return string(out), nil
}

// ---- internal structs ----

type walletSecretsV1 struct {
	V             int    `json:"v"`
	Mnemonic      string `json:"mnemonic"`
	PrivateKeyHex string `json:"privateKeyHex"`
}

// 返回给 Swift 保存的 envelope：salt + combined(nonce|ciphertext|tag)
type evmWalletEnvelopeV1 struct {
	V              int    `json:"v"`
	CreatedAt      int64  `json:"createdAt"`
	SaltB64        string `json:"saltB64"`
	CombinedB64    string `json:"combinedB64"`
	Address        string `json:"address"`
	DerivationPath string `json:"derivationPath"`
}

// ---- helpers ----

func validatePin6(pin string) error {
	if len(pin) != 6 {
		return errors.New("PIN must be 6 digits")
	}
	for _, c := range pin {
		if c < '0' || c > '9' {
			return errors.New("PIN must be 6 digits")
		}
	}
	return nil
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

func encryptWithPinEnvelopeV1(plaintext []byte, pin string) (*evmWalletEnvelopeV1, error) {
	salt := make([]byte, 16)
	if _, err := rand.Read(salt); err != nil {
		return nil, err
	}

	// demo key: SHA256(pin || salt)
	key := sha256.Sum256(append([]byte(pin), salt...))

	block, err := aes.NewCipher(key[:])
	if err != nil {
		return nil, err
	}
	gcm, err := cipher.NewGCM(block)
	if err != nil {
		return nil, err
	}

	nonce := make([]byte, gcm.NonceSize())
	if _, err := rand.Read(nonce); err != nil {
		return nil, err
	}

	ciphertext := gcm.Seal(nil, nonce, plaintext, nil)
	combined := append(nonce, ciphertext...)

	return &evmWalletEnvelopeV1{
		V:           1,
		CreatedAt:   time.Now().Unix(),
		SaltB64:     base64.StdEncoding.EncodeToString(salt),
		CombinedB64: base64.StdEncoding.EncodeToString(combined),
	}, nil
}
