package openmesh

import (
	"context"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"strings"
	"time"

	x402 "github.com/coinbase/x402/go"
	x402http "github.com/coinbase/x402/go/http"
	evmclient "github.com/coinbase/x402/go/mechanisms/evm/exact/client"
	evmsigners "github.com/coinbase/x402/go/signers/evm"
	"github.com/ethereum/go-ethereum"
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/accounts/keystore"
	"github.com/ethereum/go-ethereum/common"
	"github.com/ethereum/go-ethereum/crypto"
	"github.com/ethereum/go-ethereum/ethclient"
	"github.com/google/uuid"
	"github.com/tyler-smith/go-bip39"
)

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

//	CreateEvmWallet:
//
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

type PaymentResult struct {
	Success bool                 `json:"success"`
	Body    string               `json:"body"`
	Settle  *x402.SettleResponse `json:"settle,omitempty"`
	Error   string               `json:"error,omitempty"`
}

// MakeX402Payment executes an x402 payment for a given URL using the specified network and private key
func (a *AppLib) MakeX402Payment(url string, privateKeyHex string) (string, error) {
	// Validate inputs
	if url == "" || privateKeyHex == "" {
		return "", fmt.Errorf("missing required parameters: url, networkName, or privateKey")
	}

	// Validate private key format
	privateKeyHex = strings.TrimPrefix(privateKeyHex, "0x")

	// Create EVM signer from private key
	evmSigner, err := evmsigners.NewClientSignerFromPrivateKey(privateKeyHex)
	if err != nil {
		return "", fmt.Errorf("failed to create EVM signer: %w", err)
	}

	// Create x402 client and register the EVM scheme
	client := x402.Newx402Client().
		Register("eip155:*", evmclient.NewExactEvmScheme(evmSigner))

	// Create HTTP-aware x402 client
	x402HTTPClient := x402http.Newx402HTTPClient(client)

	// Wrap default HTTP client with x402 capabilities
	httpClient := x402http.WrapHTTPClientWithPayment(
		&http.Client{Timeout: 60 * time.Second},
		x402HTTPClient,
	)

	// Make the request - payment handling is automatic
	resp, err := httpClient.Get(url)
	if err != nil {
		return "", fmt.Errorf("failed to make x402 payment: %w", err)
	}
	defer resp.Body.Close()

	// Read response body
	bodyBytes, err := io.ReadAll(resp.Body)
	if err != nil {
		return "", fmt.Errorf("failed to read response body: %w", err)
	}

	out := &PaymentResult{
		Success: false,
		Body:    string(bodyBytes),
	}

	// 1) 非 200：直接失败（中间件会把错误原因放在 body 里）:contentReference[oaicite:6]{index=6}
	if resp.StatusCode != http.StatusOK {
		out.Error = fmt.Sprintf("non-200 response: %s", resp.Status)
		b, _ := json.Marshal(out)
		return string(b), fmt.Errorf("%s", out.Error)
	}

	paymentRespB64 := resp.Header.Get("PAYMENT-RESPONSE")
	if paymentRespB64 == "" {
		// 严格模式：你想“只有结算成功才继续”，那缺少回执就当失败
		out.Error = "missing PAYMENT-RESPONSE header (no settlement receipt)"
		b, _ := json.Marshal(out)
		return string(b), fmt.Errorf("%s", out.Error)
	}
	raw, err := base64.StdEncoding.DecodeString(paymentRespB64)
	if err != nil {
		out.Error = fmt.Sprintf("decode PAYMENT-RESPONSE failed: %v", err)
		b, _ := json.Marshal(out)
		return string(b), fmt.Errorf("%s", out.Error)
	}

	var settle x402.SettleResponse
	if err := json.Unmarshal(raw, &settle); err != nil {
		out.Error = fmt.Sprintf("unmarshal settlement failed: %v", err)
		b, _ := json.Marshal(out)
		return string(b), fmt.Errorf("%s", out.Error)
	}
	out.Settle = &settle

	if !settle.Success {
		out.Error = fmt.Sprintf("settlement failed: %s (tx=%s payer=%s network=%s)",
			settle.ErrorReason, settle.Transaction, settle.Payer, string(settle.Network))
		b, _ := json.Marshal(out)
		return string(b), fmt.Errorf("%s", out.Error)
	}

	out.Success = true

	b, _ := json.Marshal(out)
	return string(b), nil
}
