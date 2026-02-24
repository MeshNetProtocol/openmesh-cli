//go:build windows

package main

import (
	"bufio"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/csv"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"log"
	"math"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	openmeshlib "github.com/MeshNetProtocol/openmesh-cli/go-cli-lib/interface"
	"github.com/Microsoft/go-winio"
)

const pipeName = `\\.\pipe\openmesh-win-core`

type request struct {
	Action                 string `json:"action"`
	ProfilePath            string `json:"profilePath"`
	Group                  string `json:"group"`
	Outbound               string `json:"outbound"`
	Search                 string `json:"search"`
	SortBy                 string `json:"sortBy"`
	Descending             bool   `json:"descending"`
	ConnectionID           int    `json:"connectionId"`
	Password               string `json:"password"`
	Mnemonic               string `json:"mnemonic"`
	Network                string `json:"network"`
	TokenSymbol            string `json:"tokenSymbol"`
	Amount                 string `json:"amount"`
	To                     string `json:"to"`
	Resource               string `json:"resource"`
	StreamIntervalMs       int    `json:"streamIntervalMs"`
	StreamMaxEvents        int    `json:"streamMaxEvents"`
	StreamHeartbeatEnabled *bool  `json:"streamHeartbeatEnabled"`
}

type runtimeStats struct {
	TotalUploadBytes        int64   `json:"totalUploadBytes"`
	TotalDownloadBytes      int64   `json:"totalDownloadBytes"`
	UploadRateBytesPerSec   int64   `json:"uploadRateBytesPerSec"`
	DownloadRateBytesPerSec int64   `json:"downloadRateBytesPerSec"`
	MemoryMb                float64 `json:"memoryMb"`
	ThreadCount             int     `json:"threadCount"`
	UptimeSeconds           int64   `json:"uptimeSeconds"`
	ConnectionCount         int     `json:"connectionCount"`
}

type outboundItem struct {
	Tag          string `json:"tag"`
	Type         string `json:"type"`
	UrlTestDelay int    `json:"urlTestDelay"`
}

type outboundGroup struct {
	Tag        string         `json:"tag"`
	Type       string         `json:"type"`
	Selected   string         `json:"selected"`
	Selectable bool           `json:"selectable"`
	Items      []outboundItem `json:"items"`
}

type connectionItem struct {
	ID            int    `json:"id"`
	ProcessName   string `json:"processName"`
	Destination   string `json:"destination"`
	Protocol      string `json:"protocol"`
	Outbound      string `json:"outbound"`
	UploadBytes   int64  `json:"uploadBytes"`
	DownloadBytes int64  `json:"downloadBytes"`
	LastSeenUtc   string `json:"lastSeenUtc"`
	State         string `json:"state"`
}

type response struct {
	Ok                         bool             `json:"ok"`
	Message                    string           `json:"message"`
	CoreRunning                bool             `json:"coreRunning"`
	VpnRunning                 bool             `json:"vpnRunning"`
	StartedAtUtc               string           `json:"startedAtUtc"`
	ProfilePath                string           `json:"profilePath"`
	EffectiveConfigPath        string           `json:"effectiveConfigPath"`
	LastConfigHash             string           `json:"lastConfigHash"`
	InjectedRuleCount          int              `json:"injectedRuleCount"`
	LastReloadAtUtc            string           `json:"lastReloadAtUtc"`
	LastReloadError            string           `json:"lastReloadError"`
	Group                      string           `json:"group"`
	Delays                     map[string]int   `json:"delays"`
	OutboundGroups             []outboundGroup  `json:"outboundGroups"`
	Connections                []connectionItem `json:"connections"`
	Runtime                    runtimeStats     `json:"runtime"`
	WalletExists               bool             `json:"walletExists"`
	WalletUnlocked             bool             `json:"walletUnlocked"`
	WalletAddress              string           `json:"walletAddress"`
	WalletNetwork              string           `json:"walletNetwork"`
	WalletToken                string           `json:"walletToken"`
	WalletBalance              float64          `json:"walletBalance"`
	WalletBalanceSource        string           `json:"walletBalanceSource"`
	GeneratedMnemonic          string           `json:"generatedMnemonic"`
	PaymentId                  string           `json:"paymentId"`
	PaymentMode                string           `json:"paymentMode"`
	P3PreflightCheckedAtUtc    string           `json:"p3PreflightCheckedAtUtc"`
	P3Admin                    bool             `json:"p3Admin"`
	P3WintunFound              bool             `json:"p3WintunFound"`
	P3WintunPath               string           `json:"p3WintunPath"`
	P3NetworkPrepared          bool             `json:"p3NetworkPrepared"`
	P3NetworkDryRun            bool             `json:"p3NetworkDryRun"`
	P3LastNetworkError         string           `json:"p3LastNetworkError"`
	P3LastRollbackAtUtc        string           `json:"p3LastRollbackAtUtc"`
	P3AppliedCommands          []string         `json:"p3AppliedCommands"`
	P3EngineMode               string           `json:"p3EngineMode"`
	P3EngineProbeAtUtc         string           `json:"p3EngineProbeAtUtc"`
	P3SingboxFound             bool             `json:"p3SingboxFound"`
	P3SingboxPath              string           `json:"p3SingboxPath"`
	P3EngineRunning            bool             `json:"p3EngineRunning"`
	P3EnginePid                int              `json:"p3EnginePid"`
	P3EngineLastError          string           `json:"p3EngineLastError"`
	P3EngineLastExitAtUtc      string           `json:"p3EngineLastExitAtUtc"`
	P3EngineLastExitCode       int              `json:"p3EngineLastExitCode"`
	P3EngineHealthy            bool             `json:"p3EngineHealthy"`
	P3EngineHealthCheckedAtUtc string           `json:"p3EngineHealthCheckedAtUtc"`
	P3EngineHealthMessage      string           `json:"p3EngineHealthMessage"`
	StreamType                 string           `json:"streamType"`
	StreamSeq                  int              `json:"streamSeq"`
	StreamFingerprint          string           `json:"streamFingerprint"`
}

type layout struct {
	runtimeRoot    string
	profilesRoot   string
	effectiveRoot  string
	walletRoot     string
	walletKeystore string
	defaultProfile string
	routingRules   string
	effectiveCfg   string
}

type state struct {
	mu                      sync.Mutex
	startedAt               time.Time
	walletLib               *openmeshlib.AppLib
	vpnRunning              bool
	layout                  layout
	selectedProfile         string
	effectiveCfg            string
	lastConfigHash          string
	injectedRuleCount       int
	lastReloadAt            time.Time
	lastReloadError         string
	configRoot              map[string]any
	outboundGroups          []outboundGroup
	selectedByGroup         map[string]string
	p3PreflightCheckedAt    time.Time
	p3Admin                 bool
	p3WintunFound           bool
	p3WintunPath            string
	p3NetworkPrepared       bool
	p3NetworkDryRun         bool
	p3LastNetworkError      string
	p3LastRollbackAt        time.Time
	p3AppliedCommands       []string
	p3RollbackCommands      []string
	p3EngineMode            string
	p3EngineProbeAt         time.Time
	p3SingboxFound          bool
	p3SingboxPath           string
	p3EngineCmd             *exec.Cmd
	p3EngineRunning         bool
	p3EnginePid             int
	p3EngineLastError       string
	p3EngineLastExitAt      time.Time
	p3EngineLastExitCode    int
	p3EngineHealthy         bool
	p3EngineHealthCheckedAt time.Time
	p3EngineHealthMessage   string
	connections             []connectionItem
	nextConnectionID        int
	lastConnSimTick         time.Time
	walletExists            bool
	walletUnlocked          bool
	walletAddress           string
	walletNetwork           string
	walletToken             string
	walletBalance           float64
	walletBalanceSource     string
	lastPaymentMode         string
	walletKeystoreJSON      string
	walletPrivateKeyHex     string
	walletSaltBase64        string
	walletNonceBase64       string
	walletCipherBase64      string
	lastGeneratedMnemonic   string
}

type walletKeystore struct {
	Address      string  `json:"address"`
	Network      string  `json:"network"`
	TokenSymbol  string  `json:"tokenSymbol"`
	KeystoreJSON string  `json:"keystoreJson"`
	SaltBase64   string  `json:"saltBase64"`
	NonceBase64  string  `json:"nonceBase64"`
	CipherBase64 string  `json:"cipherBase64"`
	Balance      float64 `json:"balance"`
}

func main() {
	s := &state{startedAt: time.Now().UTC(), selectedByGroup: map[string]string{}}
	if err := s.init(); err != nil {
		log.Fatal(err)
	}
	ln, err := winio.ListenPipe(pipeName, nil)
	if err != nil {
		log.Fatalf("listen failed: %v", err)
	}
	defer ln.Close()
	log.Printf("openmesh-win-core listening on %s", pipeName)

	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("accept failed: %v", err)
			continue
		}
		go s.handle(conn)
	}
}

func (s *state) init() error {
	exe, err := os.Executable()
	if err != nil {
		return err
	}
	s.walletLib = openmeshlib.NewLib()
	root := filepath.Join(filepath.Dir(exe), "runtime")
	s.layout = layout{
		runtimeRoot:    root,
		profilesRoot:   filepath.Join(root, "profiles"),
		effectiveRoot:  filepath.Join(root, "effective"),
		walletRoot:     filepath.Join(root, "wallet"),
		walletKeystore: filepath.Join(root, "wallet", "keystore.json"),
		defaultProfile: filepath.Join(root, "profiles", "default_profile.json"),
		routingRules:   filepath.Join(root, "routing_rules.json"),
		effectiveCfg:   filepath.Join(root, "effective", "effective_config.json"),
	}
	for _, d := range []string{s.layout.runtimeRoot, s.layout.profilesRoot, s.layout.effectiveRoot, s.layout.walletRoot} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			return err
		}
	}
	if _, err := os.Stat(s.layout.defaultProfile); os.IsNotExist(err) {
		_ = os.WriteFile(s.layout.defaultProfile, []byte("{\"outbounds\":[{\"type\":\"direct\",\"tag\":\"direct\"},{\"type\":\"selector\",\"tag\":\"proxy\",\"outbounds\":[\"node-a\",\"node-b\"],\"default\":\"node-a\"},{\"type\":\"urltest\",\"tag\":\"auto\",\"outbounds\":[\"node-a\",\"node-b\"],\"default\":\"node-a\"},{\"type\":\"shadowsocks\",\"tag\":\"node-a\"},{\"type\":\"shadowsocks\",\"tag\":\"node-b\"}],\"route\":{\"rules\":[{\"action\":\"sniff\"}]}}"), 0o644)
	}
	if _, err := os.Stat(s.layout.routingRules); os.IsNotExist(err) {
		_ = os.WriteFile(s.layout.routingRules, []byte("{\"ip_cidr\":[\"1.1.1.1/32\"],\"domain_suffix\":[\"openai.com\"]}"), 0o644)
	}
	s.selectedProfile = s.layout.defaultProfile
	s.effectiveCfg = s.layout.effectiveCfg
	s.mu.Lock()
	s.ensureConnectionsLocked()
	_ = s.loadWalletFromDiskLocked()
	s.mu.Unlock()
	return nil
}

