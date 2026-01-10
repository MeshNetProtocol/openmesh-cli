# OpenMesh Go Library

This is a Go library that provides functionality for managing cryptocurrency wallets, particularly for EVM-compatible blockchains. The library is designed to be used with mobile applications via GoMobile bindings.

## Features

- Generate BIP-39 compliant 12-word mnemonics
- Derive EVM wallets using BIP-44 standard (m/44'/60'/0'/0/0 path)
- Encrypt wallet data with PIN-based encryption (AES-GCM)
- Decrypt wallet data to retrieve private keys and mnemonics

## API

### `NewLib() *AppLib`

Creates a new instance of the OpenMesh library.

### `InitApp(config []byte) error`

Initializes the library with configuration data.

### `GenerateMnemonic12() (string, error)`

Generates a 12-word mnemonic according to BIP-39 standard.

### `CreateEvmWallet(mnemonic string, pin string) (string, error)`

Creates an EVM wallet from a mnemonic and encrypts it with a PIN. Returns an encrypted envelope containing the wallet data.

### `DecryptEvmWallet(envelopeJSON string, pin string) (*walletSecretsV1, error)`

Decrypts the wallet envelope using the PIN and returns the original secrets.

## Security

- Wallets are encrypted using AES-GCM with keys derived from the PIN and a random salt
- Private keys are never stored in plain text
- The encryption scheme uses a unique salt for each wallet to prevent rainbow table attacks

## Building for iOS

To build the library for iOS as an XCFramework:

```bash
cd go-cli-lib
make ios
```

This will create an XCFramework in the `./lib` directory that can be integrated into iOS projects.

For faster builds during development (simulator only):

```bash
make ios-fast-sim
```

## Example Usage

See the [example](example/main.go) directory for a complete example of how to use the library.

```go
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
}
```