package lib_test

import (
	"fmt"
	"testing"

	openmesh "github.com/MeshNetProtocol/openmesh-cli/go-cli-lib/interface"
)

// 预设的测试地址和网络配置
const testAddress = "0x0be98493Af5bC50D938A91BCFAb8E8e9411C74a5" // 示例测试地址，实际使用时替换为有效地址

var testNetworks = []string{"base-mainnet", "base-testnet"}

func TestGetSupportedNetworks(t *testing.T) {
	app := openmesh.NewLib()

	supportedNetworks, err := app.GetSupportedNetworks()
	if err != nil {
		t.Fatalf("Error getting supported networks: %v", err)
	}

	if len(supportedNetworks) == 0 {
		t.Fatal("No supported networks returned")
	}

	t.Logf("Supported Networks: %s", supportedNetworks)
}

func TestGetTokenBalance(t *testing.T) {
	app := openmesh.NewLib()

	// 使用预设的测试地址，而不是每次都生成新钱包
	for _, network := range testNetworks {
		t.Run(fmt.Sprintf("Balance_%s", network), func(t *testing.T) {
			balance, err := app.GetTokenBalance(testAddress, "USDC", network)
			if err != nil {
				t.Logf("Error getting %s USDC balance for address %s: %v", network, testAddress, err)
			} else {
				t.Logf("%s USDC Balance for %s: %s", network, testAddress, balance)
			}
		})
	}
}

func TestTokenBalanceQuery(t *testing.T) {
	// Create a new instance of the OpenMesh library
	lib := openmesh.NewLib()

	// Display supported networks
	supportedNetworks, err := lib.GetSupportedNetworks()
	if err != nil {
		t.Fatalf("Error getting supported networks: %v", err)
	}
	t.Logf("Supported networks: %s", supportedNetworks)

	// Query USDC balance on Base mainnet
	t.Logf("\nQuerying USDC balance for address %s on Base mainnet...\n", testAddress)
	baseMainnetBalance, err := lib.GetTokenBalance(testAddress, "USDC", "base-mainnet")
	if err != nil {
		t.Logf("Error getting Base mainnet USDC balance: %v\n", err)
	} else {
		t.Logf("Base mainnet USDC balance: %s\n", baseMainnetBalance)
	}

	// Query USDC balance on Base testnet
	t.Logf("\nQuerying USDC balance for address %s on Base testnet...\n", testAddress)
	baseTestnetBalance, err := lib.GetTokenBalance(testAddress, "USDC", "base-testnet")
	if err != nil {
		t.Logf("Error getting Base testnet USDC balance: %v\n", err)
	} else {
		t.Logf("Base testnet USDC balance: %s\n", baseTestnetBalance)
	}
}