func (s *state) handle(conn net.Conn) {
	defer conn.Close()
	r := bufio.NewReader(conn)
	w := bufio.NewWriter(conn)
	line, err := r.ReadString('\n')
	if err != nil {
		s.write(w, s.snapshot(false, "read request failed"))
		return
	}
	line = strings.TrimSpace(line)
	if line == "" {
		s.write(w, s.snapshot(false, "empty request"))
		return
	}
	var req request
	if err := json.Unmarshal([]byte(line), &req); err != nil {
		s.write(w, s.snapshot(false, "invalid request json"))
		return
	}

	var resp response
	switch strings.ToLower(strings.TrimSpace(req.Action)) {
	case "ping":
		resp = s.snapshot(true, "pong (go core)")
	case "status":
		resp = s.snapshot(true, "status (go core)")
	case "set_profile":
		resp = s.setProfile(req.ProfilePath)
	case "reload":
		resp = s.reload()
	case "connections":
		resp = s.queryConnections(req.Search, req.SortBy, req.Descending)
	case "close_connection":
		resp = s.closeConnection(req.ConnectionID)
	case "p3_network_preflight":
		resp = s.p3NetworkPreflight()
	case "p3_network_prepare":
		resp = s.p3NetworkPrepare()
	case "p3_network_rollback":
		resp = s.p3NetworkRollback()
	case "p3_engine_probe":
		resp = s.p3EngineProbe()
	case "p3_engine_start":
		resp = s.p3EngineStart()
	case "p3_engine_stop":
		resp = s.p3EngineStop()
	case "p3_engine_health":
		resp = s.p3EngineHealth()
	case "status_stream":
		s.streamStatus(w, req)
		return
	case "groups_stream":
		s.streamGroups(w, req)
		return
	case "connections_stream":
		s.streamConnections(w, req)
		return
	case "start_vpn":
		resp = s.startVPN()
	case "stop_vpn":
		resp = s.stopVPN()
	case "urltest":
		resp = s.urltest(req.Group)
	case "select_outbound":
		resp = s.selectOutbound(req.Group, req.Outbound)
	case "wallet_generate_mnemonic":
		resp = s.walletGenerateMnemonic()
	case "wallet_create":
		resp = s.walletCreate(req.Mnemonic, req.Password)
	case "wallet_unlock":
		resp = s.walletUnlock(req.Password)
	case "wallet_balance":
		resp = s.walletQueryBalance(req.Network, req.TokenSymbol)
	case "x402_pay":
		resp = s.walletX402Pay(req.To, req.Resource, req.Amount, req.Password)
	default:
		resp = s.snapshot(false, "unknown action")
	}
	s.write(w, resp)
}

func (s *state) write(w *bufio.Writer, resp response) {
	data, err := json.Marshal(resp)
	if err != nil {
		_, _ = w.WriteString("{\"ok\":false,\"message\":\"marshal response failed\"}\n")
		_ = w.Flush()
		return
	}
	_, _ = w.WriteString(string(data) + "\n")
	_ = w.Flush()
}

func writeStream(w *bufio.Writer, resp response) bool {
	data, err := json.Marshal(resp)
	if err != nil {
		return false
	}
	if _, err := w.WriteString(string(data) + "\n"); err != nil {
		return false
	}
	if err := w.Flush(); err != nil {
		return false
	}
	return true
}

func (s *state) streamStatus(w *bufio.Writer, req request) {
	interval := normalizeStreamInterval(req.StreamIntervalMs)
	maxEvents := normalizeStreamMaxEvents(req.StreamMaxEvents)
	heartbeatEnabled := true
	if req.StreamHeartbeatEnabled != nil {
		heartbeatEnabled = *req.StreamHeartbeatEnabled
	}

	seq := 0
	lastFingerprint := s.stateFingerprint()
	first := s.snapshot(true, "status stream snapshot")
	first.StreamType = "snapshot"
	first.StreamSeq = 1
	first.StreamFingerprint = lastFingerprint
	if !writeStream(w, first) {
		return
	}
	seq++
	if maxEvents > 0 && seq >= maxEvents {
		return
	}

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for range ticker.C {
		fingerprint := s.stateFingerprint()
		streamType := ""
		message := ""

		if fingerprint != lastFingerprint {
			streamType = "delta"
			message = "status stream delta"
			lastFingerprint = fingerprint
		} else if heartbeatEnabled {
			streamType = "heartbeat"
			message = "status stream heartbeat"
		} else {
			continue
		}

		resp := s.snapshot(true, message)
		resp.StreamType = streamType
		resp.StreamSeq = seq + 1
		resp.StreamFingerprint = fingerprint
		if !writeStream(w, resp) {
			return
		}

		seq++
		if maxEvents > 0 && seq >= maxEvents {
			return
		}
	}
}

func (s *state) streamGroups(w *bufio.Writer, req request) {
	interval := normalizeStreamInterval(req.StreamIntervalMs)
	maxEvents := normalizeStreamMaxEvents(req.StreamMaxEvents)
	heartbeatEnabled := true
	if req.StreamHeartbeatEnabled != nil {
		heartbeatEnabled = *req.StreamHeartbeatEnabled
	}

	seq := 0
	s.mu.Lock()
	groups := cloneGroups(s.outboundGroups)
	lastFingerprint := groupsFingerprint(groups)
	first := s.snapshotLocked(true, "groups stream snapshot")
	first.StreamType = "snapshot"
	first.StreamSeq = 1
	first.StreamFingerprint = lastFingerprint
	first.OutboundGroups = groups
	s.mu.Unlock()
	if !writeStream(w, first) {
		return
	}
	seq++
	if maxEvents > 0 && seq >= maxEvents {
		return
	}

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for range ticker.C {
		s.mu.Lock()
		groups = cloneGroups(s.outboundGroups)
		fingerprint := groupsFingerprint(groups)

		streamType := ""
		message := ""
		if fingerprint != lastFingerprint {
			streamType = "delta"
			message = "groups stream delta"
			lastFingerprint = fingerprint
		} else if heartbeatEnabled {
			streamType = "heartbeat"
			message = "groups stream heartbeat"
		} else {
			s.mu.Unlock()
			continue
		}

		resp := s.snapshotLocked(true, message)
		resp.StreamType = streamType
		resp.StreamSeq = seq + 1
		resp.StreamFingerprint = fingerprint
		resp.OutboundGroups = groups
		s.mu.Unlock()
		if !writeStream(w, resp) {
			return
		}

		seq++
		if maxEvents > 0 && seq >= maxEvents {
			return
		}
	}
}

func (s *state) queryConnections(search, sortBy string, descending bool) response {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.simulateConnectionsLocked()
	items := filterSortConnections(s.connections, search, sortBy, descending)
	resp := s.snapshotLocked(true, "connections (go core)")
	resp.Connections = items
	return resp
}

func (s *state) closeConnection(connectionID int) response {
	if connectionID <= 0 {
		return s.snapshot(false, "invalid connection id")
	}

	s.mu.Lock()
	defer s.mu.Unlock()
	idx := -1
	for i := range s.connections {
		if s.connections[i].ID == connectionID {
			idx = i
			break
		}
	}
	if idx < 0 {
		return s.snapshotLocked(false, fmt.Sprintf("connection not found: %d", connectionID))
	}

	s.connections = append(s.connections[:idx], s.connections[idx+1:]...)
	resp := s.snapshotLocked(true, fmt.Sprintf("connection closed: %d", connectionID))
	resp.Connections = filterSortConnections(s.connections, "", "last_seen", true)
	return resp
}

func (s *state) streamConnections(w *bufio.Writer, req request) {
	interval := normalizeStreamInterval(req.StreamIntervalMs)
	maxEvents := normalizeStreamMaxEvents(req.StreamMaxEvents)
	heartbeatEnabled := true
	if req.StreamHeartbeatEnabled != nil {
		heartbeatEnabled = *req.StreamHeartbeatEnabled
	}

	seq := 0
	s.mu.Lock()
	s.simulateConnectionsLocked()
	items := filterSortConnections(s.connections, req.Search, req.SortBy, req.Descending)
	lastFingerprint := connectionsFingerprint(items)
	first := s.snapshotLocked(true, "connections stream snapshot")
	first.StreamType = "snapshot"
	first.StreamSeq = 1
	first.StreamFingerprint = lastFingerprint
	first.Connections = items
	s.mu.Unlock()
	if !writeStream(w, first) {
		return
	}
	seq++
	if maxEvents > 0 && seq >= maxEvents {
		return
	}

	ticker := time.NewTicker(interval)
	defer ticker.Stop()

	for range ticker.C {
		s.mu.Lock()
		s.simulateConnectionsLocked()
		items = filterSortConnections(s.connections, req.Search, req.SortBy, req.Descending)
		fingerprint := connectionsFingerprint(items)

		streamType := ""
		message := ""
		if fingerprint != lastFingerprint {
			streamType = "delta"
			message = "connections stream delta"
			lastFingerprint = fingerprint
		} else if heartbeatEnabled {
			streamType = "heartbeat"
			message = "connections stream heartbeat"
		} else {
			s.mu.Unlock()
			continue
		}

		resp := s.snapshotLocked(true, message)
		resp.StreamType = streamType
		resp.StreamSeq = seq + 1
		resp.StreamFingerprint = fingerprint
		resp.Connections = items
		s.mu.Unlock()
		if !writeStream(w, resp) {
			return
		}

		seq++
		if maxEvents > 0 && seq >= maxEvents {
			return
		}
	}
}

func filterSortConnections(in []connectionItem, search, sortBy string, descending bool) []connectionItem {
	items := cloneConnections(in)
	search = strings.ToLower(strings.TrimSpace(search))
	if search != "" {
		filtered := make([]connectionItem, 0, len(items))
		for _, c := range items {
			if strings.Contains(strings.ToLower(c.ProcessName), search) ||
				strings.Contains(strings.ToLower(c.Destination), search) ||
				strings.Contains(strings.ToLower(c.Protocol), search) ||
				strings.Contains(strings.ToLower(c.Outbound), search) {
				filtered = append(filtered, c)
			}
		}
		items = filtered
	}

	sortBy = normalizeConnectionSortBy(sortBy)
	sort.Slice(items, func(i, j int) bool {
		if descending {
			return compareConnections(items[j], items[i], sortBy)
		}
		return compareConnections(items[i], items[j], sortBy)
	})
	return items
}

func normalizeConnectionSortBy(sortBy string) string {
	switch strings.ToLower(strings.TrimSpace(sortBy)) {
	case "id", "process", "destination", "outbound", "upload", "download", "last_seen":
		return strings.ToLower(strings.TrimSpace(sortBy))
	default:
		return "last_seen"
	}
}

func compareConnections(a, b connectionItem, sortBy string) bool {
	switch sortBy {
	case "id":
		if a.ID == b.ID {
			return strings.Compare(strings.ToLower(a.ProcessName), strings.ToLower(b.ProcessName)) < 0
		}
		return a.ID < b.ID
	case "process":
		if strings.EqualFold(a.ProcessName, b.ProcessName) {
			return a.ID < b.ID
		}
		return strings.Compare(strings.ToLower(a.ProcessName), strings.ToLower(b.ProcessName)) < 0
	case "destination":
		if strings.EqualFold(a.Destination, b.Destination) {
			return a.ID < b.ID
		}
		return strings.Compare(strings.ToLower(a.Destination), strings.ToLower(b.Destination)) < 0
	case "outbound":
		if strings.EqualFold(a.Outbound, b.Outbound) {
			return a.ID < b.ID
		}
		return strings.Compare(strings.ToLower(a.Outbound), strings.ToLower(b.Outbound)) < 0
	case "upload":
		if a.UploadBytes == b.UploadBytes {
			return a.ID < b.ID
		}
		return a.UploadBytes < b.UploadBytes
	case "download":
		if a.DownloadBytes == b.DownloadBytes {
			return a.ID < b.ID
		}
		return a.DownloadBytes < b.DownloadBytes
	default:
		if a.LastSeenUtc == b.LastSeenUtc {
			return a.ID < b.ID
		}
		return a.LastSeenUtc < b.LastSeenUtc
	}
}

func connectionsFingerprint(items []connectionItem) string {
	if len(items) == 0 {
		return "empty"
	}
	var b strings.Builder
	for _, c := range items {
		b.WriteString(strconv.Itoa(c.ID))
		b.WriteString("|")
		b.WriteString(c.State)
		b.WriteString("|")
		b.WriteString(c.LastSeenUtc)
		b.WriteString("|")
		b.WriteString(strconv.FormatInt(c.UploadBytes, 10))
		b.WriteString("|")
		b.WriteString(strconv.FormatInt(c.DownloadBytes, 10))
		b.WriteString(";")
	}
	sum := sha256.Sum256([]byte(b.String()))
	return hex.EncodeToString(sum[:8])
}

func groupsFingerprint(groups []outboundGroup) string {
	if len(groups) == 0 {
		return "empty"
	}
	var b strings.Builder
	for _, g := range groups {
		b.WriteString(strings.ToLower(g.Tag))
		b.WriteString("|")
		b.WriteString(strings.ToLower(g.Type))
		b.WriteString("|")
		b.WriteString(strings.ToLower(g.Selected))
		b.WriteString("|")
		if g.Selectable {
			b.WriteString("1")
		} else {
			b.WriteString("0")
		}
		b.WriteString("|")
		for _, item := range g.Items {
			b.WriteString(strings.ToLower(item.Tag))
			b.WriteString(":")
			b.WriteString(strings.ToLower(item.Type))
			b.WriteString(":")
			b.WriteString(strconv.Itoa(item.UrlTestDelay))
			b.WriteString(",")
		}
		b.WriteString(";")
	}
	sum := sha256.Sum256([]byte(b.String()))
	return hex.EncodeToString(sum[:8])
}

