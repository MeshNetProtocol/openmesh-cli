package main

import (
	"encoding/json"
	"fmt"
	"log"

	openmesh "github.com/MeshNetProtocol/openmesh-cli/go-cli-lib/interface"
)

func main() {
	// Create a new instance of the OpenMesh library
	lib := openmesh.NewLib()

	// Generate a 12-word mnemonic
	mnemonic, err := lib.GenerateMnemonic12()
	if err != nil {
		log.Fatalf("Error generating mnemonic: %v", err)
	}

	fmt.Printf("Generated mnemonic: %s\n", mnemonic)

	// Create an EVM wallet using the mnemonic and a PIN
	pin := "123456" // 6-digit PIN
	walletData, err := lib.CreateEvmWallet(mnemonic, pin)
	if err != nil {
		log.Fatalf("Error creating wallet: %v", err)
	}

	fmt.Printf("Created wallet: %s\n", walletData)

	// Parse the wallet data to get the address
	var walletInfo map[string]interface{}
	if err := json.Unmarshal([]byte(walletData), &walletInfo); err != nil {
		log.Fatalf("Error parsing wallet data: %v", err)
	}

	address := walletInfo["address"]
	fmt.Printf("Wallet address: %v\n", address)

	// Decrypt the wallet using the PIN to retrieve the secrets
	secrets, err := lib.DecryptEvmWallet(walletData, pin)
	if err != nil {
		log.Fatalf("Error decrypting wallet: %v", err)
	}

	fmt.Printf("Decrypted wallet secrets:\n")
	fmt.Printf("  Version: %d\n", secrets.V)
	fmt.Printf("  Mnemonic: %s\n", secrets.Mnemonic)
	fmt.Printf("  Private Key (hex): %s\n", secrets.PrivateKeyHex)

	// Verify that the mnemonic we used to create the wallet is the same as the one retrieved
	if secrets.Mnemonic == mnemonic {
		fmt.Println("Success: Retrieved mnemonic matches the original!")
	} else {
		fmt.Println("Error: Retrieved mnemonic does not match the original")
	}
}