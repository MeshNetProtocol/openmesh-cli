package main

import (
	"log"
	"os"
	"strconv"
	"time"

	x402 "github.com/coinbase/x402/go"
	x402http "github.com/coinbase/x402/go/http"
	ginmw "github.com/coinbase/x402/go/http/gin"
	evm "github.com/coinbase/x402/go/mechanisms/evm/exact/server"
	"github.com/gin-gonic/gin"
)

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
	var price string

	if useMainnet {
		log.Println("Starting x402 server on mainnet mode")
		networkID = "eip155:8453" // Base mainnet
		price = "$0.01"           // Default price: $0.01
	} else {
		log.Println("Starting x402 server on testnet mode")
		networkID = "eip155:84532" // Base sepolia testnet
		price = "$0.01"            // Default price: $0.01
	}

	// 1. Configure payment routes
	routes := x402http.RoutesConfig{
		"GET /test": {
			Accepts: x402http.PaymentOptions{
				{
					Scheme:  "exact",
					PayTo:   "0x5926cbdc9ea2509c47d9dcd837266d4d74ca481c", // Updated to the correct address
					Price:   price,
					Network: x402.Network(networkID),
				},
			},
			Description: "Test endpoint for x402 payment",
			MimeType:    "application/json",
		},
	}

	// 2. Create facilitator client
	facilitator := x402http.NewHTTPFacilitatorClient(&x402http.FacilitatorConfig{
		URL: getFacilitatorURL(),
	})

	// 3. Add payment middleware
	r.Use(ginmw.X402Payment(ginmw.Config{
		Routes:      routes,
		Facilitator: facilitator,
		Schemes: []ginmw.SchemeConfig{
			{Network: x402.Network(networkID), Server: evm.NewExactEvmScheme()},
		},
		Timeout: 30 * time.Second, // Set timeout for operations
	}))

	// 4. Protected endpoint handler
	r.GET("/test", func(c *gin.Context) {
		c.JSON(200, gin.H{
			"result":     "success",
			"message":    "Payment verified and resource returned",
			"network":    networkID,
			"useMainnet": useMainnet,
		})
	})

	// Health check endpoint
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok", "network_mode": strconv.FormatBool(useMainnet)})
	})

	log.Println("Starting x402 server on :7788")
	if err := r.Run(":7788"); err != nil {
		log.Fatal("Failed to start server:", err)
	}
}

func getFacilitatorURL() string {
	if useMainnet {
		// For mainnet, use Coinbase CDP facilitator
		return "https://api.cdp.coinbase.com/platform/v2/x402"
	} else {
		// For testnet, use x402.org testnet facilitator
		return "https://x402.org/facilitator"
	}
}