func normalizeStreamInterval(ms int) time.Duration {
	const (
		defaultMs = 800
		minMs     = 100
		maxMs     = 5000
	)
	if ms <= 0 {
		return defaultMs * time.Millisecond
	}
	if ms < minMs {
		ms = minMs
	}
	if ms > maxMs {
		ms = maxMs
	}
	return time.Duration(ms) * time.Millisecond
}

func normalizeStreamMaxEvents(n int) int {
	if n < 0 {
		return 0
	}
	if n > 1000 {
		return 1000
	}
	return n
}

func (s *state) stateFingerprint() string {
	s.mu.Lock()
	defer s.mu.Unlock()

	var b strings.Builder
	b.WriteString("vpn=")
	if s.vpnRunning {
		b.WriteString("1")
	} else {
		b.WriteString("0")
	}
	b.WriteString("|cfg=")
	b.WriteString(s.lastConfigHash)
	b.WriteString("|rules=")
	b.WriteString(strconv.Itoa(s.injectedRuleCount))
	b.WriteString("|reloadErr=")
	b.WriteString(s.lastReloadError)
	b.WriteString("|netPrepared=")
	if s.p3NetworkPrepared {
		b.WriteString("1")
	} else {
		b.WriteString("0")
	}
	b.WriteString("|engineMode=")
	b.WriteString(s.p3EngineMode)
	b.WriteString("|engineRun=")
	if s.p3EngineRunning {
		b.WriteString("1")
	} else {
		b.WriteString("0")
	}
	b.WriteString("|engineHealthy=")
	if s.p3EngineHealthy {
		b.WriteString("1")
	} else {
		b.WriteString("0")
	}
	b.WriteString("|engineErr=")
	b.WriteString(s.p3EngineLastError)
	b.WriteString("|connfp=")
	b.WriteString(connectionsFingerprint(s.connections))

	tags := make([]string, 0, len(s.outboundGroups))
	for _, g := range s.outboundGroups {
		tags = append(tags, g.Tag+"="+g.Selected)
	}
	sort.Strings(tags)
	for _, item := range tags {
		b.WriteString("|grp=")
		b.WriteString(item)
	}

	sum := sha256.Sum256([]byte(b.String()))
	return hex.EncodeToString(sum[:8])
}

func (s *state) snapshot(ok bool, msg string) response {
	s.mu.Lock()
	defer s.mu.Unlock()
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	totalUp, totalDown, connCount := summarizeConnections(s.connections)
	upRate, downRate := estimateConnectionRates(s.connections, s.vpnRunning)
	lastReload := ""
	if !s.lastReloadAt.IsZero() {
		lastReload = s.lastReloadAt.Format(time.RFC3339)
	}
	return response{
		Ok:                  ok,
		Message:             msg,
		CoreRunning:         true,
		VpnRunning:          s.vpnRunning,
		StartedAtUtc:        s.startedAt.Format(time.RFC3339),
		ProfilePath:         s.selectedProfile,
		EffectiveConfigPath: s.effectiveCfg,
		LastConfigHash:      s.lastConfigHash,
		InjectedRuleCount:   s.injectedRuleCount,
		LastReloadAtUtc:     lastReload,
		LastReloadError:     s.lastReloadError,
		Group:               "",
		Delays:              map[string]int{},
		OutboundGroups:      cloneGroups(s.outboundGroups),
		Connections:         cloneConnections(s.connections),
		Runtime: runtimeStats{
			TotalUploadBytes:        totalUp,
			TotalDownloadBytes:      totalDown,
			UploadRateBytesPerSec:   upRate,
			DownloadRateBytesPerSec: downRate,
			MemoryMb:                float64(m.Alloc) / 1024.0 / 1024.0,
			ThreadCount:             runtime.NumGoroutine(),
			UptimeSeconds:           int64(time.Since(s.startedAt).Seconds()),
			ConnectionCount:         connCount,
		},
		WalletExists:               s.walletExists,
		WalletUnlocked:             s.walletUnlocked,
		WalletAddress:              s.walletAddress,
		WalletNetwork:              s.walletNetwork,
		WalletToken:                s.walletToken,
		WalletBalance:              roundAmount(s.walletBalance),
		WalletBalanceSource:        s.walletBalanceSource,
		GeneratedMnemonic:          s.lastGeneratedMnemonic,
		PaymentId:                  "",
		PaymentMode:                s.lastPaymentMode,
		P3PreflightCheckedAtUtc:    formatTime(s.p3PreflightCheckedAt),
		P3Admin:                    s.p3Admin,
		P3WintunFound:              s.p3WintunFound,
		P3WintunPath:               s.p3WintunPath,
		P3NetworkPrepared:          s.p3NetworkPrepared,
		P3NetworkDryRun:            s.p3NetworkDryRun,
		P3LastNetworkError:         s.p3LastNetworkError,
		P3LastRollbackAtUtc:        formatTime(s.p3LastRollbackAt),
		P3AppliedCommands:          append([]string{}, s.p3AppliedCommands...),
		P3EngineMode:               s.p3EngineMode,
		P3EngineProbeAtUtc:         formatTime(s.p3EngineProbeAt),
		P3SingboxFound:             s.p3SingboxFound,
		P3SingboxPath:              s.p3SingboxPath,
		P3EngineRunning:            s.p3EngineRunning,
		P3EnginePid:                s.p3EnginePid,
		P3EngineLastError:          s.p3EngineLastError,
		P3EngineLastExitAtUtc:      formatTime(s.p3EngineLastExitAt),
		P3EngineLastExitCode:       s.p3EngineLastExitCode,
		P3EngineHealthy:            s.p3EngineHealthy,
		P3EngineHealthCheckedAtUtc: formatTime(s.p3EngineHealthCheckedAt),
		P3EngineHealthMessage:      s.p3EngineHealthMessage,
		StreamType:                 "",
		StreamSeq:                  0,
		StreamFingerprint:          "",
	}
}

func cloneGroups(in []outboundGroup) []outboundGroup {
	out := make([]outboundGroup, 0, len(in))
	for _, g := range in {
		ng := outboundGroup{Tag: g.Tag, Type: g.Type, Selected: g.Selected, Selectable: g.Selectable}
		ng.Items = append(ng.Items, g.Items...)
		out = append(out, ng)
	}
	return out
}

func cloneConnections(in []connectionItem) []connectionItem {
	out := make([]connectionItem, len(in))
	copy(out, in)
	return out
}

func summarizeConnections(conns []connectionItem) (int64, int64, int) {
	var totalUp int64
	var totalDown int64
	for _, c := range conns {
		totalUp += c.UploadBytes
		totalDown += c.DownloadBytes
	}
	return totalUp, totalDown, len(conns)
}

func estimateConnectionRates(conns []connectionItem, vpnRunning bool) (int64, int64) {
	if !vpnRunning || len(conns) == 0 {
		return 0, 0
	}
	var up int64
	var down int64
	for _, c := range conns {
		if strings.EqualFold(c.State, "idle") {
			up += 800
			down += 1600
			continue
		}
		up += 6400
		down += 12800
	}
	return up, down
}

func (s *state) setProfile(p string) response {
	p = strings.TrimSpace(p)
	if p == "" {
		return s.snapshot(false, "profile path is empty")
	}
	if !filepath.IsAbs(p) {
		for _, c := range []string{p, filepath.Join(s.layout.profilesRoot, p), filepath.Join(s.layout.runtimeRoot, p)} {
			if _, err := os.Stat(c); err == nil {
				p = c
				break
			}
		}
	}
	if _, err := os.Stat(p); err != nil {
		return s.snapshot(false, fmt.Sprintf("profile not found: %s", p))
	}
	s.mu.Lock()
	s.selectedProfile = p
	s.mu.Unlock()
	resp := s.reload()
	if resp.Ok {
		resp.Message = "profile set: " + p
	}
	return resp
}

func (s *state) startVPN() response {
	s.mu.Lock()
	needReload := s.lastConfigHash == ""
	s.mu.Unlock()
	if needReload {
		r := s.reload()
		if !r.Ok {
			return s.snapshot(false, "reload failed before start_vpn: "+r.Message)
		}
	}
	if prep := s.p3AutoPrepareNetwork(); !prep.Ok {
		return prep
	}
	if eng := s.p3AutoStartEngine(); !eng.Ok {
		_ = s.p3AutoRollbackNetwork()
		return eng
	}
	s.mu.Lock()
	s.vpnRunning = true
	s.ensureConnectionsLocked()
	s.simulateConnectionsLocked()
	s.mu.Unlock()
	return s.snapshot(true, "vpn started (go core)")
}

func (s *state) stopVPN() response {
	_ = s.p3AutoStopEngine()
	s.mu.Lock()
	s.vpnRunning = false
	now := time.Now().UTC().Format(time.RFC3339)
	for i := range s.connections {
		s.connections[i].State = "idle"
		s.connections[i].LastSeenUtc = now
	}
	s.mu.Unlock()
	_ = s.p3AutoRollbackNetwork()
	return s.snapshot(true, "vpn stopped (go core)")
}

func (s *state) reload() response {
	s.mu.Lock()
	profile := s.selectedProfile
	if profile == "" {
		profile = s.layout.defaultProfile
	}
	rulesPath := s.layout.routingRules
	effectivePath := s.layout.effectiveCfg
	prevGroups := cloneGroups(s.outboundGroups)
	pref := map[string]string{}
	for k, v := range s.selectedByGroup {
		pref[k] = v
	}
	s.mu.Unlock()

	cfgRaw, err := os.ReadFile(profile)
	if err != nil {
		return s.reloadFail(fmt.Sprintf("read profile failed: %v", err))
	}
	root, err := parseRelaxedObject(string(cfgRaw))
	if err != nil {
		return s.reloadFail(fmt.Sprintf("profile parse failed: %v", err))
	}

	rulesRaw, err := os.ReadFile(rulesPath)
	if err != nil {
		rulesRaw = []byte("{}")
	}
	dr := parseDynamicRules(string(rulesRaw))
	injected := injectRules(root, dr)

	groups := buildGroups(root, prevGroups)
	applySelection(root, groups, pref)
	cfgBytes, hash, err := writeEffective(root, effectivePath)
	if err != nil {
		return s.reloadFail(fmt.Sprintf("persist effective config failed: %v", err))
	}
	_ = cfgBytes

	s.mu.Lock()
	s.configRoot = root
	s.selectedProfile = profile
	s.effectiveCfg = effectivePath
	s.lastConfigHash = hash
	s.injectedRuleCount = injected
	s.lastReloadAt = time.Now().UTC()
	s.lastReloadError = ""
	s.outboundGroups = groups
	for _, g := range groups {
		if g.Selected != "" {
			s.selectedByGroup[g.Tag] = g.Selected
		}
	}
	s.mu.Unlock()
	return s.snapshot(true, fmt.Sprintf("config reloaded (go core), injected_rules=%d", injected))
}

func (s *state) reloadFail(msg string) response {
	s.mu.Lock()
	s.lastReloadError = msg
	s.mu.Unlock()
	return s.snapshot(false, msg)
}

func (s *state) urltest(group string) response {
	s.mu.Lock()
	defer s.mu.Unlock()
	if len(s.outboundGroups) == 0 {
		return s.snapshotLocked(false, "no outbound groups available")
	}
	idx := -1
	if strings.TrimSpace(group) != "" {
		for i := range s.outboundGroups {
			if strings.EqualFold(s.outboundGroups[i].Tag, group) {
				idx = i
				break
			}
		}
	}
	if idx < 0 {
		for i := range s.outboundGroups {
			if s.outboundGroups[i].Selectable {
				idx = i
				break
			}
		}
	}
	if idx < 0 {
		idx = 0
	}
	delays := map[string]int{}
	for i := range s.outboundGroups[idx].Items {
		d := genDelay(s.outboundGroups[idx].Tag, s.outboundGroups[idx].Items[i].Tag)
		s.outboundGroups[idx].Items[i].UrlTestDelay = d
		delays[s.outboundGroups[idx].Items[i].Tag] = d
	}
	resp := s.snapshotLocked(true, "urltest completed (go core)")
	resp.Group = s.outboundGroups[idx].Tag
	resp.Delays = delays
	return resp
}

