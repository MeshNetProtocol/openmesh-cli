package openmesh

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"math/big"
	"strings"

	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/keystore"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/google/uuid"
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
func (a *AppLib) DecryptEvmWallet(keystoreJSON string, password string) (*WalletSecretsV1, error) {
	// Use go-ethereum's keystore to decrypt
	key, err := keystore.DecryptKey([]byte(keystoreJSON), password)
	if err != nil {
		return nil, fmt.Errorf("failed to decrypt keystore: %w", err)
	}

	privKeyHex := hex.EncodeToString(crypto.FromECDSA(key.PrivateKey))
	address := crypto.PubkeyToAddress(key.PrivateKey.PublicKey).Hex()

	// Note: We can't return the original mnemonic from the keystore
	// The keystore only contains the encrypted private key
	return &WalletSecretsV1{
		V:             1,
		PrivateKeyHex: privKeyHex,
		Address:       address,
	}, nil
}

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

// GetTokenBalance queries the balance of an ERC20 token for a given address on a specific network
func (a *AppLib) GetTokenBalance(address string, tokenName string, networkName string) (string, error) {
	// Validate inputs to avoid any potential issues
	if address == "" || tokenName == "" || networkName == "" {
		return "0.00", fmt.Errorf("invalid input parameters")
	}

	network, exists := Networks[networkName]
	if !exists {
		return "0.00", fmt.Errorf("network %s not supported", networkName)
	}

	tokenAddr, tokenExists := network.USDCAddresses[tokenName]
	if !tokenExists {
		return "0.00", fmt.Errorf("%s token not available on %s network", tokenName, networkName)
	}

	client, err := ethclient.Dial(network.RPCUrl)
	if err != nil {
		return "0.00", fmt.Errorf("failed to connect to network %s: %w", networkName, err)
	}
	defer client.Close()

	// Prepare the contract call for balanceOf
	// Define the function signature
	parsedABI, err := abi.JSON(strings.NewReader(`[
		{"constant":true,"inputs":[{"name":"_owner","type":"address"}],"name":"balanceOf","outputs":[{"name":"balance","type":"uint256"}],"payable":false,"stateMutability":"view","type":"function"}
	]`))
	if err != nil {
		return "0.00", fmt.Errorf("failed to parse ABI: %w", err)
	}

	// Pack the function call with the address parameter
	data, err := parsedABI.Pack("balanceOf", common.HexToAddress(address))
	if err != nil {
		return "0.00", fmt.Errorf("failed to pack data: %w", err)
	}

	// Create the contract call message using ethereum.CallMsg
	toAddr := common.HexToAddress(tokenAddr)
	msg := ethereum.CallMsg{
		To:   &toAddr,
		Data: data,
	}

	result, err := client.CallContract(context.Background(), msg, nil)
	if err != nil {
		return "0.00", fmt.Errorf("failed to call contract: %w", err)
	}

	// Convert result to big.Int
	balance := new(big.Int).SetBytes(result)

	// For USDC, we typically need to handle decimals (6 for USDC)
	// Divide by 10^6 to get the actual amount
	decimals := new(big.Int).Exp(big.NewInt(10), big.NewInt(6), nil)
	wholePart := new(big.Int).Div(balance, decimals)
	decimalPart := new(big.Int).Mod(balance, decimals)

	// Format as readable string
	decimalStr := fmt.Sprintf("%06s", decimalPart.String())
	decimalStr = decimalStr[len(decimalStr)-6:] // Ensure exactly 6 digits

	return fmt.Sprintf("%s.%s", wholePart.String(), decimalStr), nil
}

// GetSupportedNetworks returns a list of supported networks as a JSON string
func (a *AppLib) GetSupportedNetworks() (string, error) {
	networks := make([]string, 0, len(Networks))
	for name := range Networks {
		networks = append(networks, name)
	}

	jsonData, err := json.Marshal(networks)
	if err != nil {
		return "", err
	}

	return string(jsonData), nil
}
