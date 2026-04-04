package main

import (
	"encoding/json"
	"log"
	"net"
	"net/http"
)

type IPResponse struct {
	IP      string `json:"ip"`
	Message string `json:"message"`
}

func main() {
	http.HandleFunc("/", handleGetIP)
	http.HandleFunc("/ip", handleGetIP)

	addr := ":9999"
	log.Printf("IP Query Service started at http://localhost%s", addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func handleGetIP(w http.ResponseWriter, r *http.Request) {
	// 获取客户端 IP
	ip, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		ip = r.RemoteAddr
	}

	// 检查 X-Forwarded-For 头
	if xff := r.Header.Get("X-Forwarded-For"); xff != "" {
		ip = xff
	}

	response := IPResponse{
		IP:      ip,
		Message: "Your IP address",
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(response)

	log.Printf("IP query from: %s", ip)
}