func genDelay(group, out string) int {
	h := fnv.New32a()
	_, _ = h.Write([]byte(strings.ToLower(group + "|" + out + "|" + fmt.Sprint(time.Now().Unix()/15))))
	return 25 + int(h.Sum32()%220)
}

func (s *state) ensureConnectionsLocked() {
	if len(s.connections) > 0 {
		return
	}

	outbound := "direct"
	for _, g := range s.outboundGroups {
		if g.Selected != "" {
			outbound = g.Selected
			break
		}
	}
	if outbound == "" {
		outbound = "direct"
	}

	now := time.Now().UTC().Format(time.RFC3339)
	seeds := []struct {
		process     string
		destination string
		protocol    string
		state       string
	}{
		{process: "chrome.exe", destination: "api.openai.com:443", protocol: "tcp", state: "active"},
		{process: "msedge.exe", destination: "www.github.com:443", protocol: "tcp", state: "active"},
		{process: "discord.exe", destination: "gateway.discord.gg:443", protocol: "tcp", state: "idle"},
		{process: "steam.exe", destination: "cm0.steampowered.com:27017", protocol: "udp", state: "active"},
	}
	for _, seed := range seeds {
		s.nextConnectionID++
		s.connections = append(s.connections, connectionItem{
			ID:            s.nextConnectionID,
			ProcessName:   seed.process,
			Destination:   seed.destination,
			Protocol:      seed.protocol,
			Outbound:      outbound,
			UploadBytes:   int64(12000 + s.nextConnectionID*200),
			DownloadBytes: int64(40000 + s.nextConnectionID*500),
			LastSeenUtc:   now,
			State:         seed.state,
		})
	}
}

func (s *state) simulateConnectionsLocked() {
	s.ensureConnectionsLocked()
	now := time.Now().UTC()
	if !s.lastConnSimTick.IsZero() && now.Sub(s.lastConnSimTick) < 350*time.Millisecond {
		return
	}
	s.lastConnSimTick = now

	if !s.vpnRunning {
		for i := range s.connections {
			s.connections[i].State = "idle"
			s.connections[i].LastSeenUtc = now.Format(time.RFC3339)
		}
		return
	}

	for i := range s.connections {
		upDelta := int64(1200 + metricSeed("up", s.connections[i].ProcessName, strconv.Itoa(s.connections[i].ID), fmt.Sprint(now.Unix()/2))%6000)
		downDelta := int64(2400 + metricSeed("down", s.connections[i].Destination, strconv.Itoa(s.connections[i].ID), fmt.Sprint(now.Unix()/2))%14000)

		if strings.EqualFold(s.connections[i].State, "idle") {
			upDelta /= 3
			downDelta /= 3
		}

		s.connections[i].UploadBytes += upDelta
		s.connections[i].DownloadBytes += downDelta
		s.connections[i].LastSeenUtc = now.Format(time.RFC3339)

		if metricSeed("state", s.connections[i].ProcessName, strconv.Itoa(s.connections[i].ID), fmt.Sprint(now.Unix()/3))%17 == 0 {
			if strings.EqualFold(s.connections[i].State, "idle") {
				s.connections[i].State = "active"
			} else {
				s.connections[i].State = "idle"
			}
		}
	}

	if len(s.connections) < 10 && metricSeed("add", fmt.Sprint(now.Unix()/5), strconv.Itoa(len(s.connections)))%19 == 0 {
		outbound := "direct"
		for _, g := range s.outboundGroups {
			if g.Selected != "" {
				outbound = g.Selected
				break
			}
		}
		s.nextConnectionID++
		s.connections = append(s.connections, connectionItem{
			ID:            s.nextConnectionID,
			ProcessName:   "agent-" + strconv.Itoa(s.nextConnectionID) + ".exe",
			Destination:   "edge.openmesh.local:443",
			Protocol:      "tcp",
			Outbound:      outbound,
			UploadBytes:   2000,
			DownloadBytes: 5000,
			LastSeenUtc:   now.Format(time.RFC3339),
			State:         "active",
		})
	}

	if len(s.connections) > 4 && metricSeed("drop", fmt.Sprint(now.Unix()/7), strconv.Itoa(len(s.connections)))%23 == 0 {
		dropIdx := -1
		for i := range s.connections {
			if strings.EqualFold(s.connections[i].State, "idle") {
				dropIdx = i
				break
			}
		}
		if dropIdx >= 0 {
			s.connections = append(s.connections[:dropIdx], s.connections[dropIdx+1:]...)
		}
	}
}

func metricSeed(parts ...string) int64 {
	h := fnv.New32a()
	_, _ = h.Write([]byte(strings.ToLower(strings.Join(parts, "|"))))
	return int64(h.Sum32())
}

func (s *state) walletGenerateMnemonic() response {
	if s.walletLib == nil {
		s.walletLib = openmeshlib.NewLib()
	}
	mnemonic, err := s.walletLib.GenerateMnemonic12()
	if err != nil {
		return s.snapshot(false, "generate mnemonic via go-cli-lib failed: "+err.Error())
	}
	mnemonic = normalizeMnemonic(mnemonic)

	s.mu.Lock()
	s.lastGeneratedMnemonic = mnemonic
	resp := s.snapshotLocked(true, "mnemonic generated")
	resp.GeneratedMnemonic = s.lastGeneratedMnemonic
	s.mu.Unlock()
	return resp
}

func (s *state) walletCreate(mnemonic, password string) response {
	mnemonic = normalizeMnemonic(mnemonic)
	if mnemonic == "" {
		return s.snapshot(false, "mnemonic is empty")
	}
	if !validatePassword(password) {
		return s.snapshot(false, "password must be at least 6 characters")
	}

	if s.walletLib == nil {
		s.walletLib = openmeshlib.NewLib()
	}

	keystoreJSON, err := s.walletLib.CreateEvmWallet(mnemonic, password)
	if err != nil {
		return s.snapshot(false, "create wallet via go-cli-lib failed: "+err.Error())
	}
	secrets, err := s.walletLib.DecryptEvmWallet(keystoreJSON, password)
	if err != nil {
		return s.snapshot(false, "verify wallet via go-cli-lib failed: "+err.Error())
	}
	address := strings.TrimSpace(secrets.Address)
	if address == "" {
		return s.snapshot(false, "wallet address is empty after create")
	}

	balanceSeed := metricSeed("wallet", address)
	balance := roundAmount(10.0 + float64(balanceSeed%1500)/100.0)

	s.mu.Lock()
	s.walletExists = true
	s.walletUnlocked = true
	s.walletAddress = address
	s.walletNetwork = "base-mainnet"
	s.walletToken = "USDC"
	s.walletBalance = balance
	s.walletBalanceSource = "seeded"
	s.lastPaymentMode = ""
	s.walletKeystoreJSON = keystoreJSON
	s.walletPrivateKeyHex = strings.TrimSpace(secrets.PrivateKeyHex)
	s.walletSaltBase64 = ""
	s.walletNonceBase64 = ""
	s.walletCipherBase64 = ""
	if err := s.saveWalletKeystoreLocked(); err != nil {
		resp := s.snapshotLocked(false, "persist wallet failed: "+err.Error())
		s.mu.Unlock()
		return resp
	}

	resp := s.snapshotLocked(true, "wallet created (go-cli-lib bridge)")
	resp.WalletUnlocked = true
	resp.WalletAddress = s.walletAddress
	resp.WalletBalance = roundAmount(s.walletBalance)
	s.mu.Unlock()
	return resp
}

func (s *state) walletUnlock(password string) response {
	if !validatePassword(password) {
		return s.snapshot(false, "invalid password")
	}

	s.mu.Lock()
	if !s.walletExists {
		_ = s.loadWalletFromDiskLocked()
	}
	if !s.walletExists {
		resp := s.snapshotLocked(false, "wallet not found")
		s.mu.Unlock()
		return resp
	}

	if err := s.unlockWalletLocked(password); err != nil {
		resp := s.snapshotLocked(false, "wallet unlock failed: "+err.Error())
		s.mu.Unlock()
		return resp
	}

	s.walletUnlocked = true
	resp := s.snapshotLocked(true, "wallet unlocked")
	resp.WalletUnlocked = true
	resp.WalletAddress = s.walletAddress
	resp.WalletBalance = roundAmount(s.walletBalance)
	s.mu.Unlock()
	return resp
}

func (s *state) walletQueryBalance(network, token string) response {
	wantRealBalance := envEnabled("OPENMESH_WIN_P5_BALANCE_REAL")
	strictRealBalance := envEnabled("OPENMESH_WIN_P5_BALANCE_STRICT")

	s.mu.Lock()
	if !s.walletExists {
		_ = s.loadWalletFromDiskLocked()
	}
	if !s.walletExists {
		resp := s.snapshotLocked(false, "wallet not found")
		s.mu.Unlock()
		return resp
	}

	network = strings.TrimSpace(network)
	token = strings.TrimSpace(token)
	if network != "" {
		s.walletNetwork = network
	}
	if token != "" {
		s.walletToken = token
	}
	address := s.walletAddress
	tokenName := s.walletToken
	networkName := s.walletNetwork
	currentBalance := s.walletBalance
	s.mu.Unlock()

	balanceSource := "cached"
	if wantRealBalance {
		if s.walletLib == nil {
			s.walletLib = openmeshlib.NewLib()
		}
		balanceText, err := s.walletLib.GetTokenBalance(address, tokenName, networkName)
		if err != nil {
			if strictRealBalance {
				resp := s.snapshot(false, "wallet balance real query failed: "+err.Error())
				resp.WalletBalanceSource = "real"
				return resp
			}
			balanceSource = "cached (real query failed)"
		} else if parsed, parseErr := strconv.ParseFloat(strings.TrimSpace(balanceText), 64); parseErr != nil {
			if strictRealBalance {
				resp := s.snapshot(false, "wallet balance parse failed: "+parseErr.Error())
				resp.WalletBalanceSource = "real"
				return resp
			}
			balanceSource = "cached (real parse failed)"
		} else {
			currentBalance = roundAmount(parsed)
			balanceSource = "real"
		}
	}

	s.mu.Lock()
	s.walletBalance = currentBalance
	s.walletBalanceSource = balanceSource
	if err := s.saveWalletKeystoreLocked(); err != nil {
		resp := s.snapshotLocked(false, "persist wallet failed: "+err.Error())
		s.mu.Unlock()
		return resp
	}
	resp := s.snapshotLocked(true, "wallet balance ("+balanceSource+")")
	resp.WalletAddress = s.walletAddress
	resp.WalletBalance = roundAmount(s.walletBalance)
	resp.WalletBalanceSource = s.walletBalanceSource
	resp.WalletNetwork = s.walletNetwork
	resp.WalletToken = s.walletToken
	s.mu.Unlock()
	return resp
}

