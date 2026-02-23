//go:build windows

package main

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"hash/fnv"
	"log"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/Microsoft/go-winio"
)

const pipeName = `\\.\pipe\openmesh-win-core`

type request struct {
	Action      string `json:"action"`
	ProfilePath string `json:"profilePath"`
	Group       string `json:"group"`
	Outbound    string `json:"outbound"`
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

type response struct {
	Ok                 bool           `json:"ok"`
	Message            string         `json:"message"`
	CoreRunning        bool           `json:"coreRunning"`
	VpnRunning         bool           `json:"vpnRunning"`
	StartedAtUtc       string         `json:"startedAtUtc"`
	ProfilePath        string         `json:"profilePath"`
	EffectiveConfigPath string        `json:"effectiveConfigPath"`
	LastConfigHash     string         `json:"lastConfigHash"`
	InjectedRuleCount  int            `json:"injectedRuleCount"`
	LastReloadAtUtc    string         `json:"lastReloadAtUtc"`
	LastReloadError    string         `json:"lastReloadError"`
	Group              string         `json:"group"`
	Delays             map[string]int `json:"delays"`
	OutboundGroups     []outboundGroup `json:"outboundGroups"`
	Runtime            runtimeStats   `json:"runtime"`
	P3PreflightCheckedAtUtc string    `json:"p3PreflightCheckedAtUtc"`
	P3Admin            bool           `json:"p3Admin"`
	P3WintunFound      bool           `json:"p3WintunFound"`
	P3WintunPath       string         `json:"p3WintunPath"`
	P3NetworkPrepared  bool           `json:"p3NetworkPrepared"`
	P3NetworkDryRun    bool           `json:"p3NetworkDryRun"`
	P3LastNetworkError string         `json:"p3LastNetworkError"`
	P3LastRollbackAtUtc string        `json:"p3LastRollbackAtUtc"`
	P3AppliedCommands  []string       `json:"p3AppliedCommands"`
}

type layout struct {
	runtimeRoot   string
	profilesRoot  string
	effectiveRoot string
	defaultProfile string
	routingRules  string
	effectiveCfg  string
}

type state struct {
	mu                 sync.Mutex
	startedAt          time.Time
	vpnRunning         bool
	layout             layout
	selectedProfile    string
	effectiveCfg       string
	lastConfigHash     string
	injectedRuleCount  int
	lastReloadAt       time.Time
	lastReloadError    string
	configRoot         map[string]any
	outboundGroups     []outboundGroup
	selectedByGroup    map[string]string
	p3PreflightCheckedAt time.Time
	p3Admin            bool
	p3WintunFound      bool
	p3WintunPath       string
	p3NetworkPrepared  bool
	p3NetworkDryRun    bool
	p3LastNetworkError string
	p3LastRollbackAt   time.Time
	p3AppliedCommands  []string
	p3RollbackCommands []string
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
	root := filepath.Join(filepath.Dir(exe), "runtime")
	s.layout = layout{
		runtimeRoot:   root,
		profilesRoot:  filepath.Join(root, "profiles"),
		effectiveRoot: filepath.Join(root, "effective"),
		defaultProfile: filepath.Join(root, "profiles", "default_profile.json"),
		routingRules:  filepath.Join(root, "routing_rules.json"),
		effectiveCfg:  filepath.Join(root, "effective", "effective_config.json"),
	}
	for _, d := range []string{s.layout.runtimeRoot, s.layout.profilesRoot, s.layout.effectiveRoot} {
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
	case "p3_network_preflight":
		resp = s.p3NetworkPreflight()
	case "p3_network_prepare":
		resp = s.p3NetworkPrepare()
	case "p3_network_rollback":
		resp = s.p3NetworkRollback()
	case "start_vpn":
		resp = s.startVPN()
	case "stop_vpn":
		resp = s.stopVPN()
	case "urltest":
		resp = s.urltest(req.Group)
	case "select_outbound":
		resp = s.selectOutbound(req.Group, req.Outbound)
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

func (s *state) snapshot(ok bool, msg string) response {
	s.mu.Lock()
	defer s.mu.Unlock()
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
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
		Runtime: runtimeStats{
			MemoryMb:      float64(m.Alloc) / 1024.0 / 1024.0,
			ThreadCount:   runtime.NumGoroutine(),
			UptimeSeconds: int64(time.Since(s.startedAt).Seconds()),
		},
		P3PreflightCheckedAtUtc: formatTime(s.p3PreflightCheckedAt),
		P3Admin:            s.p3Admin,
		P3WintunFound:      s.p3WintunFound,
		P3WintunPath:       s.p3WintunPath,
		P3NetworkPrepared:  s.p3NetworkPrepared,
		P3NetworkDryRun:    s.p3NetworkDryRun,
		P3LastNetworkError: s.p3LastNetworkError,
		P3LastRollbackAtUtc: formatTime(s.p3LastRollbackAt),
		P3AppliedCommands:  append([]string{}, s.p3AppliedCommands...),
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
	s.mu.Lock()
	s.vpnRunning = true
	s.mu.Unlock()
	return s.snapshot(true, "vpn started (go core)")
}

func (s *state) stopVPN() response {
	s.mu.Lock()
	s.vpnRunning = false
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
		Runtime: runtimeStats{
			MemoryMb:      float64(m.Alloc) / 1024.0 / 1024.0,
			ThreadCount:   runtime.NumGoroutine(),
			UptimeSeconds: int64(time.Since(s.startedAt).Seconds()),
		},
		P3PreflightCheckedAtUtc: formatTime(s.p3PreflightCheckedAt),
		P3Admin:            s.p3Admin,
		P3WintunFound:      s.p3WintunFound,
		P3WintunPath:       s.p3WintunPath,
		P3NetworkPrepared:  s.p3NetworkPrepared,
		P3NetworkDryRun:    s.p3NetworkDryRun,
		P3LastNetworkError: s.p3LastNetworkError,
		P3LastRollbackAtUtc: formatTime(s.p3LastRollbackAt),
		P3AppliedCommands:  append([]string{}, s.p3AppliedCommands...),
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
