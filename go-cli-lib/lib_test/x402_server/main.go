// server/main.go
package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"log"
	"net/http"
	"strconv"
	"time"

	x402 "github.com/coinbase/x402/go"
	x402http "github.com/coinbase/x402/go/http"
	ginmw "github.com/coinbase/x402/go/http/gin"
	evm "github.com/coinbase/x402/go/mechanisms/evm/exact/server"
	"github.com/gin-gonic/gin"
)

// ✅ 临时测试：用全局变量模拟（你后面换成 DB 查询即可）
var payTo = "0x5926cbdc9ea2509c47d9dcd837266d4d74ca481c"
var price = "$0.01"

var useMainnet = false

func main() {
	r := gin.Default()

	var networkID string
	if useMainnet {
		log.Println("Starting x402 server on mainnet mode")
		networkID = "eip155:8453" // Base mainnet
	} else {
		log.Println("Starting x402 server on testnet mode")
		networkID = "eip155:84532" // Base sepolia
	}
	network := x402.Network(networkID)

	// Facilitator
	facilitator := x402http.NewHTTPFacilitatorClient(&x402http.FacilitatorConfig{
		URL: getFacilitatorURL(useMainnet),
	})

	// ✅ routes：使用 Accepts + PaymentOptions（新版 RouteConfig 结构）
	// ✅ PayTo / Price 支持动态函数（你未来在函数里查 DB 即可）:contentReference[oaicite:6]{index=6}
	routes := x402http.RoutesConfig{
		"GET /test": {
			Accepts: x402http.PaymentOptions{
				{
					Scheme: "exact",
					PayTo: x402http.DynamicPayToFunc(func(ctx context.Context, reqCtx x402http.HTTPRequestContext) (string, error) {
						return payTo, nil
					}),
					Price: x402http.DynamicPriceFunc(func(ctx context.Context, reqCtx x402http.HTTPRequestContext) (x402.Price, error) {
						return x402.Price(price), nil
					}),
					Network:           network,
					MaxTimeoutSeconds: 600,
				},
			},
			Description: "x402 test endpoint",
			MimeType:    "application/json",
		},
	}

	// ✅ x402 middleware
	r.Use(ginmw.X402Payment(ginmw.Config{
		Routes:      routes,
		Facilitator: facilitator,
		Schemes: []ginmw.SchemeConfig{
			// 这里也可以写成 network（单网络），但建议用 wildcard
			{Network: x402.Network(networkID), Server: evm.NewExactEvmScheme()},
		},
		// 文档里旧字段 Initialize 已不存在；现在叫 SyncFacilitatorOnStart :contentReference[oaicite:7]{index=7}
		SyncFacilitatorOnStart: true,
		Timeout:                30 * time.Second,

		// ✅ 结算成功后：把 tx hash 返回给调用方 :contentReference[oaicite:8]{index=8}
		SettlementHandler: func(c *gin.Context, settle *x402.SettleResponse) {
			if settle == nil {
				return
			}
			// 给 handler 用
			c.Header("X-402-Transaction", settle.Transaction)
			settleJSON, _ := json.Marshal(settle)
			c.Header("PAYMENT-RESPONSE", base64.StdEncoding.EncodeToString(settleJSON))
		},
	}))

	// Protected endpoint
	r.GET("/test", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"result":     "success",
			"network":    networkID,
			"useMainnet": strconv.FormatBool(useMainnet),

			"payTo": payTo,
			"price": price,
		})
	})

	// Health
	r.GET("/health", func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status":       "ok",
			"network_mode": strconv.FormatBool(useMainnet),
		})
	})

	log.Println("Starting x402 server on :7788")
	log.Fatal(r.Run("0.0.0.0:7788"))
}

func getFacilitatorURL(useMainnet bool) string {
	if useMainnet {
		return "https://api.cdp.coinbase.com/platform/v2/x402"
	}
	return "https://x402.org/facilitator"
}