func (s *state) walletX402Pay(to, resource, amountText, password string) response {
	to = strings.TrimSpace(to)
	resource = strings.TrimSpace(resource)
	if !validateTag(to) || !validateTag(resource) {
		return s.snapshot(false, "invalid to/resource")
	}

	amount, err := strconv.ParseFloat(strings.TrimSpace(amountText), 64)
	if err != nil {
		return s.snapshot(false, "invalid amount")
	}
	amount = roundAmount(amount)
	if amount <= 0 {
		return s.snapshot(false, "amount must be positive")
	}
	wantRealX402 := envEnabled("OPENMESH_WIN_P5_X402_REAL")
	strictRealX402 := envEnabled("OPENMESH_WIN_P5_X402_STRICT")

	s.mu.Lock()
	if !s.walletExists {
		_ = s.loadWalletFromDiskLocked()
	}
	if !s.walletExists {
		resp := s.snapshotLocked(false, "wallet not found")
		s.mu.Unlock()
		return resp
	}
	if !s.walletUnlocked {
		if err := s.unlockWalletLocked(password); err != nil {
			resp := s.snapshotLocked(false, "wallet is locked; unlock failed: "+err.Error())
			s.mu.Unlock()
			return resp
		}
		s.walletUnlocked = true
	}
	x402URL := buildX402URL(to, resource)
	privateKeyHex := s.walletPrivateKeyHex

	if amount > s.walletBalance {
		resp := s.snapshotLocked(false, "insufficient balance")
		s.mu.Unlock()
		return resp
	}
	s.mu.Unlock()

	mode := "simulated"
	paymentID := "x402-" + shortRandID(12)
	if wantRealX402 {
		if x402URL == "" || privateKeyHex == "" {
			if strictRealX402 {
				resp := s.snapshot(false, "x402 real mode requires unlocked private key and valid url")
				resp.PaymentMode = "real"
				return resp
			}
		} else {
			if s.walletLib == nil {
				s.walletLib = openmeshlib.NewLib()
			}
			raw, err := s.walletLib.MakeX402Payment(x402URL, privateKeyHex)
			if err != nil {
				if strictRealX402 {
					resp := s.snapshot(false, "x402 real payment failed: "+err.Error())
					resp.PaymentMode = "real"
					return resp
				}
			} else {
				if parsed := parseX402PaymentID(raw); parsed != "" {
					paymentID = parsed
				}
				mode = "real"
			}
		}
	}

	s.mu.Lock()
	s.walletBalance = roundAmount(s.walletBalance - amount)
	s.lastPaymentMode = mode
	if err := s.saveWalletKeystoreLocked(); err != nil {
		resp := s.snapshotLocked(false, "persist wallet failed: "+err.Error())
		s.mu.Unlock()
		return resp
	}

	resp := s.snapshotLocked(true, fmt.Sprintf("x402 payment sent (%s): %s %s", mode, formatAmount(amount), s.walletToken))
	resp.WalletAddress = s.walletAddress
	resp.WalletBalance = roundAmount(s.walletBalance)
	resp.PaymentId = paymentID
	resp.PaymentMode = s.lastPaymentMode
	s.mu.Unlock()
	return resp
}

func (s *state) unlockWalletLocked(password string) error {
	password = strings.TrimSpace(password)
	if !validatePassword(password) {
		return fmt.Errorf("invalid password")
	}
	if strings.TrimSpace(s.walletKeystoreJSON) != "" {
		if s.walletLib == nil {
			s.walletLib = openmeshlib.NewLib()
		}
		secrets, err := s.walletLib.DecryptEvmWallet(s.walletKeystoreJSON, password)
		if err != nil {
			return err
		}
		if !strings.EqualFold(strings.TrimSpace(secrets.Address), strings.TrimSpace(s.walletAddress)) {
			return fmt.Errorf("wallet integrity check failed")
		}
		s.walletPrivateKeyHex = strings.TrimSpace(secrets.PrivateKeyHex)
		s.walletUnlocked = true
		return nil
	}

	// Backward compatibility: unlock older v1 keystore layout.
	mnemonic, err := decryptSecret(s.walletCipherBase64, s.walletSaltBase64, s.walletNonceBase64, password)
	if err != nil {
		return err
	}
	if deriveAddressFromMnemonic(mnemonic) != strings.ToLower(s.walletAddress) {
		return fmt.Errorf("wallet integrity check failed")
	}
	s.walletUnlocked = true
	return nil
}

func (s *state) loadWalletFromDiskLocked() error {
	raw, err := os.ReadFile(s.layout.walletKeystore)
	if err != nil {
		if os.IsNotExist(err) {
			s.walletExists = false
			s.walletUnlocked = false
			s.walletAddress = ""
			s.walletNetwork = "base-mainnet"
			s.walletToken = "USDC"
			s.walletBalance = 0
			s.walletBalanceSource = "cached"
			s.lastPaymentMode = ""
			s.walletKeystoreJSON = ""
			s.walletPrivateKeyHex = ""
			s.walletSaltBase64 = ""
			s.walletNonceBase64 = ""
			s.walletCipherBase64 = ""
			return nil
		}
		return err
	}

	var ks walletKeystore
	if err := json.Unmarshal(raw, &ks); err != nil {
		return err
	}
	s.walletExists = true
	s.walletUnlocked = false
	s.walletAddress = strings.TrimSpace(ks.Address)
	s.walletNetwork = strings.TrimSpace(ks.Network)
	if s.walletNetwork == "" {
		s.walletNetwork = "base-mainnet"
	}
	s.walletToken = strings.TrimSpace(ks.TokenSymbol)
	if s.walletToken == "" {
		s.walletToken = "USDC"
	}
	s.walletBalance = roundAmount(ks.Balance)
	s.walletBalanceSource = "cached"
	s.lastPaymentMode = ""
	s.walletKeystoreJSON = strings.TrimSpace(ks.KeystoreJSON)
	s.walletPrivateKeyHex = ""
	s.walletSaltBase64 = strings.TrimSpace(ks.SaltBase64)
	s.walletNonceBase64 = strings.TrimSpace(ks.NonceBase64)
	s.walletCipherBase64 = strings.TrimSpace(ks.CipherBase64)
	return nil
}

func (s *state) saveWalletKeystoreLocked() error {
	if err := os.MkdirAll(s.layout.walletRoot, 0o755); err != nil {
		return err
	}
	ks := walletKeystore{
		Address:      s.walletAddress,
		Network:      s.walletNetwork,
		TokenSymbol:  s.walletToken,
		KeystoreJSON: s.walletKeystoreJSON,
		SaltBase64:   s.walletSaltBase64,
		NonceBase64:  s.walletNonceBase64,
		CipherBase64: s.walletCipherBase64,
		Balance:      roundAmount(s.walletBalance),
	}
	data, err := json.MarshalIndent(ks, "", "  ")
	if err != nil {
		return err
	}
	return os.WriteFile(s.layout.walletKeystore, data, 0o644)
}

type encSecret struct {
	saltBase64   string
	nonceBase64  string
	cipherBase64 string
}

func encryptSecret(plain, password string) (encSecret, error) {
	salt := make([]byte, 16)
	nonce := make([]byte, 12)
	if _, err := rand.Read(salt); err != nil {
		return encSecret{}, err
	}
	if _, err := rand.Read(nonce); err != nil {
		return encSecret{}, err
	}
	key := deriveKey(password, salt)
	block, err := aes.NewCipher(key)
	if err != nil {
		return encSecret{}, err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return encSecret{}, err
	}
	cipherData := aead.Seal(nil, nonce, []byte(plain), nil)
	return encSecret{
		saltBase64:   base64.StdEncoding.EncodeToString(salt),
		nonceBase64:  base64.StdEncoding.EncodeToString(nonce),
		cipherBase64: base64.StdEncoding.EncodeToString(cipherData),
	}, nil
}

func decryptSecret(cipherB64, saltB64, nonceB64, password string) (string, error) {
	salt, err := base64.StdEncoding.DecodeString(strings.TrimSpace(saltB64))
	if err != nil {
		return "", err
	}
	nonce, err := base64.StdEncoding.DecodeString(strings.TrimSpace(nonceB64))
	if err != nil {
		return "", err
	}
	cipherData, err := base64.StdEncoding.DecodeString(strings.TrimSpace(cipherB64))
	if err != nil {
		return "", err
	}

	key := deriveKey(password, salt)
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	aead, err := cipher.NewGCM(block)
	if err != nil {
		return "", err
	}
	plain, err := aead.Open(nil, nonce, cipherData, nil)
	if err != nil {
		return "", err
	}
	return string(plain), nil
}

func deriveKey(password string, salt []byte) []byte {
	sum := sha256.Sum256(append([]byte(strings.TrimSpace(password)), salt...))
	key := sum[:]
	for i := 0; i < 50; i++ {
		next := sha256.Sum256(append(key, salt...))
		key = next[:]
	}
	out := make([]byte, 32)
	copy(out, key)
	return out
}

func deriveAddressFromMnemonic(mnemonic string) string {
	mnemonic = normalizeMnemonic(mnemonic)
	sum := sha256.Sum256([]byte(strings.ToLower(mnemonic)))
	return "0x" + hex.EncodeToString(sum[:20])
}

func normalizeMnemonic(in string) string {
	parts := strings.Fields(strings.TrimSpace(in))
	return strings.Join(parts, " ")
}

func validatePassword(password string) bool {
	return len(strings.TrimSpace(password)) >= 6
}

func validateTag(v string) bool {
	return strings.TrimSpace(v) != ""
}

func envEnabled(name string) bool {
	v := strings.ToLower(strings.TrimSpace(os.Getenv(name)))
	return v == "1" || v == "true" || v == "yes" || v == "on"
}

func buildX402URL(to, resource string) string {
	base := strings.TrimSpace(to)
	path := strings.TrimSpace(resource)
	if base == "" {
		return ""
	}
	if path != "" && !strings.HasPrefix(path, "/") {
		path = "/" + path
	}

	if strings.HasPrefix(strings.ToLower(base), "http://") || strings.HasPrefix(strings.ToLower(base), "https://") {
		if path == "" {
			return base
		}
		return strings.TrimRight(base, "/") + path
	}
	if path == "" {
		path = "/"
	}
	return "https://" + strings.Trim(base, "/") + path
}

func parseX402PaymentID(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	var payload map[string]any
	if err := json.Unmarshal([]byte(raw), &payload); err != nil {
		return ""
	}
	if settleRaw, ok := payload["settle"]; ok {
		if settle, ok := settleRaw.(map[string]any); ok {
			if txRaw, ok := settle["transaction"]; ok {
				if tx, ok := txRaw.(string); ok && strings.TrimSpace(tx) != "" {
					return strings.TrimSpace(tx)
				}
			}
		}
	}
	if idRaw, ok := payload["paymentId"]; ok {
		if paymentID, ok := idRaw.(string); ok && strings.TrimSpace(paymentID) != "" {
			return strings.TrimSpace(paymentID)
		}
	}
	return ""
}

func roundAmount(v float64) float64 {
	return math.Round(v*1_000_000) / 1_000_000
}

func formatAmount(v float64) string {
	return strconv.FormatFloat(roundAmount(v), 'f', -1, 64)
}

func shortRandID(n int) string {
	if n <= 0 {
		return "0"
	}
	raw := make([]byte, (n+1)/2)
	if _, err := rand.Read(raw); err != nil {
		return fmt.Sprintf("%d", time.Now().UnixNano())
	}
	hexv := hex.EncodeToString(raw)
	if len(hexv) > n {
		return hexv[:n]
	}
	return hexv
}

