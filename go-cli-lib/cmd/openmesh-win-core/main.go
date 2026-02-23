//go:build windows

package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/Microsoft/go-winio"
)

const pipeName = `\\.\pipe\openmesh-win-core`

type coreRequest struct {
	Action string `json:"action"`
}

type coreRuntimeStats struct {
	TotalUploadBytes      int64   `json:"totalUploadBytes"`
	TotalDownloadBytes    int64   `json:"totalDownloadBytes"`
	UploadRateBytesPerSec int64   `json:"uploadRateBytesPerSec"`
	DownloadRateBytesPerSec int64 `json:"downloadRateBytesPerSec"`
	MemoryMb              float64 `json:"memoryMb"`
	ThreadCount           int     `json:"threadCount"`
	UptimeSeconds         int64   `json:"uptimeSeconds"`
	ConnectionCount       int     `json:"connectionCount"`
}

type coreResponse struct {
	Ok               bool             `json:"ok"`
	Message          string           `json:"message"`
	CoreRunning      bool             `json:"coreRunning"`
	VpnRunning       bool             `json:"vpnRunning"`
	StartedAtUtc     string           `json:"startedAtUtc"`
	LastReloadAtUtc  string           `json:"lastReloadAtUtc"`
	LastConfigHash   string           `json:"lastConfigHash"`
	InjectedRuleCount int             `json:"injectedRuleCount"`
	LastReloadError  string           `json:"lastReloadError"`
	Runtime          coreRuntimeStats `json:"runtime"`
}

type coreState struct {
	mu               sync.Mutex
	startedAt        time.Time
	vpnRunning       bool
	lastReloadAt     time.Time
	lastConfigHash   string
	injectedRuleCount int
	lastReloadError  string
}

func newCoreState() *coreState {
	return &coreState{
		startedAt: time.Now().UTC(),
	}
}

func main() {
	state := newCoreState()

	listener, err := winio.ListenPipe(pipeName, nil)
	if err != nil {
		log.Fatalf("openmesh-win-core listen failed: %v", err)
	}
	defer listener.Close()

	log.Printf("openmesh-win-core listening on %s", pipeName)
	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Printf("accept failed: %v", err)
			continue
		}

		go func(c net.Conn) {
			defer c.Close()
			handleConn(c, state)
		}(conn)
	}
}

func handleConn(conn net.Conn, state *coreState) {
	reader := bufio.NewReader(conn)
	writer := bufio.NewWriter(conn)

	line, err := reader.ReadString('\n')
	if err != nil {
		writeResponse(writer, state.buildResponse(false, "read request failed"))
		return
	}

	var req coreRequest
	if err := json.Unmarshal([]byte(strings.TrimSpace(line)), &req); err != nil {
		writeResponse(writer, state.buildResponse(false, "invalid request json"))
		return
	}

	resp := state.handleAction(strings.ToLower(strings.TrimSpace(req.Action)))
	writeResponse(writer, resp)
}

func writeResponse(writer *bufio.Writer, resp coreResponse) {
	payload, err := json.Marshal(resp)
	if err != nil {
		fallback := `{"ok":false,"message":"response marshal failed","coreRunning":true,"vpnRunning":false}`
		_, _ = writer.WriteString(fallback + "\n")
		_ = writer.Flush()
		return
	}

	_, _ = writer.WriteString(string(payload) + "\n")
	_ = writer.Flush()
}

func (s *coreState) handleAction(action string) coreResponse {
	switch action {
	case "ping":
		return s.buildResponse(true, "pong (go core)")
	case "status":
		return s.buildResponse(true, "status (go core)")
	case "reload":
		return s.reload()
	case "start_vpn":
		s.mu.Lock()
		s.vpnRunning = true
		s.mu.Unlock()
		return s.buildResponse(true, "vpn started (go core)")
	case "stop_vpn":
		s.mu.Lock()
		s.vpnRunning = false
		s.mu.Unlock()
		return s.buildResponse(true, "vpn stopped (go core)")
	default:
		return s.buildResponse(false, "unknown action")
	}
}

func (s *coreState) reload() coreResponse {
	s.mu.Lock()
	defer s.mu.Unlock()

	now := time.Now().UTC()
	s.lastReloadAt = now
	hashInput := fmt.Sprintf("reload:%d:%d", now.UnixNano(), os.Getpid())
	sum := sha256.Sum256([]byte(hashInput))
	s.lastConfigHash = hex.EncodeToString(sum[:])
	s.injectedRuleCount = 0
	s.lastReloadError = ""

	return s.buildResponseLocked(true, "config reloaded (go core)")
}

func (s *coreState) buildResponse(ok bool, message string) coreResponse {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.buildResponseLocked(ok, message)
}

func (s *coreState) buildResponseLocked(ok bool, message string) coreResponse {
	uptime := int64(time.Since(s.startedAt).Seconds())
	lastReload := ""
	if !s.lastReloadAt.IsZero() {
		lastReload = s.lastReloadAt.Format(time.RFC3339)
	}

	return coreResponse{
		Ok:                ok,
		Message:           message,
		CoreRunning:       true,
		VpnRunning:        s.vpnRunning,
		StartedAtUtc:      s.startedAt.Format(time.RFC3339),
		LastReloadAtUtc:   lastReload,
		LastConfigHash:    s.lastConfigHash,
		InjectedRuleCount: s.injectedRuleCount,
		LastReloadError:   s.lastReloadError,
		Runtime: coreRuntimeStats{
			UptimeSeconds: uptime,
		},
	}
}
