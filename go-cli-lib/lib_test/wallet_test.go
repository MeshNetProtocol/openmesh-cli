package lib_test

import (
	"encoding/json"
	"testing"

	openmesh "github.com/MeshNetProtocol/openmesh-cli/go-cli-lib/interface"
	"github.com/ethereum/go-ethereum/crypto"
)

func TestGenerateMnemonic(t *testing.T) {
	app := openmesh.NewLib()

	mnemonic, err := app.GenerateMnemonic12()
	if err != nil {
		t.Fatalf("Error generating mnemonic: %v", err)
	}

	if len(mnemonic) == 0 {
		t.Fatal("Generated mnemonic is empty")
	}

	t.Logf("Generated Mnemonic: %s", mnemonic)
}

func TestCreateAndDecryptWallet(t *testing.T) {
	app := openmesh.NewLib()

	// Generate a mnemonic
	mnemonic, err := app.GenerateMnemonic12()
	if err != nil {
		t.Fatalf("Error generating mnemonic: %v", err)
	}

	// Create an EVM wallet from mnemonic
	password := "securePassword123"
	keystoreJSON, err := app.CreateEvmWallet(mnemonic, password)
	if err != nil {
		t.Fatalf("Error creating wallet: %v", err)
	}

	if len(keystoreJSON) == 0 {
		t.Fatal("Created keystore is empty")
	}

	// Decrypt the wallet
	wallet, err := app.DecryptEvmWallet(keystoreJSON, password)
	if err != nil {
		t.Fatalf("Error decrypting wallet: %v", err)
	}

	if wallet.Address == "" {
		t.Fatal("Decrypted wallet address is empty")
	}

	t.Logf("Decrypted Wallet Address: %s", wallet.Address)
}

func TestFullWalletFlow(t *testing.T) {
	// Create a new instance of the OpenMesh library
	lib := openmesh.NewLib()

	// Generate a 12-word mnemonic
	mnemonic, err := lib.GenerateMnemonic12()
	if err != nil {
		t.Fatalf("Error generating mnemonic: %v", err)
	}

	t.Logf("Generated mnemonic: %s", mnemonic)

	// Create an EVM wallet using the mnemonic and a PIN
	pin := "123456" // 6-digit PIN
	walletData, err := lib.CreateEvmWallet(mnemonic, pin)
	if err != nil {
		t.Fatalf("Error creating wallet: %v", err)
	}

	t.Logf("Created wallet: %s", walletData)

	// Parse the wallet data to get the address
	var walletInfo map[string]interface{}
	if err := json.Unmarshal([]byte(walletData), &walletInfo); err != nil {
		t.Fatalf("Error parsing wallet data: %v", err)
	}

	address := walletInfo["address"]
	t.Logf("Wallet address: %v", address)

	// Decrypt the wallet using the PIN to retrieve the secrets
	secrets, err := lib.DecryptEvmWallet(walletData, pin)
	if err != nil {
		t.Fatalf("Error decrypting wallet: %v", err)
	}

	t.Logf("Decrypted wallet secrets:")
	t.Logf("  Version: %d", secrets.V)
	t.Logf("  Address: %s", secrets.Address)
	t.Logf("  Private Key (hex): %s", secrets.PrivateKeyHex)

	// Note: We can't retrieve the original mnemonic from the keystore
	// This is by design for security purposes
	t.Log("Note: Original mnemonic cannot be retrieved from standard keystore")
	t.Log("Success: Wallet was created and decrypted successfully!")
}

func TestPrintPrivateKeyAddress(t *testing.T) {
	privateKeyHex := "a897823a4544e741b6ab08da8b6cf25e16c7c9d7ea8a7a1987fe5cf68c77e37c"

	// Convert hex string to private key
	privateKey, err := crypto.HexToECDSA(privateKeyHex)
	if err != nil {
		t.Fatalf("Error converting hex to ECDSA: %v", err)
	}

	// Derive the address from the public key
	address := crypto.PubkeyToAddress(privateKey.PublicKey).Hex()

	t.Logf("Private Key: %s", privateKeyHex)
	t.Logf("Corresponding Address: 0x%s", address)
}