func (s *state) selectOutbound(group, outbound string) response {
	group = strings.TrimSpace(group)
	outbound = strings.TrimSpace(outbound)
	if group == "" || outbound == "" {
		return s.snapshot(false, "invalid group/outbound tag")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	gidx := -1
	for i := range s.outboundGroups {
		if strings.EqualFold(s.outboundGroups[i].Tag, group) {
			gidx = i
			break
		}
	}
	if gidx < 0 {
		return s.snapshotLocked(false, "group not found: "+group)
	}
	found := ""
	for _, item := range s.outboundGroups[gidx].Items {
		if strings.EqualFold(item.Tag, outbound) {
			found = item.Tag
			break
		}
	}
	if found == "" {
		return s.snapshotLocked(false, "outbound not in group: "+outbound)
	}
	s.outboundGroups[gidx].Selected = found
	s.selectedByGroup[s.outboundGroups[gidx].Tag] = found
	if s.configRoot != nil {
		cfg := deepCopy(s.configRoot)
		groups := cloneGroups(s.outboundGroups)
		applySelection(cfg, groups, s.selectedByGroup)
		if _, hash, err := writeEffective(cfg, s.layout.effectiveCfg); err == nil {
			s.configRoot = cfg
			s.lastConfigHash = hash
		} else {
			s.lastReloadError = err.Error()
			return s.snapshotLocked(false, "persist selection failed: "+err.Error())
		}
	}
	return s.snapshotLocked(true, fmt.Sprintf("selected %s in %s (go core)", found, s.outboundGroups[gidx].Tag))
}

func (s *state) snapshotLocked(ok bool, msg string) response {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	totalUp, totalDown, connCount := summarizeConnections(s.connections)
	upRate, downRate := estimateConnectionRates(s.connections, s.vpnRunning)
	lastReload := ""
	if !s.lastReloadAt.IsZero() {
		lastReload = s.lastReloadAt.Format(time.RFC3339)
	}
	return response{
		Ok:                  ok,
		Message:             msg,
		CoreRunning:         true,
		VpnRunning:          s.vpnRunning,
		StartedAtUtc:        s.startedAt.Format(time.RFC3339),
		ProfilePath:         s.selectedProfile,
		EffectiveConfigPath: s.effectiveCfg,
		LastConfigHash:      s.lastConfigHash,
		InjectedRuleCount:   s.injectedRuleCount,
		LastReloadAtUtc:     lastReload,
		LastReloadError:     s.lastReloadError,
		Group:               "",
		Delays:              map[string]int{},
		OutboundGroups:      cloneGroups(s.outboundGroups),
		Connections:         cloneConnections(s.connections),
		Runtime: runtimeStats{
			TotalUploadBytes:        totalUp,
			TotalDownloadBytes:      totalDown,
			UploadRateBytesPerSec:   upRate,
			DownloadRateBytesPerSec: downRate,
			MemoryMb:                float64(m.Alloc) / 1024.0 / 1024.0,
			ThreadCount:             runtime.NumGoroutine(),
			UptimeSeconds:           int64(time.Since(s.startedAt).Seconds()),
			ConnectionCount:         connCount,
		},
		WalletExists:               s.walletExists,
		WalletUnlocked:             s.walletUnlocked,
		WalletAddress:              s.walletAddress,
		WalletNetwork:              s.walletNetwork,
		WalletToken:                s.walletToken,
		WalletBalance:              roundAmount(s.walletBalance),
		WalletBalanceSource:        s.walletBalanceSource,
		GeneratedMnemonic:          s.lastGeneratedMnemonic,
		PaymentId:                  "",
		PaymentMode:                s.lastPaymentMode,
		P3PreflightCheckedAtUtc:    formatTime(s.p3PreflightCheckedAt),
		P3Admin:                    s.p3Admin,
		P3WintunFound:              s.p3WintunFound,
		P3WintunPath:               s.p3WintunPath,
		P3NetworkPrepared:          s.p3NetworkPrepared,
		P3NetworkDryRun:            s.p3NetworkDryRun,
		P3LastNetworkError:         s.p3LastNetworkError,
		P3LastRollbackAtUtc:        formatTime(s.p3LastRollbackAt),
		P3AppliedCommands:          append([]string{}, s.p3AppliedCommands...),
		P3EngineMode:               s.p3EngineMode,
		P3EngineProbeAtUtc:         formatTime(s.p3EngineProbeAt),
		P3SingboxFound:             s.p3SingboxFound,
		P3SingboxPath:              s.p3SingboxPath,
		P3EngineRunning:            s.p3EngineRunning,
		P3EnginePid:                s.p3EnginePid,
		P3EngineLastError:          s.p3EngineLastError,
		P3EngineLastExitAtUtc:      formatTime(s.p3EngineLastExitAt),
		P3EngineLastExitCode:       s.p3EngineLastExitCode,
		P3EngineHealthy:            s.p3EngineHealthy,
		P3EngineHealthCheckedAtUtc: formatTime(s.p3EngineHealthCheckedAt),
		P3EngineHealthMessage:      s.p3EngineHealthMessage,
		StreamType:                 "",
		StreamSeq:                  0,
		StreamFingerprint:          "",
	}
}

func formatTime(t time.Time) string {
	if t.IsZero() {
		return ""
	}
	return t.UTC().Format(time.RFC3339)
}

func (s *state) p3NetworkPreflight() response {
	admin := detectAdmin()
	wintunPath := findWintunPath()
	wintunFound := wintunPath != ""
	errs := []string{}
	if !admin {
		errs = append(errs, "administrator privilege missing")
	}
	if !wintunFound {
		errs = append(errs, "wintun.dll not found")
	}

	s.mu.Lock()
	s.p3PreflightCheckedAt = time.Now().UTC()
	s.p3Admin = admin
	s.p3WintunFound = wintunFound
	s.p3WintunPath = wintunPath
	if len(errs) > 0 {
		s.p3LastNetworkError = strings.Join(errs, "; ")
	} else {
		s.p3LastNetworkError = ""
	}
	s.mu.Unlock()

	if len(errs) > 0 {
		return s.snapshot(false, "p3 preflight failed: "+strings.Join(errs, "; "))
	}
	return s.snapshot(true, "p3 preflight ok")
}

func (s *state) p3AutoPrepareNetwork() response {
	if !isTruthyEnv("OPENMESH_WIN_P3_ENABLE") {
		return s.snapshot(true, "p3 network framework disabled")
	}
	return s.p3NetworkPrepare()
}

func (s *state) p3AutoRollbackNetwork() response {
	if !isTruthyEnv("OPENMESH_WIN_P3_ENABLE") {
		return s.snapshot(true, "p3 network framework disabled")
	}
	return s.p3NetworkRollback()
}

func (s *state) p3CurrentEngineMode() string {
	mode := strings.TrimSpace(strings.ToLower(os.Getenv("OPENMESH_WIN_P3_ENGINE")))
	if mode == "" {
		return "mock"
	}
	if mode == "singbox" || mode == "sing-box" {
		return "singbox"
	}
	return "mock"
}

func (s *state) p3RefreshEngineProbeLocked() {
	mode := s.p3CurrentEngineMode()
	s.p3EngineMode = mode
	s.p3EngineProbeAt = time.Now().UTC()
	s.p3SingboxFound = false
	s.p3SingboxPath = ""

	if mode != "singbox" {
		return
	}

	if p := findSingboxPath(); p != "" {
		s.p3SingboxFound = true
		s.p3SingboxPath = p
	}
}

func (s *state) p3EngineProbe() response {
	s.mu.Lock()
	s.p3RefreshEngineProbeLocked()
	mode := s.p3EngineMode
	found := s.p3SingboxFound
	if s.p3EngineMode == "singbox" && !s.p3SingboxFound {
		s.p3EngineLastError = "sing-box executable not found"
	}
	s.mu.Unlock()

	if mode != "singbox" {
		return s.snapshot(true, "p3 engine mode=mock (sing-box not required)")
	}
	if !found {
		return s.snapshot(false, "p3 engine probe: sing-box executable not found")
	}
	return s.snapshot(true, "p3 engine probe: sing-box executable found")
}

func (s *state) p3AutoStartEngine() response {
	return s.p3EngineStart()
}

func (s *state) p3AutoStopEngine() response {
	return s.p3EngineStop()
}

func (s *state) p3EngineStart() response {
	s.mu.Lock()
	s.p3RefreshEngineProbeLocked()
	mode := s.p3EngineMode
	alreadyRunning := s.p3EngineRunning
	singboxPath := s.p3SingboxPath
	configPath := s.effectiveCfg
	s.mu.Unlock()

	if mode != "singbox" {
		return s.snapshot(true, "p3 engine start skipped: mode=mock")
	}
	if alreadyRunning {
		return s.snapshot(true, "p3 engine already running")
	}
	if singboxPath == "" {
		s.mu.Lock()
		s.p3EngineLastError = "sing-box executable not found"
		s.mu.Unlock()
		return s.snapshot(false, "p3 engine start failed: sing-box executable not found")
	}
	if strings.TrimSpace(configPath) == "" || !fileExists(configPath) {
		s.mu.Lock()
		s.p3EngineLastError = "effective config missing"
		s.mu.Unlock()
		return s.snapshot(false, "p3 engine start failed: effective config missing")
	}

	args := buildSingboxArgs(configPath)
	cmd := exec.Command(singboxPath, args...)

	logDir := filepath.Join(s.layout.runtimeRoot, "logs")
	_ = os.MkdirAll(logDir, 0o755)
	stdoutPath := filepath.Join(logDir, "singbox.stdout.log")
	stderrPath := filepath.Join(logDir, "singbox.stderr.log")
	stdoutFile, _ := os.OpenFile(stdoutPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	stderrFile, _ := os.OpenFile(stderrPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if stdoutFile != nil {
		cmd.Stdout = stdoutFile
	}
	if stderrFile != nil {
		cmd.Stderr = stderrFile
	}

	if err := cmd.Start(); err != nil {
		s.mu.Lock()
		s.p3EngineLastError = "start sing-box failed: " + err.Error()
		s.mu.Unlock()
		if stdoutFile != nil {
			_ = stdoutFile.Close()
		}
		if stderrFile != nil {
			_ = stderrFile.Close()
		}
		return s.snapshot(false, "p3 engine start failed: "+err.Error())
	}

	s.mu.Lock()
	s.p3EngineCmd = cmd
	s.p3EngineRunning = true
	s.p3EnginePid = cmd.Process.Pid
	s.p3EngineLastError = ""
	s.p3EngineLastExitCode = 0
	s.p3EngineHealthy = false
	s.p3EngineHealthCheckedAt = time.Time{}
	s.p3EngineHealthMessage = ""
	s.mu.Unlock()

	go func(c *exec.Cmd, outF, errF *os.File) {
		waitErr := c.Wait()
		exitCode := 0
		if c.ProcessState != nil {
			exitCode = c.ProcessState.ExitCode()
		} else if waitErr != nil {
			exitCode = -1
		}

		needRollback := false
		s.mu.Lock()
		s.p3EngineRunning = false
		s.p3EnginePid = 0
		s.p3EngineCmd = nil
		s.p3EngineLastExitAt = time.Now().UTC()
		s.p3EngineLastExitCode = exitCode
		s.p3EngineHealthy = false
		if waitErr != nil {
			s.p3EngineLastError = "sing-box exited: " + waitErr.Error()
		}
		if s.vpnRunning {
			s.vpnRunning = false
		}
		needRollback = s.p3NetworkPrepared
		s.mu.Unlock()

		if needRollback {
			_ = s.p3AutoRollbackNetwork()
		}
		if outF != nil {
			_ = outF.Close()
		}
		if errF != nil {
			_ = errF.Close()
		}
	}(cmd, stdoutFile, stderrFile)

	health := s.p3EngineHealth()
	if !health.Ok {
		_ = s.p3EngineStop()
		return s.snapshot(false, "p3 engine start failed: "+health.Message)
	}
	return s.snapshot(true, fmt.Sprintf("p3 engine started pid=%d", cmd.Process.Pid))
}

func (s *state) p3EngineStop() response {
	s.mu.Lock()
	s.p3RefreshEngineProbeLocked()
	mode := s.p3EngineMode
	cmd := s.p3EngineCmd
	running := s.p3EngineRunning
	pid := s.p3EnginePid
	s.mu.Unlock()

	if mode != "singbox" {
		return s.snapshot(true, "p3 engine stop skipped: mode=mock")
	}
	if !running || cmd == nil || pid <= 0 {
		return s.snapshot(true, "p3 engine stop skipped: engine not running")
	}

	if err := terminateProcessTree(pid); err != nil {
		if cmd.Process != nil {
			_ = cmd.Process.Kill()
		}
		s.mu.Lock()
		s.p3EngineLastError = "stop sing-box failed: " + err.Error()
		s.mu.Unlock()
		return s.snapshot(false, "p3 engine stop failed: "+err.Error())
	}

	s.mu.Lock()
	s.p3EngineRunning = false
	s.p3EnginePid = 0
	s.p3EngineCmd = nil
	s.p3EngineLastExitAt = time.Now().UTC()
	s.p3EngineHealthy = false
	s.p3EngineHealthMessage = "engine stopped"
	s.p3EngineHealthCheckedAt = time.Now().UTC()
	s.mu.Unlock()
	return s.snapshot(true, "p3 engine stopped")
}

func (s *state) p3EngineHealth() response {
	s.mu.Lock()
	s.p3RefreshEngineProbeLocked()
	mode := s.p3EngineMode
	running := s.p3EngineRunning
	pid := s.p3EnginePid
	s.mu.Unlock()

	if mode != "singbox" {
		s.mu.Lock()
		s.p3EngineHealthy = true
		s.p3EngineHealthCheckedAt = time.Now().UTC()
		s.p3EngineHealthMessage = "mode=mock"
		s.mu.Unlock()
		return s.snapshot(true, "p3 engine health: mock mode")
	}

	if !running || pid <= 0 {
		s.mu.Lock()
		s.p3EngineHealthy = false
		s.p3EngineHealthCheckedAt = time.Now().UTC()
		s.p3EngineHealthMessage = "engine not running"
		s.p3EngineLastError = "engine not running"
		s.mu.Unlock()
		return s.snapshot(false, "p3 engine health failed: engine not running")
	}

	ok, msg := waitEngineHealthy(pid)
	s.mu.Lock()
	s.p3EngineHealthy = ok
	s.p3EngineHealthCheckedAt = time.Now().UTC()
	s.p3EngineHealthMessage = msg
	if !ok {
		s.p3EngineLastError = msg
	}
	s.mu.Unlock()

	if !ok {
		return s.snapshot(false, "p3 engine health failed: "+msg)
	}
	return s.snapshot(true, "p3 engine health ok: "+msg)
}

func waitEngineHealthy(pid int) (bool, string) {
	if pid <= 0 {
		return false, "invalid engine pid"
	}
	if !processExists(pid) {
		return false, "engine process not found"
	}

	endpoint := strings.TrimSpace(os.Getenv("OPENMESH_WIN_P3_HEALTH_TCP"))
	timeout := healthCheckTimeout()
	if endpoint == "" {
		return true, fmt.Sprintf("process alive pid=%d", pid)
	}

	deadline := time.Now().Add(timeout)
	lastErr := ""
	for {
		if !processExists(pid) {
			return false, "engine process exited before tcp health check passed"
		}
		conn, err := net.DialTimeout("tcp", endpoint, 350*time.Millisecond)
		if err == nil {
			_ = conn.Close()
			return true, "tcp health reachable: " + endpoint
		}
		lastErr = err.Error()
		if time.Now().After(deadline) {
			break
		}
		time.Sleep(150 * time.Millisecond)
	}
	return false, fmt.Sprintf("tcp health timeout endpoint=%s within %dms: %s", endpoint, timeout.Milliseconds(), lastErr)
}

func healthCheckTimeout() time.Duration {
	const (
		defaultMs = 3000
		minMs     = 200
		maxMs     = 60000
	)
	raw := strings.TrimSpace(os.Getenv("OPENMESH_WIN_P3_HEALTH_TIMEOUT_MS"))
	if raw == "" {
		return defaultMs * time.Millisecond
	}
	ms, err := strconv.Atoi(raw)
	if err != nil || ms <= 0 {
		return defaultMs * time.Millisecond
	}
	if ms < minMs {
		ms = minMs
	}
	if ms > maxMs {
		ms = maxMs
	}
	return time.Duration(ms) * time.Millisecond
}

func processExists(pid int) bool {
	if pid <= 0 {
		return false
	}
	cmd := exec.Command("tasklist", "/FI", fmt.Sprintf("PID eq %d", pid), "/FO", "CSV", "/NH")
	out, err := cmd.CombinedOutput()
	if err != nil {
		return false
	}

	text := strings.TrimSpace(string(out))
	if text == "" {
		return false
	}
	lower := strings.ToLower(text)
	if strings.Contains(lower, "no tasks are running") || strings.Contains(text, "没有运行的任务") {
		return false
	}

	reader := csv.NewReader(strings.NewReader(text))
	row, err := reader.Read()
	if err == nil && len(row) >= 2 {
		return strings.TrimSpace(row[1]) == strconv.Itoa(pid)
	}
	return strings.Contains(text, "\""+strconv.Itoa(pid)+"\"")
}

func buildSingboxArgs(configPath string) []string {
	template := strings.TrimSpace(os.Getenv("OPENMESH_WIN_P3_SINGBOX_ARGS"))
	if template == "" {
		return []string{"run", "-c", configPath}
	}
	parts := strings.Fields(template)
	args := make([]string, 0, len(parts))
	usedConfigToken := false
	for _, p := range parts {
		if p == "{config}" {
			args = append(args, configPath)
			usedConfigToken = true
		} else {
			args = append(args, p)
		}
	}
	if !usedConfigToken {
		args = append(args, "-c", configPath)
	}
	return args
}

func (s *state) p3NetworkPrepare() response {
	pref := s.p3NetworkPreflight()
	if !pref.Ok && isTruthyEnv("OPENMESH_WIN_P3_STRICT") {
		return s.snapshot(false, "p3 prepare blocked by strict preflight: "+pref.Message)
	}

	apply := isTruthyEnv("OPENMESH_WIN_P3_APPLY")
	planned, rollback := buildP3CommandPlan(apply)

	executed := []string{}
	if apply {
		for _, cmd := range planned {
			if err := runShellCommand(cmd); err != nil {
				s.mu.Lock()
				s.p3LastNetworkError = "p3 command failed: " + cmd + " error: " + err.Error()
				s.mu.Unlock()
				_ = s.p3RollbackFromCommands(rollback)
				return s.snapshot(false, s.p3LastNetworkError)
			}
			executed = append(executed, cmd)
		}
	} else {
		executed = append(executed, planned...)
	}

	s.mu.Lock()
	s.p3NetworkPrepared = true
	s.p3NetworkDryRun = !apply
	s.p3LastNetworkError = ""
	s.p3AppliedCommands = append([]string{}, executed...)
	s.p3RollbackCommands = append([]string{}, rollback...)
	s.mu.Unlock()

	if apply {
		return s.snapshot(true, "p3 network prepared (applied)")
	}
	return s.snapshot(true, "p3 network prepared (dry-run)")
}

func (s *state) p3NetworkRollback() response {
	s.mu.Lock()
	rollback := append([]string{}, s.p3RollbackCommands...)
	wasPrepared := s.p3NetworkPrepared
	s.mu.Unlock()

	if !wasPrepared {
		return s.snapshot(true, "p3 rollback skipped: network not prepared")
	}

	if err := s.p3RollbackFromCommands(rollback); err != nil {
		s.mu.Lock()
		s.p3LastNetworkError = err.Error()
		s.mu.Unlock()
		return s.snapshot(false, "p3 rollback failed: "+err.Error())
	}

	s.mu.Lock()
	s.p3NetworkPrepared = false
	s.p3AppliedCommands = []string{}
	s.p3RollbackCommands = []string{}
	s.p3LastRollbackAt = time.Now().UTC()
	s.p3LastNetworkError = ""
	s.mu.Unlock()
	return s.snapshot(true, "p3 rollback completed")
}

func (s *state) p3RollbackFromCommands(rollback []string) error {
	if len(rollback) == 0 {
		return nil
	}
	if !isTruthyEnv("OPENMESH_WIN_P3_APPLY") {
		return nil
	}
	for _, cmd := range rollback {
		if err := runShellCommand(cmd); err != nil {
			return fmt.Errorf("rollback command failed: %s error: %w", cmd, err)
		}
	}
	return nil
}

func buildP3CommandPlan(apply bool) ([]string, []string) {
	planned := []string{}
	rollback := []string{}

	routeCidr := strings.TrimSpace(os.Getenv("OPENMESH_WIN_P3_ROUTE_CIDR"))
	routeGw := strings.TrimSpace(os.Getenv("OPENMESH_WIN_P3_ROUTE_GATEWAY"))
	if routeCidr != "" && routeGw != "" {
		planned = append(planned, fmt.Sprintf("route add %s %s metric 5", routeCidr, routeGw))
		rollback = append([]string{fmt.Sprintf("route delete %s", routeCidr)}, rollback...)
	}

	iface := strings.TrimSpace(os.Getenv("OPENMESH_WIN_P3_DNS_IFACE"))
	dnsServer := strings.TrimSpace(os.Getenv("OPENMESH_WIN_P3_DNS_SERVER"))
	if iface != "" && dnsServer != "" {
		planned = append(planned, fmt.Sprintf("netsh interface ipv4 set dnsservers name=\"%s\" static %s primary", iface, dnsServer))
		rollbackMode := strings.TrimSpace(os.Getenv("OPENMESH_WIN_P3_DNS_ROLLBACK"))
		if rollbackMode == "" || strings.EqualFold(rollbackMode, "dhcp") {
			rollback = append([]string{fmt.Sprintf("netsh interface ipv4 set dnsservers name=\"%s\" dhcp", iface)}, rollback...)
		} else {
			rollback = append([]string{fmt.Sprintf("netsh interface ipv4 set dnsservers name=\"%s\" static %s primary", iface, rollbackMode)}, rollback...)
		}
	}

	if len(planned) == 0 {
		planned = append(planned, "echo p3: no route/dns operation configured")
	}
	if !apply {
		rollback = []string{}
	}
	return planned, rollback
}

func isTruthyEnv(key string) bool {
	v := strings.TrimSpace(strings.ToLower(os.Getenv(key)))
	return v == "1" || v == "true" || v == "yes" || v == "on"
}

func detectAdmin() bool {
	cmd := exec.Command("cmd", "/C", "net session >nul 2>&1")
	return cmd.Run() == nil
}

func findWintunPath() string {
	if explicit := strings.TrimSpace(os.Getenv("OPENMESH_WIN_WINTUN_DLL")); explicit != "" {
		if fileExists(explicit) {
			return explicit
		}
	}
	exe, _ := os.Executable()
	base := filepath.Dir(exe)
	candidates := []string{
		filepath.Join(base, "wintun.dll"),
		filepath.Join(base, "deps", "wintun.dll"),
		filepath.Join(os.Getenv("WINDIR"), "System32", "wintun.dll"),
		filepath.Join(os.Getenv("WINDIR"), "SysWOW64", "wintun.dll"),
	}
	for _, c := range candidates {
		if fileExists(c) {
			return c
		}
	}
	return ""
}

func findSingboxPath() string {
	if explicit := strings.TrimSpace(os.Getenv("OPENMESH_WIN_SINGBOX_EXE")); explicit != "" {
		if fileExists(explicit) {
			return explicit
		}
	}
	exe, _ := os.Executable()
	base := filepath.Dir(exe)
	candidates := []string{
		filepath.Join(base, "sing-box.exe"),
		filepath.Join(base, "deps", "sing-box.exe"),
		filepath.Join(base, "..", "..", "..", "sing-box", "sing-box.exe"),
		filepath.Join(base, "..", "..", "sing-box", "sing-box.exe"),
		filepath.Join(base, "..", "sing-box", "sing-box.exe"),
		filepath.Join("C:\\", "Program Files", "sing-box", "sing-box.exe"),
	}
	for _, c := range candidates {
		abs := c
		if !filepath.IsAbs(c) {
			if r, err := filepath.Abs(c); err == nil {
				abs = r
			}
		}
		if fileExists(abs) {
			return abs
		}
	}
	return ""
}

func terminateProcessTree(pid int) error {
	if pid <= 0 {
		return nil
	}
	kill := exec.Command("taskkill", "/PID", strconv.Itoa(pid), "/T", "/F")
	if out, err := kill.CombinedOutput(); err != nil {
		msg := strings.TrimSpace(string(out))
		if msg == "" {
			msg = err.Error()
		}
		return fmt.Errorf(msg)
	}
	return nil
}

func fileExists(path string) bool {
	if strings.TrimSpace(path) == "" {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
}

func runShellCommand(command string) error {
	command = strings.TrimSpace(command)
	if command == "" {
		return nil
	}
	cmd := exec.Command("cmd", "/C", command)
	output, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("%w: %s", err, strings.TrimSpace(string(output)))
	}
	return nil
}

func parseRelaxedObject(raw string) (map[string]any, error) {
	raw = strings.TrimPrefix(raw, "\uFEFF")
	clean := stripTrailingComma(stripJSONComments(raw))
	var out map[string]any
	err := json.Unmarshal([]byte(clean), &out)
	return out, err
}

func stripJSONComments(in string) string {
	b := []byte(in)
	var o strings.Builder
	o.Grow(len(b))
	str := false
	esc := false
	for i := 0; i < len(b); i++ {
		c := b[i]
		if str {
			o.WriteByte(c)
			if esc {
				esc = false
			} else if c == '\\' {
				esc = true
			} else if c == '"' {
				str = false
			}
			continue
		}
		if c == '"' {
			str = true
			o.WriteByte(c)
			continue
		}
		if c == '/' && i+1 < len(b) && b[i+1] == '/' {
			for i < len(b) && b[i] != '\n' {
				i++
			}
			if i < len(b) {
				o.WriteByte('\n')
			}
			continue
		}
		if c == '/' && i+1 < len(b) && b[i+1] == '*' {
			i += 2
			for i+1 < len(b) && !(b[i] == '*' && b[i+1] == '/') {
				i++
			}
			i++
			continue
		}
		o.WriteByte(c)
	}
	return o.String()
}

func stripTrailingComma(in string) string {
	b := []byte(in)
	var o strings.Builder
	o.Grow(len(b))
	str := false
	esc := false
	for i := 0; i < len(b); i++ {
		c := b[i]
		if str {
			o.WriteByte(c)
			if esc {
				esc = false
			} else if c == '\\' {
				esc = true
			} else if c == '"' {
				str = false
			}
			continue
		}
		if c == '"' {
			str = true
			o.WriteByte(c)
			continue
		}
		if c == ',' {
			j := i + 1
			for j < len(b) && (b[j] == ' ' || b[j] == '\t' || b[j] == '\r' || b[j] == '\n') {
				j++
			}
			if j < len(b) && (b[j] == ']' || b[j] == '}') {
				continue
			}
		}
		o.WriteByte(c)
	}
	return o.String()
}

type dynRules struct {
	ipCIDR       []string
	domain       []string
	domainSuffix []string
	domainRegex  []string
}

func parseDynamicRules(raw string) dynRules {
	raw = strings.TrimSpace(raw)
	raw = strings.TrimPrefix(raw, "\uFEFF")
	if raw == "" {
		return dynRules{}
	}
	if strings.HasPrefix(raw, "{") {
		if root, err := parseRelaxedObject(raw); err == nil {
			return parseDynamicRulesJSON(root)
		}
	}
	return parseDynamicRulesText(raw)
}

func parseDynamicRulesJSON(root map[string]any) dynRules {
	if proxy, ok := root["proxy"].(map[string]any); ok {
		root = proxy
	}
	out := dynRules{}
	if rules, ok := asArr(root["rules"]); ok {
		for _, r := range rules {
			obj, ok := r.(map[string]any)
			if !ok {
				continue
			}
			out.ipCIDR = append(out.ipCIDR, readStrings(obj["ip_cidr"])...)
			out.domain = append(out.domain, readStrings(obj["domain"])...)
			out.domainSuffix = append(out.domainSuffix, readStrings(obj["domain_suffix"])...)
			out.domainRegex = append(out.domainRegex, readStrings(obj["domain_regex"])...)
		}
	} else {
		out.ipCIDR = append(out.ipCIDR, readStrings(root["ip_cidr"])...)
		out.domain = append(out.domain, readStrings(root["domain"])...)
		out.domainSuffix = append(out.domainSuffix, readStrings(root["domain_suffix"])...)
		out.domainRegex = append(out.domainRegex, readStrings(root["domain_regex"])...)
	}
	out.ipCIDR = uniq(out.ipCIDR)
	out.domain = uniq(out.domain)
	out.domainSuffix = uniq(out.domainSuffix)
	out.domainRegex = uniq(out.domainRegex)
	return out
}

func parseDynamicRulesText(raw string) dynRules {
	out := dynRules{}
	for _, line := range strings.Split(raw, "\n") {
		line = strings.TrimSpace(line)
		if line == "" || strings.HasPrefix(line, "#") || strings.HasPrefix(line, "//") || strings.HasPrefix(line, ";") {
			continue
		}
		if idx := strings.Index(line, ":"); idx > 0 {
			k := strings.ToLower(strings.TrimSpace(line[:idx]))
			v := splitVals(line[idx+1:])
			switch k {
			case "ip", "ipcidr", "ip_cidr":
				out.ipCIDR = append(out.ipCIDR, v...)
			case "domain", "host":
				out.domain = append(out.domain, v...)
			case "domain_suffix", "suffix", "domainsuffix":
				out.domainSuffix = append(out.domainSuffix, v...)
			case "domain_regex", "regex", "re":
				out.domainRegex = append(out.domainRegex, v...)
			default:
				for _, item := range v {
					classifyRule(&out, item)
				}
			}
			continue
		}
		classifyRule(&out, line)
	}
	out.ipCIDR = uniq(out.ipCIDR)
	out.domain = uniq(out.domain)
	out.domainSuffix = uniq(out.domainSuffix)
	out.domainRegex = uniq(out.domainRegex)
	return out
}

func classifyRule(out *dynRules, s string) {
	s = strings.TrimSpace(s)
	if s == "" {
		return
	}
	if _, _, err := net.ParseCIDR(s); err == nil {
		out.ipCIDR = append(out.ipCIDR, s)
		return
	}
	if strings.HasPrefix(s, ".") {
		out.domainSuffix = append(out.domainSuffix, s)
		return
	}
	if strings.ContainsAny(s, "*^$[]()|\\+?") {
		out.domainRegex = append(out.domainRegex, s)
		return
	}
	out.domain = append(out.domain, s)
}

func splitVals(s string) []string {
	parts := strings.FieldsFunc(s, func(r rune) bool { return r == ',' || r == ';' })
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		p = strings.TrimSpace(p)
		if p != "" {
			out = append(out, p)
		}
	}
	return out
}

func uniq(in []string) []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, len(in))
	for _, s := range in {
		s = strings.TrimSpace(s)
		if s == "" {
			continue
		}
		if _, ok := seen[s]; ok {
			continue
		}
		seen[s] = struct{}{}
		out = append(out, s)
	}
	return out
}

