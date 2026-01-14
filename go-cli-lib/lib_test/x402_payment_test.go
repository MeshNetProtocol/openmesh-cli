package lib_test

import (
	"fmt"
	"testing"

	openmesh "github.com/MeshNetProtocol/openmesh-cli/go-cli-lib/interface"
)

// Private Key: a897823a4544e741b6ab08da8b6cf25e16c7c9d7ea8a7a1987fe5cf68c77e37c
// Corresponding Address: 0x0be98493Af5bC50D938A91BCFAb8E8e9411C74a5
func TestMakeX402Payment(t *testing.T) {
	// Use the original private key that contains funds
	privateKeyHex := "a897823a4544e741b6ab08da8b6cf25e16c7c9d7ea8a7a1987fe5cf68c77e37c"

	// Test with localhost:7788 server
	url := "http://localhost:7788/test"
	// Initialize the library
	lib := openmesh.NewLib()

	// Call the function
	result, err := lib.MakeX402Payment(url, privateKeyHex)
	if err != nil {
		t.Errorf("MakeX402Payment returned error: %v", err)
		return
	}

	fmt.Printf("MakeX402Payment result: %s\n", result)
}
