package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"strconv"

	x402 "github.com/coinbase/x402/go"
	x402http "github.com/coinbase/x402/go/http"
	evm "github.com/coinbase/x402/go/mechanisms/evm/exact/server"
	"github.com/coinbase/x402/go/types"
	"github.com/gin-gonic/gin"
)

// Global variables for dynamic PayTo and Price
var payTo = "0x5926cbdc9ea2509c47d9dcd837266d4d74ca481c"
var price = "$0.01"

// Global variable to control network (defaults to testnet)
var useMainnet = false

func init() {
	// Check environment variable to determine network
	mainnetEnv := os.Getenv("USE_MAINNET")
	if mainnetEnv == "true" || mainnetEnv == "1" {
		useMainnet = true
	}
}

func main() {
	r := gin.Default()

	var networkID string

	if useMainnet {
		log.Println("Starting x402 server on mainnet mode")
		networkID = "eip155:8453" // Base mainnet
	} else {
		log.Println("Starting x402 server on testnet mode")
		networkID = "eip155:84532" // Base sepolia testnet
	}

	// Create facilitator client
	facilitator := x402http.NewHTTPFacilitatorClient(&x402http.FacilitatorConfig{
		URL: getFacilitatorURL(),
	})

	// Create the x402 resource server
	server := x402.Newx402ResourceServer(
		x402.WithFacilitatorClient(facilitator),
		x402.WithSchemeServer(x402.Network(networkID), evm.NewExactEvmScheme()),
	)

	// Initialize the server
	ctx := context.Background()
	if err := server.Initialize(ctx); err != nil {
		log.Fatalf("Failed to initialize server: %v", err)
	}

	// Protected endpoint handler
	r.GET("/test", func(c *gin.Context) {
		ctx := c.Request.Context()

		// Initialize server before use
		if err := server.Initialize(ctx); err != nil {
			log.Printf("Failed to initialize server: %v", err)
			c.JSON(500, gin.H{"error": "server initialization failed"})
			return
		}
		// Build payment requirements for the resource
		config := x402.ResourceConfig{
			Scheme:            "exact",
			PayTo:             payTo,
			Price:             price,
			Network:           x402.Network(networkID),
			MaxTimeoutSeconds: 600,
		}

		supportedKind := types.SupportedKind{
			Scheme:  "exact",
			Network: networkID,
		}

		requirements, err := server.BuildPaymentRequirements(ctx, config, supportedKind, []string{})
		if err != nil {
			log.Printf("Error building payment requirements: %v", err)
			c.JSON(500, gin.H{"error": "failed to build payment requirements"})
			return
		}

		// 2. Get payment payload from request header
		payloadHeader := c.GetHeader("X-402-Payment")
		if payloadHeader == "" {
			// Return 402 with payment requirements
			jsonBytes, err := json.Marshal(requirements)
			if err != nil {
				log.Printf("Error marshaling requirements: %v", err)
				c.JSON(500, gin.H{"error": "failed to marshal requirements"})
				return
			}
			c.Header("X-402-Payment-Required", string(jsonBytes))
			c.JSON(402, gin.H{"error": "payment required"})
			return
		}

		// Parse payload header into PaymentPayload
		var payload types.PaymentPayload
		err = json.Unmarshal([]byte(payloadHeader), &payload)
		if err != nil {
			log.Printf("Error parsing payment payload: %v", err)
			c.JSON(402, gin.H{"error": "invalid payment payload"})
			return
		}

		// 3. Verify payment
		_, err = server.VerifyPayment(ctx, payload, requirements)
		if err != nil {
			log.Printf("Payment verification failed: %v", err)
			c.JSON(402, gin.H{"error": "payment verification failed"})
			return
		}

		// 4. Settle payment
		settleResult, err := server.SettlePayment(ctx, payload, requirements)
		if err != nil {
			log.Printf("Failed to settle payment: %v", err)
			c.JSON(500, gin.H{"error": "failed to settle payment"})
			return
		}

		// 5. Return the resource with settlement result
		response := gin.H{
			"result":     "success",
			"message":    "Payment verified and resource returned",
			"network":    networkID,
			"useMainnet": useMainnet,
			"settleResult": gin.H{
				"success":     settleResult.Success,
				"transaction": settleResult.Transaction,
				"payer":       settleResult.Payer,
				"network":     string(settleResult.Network),
				"errorReason": settleResult.ErrorReason,
			},
		}

		c.JSON(200, response)
	})

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok", "network_mode": strconv.FormatBool(useMainnet)})
	})

	log.Println("Starting x402 server on :7788")
	if err := r.Run("0.0.0.0:7788"); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}

func getFacilitatorURL() string {
	if useMainnet {
		// For mainnet, use Coinbase CDP facilitator
		return "https://api.cdp.coinbase.com/platform/v2/x402"
	}

	// For testnet, use x402.org testnet facilitator
	return "https://x402.org/facilitator"
}