func injectRules(root map[string]any, dr dynRules) int {
	route := ensureMap(root, "route")
	rules := ensureArr(route, "rules")
	sniffIdx := -1
	for i, r := range rules {
		if obj, ok := r.(map[string]any); ok {
			if act, _ := obj["action"].(string); strings.EqualFold(act, "sniff") {
				sniffIdx = i
				break
			}
		}
	}
	if sniffIdx < 0 {
		rules = append([]any{map[string]any{"action": "sniff"}}, rules...)
		sniffIdx = 0
	}

	injected := make([]map[string]any, 0, 4)
	if len(dr.ipCIDR) > 0 {
		injected = append(injected, map[string]any{"ip_cidr": toAny(dr.ipCIDR), "outbound": "proxy"})
	}
	suffix := make([]string, 0, len(dr.domainSuffix))
	domain := append([]string{}, dr.domain...)
	for _, s := range dr.domainSuffix {
		if strings.HasPrefix(s, ".") {
			suffix = append(suffix, s)
		} else {
			suffix = append(suffix, "."+s)
			domain = append(domain, s)
		}
	}
	domain = uniq(domain)
	suffix = uniq(suffix)
	if len(domain) > 0 {
		injected = append(injected, map[string]any{"domain": toAny(domain), "outbound": "proxy"})
	}
	if len(suffix) > 0 {
		injected = append(injected, map[string]any{"domain_suffix": toAny(suffix), "outbound": "proxy"})
	}
	if len(dr.domainRegex) > 0 {
		injected = append(injected, map[string]any{"domain_regex": toAny(dr.domainRegex), "outbound": "proxy"})
	}

	managed := map[string]struct{}{}
	for _, r := range injected {
		managed[ruleKey(r)] = struct{}{}
	}
	for i := len(rules) - 1; i >= 0; i-- {
		if obj, ok := rules[i].(map[string]any); ok {
			if _, hit := managed[ruleKey(obj)]; hit {
				rules = append(rules[:i], rules[i+1:]...)
			}
		}
	}
	insert := sniffIdx + 1
	if insert > len(rules) {
		insert = len(rules)
	}
	for _, r := range injected {
		rules = append(rules[:insert], append([]any{deepCopy(r)}, rules[insert:]...)...)
		insert++
	}
	route["rules"] = rules
	root["route"] = route
	return len(injected)
}

func ruleKey(rule map[string]any) string {
	keys := make([]string, 0, len(rule))
	for k := range rule {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	var b strings.Builder
	for _, k := range keys {
		b.WriteString(k + "=")
		if arr, ok := asArr(rule[k]); ok {
			s := make([]string, 0, len(arr))
			for _, it := range arr {
				s = append(s, fmt.Sprint(it))
			}
			sort.Strings(s)
			b.WriteString(strings.Join(s, ","))
		} else {
			b.WriteString(fmt.Sprint(rule[k]))
		}
		b.WriteString("|")
	}
	return b.String()
}

func buildGroups(root map[string]any, prev []outboundGroup) []outboundGroup {
	outArr, ok := asArr(root["outbounds"])
	if !ok {
		return []outboundGroup{}
	}
	delay := map[string]int{}
	for _, g := range prev {
		for _, i := range g.Items {
			delay[strings.ToLower(g.Tag)+"::"+strings.ToLower(i.Tag)] = i.UrlTestDelay
		}
	}
	typ := map[string]string{}
	for _, o := range outArr {
		if obj, ok := o.(map[string]any); ok {
			if tag, _ := obj["tag"].(string); tag != "" {
				typ[tag], _ = obj["type"].(string)
			}
		}
	}
	groups := []outboundGroup{}
	for _, o := range outArr {
		obj, ok := o.(map[string]any)
		if !ok {
			continue
		}
		t, _ := obj["type"].(string)
		if !strings.EqualFold(t, "selector") && !strings.EqualFold(t, "urltest") {
			continue
		}
		tag, _ := obj["tag"].(string)
		if tag == "" {
			continue
		}
		items := []outboundItem{}
		for _, it := range readStrings(obj["outbounds"]) {
			items = append(items, outboundItem{Tag: it, Type: typ[it], UrlTestDelay: delay[strings.ToLower(tag)+"::"+strings.ToLower(it)]})
		}
		selected, _ := obj["default"].(string)
		if selected == "" && len(items) > 0 {
			selected = items[0].Tag
		}
		groups = append(groups, outboundGroup{Tag: tag, Type: t, Selected: selected, Selectable: true, Items: items})
	}
	return groups
}

func applySelection(root map[string]any, groups []outboundGroup, sel map[string]string) {
	outArr, ok := asArr(root["outbounds"])
	if !ok {
		return
	}
	idx := map[string]int{}
	for i := range groups {
		idx[strings.ToLower(groups[i].Tag)] = i
	}
	for _, o := range outArr {
		obj, ok := o.(map[string]any)
		if !ok {
			continue
		}
		t, _ := obj["type"].(string)
		if !strings.EqualFold(t, "selector") && !strings.EqualFold(t, "urltest") {
			continue
		}
		tag, _ := obj["tag"].(string)
		if tag == "" {
			continue
		}
		items := readStrings(obj["outbounds"])
		want := sel[tag]
		if want == "" {
			want = sel[strings.ToLower(tag)]
		}
		if want != "" && hasTag(items, want) {
			for _, it := range items {
				if strings.EqualFold(it, want) {
					want = it
					break
				}
			}
			obj["default"] = want
			if i, ok := idx[strings.ToLower(tag)]; ok {
				groups[i].Selected = want
			}
			continue
		}
		if i, ok := idx[strings.ToLower(tag)]; ok {
			if groups[i].Selected != "" {
				obj["default"] = groups[i].Selected
			}
		}
	}
}

func hasTag(items []string, t string) bool {
	for _, i := range items {
		if strings.EqualFold(i, t) {
			return true
		}
	}
	return false
}

func deepCopy(in map[string]any) map[string]any {
	b, _ := json.Marshal(in)
	out := map[string]any{}
	_ = json.Unmarshal(b, &out)
	return out
}

func writeEffective(root map[string]any, path string) ([]byte, string, error) {
	b, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return nil, "", err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, "", err
	}
	if err := os.WriteFile(path, b, 0o644); err != nil {
		return nil, "", err
	}
	sum := sha256.Sum256(b)
	return b, hex.EncodeToString(sum[:]), nil
}

func ensureMap(root map[string]any, k string) map[string]any {
	if m, ok := root[k].(map[string]any); ok {
		return m
	}
	m := map[string]any{}
	root[k] = m
	return m
}

func ensureArr(root map[string]any, k string) []any {
	if a, ok := asArr(root[k]); ok {
		return a
	}
	a := []any{}
	root[k] = a
	return a
}

func asArr(v any) ([]any, bool) {
	if a, ok := v.([]any); ok {
		return a, true
	}
	if a, ok := v.([]interface{}); ok {
		out := make([]any, 0, len(a))
		for _, x := range a {
			out = append(out, x)
		}
		return out, true
	}
	return nil, false
}

func toAny(in []string) []any {
	out := make([]any, 0, len(in))
	for _, s := range in {
		out = append(out, s)
	}
	return out
}

func readStrings(v any) []string {
	if s, ok := v.(string); ok {
		s = strings.TrimSpace(s)
		if s == "" {
			return nil
		}
		return []string{s}
	}
	a, ok := asArr(v)
	if !ok {
		return nil
	}
	out := []string{}
	for _, x := range a {
		if s, ok := x.(string); ok {
			s = strings.TrimSpace(s)
			if s != "" {
				out = append(out, s)
			}
		}
	}
	return out
}
