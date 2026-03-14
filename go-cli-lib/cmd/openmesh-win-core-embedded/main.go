package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"crypto/sha256"
	_ "embed"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"net/netip"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"sync"
	"sync/atomic"
	"time"
	"unsafe"

	"github.com/MeshNetProtocol/openmesh-cli/go-cli-lib/market"
	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	sburltest "github.com/sagernet/sing-box/common/urltest"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/bufio"
	sjson "github.com/sagernet/sing/common/json"
	N "github.com/sagernet/sing/common/network"
	"github.com/sagernet/sing/service/filemanager"
)

type request struct {
	Action        string `json:"action"`
	ImportContent string `json:"importContent"`
	ProviderID    string `json:"providerId"`
	ProfilePath   string `json:"profilePath"`
	Group         string `json:"group"`
	Outbound      string `json:"outbound"`
	Payload       any    `json:"payload"`
}

func actionStartVpn(req request) map[string]any {
	if !isProcessElevated() {
		mu.Lock()
		engineError = "admin privileges required for tun interface on windows"
		engineRunning = false
		engineHealthy = false
		enginePID = 0
		vpnOnline = false
		mu.Unlock()
		return snapshot(false, "start_vpn failed: administrator privileges required (run app from elevated shell)")
	}

	mu.Lock()
	if engineRunning {
		vpnOnline = true
		mu.Unlock()
		return snapshot(true, "vpn already running (embedded)")
	}

	// Determine config path
	// 1. If payload has config_path, use it
	// 2. Fallback to effectivePath
	cfgPath := ""
	selectedSnapshot := strings.TrimSpace(selectedPath)
	lastConfigSnapshot := lastConfig
	if payloadMap, ok := req.Payload.(map[string]any); ok {
		if p, ok2 := payloadMap["config_path"].(string); ok2 && p != "" {
			cfgPath = p
		}
	}

	if cfgPath == "" {
		cfgPath = strings.TrimSpace(effectivePath)
	} else {
		// Update selected path if explicit path provided
		selectedPath = cfgPath
		selectedSnapshot = cfgPath
	}

	mu.Unlock()

	if cfgPath == "" || (!fileExists(cfgPath) && strings.TrimSpace(lastConfigSnapshot) == "") {
		if err := ensureEffectiveConfigAvailable(); err != nil {
			return snapshot(false, "start_vpn failed: no config available: "+err.Error())
		}
		// effective config was restored to effectivePath
		cfgPath = effectivePath
	}

	loadPath := cfgPath
	var configData []byte
	var err error
	if strings.TrimSpace(lastConfigSnapshot) != "" &&
		strings.TrimSpace(selectedSnapshot) != "" &&
		strings.EqualFold(filepath.Clean(cfgPath), filepath.Clean(selectedSnapshot)) {
		configData = []byte(lastConfigSnapshot)
		debugLog("actionStartVpn: using in-memory config snapshot for %s", cfgPath)
	} else {
		loadPath = resolveProfileSourcePath(cfgPath)
		configData, err = os.ReadFile(loadPath)
		if err != nil {
			return snapshot(false, "start_vpn failed: read config error: "+err.Error())
		}
	}
	if fixed, fixErr := sanitizeConfigForSingbox(configData); fixErr == nil {
		configData = fixed
	}
	debugLog("actionStartVpn: Config loaded: %s (size=%d)", loadPath, len(configData))
	logConfigDiagnostics(configData)
	if fatal, warnings := validateWindowsConfigCompatibilityBytes(configData); fatal != "" {
		for _, warning := range warnings {
			debugLog("config-validate: warning: %s", warning)
		}
		debugLog("config-validate: fatal: %s", fatal)
		mu.Lock()
		engineError = fatal
		engineRunning = false
		engineHealthy = false
		enginePID = 0
		vpnOnline = false
		mu.Unlock()
		return snapshot(false, "start_vpn failed: incompatible windows config: "+fatal)
	} else {
		for _, warning := range warnings {
			debugLog("config-validate: warning: %s", warning)
		}
	}

	mu.Lock()
	lastConfig = string(configData)
	lastHash = shortHash(configData)
	groupsCacheHash = ""
	if injectedRules <= 0 {
		injectedRules = 3
	}
	if strings.TrimSpace(selectedPath) == "" {
		selectedPath = cfgPath
	}
	_ = os.WriteFile(effectivePath, configData, 0o644)
	mu.Unlock()

	// Start Engine
	tsStart := time.Now()
	service, cancel, err := startEmbeddedBoxServiceWithRetry(configData)
	if err != nil {
		debugLog("actionStartVpn: Engine start failed: %v (took %v)", err, time.Since(tsStart))
		return snapshot(false, "start_vpn failed: engine error: "+err.Error())
	}
	debugLog("actionStartVpn: Engine started successfully (took %v)", time.Since(tsStart))
	go logInterestingDNSResolutions(service)
	go logWindowsDNSDiagnostics(configData)
	go logWindowsNetworkSnapshot()

	mu.Lock()
	boxService = service
	coreCancel = cancel
	engineRunning = true
	engineHealthy = true
	engineError = ""
	vpnOnline = true
	enginePID = os.Getpid()
	mu.Unlock()

	return snapshot(true, "vpn started (embedded)")
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

type recentConnection struct {
	Time        string `json:"time"`
	Network     string `json:"network"`
	Domain      string `json:"domain"`
	Destination string `json:"destination"`
	Protocol    string `json:"protocol"`
	Rule        string `json:"rule"`
	Outbound    string `json:"outbound"`
}

var (
	mu              sync.Mutex
	coreOnline      = true
	vpnOnline       = false
	startedAt       = time.Now()
	runtimeRoot     = ""
	profilesRoot    = ""
	effectivePath   = ""
	selectedPath    = ""
	lastConfig      = ""
	lastHash        = ""
	injectedRules   = 0
	providers       []market.ProviderOffer
	installed       = map[string]bool{}
	installedHash   = map[string]string{}
	wintunPath      = ""
	engineCmd       *exec.Cmd
	enginePID       = 0
	engineRunning   = false
	engineHealthy   = false
	engineError     = ""
	marketCache     = ""
	boxService      *box.Box
	coreCancel      context.CancelFunc
	coreReady       = false
	marketService   *market.Service
	groupsCacheHash = ""
	groupsCache     []any
	endpointByTag   = map[string]string{}
	typeByTag       = map[string]string{}
	recentConnLog   []recentConnection

	// Traffic tracking
	totalUpload      atomic.Int64
	totalDownload    atomic.Int64
	lastUpload       atomic.Int64
	lastDownload     atomic.Int64
	uploadRate       atomic.Int64
	downloadRate     atomic.Int64
	trafficTimerStop chan struct{}

	//go:embed embeds/wintun.dll
	embeddedWintun []byte
)

func initState() {
	mu.Lock()
	defer mu.Unlock()
	if runtimeRoot != "" {
		return
	}
	runtimeRoot = resolveRuntimeRoot()
	profilesRoot = filepath.Join(runtimeRoot, "profiles")
	effectivePath = filepath.Join(runtimeRoot, "effective", "effective_config.json")
	marketCache = filepath.Join(runtimeRoot, "provider_market_cache.json")
	_ = os.MkdirAll(profilesRoot, 0o755)
	_ = os.MkdirAll(filepath.Dir(effectivePath), 0o755)
	_ = os.MkdirAll(filepath.Join(runtimeRoot, "logs"), 0o755)

	marketService = market.NewService(runtimeRoot)

	restoreInstalledProvidersFromDisk(profilesRoot)
	restoreEffectiveConfigState(effectivePath)
	mu.Unlock()
	// findWintunPath and ensureWintunOnPath must be called WITHOUT mu held:
	// findWintunPath's "Last Resort" branch calls debugLog, which acquires mu.
	// Calling findWintunPath while mu is held would cause a deadlock on that path.
	snapshotWintun := findWintunPath()
	if snapshotWintun != "" {
		ensureWintunOnPath(snapshotWintun)
		debugLog("initState: wintun resolved at %s", snapshotWintun)
	} else {
		debugLog("initState: WARN wintun.dll not found anywhere")
	}
	mu.Lock()
	wintunPath = snapshotWintun
}

func getMemMb() float64 {
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	return float64(m.Alloc) / 1024 / 1024
}

func snapshot(ok bool, message string) map[string]any {
	mu.Lock()
	defer mu.Unlock()
	outProviders := make([]market.ProviderOffer, 0, len(providers))
	for _, p := range providers {
		cp := p
		if installed[cp.ID] {
			cp.InstalledPackageHash = installedHash[cp.ID]
			cp.UpgradeAvailable = cp.PackageHash != "" && !strings.EqualFold(cp.PackageHash, cp.InstalledPackageHash)
		} else {
			cp.InstalledPackageHash = ""
			cp.UpgradeAvailable = false
		}
		outProviders = append(outProviders, cp)
	}
	sort.Slice(outProviders, func(i, j int) bool {
		return strings.ToLower(outProviders[i].ID) < strings.ToLower(outProviders[j].ID)
	})
	installedIDs := make([]string, 0, len(installed))
	for id, v := range installed {
		if v {
			installedIDs = append(installedIDs, id)
		}
	}
	sort.Strings(installedIDs)
	outGroups := getOutboundGroupsLocked()
	return map[string]any{
		"ok":                   ok,
		"message":              message,
		"coreRunning":          coreOnline,
		"vpnRunning":           vpnOnline,
		"profilePath":          selectedPath,
		"effectiveConfigPath":  effectivePath,
		"lastConfigHash":       lastHash,
		"injectedRuleCount":    injectedRules,
		"providers":            outProviders,
		"installedProviderIds": installedIDs,
		"outboundGroups":       outGroups,
		"connections":          []any{},
		"runtime": runtimeStats{
			TotalUploadBytes:        totalUpload.Load(),
			TotalDownloadBytes:      totalDownload.Load(),
			UploadRateBytesPerSec:   uploadRate.Load(),
			DownloadRateBytesPerSec: downloadRate.Load(),
			MemoryMb:                getMemMb(),
			ThreadCount:             runtime.NumGoroutine(),
			UptimeSeconds:           int64(time.Since(startedAt).Seconds()),
			ConnectionCount:         0,
		},
		"p3EngineMode":      "embedded",
		"p3WintunFound":     strings.TrimSpace(wintunPath) != "",
		"p3WintunPath":      wintunPath,
		"p3SingboxFound":    true,
		"p3SingboxPath":     "embedded",
		"p3NetworkPrepared": vpnOnline,
		"p3EngineRunning":   engineRunning,
		"p3EngineHealthy":   engineHealthy,
		"p3EnginePid":       enginePID,
		"p3EngineLastError": engineError,
		"routeABMode":       strings.ToLower(strings.TrimSpace(os.Getenv("OPENMESH_WIN_ROUTE_MODE"))),
		"coreVersion":       "v0.0.2-fallback",
	}
}

func getOutboundGroupsLocked() []any {
	// When VPN is running, always derive groups from the live sing-box instance.
	// This keeps selection state and group membership accurate even if config defaults are stale.
	if vpnOnline && boxService != nil {
		return buildOutboundGroupsFromServiceLocked(boxService)
	}

	currentHash := strings.TrimSpace(lastHash)
	if currentHash == "" {
		if strings.TrimSpace(lastConfig) == "" {
			groupsCacheHash = ""
			groupsCache = []any{}
			endpointByTag = map[string]string{}
			typeByTag = map[string]string{}
			return groupsCache
		}
		currentHash = shortHash([]byte(lastConfig))
		lastHash = currentHash
	}

	if groupsCacheHash == currentHash && groupsCache != nil {
		return groupsCache
	}

	rebuildOutboundCachesLocked(currentHash)
	return groupsCache
}

func buildOutboundGroupsFromServiceLocked(serviceNow *box.Box) []any {
	if serviceNow == nil {
		return []any{}
	}

	outbounds := serviceNow.Outbound().Outbounds()
	groups := make([]map[string]any, 0, 8)
	for _, ob := range outbounds {
		if ob == nil {
			continue
		}
		groupTag := strings.TrimSpace(ob.Tag())
		if groupTag == "" {
			continue
		}
		typ := strings.ToLower(strings.TrimSpace(ob.Type()))
		if typ != "selector" && typ != "urltest" && typ != "url_test" {
			continue
		}
		group, isGroup := ob.(adapter.OutboundGroup)
		if !isGroup {
			continue
		}

		items := make([]any, 0, 8)
		for _, tag := range group.All() {
			tag = strings.TrimSpace(tag)
			if tag == "" {
				continue
			}
			itemType := ""
			if itemOutbound, loaded := serviceNow.Outbound().Outbound(tag); loaded && itemOutbound != nil {
				itemType = strings.TrimSpace(itemOutbound.Type())
			}
			items = append(items, map[string]any{
				"tag":          tag,
				"type":         itemType,
				"urlTestDelay": 0,
			})
		}

		selected := strings.TrimSpace(group.Now())
		if selected == "" && len(items) > 0 {
			if first, ok := items[0].(map[string]any); ok {
				if s, ok := first["tag"].(string); ok {
					selected = strings.TrimSpace(s)
				}
			}
		}

		groups = append(groups, map[string]any{
			"tag":        groupTag,
			"type":       typ,
			"selected":   selected,
			"selectable": typ == "selector",
			"items":      items,
		})
	}

	sort.Slice(groups, func(i, j int) bool {
		return strings.ToLower(getString(groups[i], "tag")) < strings.ToLower(getString(groups[j], "tag"))
	})

	out := make([]any, 0, len(groups))
	for _, g := range groups {
		out = append(out, g)
	}
	return out
}

func rebuildOutboundCachesLocked(hash string) {
	groupsCacheHash = hash
	groupsCache = []any{}
	endpointByTag = map[string]string{}
	typeByTag = map[string]string{}

	raw := strings.TrimSpace(lastConfig)
	if raw == "" {
		return
	}

	var root map[string]any
	if err := json.Unmarshal([]byte(raw), &root); err != nil {
		return
	}

	outboundsAny, ok := root["outbounds"].([]any)
	if !ok {
		return
	}

	for _, node := range outboundsAny {
		ob, ok := asMap(node)
		if !ok {
			continue
		}
		tag := strings.TrimSpace(getString(ob, "tag"))
		typ := strings.TrimSpace(getString(ob, "type"))
		if tag != "" && typ != "" {
			typeByTag[tag] = typ
		}
		if tag != "" {
			if addr := resolveOutboundEndpoint(ob); addr != "" {
				endpointByTag[tag] = addr
			}
		}
	}

	for _, node := range outboundsAny {
		ob, ok := asMap(node)
		if !ok {
			continue
		}

		typ := strings.ToLower(strings.TrimSpace(getString(ob, "type")))
		if typ != "selector" && typ != "urltest" && typ != "url_test" {
			continue
		}

		groupTag := strings.TrimSpace(getString(ob, "tag"))
		if groupTag == "" {
			continue
		}

		var items []any
		if outs, ok := ob["outbounds"].([]any); ok {
			for _, x := range outs {
				s, _ := x.(string)
				s = strings.TrimSpace(s)
				if s == "" {
					continue
				}
				itemType := typeByTag[s]
				items = append(items, map[string]any{
					"tag":          s,
					"type":         itemType,
					"urlTestDelay": 0,
				})
			}
		}

		selected := strings.TrimSpace(getString(ob, "default"))
		if selected == "" && len(items) > 0 {
			if first, ok := items[0].(map[string]any); ok {
				if s, ok := first["tag"].(string); ok {
					selected = s
				}
			}
		}

		groupsCache = append(groupsCache, map[string]any{
			"tag":        groupTag,
			"type":       typ,
			"selected":   selected,
			"selectable": typ == "selector",
			"items":      items,
		})
	}
}

func getString(m map[string]any, key string) string {
	if v, ok := m[key]; ok {
		if s, ok := v.(string); ok {
			return s
		}
	}
	return ""
}

func resolveOutboundEndpoint(ob map[string]any) string {
	host := ""
	for _, k := range []string{"server", "server_address", "address", "host"} {
		if s := strings.TrimSpace(getString(ob, k)); s != "" {
			host = s
			break
		}
	}
	if host == "" {
	}

	port := 0
	if v, ok := ob["server_port"]; ok {
		port = parseInt(v)
	} else if v, ok := ob["port"]; ok {
		port = parseInt(v)
	}

	if port > 0 && port <= 65535 {
		return fmt.Sprintf("%s:%d", host, port)
	}
	return host
}

func parseInt(v any) int {
	switch t := v.(type) {
	case float64:
		return int(t)
	case float32:
		return int(t)
	case int:
		return t
	case int64:
		return int(t)
	case json.Number:
		if i, err := t.Int64(); err == nil {
			return int(i)
		}
	case string:
		if i, err := strconv.Atoi(strings.TrimSpace(t)); err == nil {
			return i
		}
	}
	return 0
}

func encodePayload(payload map[string]any) *C.char {
	data, _ := json.Marshal(payload)
	return C.CString(string(data))
}

func actionURLTest(req request) map[string]any {
	mu.Lock()
	running := vpnOnline
	serviceNow := boxService
	_ = getOutboundGroupsLocked()
	groups := make([]any, 0, len(groupsCache))
	for _, g := range groupsCache {
		groups = append(groups, g)
	}
	mu.Unlock()

	if !running || serviceNow == nil {
		return snapshot(false, "urltest requires vpn running")
	}

	groupTag := strings.TrimSpace(req.Group)
	if groupTag == "" {
		groupTag = pickPreferredGroupTag(groups)
	}
	if groupTag == "" {
		return snapshot(false, "urltest group not found or empty")
	}

	abstractGroup, loaded := serviceNow.Outbound().Outbound(groupTag)
	if !loaded {
		return snapshot(false, "urltest group not found or empty: "+groupTag)
	}

	outboundGroup, isOutboundGroup := abstractGroup.(adapter.OutboundGroup)
	if !isOutboundGroup {
		return snapshot(false, "outbound is not a group: "+groupTag)
	}

	delays := make(map[string]int)
	urlTestCtx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	tags := outboundGroup.All()
	if urlTestGroup, isURLTestGroup := abstractGroup.(adapter.URLTestGroup); isURLTestGroup && len(tags) > 1 {
		// Use sing-box URLTestGroup first (parallelized internally, may be rate-limited by interval).
		result, err := urlTestGroup.URLTest(urlTestCtx)
		if err == nil {
			for tag, d := range result {
				delays[tag] = int(d)
			}
			debugLog("actionURLTest: group=%q used URLTestGroup result=%s", groupTag, formatDelayMap(delays))
		} else {
			debugLog("actionURLTest: group=%q URLTestGroup failed: %v", groupTag, err)
		}
	}

	if len(delays) == 0 {
		// Fallback: do an actual URLTest per outbound, always returning results on demand.
		delays = directURLTestDelays(urlTestCtx, serviceNow, tags)
		debugLog("actionURLTest: group=%q used direct URL tests result=%s", groupTag, formatDelayMap(delays))
	}

	if len(delays) == 0 {
		debugLog("actionURLTest: group=%q finished with no delay updates", groupTag)
		return snapshot(false, "urltest finished with no delay updates")
	}

	outGroups := applyDelaysToGroups(groups, groupTag, delays)

	resp := snapshot(true, "urltest completed (embedded)")
	resp["group"] = groupTag
	resp["delays"] = delays
	resp["outboundGroups"] = outGroups
	return resp
}

func directURLTestDelays(ctx context.Context, serviceNow *box.Box, tags []string) map[string]int {
	if serviceNow == nil || len(tags) == 0 {
		return map[string]int{}
	}
	// Workaround: some sing-box urltest group flows may not yield updates with a single outbound.
	// To align with MeshFluxMac behavior, we "pad" a fake outbound (e.g. direct) so the test set
	// has at least 2 candidates, but we only return delays for real tags.
	realTags := make(map[string]bool, len(tags))
	for _, t := range tags {
		t = strings.TrimSpace(t)
		if t != "" {
			realTags[t] = true
		}
	}
	if len(realTags) == 1 {
		if _, loaded := serviceNow.Outbound().Outbound("direct"); loaded {
			tags = append(tags, "direct")
		}
	}
	delays := make(map[string]int)
	var delaysMu sync.Mutex
	sem := make(chan struct{}, 10)
	var wg sync.WaitGroup

	for _, tag := range tags {
		tag = strings.TrimSpace(tag)
		if tag == "" {
			continue
		}
		wg.Add(1)
		go func(tag string) {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
			case <-ctx.Done():
				return
			}
			defer func() { <-sem }()

			itemOutbound, loaded := serviceNow.Outbound().Outbound(tag)
			if !loaded || itemOutbound == nil {
				debugLog("directURLTestDelays: outbound %q not found", tag)
				return
			}
			if _, isGroup := itemOutbound.(adapter.OutboundGroup); isGroup {
				debugLog("directURLTestDelays: outbound %q skipped because it is a group", tag)
				return
			}
			t, err := sburltest.URLTest(ctx, "", itemOutbound)
			if err != nil {
				debugLog("directURLTestDelays: outbound %q failed: %v", tag, err)
				return
			}
			delaysMu.Lock()
			if realTags[tag] {
				delays[tag] = int(t)
			}
			delaysMu.Unlock()
			debugLog("directURLTestDelays: outbound %q delay=%dms", tag, int(t))
		}(tag)
	}
	wg.Wait()
	return delays
}

func actionSetProfile(req request) map[string]any {
	profilePath := strings.TrimSpace(req.ProfilePath)
	if profilePath == "" {
		return snapshot(false, "profile path is empty")
	}

	if !filepath.IsAbs(profilePath) {
		mu.Lock()
		base := strings.TrimSpace(runtimeRoot)
		mu.Unlock()
		if base != "" {
			profilePath = filepath.Join(base, profilePath)
		}
	}

	sourcePath := resolveProfileSourcePath(profilePath)
	if !strings.EqualFold(filepath.Clean(sourcePath), filepath.Clean(profilePath)) {
		debugLog("actionSetProfile: using source config %s for profile %s", sourcePath, profilePath)
	}

	raw, err := os.ReadFile(sourcePath)
	if err != nil {
		return snapshot(false, "profile not found: "+sourcePath)
	}

	fixed, err := sanitizeConfigForSingbox(raw)
	if err == nil {
		raw = fixed
	}

	mu.Lock()
	selectedPath = profilePath
	lastConfig = string(raw)
	lastHash = shortHash(raw)
	groupsCacheHash = ""
	if injectedRules <= 0 {
		injectedRules = 3
	}
	running := engineRunning
	_ = os.WriteFile(effectivePath, raw, 0o644)
	mu.Unlock()

	if running {
		stopResp := actionStopVpn()
		if ok, _ := stopResp["ok"].(bool); !ok {
			return snapshot(false, "profile set but failed to stop running vpn")
		}
		startResp := actionStartVpn(request{Payload: map[string]any{"config_path": profilePath}})
		if ok, _ := startResp["ok"].(bool); !ok {
			msg, _ := startResp["message"].(string)
			return snapshot(false, "profile set but restart failed: "+msg)
		}
	}

	return snapshot(true, "profile set: "+profilePath)
}

func actionSelectOutbound(req request) map[string]any {
	groupTag := strings.TrimSpace(req.Group)
	outboundTag := strings.TrimSpace(req.Outbound)
	if groupTag == "" || outboundTag == "" {
		return snapshot(false, "group/outbound is empty")
	}

	mu.Lock()
	running := vpnOnline
	serviceNow := boxService
	mu.Unlock()

	// Match macOS behavior: only switch live inside the running service.
	if running && serviceNow != nil {
		abstractGroup, loaded := serviceNow.Outbound().Outbound(groupTag)
		if !loaded || abstractGroup == nil {
			return snapshot(false, "group not found: "+groupTag)
		}
		if _, isGroup := abstractGroup.(adapter.OutboundGroup); !isGroup {
			return snapshot(false, "outbound is not a group: "+groupTag)
		}
		selector, ok := abstractGroup.(interface{ SelectOutbound(string) bool })
		if !ok {
			return snapshot(false, "group not selectable: "+groupTag)
		}
		if !selector.SelectOutbound(outboundTag) {
			return snapshot(false, "outbound not in group: "+outboundTag)
		}
		selectedNow := outboundTag
		if group, ok := abstractGroup.(adapter.OutboundGroup); ok {
			if now := strings.TrimSpace(group.Now()); now != "" {
				selectedNow = now
			}
		}
		debugLog("actionSelectOutbound: live group=%q requested=%q active=%q", groupTag, outboundTag, selectedNow)
		return snapshot(true, fmt.Sprintf("selected %s in %s", outboundTag, groupTag))
	}

	return snapshot(false, "vpn not connected")
}

func formatDelayMap(delays map[string]int) string {
	if len(delays) == 0 {
		return "{}"
	}
	keys := make([]string, 0, len(delays))
	for k := range delays {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		parts = append(parts, fmt.Sprintf("%s=%dms", k, delays[k]))
	}
	return "{" + strings.Join(parts, ", ") + "}"
}

func resolveProfileSourcePath(profilePath string) string {
	profilePath = strings.TrimSpace(profilePath)
	if profilePath == "" {
		return ""
	}

	if strings.EqualFold(filepath.Base(profilePath), "config.json") {
		fullConfigPath := filepath.Join(filepath.Dir(profilePath), "config_full.json")
		if fileExists(fullConfigPath) {
			return fullConfigPath
		}
	}

	return profilePath
}

func pickPreferredGroupTag(groups []any) string {
	for _, preferred := range []string{"primary-selector", "proxy", "auto", "select", "main", "node"} {
		for _, g := range groups {
			m, ok := g.(map[string]any)
			if !ok {
				continue
			}
			tag := strings.TrimSpace(getString(m, "tag"))
			if strings.EqualFold(tag, preferred) {
				return tag
			}
		}
	}
	for _, g := range groups {
		m, ok := g.(map[string]any)
		if !ok {
			continue
		}
		tag := strings.TrimSpace(getString(m, "tag"))
		if tag != "" {
			return tag
		}
	}
	return ""
}

func extractGroupItemTags(groups []any, groupTag string) []string {
	groupTag = strings.TrimSpace(groupTag)
	if groupTag == "" {
		return nil
	}
	for _, g := range groups {
		m, ok := g.(map[string]any)
		if !ok {
			continue
		}
		tag := strings.TrimSpace(getString(m, "tag"))
		if !strings.EqualFold(tag, groupTag) {
			continue
		}
		items, _ := m["items"].([]any)
		out := make([]string, 0, len(items))
		for _, it := range items {
			im, ok := it.(map[string]any)
			if !ok {
				continue
			}
			t := strings.TrimSpace(getString(im, "tag"))
			if t != "" {
				out = append(out, t)
			}
		}
		return out
	}
	return nil
}

func applyDelaysToGroups(groups []any, groupTag string, delays map[string]int) []any {
	out := make([]any, 0, len(groups))
	for _, g := range groups {
		m, ok := g.(map[string]any)
		if !ok {
			out = append(out, g)
			continue
		}
		copyG := map[string]any{}
		for k, v := range m {
			copyG[k] = v
		}
		if strings.EqualFold(strings.TrimSpace(getString(m, "tag")), groupTag) {
			items, _ := m["items"].([]any)
			newItems := make([]any, 0, len(items))
			for _, it := range items {
				im, ok := it.(map[string]any)
				if !ok {
					newItems = append(newItems, it)
					continue
				}
				copyI := map[string]any{}
				for k, v := range im {
					copyI[k] = v
				}
				t := strings.TrimSpace(getString(im, "tag"))
				if t != "" {
					if d, ok := delays[t]; ok {
						copyI["urlTestDelay"] = d
					}
				}
				newItems = append(newItems, copyI)
			}
			copyG["items"] = newItems
		}
		out = append(out, copyG)
	}
	return out
}

func runTCPDelayTests(tags []string, endpoints map[string]string, concurrency int, timeout time.Duration) map[string]int {
	if concurrency <= 0 {
		concurrency = 4
	}
	sem := make(chan struct{}, concurrency)
	results := make(chan struct {
		tag   string
		delay int
	}, len(tags))

	for _, tag := range tags {
		tag := tag
		addr := strings.TrimSpace(endpoints[tag])
		if addr == "" {
			results <- struct {
				tag   string
				delay int
			}{tag: tag, delay: 0}
			continue
		}
		sem <- struct{}{}
		go func() {
			defer func() { <-sem }()
			results <- struct {
				tag   string
				delay int
			}{tag: tag, delay: tcpConnectDelay(addr, timeout)}
		}()
	}

	for i := 0; i < cap(sem); i++ {
		sem <- struct{}{}
	}
	for i := 0; i < cap(sem); i++ {
		<-sem
	}
	close(results)

	delays := map[string]int{}
	for r := range results {
		delays[r.tag] = r.delay
	}
	return delays
}

func tcpConnectDelay(addr string, timeout time.Duration) int {
	addr = strings.TrimSpace(addr)
	if addr == "" {
		return 0
	}
	if _, _, err := net.SplitHostPort(addr); err != nil {
		return 0
	}
	start := time.Now()
	conn, err := net.DialTimeout("tcp", addr, timeout)
	if err != nil {
		return 0
	}
	_ = conn.Close()
	ms := int(time.Since(start).Milliseconds())
	if ms < 1 {
		ms = 1
	}
	if ms > 5000 {
		ms = 5000
	}
	return ms
}

func actionProviderMarketList() map[string]any {
	hashes := map[string]string{}
	mu.Lock()
	for k, v := range installedHash {
		hashes[k] = v
	}
	mu.Unlock()

	offers, err := marketService.FetchProviders(hashes)
	if err == nil && len(offers) > 0 {
		mu.Lock()
		providers = mergeProviderOffers(providers, offers)
		mu.Unlock()
		return snapshot(true, "provider market listed (embedded)")
	}

	return snapshot(true, "provider market listed (embedded, error/empty: "+fmt.Sprintf("%v", err)+")")
}

func actionImportInstall(importContent string) map[string]any {
	importContent = strings.TrimSpace(importContent)
	if importContent == "" {
		return snapshot(false, "import content is empty")
	}
	providerID, providerName, packageHash, configData, err := parseImportedInstallPayload(importContent)
	if err != nil {
		return snapshot(false, "invalid import payload: "+err.Error())
	}
	configData, err = sanitizeConfigForSingbox(configData)
	if err != nil {
		return snapshot(false, "invalid import config: "+err.Error())
	}
	mu.Lock()
	var opErr error
	var providerIDResult = providerID
	if err := os.MkdirAll(profilesRoot, 0o755); err != nil {
		opErr = fmt.Errorf("create profiles dir failed: %w", err)
	} else {
		safe := sanitizeProviderID(providerID)
		profilePath := filepath.Join(profilesRoot, "provider-"+safe+".json")
		if err := os.WriteFile(profilePath, configData, 0o644); err != nil {
			opErr = fmt.Errorf("write provider profile failed: %w", err)
		} else {
			selectedPath = profilePath
			lastConfig = string(configData)
			lastHash = shortHash(configData)
			injectedRules = 3
			installed[providerID] = true
			installedHash[providerID] = packageHash
			offer := market.ProviderOffer{
				ID:                   providerID,
				Name:                 providerName,
				Region:               "imported",
				PricePerGB:           0,
				PackageHash:          packageHash,
				InstalledPackageHash: packageHash,
				Description:          "Imported provider profile.",
			}
			upsertProviderOffer(offer)
			_ = os.WriteFile(effectivePath, configData, 0o644)
		}
	}
	mu.Unlock()

	if opErr != nil {
		return snapshot(false, opErr.Error())
	}
	return snapshot(true, "provider imported and installed: "+providerIDResult)
}

func actionProviderActivate(providerID string) map[string]any {
	providerID = strings.TrimSpace(providerID)
	if providerID == "" {
		return snapshot(false, "provider id is empty")
	}

	mu.Lock()
	safe := sanitizeProviderID(providerID)
	profilePath := filepath.Join(profilesRoot, "provider-"+safe+".json")
	mu.Unlock()

	raw, err := os.ReadFile(profilePath)
	if err != nil {
		return snapshot(false, "provider profile not found: "+providerID)
	}

	mu.Lock()
	selectedPath = profilePath
	lastConfig = string(raw)
	lastHash = shortHash(raw)
	if injectedRules <= 0 {
		injectedRules = 3
	}
	installed[providerID] = true
	if installedHash[providerID] == "" {
		installedHash[providerID] = "installed"
	}
	mu.Unlock()
	_ = os.WriteFile(effectivePath, raw, 0o644)
	return snapshot(true, "provider activated: "+providerID)
}

func actionProviderInstall(providerID string) map[string]any {
	providerID = strings.TrimSpace(providerID)
	if providerID == "" {
		return snapshot(false, "provider id is empty")
	}

	err := marketService.InstallProvider(providerID, func(msg string) {})
	if err != nil {
		return snapshot(false, "provider install failed: "+err.Error())
	}

	mu.Lock()
	var offer *market.ProviderOffer
	for i := range providers {
		if strings.EqualFold(providers[i].ID, providerID) {
			offer = &providers[i]
			break
		}
	}
	installed[providerID] = true
	if offer != nil {
		installedHash[providerID] = offer.PackageHash
	} else {
		installedHash[providerID] = "installed"
	}
	mu.Unlock()
	return snapshot(true, "provider installed: "+providerID)
}

func actionProviderUninstall(providerID string) map[string]any {
	providerID = strings.TrimSpace(providerID)
	if providerID == "" {
		return snapshot(false, "provider id is empty")
	}

	mu.Lock()
	safe := sanitizeProviderID(providerID)
	profilePath := filepath.Join(profilesRoot, "provider-"+safe+".json")
	wasSelected := strings.EqualFold(profilePath, selectedPath)
	delete(installed, providerID)
	delete(installedHash, providerID)
	mu.Unlock()

	_ = os.Remove(profilePath)
	if wasSelected {
		mu.Lock()
		selectedPath = ""
		lastConfig = ""
		lastHash = ""
		injectedRules = 0
		mu.Unlock()
	}
	return snapshot(true, "provider uninstalled: "+providerID)
}

func actionProviderUpgrade(providerID string) map[string]any {
	providerID = strings.TrimSpace(providerID)
	if providerID == "" {
		return snapshot(false, "provider id is empty")
	}
	mu.Lock()
	if !installed[providerID] {
		mu.Unlock()
		return snapshot(false, "provider not installed: "+providerID)
	}
	upgraded := false
	for _, p := range providers {
		if strings.EqualFold(p.ID, providerID) {
			installedHash[providerID] = p.PackageHash
			upgraded = true
			break
		}
	}
	mu.Unlock()
	if upgraded {
		return snapshot(true, "provider upgraded: "+providerID)
	}
	return snapshot(false, "provider not found in market: "+providerID)
}

func actionStartVpnLegacy() map[string]any {
	// Replaced by actionStartVpn(req)
	return nil
}

func actionStopVpn() map[string]any {
	stopTrafficMonitoring()
	debugLog("actionStopVpn: Entering")
	mu.Lock()
	service := boxService
	cancel := coreCancel
	if service == nil && !engineRunning {
		debugLog("actionStopVpn: Already stopped")
		vpnOnline = false
		engineHealthy = false
		mu.Unlock()
		return snapshot(true, "vpn stopped (embedded, no service running)")
	}

	// Mark as stopping
	engineRunning = false
	mu.Unlock()
	debugLog("actionStopVpn: Marked as stopping, lock released")

	// Release resources outside lock
	if cancel != nil {
		cancel()
	}

	debugLog("actionStopVpn: Closing service...")
	// Close service with timeout safety
	done := make(chan struct{})
	go func() {
		if service != nil {
			_ = service.Close()
		}
		close(done)
	}()

	select {
	case <-done:
		debugLog("actionStopVpn: Service closed gracefully")
	case <-time.After(2 * time.Second):
		debugLog("actionStopVpn: Service close timed out")
	}

	mu.Lock()
	boxService = nil
	coreCancel = nil
	vpnOnline = false
	engineRunning = false
	engineHealthy = false
	enginePID = 0
	mu.Unlock()
	debugLog("actionStopVpn: State updated, exiting")

	totalUpload.Store(0)
	totalDownload.Store(0)
	lastUpload.Store(0)
	lastDownload.Store(0)
	uploadRate.Store(0)
	downloadRate.Store(0)

	return snapshot(true, "vpn stopped (embedded)")
}

func startTrafficMonitoring(instance *box.Box) {
	stopTrafficMonitoring()
	mu.Lock()
	trafficTimerStop = make(chan struct{})
	stopCh := trafficTimerStop
	mu.Unlock()

	go func() {
		ticker := time.NewTicker(time.Second)
		defer ticker.Stop()
		for {
			select {
			case <-stopCh:
				return
			case <-ticker.C:
				up := totalUpload.Load()
				down := totalDownload.Load()

				prevUp := lastUpload.Swap(up)
				prevDown := lastDownload.Swap(down)

				if prevUp > 0 {
					uploadRate.Store(up - prevUp)
				}
				if prevDown > 0 {
					downloadRate.Store(down - prevDown)
				}
			}
		}
	}()
}

type trafficTracker struct{}

func (t *trafficTracker) RoutedConnection(ctx context.Context, conn net.Conn, metadata adapter.InboundContext, matchedRule adapter.Rule, matchOutbound adapter.Outbound) net.Conn {
	recordRecentConnection("tcp", metadata, matchedRule, matchOutbound)
	return bufio.NewCounterConn(conn, []N.CountFunc{func(n int64) {
		totalUpload.Add(n)
	}}, []N.CountFunc{func(n int64) {
		totalDownload.Add(n)
	}})
}

func (t *trafficTracker) RoutedPacketConnection(ctx context.Context, conn N.PacketConn, metadata adapter.InboundContext, matchedRule adapter.Rule, matchOutbound adapter.Outbound) N.PacketConn {
	recordRecentConnection("udp", metadata, matchedRule, matchOutbound)
	return bufio.NewCounterPacketConn(conn, []N.CountFunc{func(n int64) {
		totalUpload.Add(n)
	}}, []N.CountFunc{func(n int64) {
		totalDownload.Add(n)
	}})
}

func recordRecentConnection(network string, metadata adapter.InboundContext, matchedRule adapter.Rule, matchOutbound adapter.Outbound) {
	domain := strings.TrimSpace(metadata.Domain)
	destination := strings.TrimSpace(metadata.Destination.String())
	if domain == "" && destination == "" {
		return
	}

	ruleText := ""
	if matchedRule != nil {
		ruleText = strings.TrimSpace(matchedRule.String())
	}

	outboundTag := ""
	if matchOutbound != nil {
		outboundTag = strings.TrimSpace(matchOutbound.Tag())
	}

	entry := recentConnection{
		Time:        time.Now().Format("2006-01-02 15:04:05.000"),
		Network:     strings.TrimSpace(network),
		Domain:      domain,
		Destination: destination,
		Protocol:    strings.TrimSpace(metadata.Protocol),
		Rule:        ruleText,
		Outbound:    outboundTag,
	}

	mu.Lock()
	recentConnLog = append(recentConnLog, entry)
	if len(recentConnLog) > 200 {
		recentConnLog = append([]recentConnection(nil), recentConnLog[len(recentConnLog)-200:]...)
	}
	mu.Unlock()

	if isInterestingTraffic(domain, destination) {
		debugLog("traffic-diag: net=%s domain=%q dest=%q proto=%q rule=%q outbound=%q",
			entry.Network, entry.Domain, entry.Destination, entry.Protocol, entry.Rule, entry.Outbound)
	}
	if isInterestingDNSPath(entry) {
		debugLog("dns-path-diag: net=%s domain=%q dest=%q proto=%q rule=%q outbound=%q",
			entry.Network, entry.Domain, entry.Destination, entry.Protocol, entry.Rule, entry.Outbound)
	}
}

func isInterestingTraffic(domain string, destination string) bool {
	text := strings.ToLower(strings.TrimSpace(domain))
	if text == "" {
		text = strings.ToLower(strings.TrimSpace(destination))
	}
	if text == "" {
		return false
	}
	for _, token := range []string{
		"x.com",
		"twitter.com",
		"t.co",
		"twimg.com",
		"youtube.com",
		"googlevideo.com",
		"ytimg.com",
		"googleapis.com",
		"gstatic.com",
		"google.com",
		"gemini.google.com",
		"chatgpt.com",
		"openai.com",
		"oaistatic.com",
	} {
		if strings.Contains(text, token) {
			return true
		}
	}
	return false
}

func isInterestingDNSPath(entry recentConnection) bool {
	if strings.EqualFold(strings.TrimSpace(entry.Protocol), "dns") {
		return true
	}
	dest := strings.TrimSpace(entry.Destination)
	if dest == "" {
		return false
	}
	_, port, err := net.SplitHostPort(dest)
	if err != nil {
		return false
	}
	return port == "53"
}

func logInterestingDNSResolutions(serviceNow *box.Box) {
	if serviceNow == nil {
		return
	}
	resolver := serviceNow.DNS()
	if resolver == nil {
		debugLog("dns-diag: resolver unavailable")
		return
	}

	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	for _, domain := range []string{
		"x.com",
		"api.x.com",
		"pbs.twimg.com",
		"video.twimg.com",
		"gemini.google.com",
		"www.youtube.com",
		"i.ytimg.com",
		"rr3---sn-3pm76nee.googlevideo.com",
		"chatgpt.com",
		"ab.chatgpt.com",
		"chat.openai.com",
		"www.google.com",
	} {
		addresses, err := resolver.Lookup(ctx, domain, adapter.DNSQueryOptions{})
		if err != nil {
			debugLog("dns-diag: lookup domain=%q failed: %v", domain, err)
			continue
		}
		addrText := make([]string, 0, len(addresses))
		for _, addr := range addresses {
			addrText = append(addrText, addr.String())
		}
		debugLog("dns-diag: lookup domain=%q answers=%s", domain, strings.Join(addrText, ","))
	}
}

func logWindowsDNSDiagnostics(configData []byte) {
	localServers := extractPlainDNSServers(configData)
	tunServers := extractTunDNSServers(configData)
	if len(localServers) == 0 {
		debugLog("local-dns-diag: no plain DNS server found in config")
	} else {
		debugLog("local-dns-diag: configured plain DNS servers=%s", strings.Join(localServers, ","))
	}
	if len(tunServers) == 0 {
		debugLog("tun-dns-diag: no tun DNS server inferred from config")
	} else {
		debugLog("tun-dns-diag: inferred tun DNS servers=%s", strings.Join(tunServers, ","))
	}

	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()

	for _, domain := range []string{
		"x.com",
		"gemini.google.com",
		"www.youtube.com",
		"chatgpt.com",
		"chat.openai.com",
		"pbs.twimg.com",
		"www.google.com",
	} {
		logResolverLookup(ctx, "os-dns-diag", nil, domain)
		for _, server := range tunServers {
			logResolverLookup(ctx, "tun-dns-diag", []string{server}, domain)
		}
		for _, server := range localServers {
			logResolverLookup(ctx, "local-dns-diag", []string{server}, domain)
		}
	}
}

func extractPlainDNSServers(configData []byte) []string {
	var root map[string]any
	if err := json.Unmarshal(configData, &root); err != nil {
		return nil
	}
	dnsMap, ok := root["dns"].(map[string]any)
	if !ok {
		return nil
	}
	serversAny, ok := dnsMap["servers"].([]any)
	if !ok {
		return nil
	}
	var servers []string
	for _, item := range serversAny {
		serverMap, ok := item.(map[string]any)
		if !ok {
			continue
		}
		address := strings.TrimSpace(getString(serverMap, "address"))
		if address == "" {
			address = strings.TrimSpace(getString(serverMap, "server"))
		}
		if address == "" {
			continue
		}
		lower := strings.ToLower(address)
		if strings.HasPrefix(lower, "https://") || strings.HasPrefix(lower, "tls://") || strings.HasPrefix(lower, "quic://") {
			continue
		}
		if _, _, err := net.SplitHostPort(address); err != nil {
			address = net.JoinHostPort(address, "53")
		}
		servers = append(servers, address)
	}
	return servers
}

func extractTunDNSServers(configData []byte) []string {
	var root map[string]any
	if err := json.Unmarshal(configData, &root); err != nil {
		return nil
	}
	inboundsAny, ok := root["inbounds"].([]any)
	if !ok {
		return nil
	}
	var servers []string
	for _, item := range inboundsAny {
		inboundMap, ok := item.(map[string]any)
		if !ok {
			continue
		}
		if !strings.EqualFold(getString(inboundMap, "type"), "tun") {
			continue
		}
		addresses, ok := inboundMap["address"].([]any)
		if !ok {
			continue
		}
		for _, rawAddr := range addresses {
			addrText, ok := rawAddr.(string)
			if !ok {
				continue
			}
			prefix, err := netip.ParsePrefix(strings.TrimSpace(addrText))
			if err != nil {
				continue
			}
			addr := prefix.Addr().Next()
			if !addr.IsValid() {
				continue
			}
			servers = append(servers, net.JoinHostPort(addr.String(), "53"))
		}
	}
	return servers
}

func logResolverLookup(ctx context.Context, prefix string, servers []string, domain string) {
	addresses, err := lookupWithResolver(ctx, servers, domain)
	if err != nil {
		if len(servers) == 0 {
			debugLog("%s: lookup domain=%q failed: %v", prefix, domain, err)
			return
		}
		debugLog("%s: server=%q lookup domain=%q failed: %v", prefix, strings.Join(servers, ","), domain, err)
		return
	}
	addrText := make([]string, 0, len(addresses))
	for _, addr := range addresses {
		addrText = append(addrText, addr.String())
	}
	if len(servers) == 0 {
		debugLog("%s: lookup domain=%q answers=%s", prefix, domain, strings.Join(addrText, ","))
		return
	}
	debugLog("%s: server=%q lookup domain=%q answers=%s", prefix, strings.Join(servers, ","), domain, strings.Join(addrText, ","))
}

func lookupWithResolver(ctx context.Context, servers []string, domain string) ([]net.IP, error) {
	resolver := net.DefaultResolver
	if len(servers) > 0 {
		serverList := append([]string(nil), servers...)
		resolver = &net.Resolver{
			PreferGo: true,
			Dial: func(ctx context.Context, network, address string) (net.Conn, error) {
				dialer := &net.Dialer{Timeout: 3 * time.Second}
				for _, server := range serverList {
					conn, err := dialer.DialContext(ctx, "udp", server)
					if err == nil {
						return conn, nil
					}
				}
				return nil, fmt.Errorf("all DNS servers failed: %s", strings.Join(serverList, ","))
			},
		}
	}
	results, err := resolver.LookupIP(ctx, "ip", domain)
	if err != nil {
		return nil, err
	}
	return results, nil
}

func stopTrafficMonitoring() {
	mu.Lock()
	if trafficTimerStop != nil {
		close(trafficTimerStop)
		trafficTimerStop = nil
	}
	mu.Unlock()
}

func ensureEffectiveConfigAvailable() error {
	mu.Lock()
	cfgPath := strings.TrimSpace(effectivePath)
	selected := strings.TrimSpace(selectedPath)
	lastCfg := strings.TrimSpace(lastConfig)
	profilesDir := strings.TrimSpace(profilesRoot)
	mu.Unlock()

	if cfgPath == "" {
		return fmt.Errorf("effective path is empty")
	}
	if fileExists(cfgPath) {
		return nil
	}
	if lastCfg != "" {
		cfgBytes := []byte(lastCfg)
		fixed, err := sanitizeConfigForSingbox(cfgBytes)
		if err == nil {
			cfgBytes = fixed
		}
		if err := os.MkdirAll(filepath.Dir(cfgPath), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(cfgPath, cfgBytes, 0o644); err != nil {
			return err
		}
		mu.Lock()
		lastConfig = string(cfgBytes)
		lastHash = shortHash(cfgBytes)
		if injectedRules == 0 {
			injectedRules = 3
		}
		mu.Unlock()
		return nil
	}

	candidates := make([]string, 0, 8)
	if selected != "" {
		candidates = append(candidates, selected)
	}
	if profilesDir != "" {
		entries, _ := os.ReadDir(profilesDir)
		for _, entry := range entries {
			if entry.IsDir() {
				continue
			}
			name := strings.ToLower(entry.Name())
			if !strings.HasPrefix(name, "provider-") || !strings.HasSuffix(name, ".json") {
				continue
			}
			candidates = append(candidates, filepath.Join(profilesDir, entry.Name()))
		}
	}

	for _, candidate := range candidates {
		if strings.TrimSpace(candidate) == "" || !fileExists(candidate) {
			continue
		}
		raw, err := os.ReadFile(candidate)
		if err != nil || len(raw) == 0 {
			continue
		}
		fixed, err := sanitizeConfigForSingbox(raw)
		if err == nil {
			raw = fixed
		}
		if err := os.MkdirAll(filepath.Dir(cfgPath), 0o755); err != nil {
			return err
		}
		if err := os.WriteFile(cfgPath, raw, 0o644); err != nil {
			return err
		}
		mu.Lock()
		selectedPath = candidate
		lastConfig = string(raw)
		lastHash = shortHash(raw)
		if injectedRules == 0 {
			injectedRules = 3
		}
		mu.Unlock()
		return nil
	}

	return fmt.Errorf("no available profile to rebuild effective config")
}

func initEmbeddedRuntimeLocked() error {
	mu.Lock()
	defer mu.Unlock()
	if coreReady {
		return nil
	}
	workingPath := filepath.Join(runtimeRoot, "working")
	tempPath := filepath.Join(runtimeRoot, "temp")
	if err := os.MkdirAll(workingPath, 0o755); err != nil {
		return err
	}
	if err := os.MkdirAll(tempPath, 0o755); err != nil {
		return err
	}
	coreReady = true
	return nil
}

func startEmbeddedBoxService(configData []byte) (*box.Box, context.CancelFunc, error) {
	if err := initEmbeddedRuntimeLocked(); err != nil {
		return nil, nil, err
	}

	ctx := context.Background()
	ctx = filemanager.WithDefault(
		ctx,
		filepath.Join(runtimeRoot, "working"),
		filepath.Join(runtimeRoot, "temp"),
		0,
		0,
	)
	ctx = box.Context(
		ctx,
		include.InboundRegistry(),
		include.OutboundRegistry(),
		include.EndpointRegistry(),
		include.DNSTransportRegistry(),
		include.ServiceRegistry(),
	)

	options, err := sjson.UnmarshalExtendedContext[option.Options](ctx, configData)
	if err != nil {
		return nil, nil, fmt.Errorf("decode config: %w", err)
	}

	runCtx, cancel := context.WithCancel(ctx)
	instance, err := box.New(box.Options{
		Context: runCtx,
		Options: options,
	})
	if err != nil {
		cancel()
		return nil, nil, fmt.Errorf("create service: %w", err)
	}

	if err := instance.Start(); err != nil {
		_ = instance.Close()
		cancel()
		return nil, nil, fmt.Errorf("start service: %w", err)
	}

	instance.Router().AppendTracker(&trafficTracker{})
	startTrafficMonitoring(instance)

	return instance, cancel, nil
}

func startEmbeddedBoxServiceWithRetry(configData []byte) (*box.Box, context.CancelFunc, error) {
	service, cancel, err := startEmbeddedBoxService(configData)
	if err == nil {
		return service, cancel, nil
	}

	// Windows tun creation may race with previous adapter/session cleanup.
	if !isTransientTunCreateConflict(err) {
		return nil, nil, err
	}

	time.Sleep(900 * time.Millisecond)
	return startEmbeddedBoxService(configData)
}

func isTransientTunCreateConflict(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	if strings.Contains(msg, "cannot create a file when that file already exists") {
		return true
	}
	if strings.Contains(msg, "file already exists") && strings.Contains(msg, "tun") {
		return true
	}
	return false
}

func upsertProviderOffer(offer market.ProviderOffer) {
	for i := range providers {
		if strings.EqualFold(providers[i].ID, offer.ID) {
			providers[i] = offer
			return
		}
	}
	providers = append(providers, offer)
}

func parseImportedInstallPayload(input string) (providerID string, providerName string, packageHash string, configData []byte, err error) {
	var root map[string]any
	if e := json.Unmarshal([]byte(input), &root); e != nil {
		decoded, dErr := base64.StdEncoding.DecodeString(strings.TrimSpace(input))
		if dErr != nil {
			err = e
			return
		}
		if e2 := json.Unmarshal(decoded, &root); e2 != nil {
			err = e2
			return
		}
	}
	providerID = "com.meshnetprotocol.profile"
	providerName = "Imported Provider"
	packageHash = "pkg-" + shortHash([]byte(input))[:12]
	if providerObj, ok := root["provider"].(map[string]any); ok {
		if id, ok := providerObj["id"].(string); ok && strings.TrimSpace(id) != "" {
			providerID = strings.TrimSpace(id)
		}
		if name, ok := providerObj["name"].(string); ok && strings.TrimSpace(name) != "" {
			providerName = strings.TrimSpace(name)
		}
		if hash, ok := providerObj["package_hash"].(string); ok && strings.TrimSpace(hash) != "" {
			packageHash = strings.TrimSpace(hash)
		}
	}
	configValue := extractEmbeddedConfigValue(root)
	if configValue == nil {
		configValue = root
	}
	configData, err = normalizeJSONConfigBytes(configValue)
	return
}

func extractEmbeddedConfigValue(root map[string]any) any {
	keys := []string{
		"config",
		"config_json",
		"configJSON",
		"singbox_config",
		"sing_box_config",
	}
	for _, key := range keys {
		if v, ok := root[key]; ok {
			return v
		}
	}
	return nil
}

func normalizeJSONConfigBytes(value any) ([]byte, error) {
	if s, ok := value.(string); ok {
		trimmed := strings.TrimSpace(s)
		if trimmed == "" {
			return nil, fmt.Errorf("empty config string")
		}
		if !strings.HasPrefix(trimmed, "{") && !strings.HasPrefix(trimmed, "[") {
			if decoded, err := base64.StdEncoding.DecodeString(trimmed); err == nil {
				trimmed = strings.TrimSpace(string(decoded))
			}
		}
		var verify any
		if err := json.Unmarshal([]byte(trimmed), &verify); err != nil {
			return nil, fmt.Errorf("invalid config json string")
		}
		return []byte(trimmed), nil
	}

	data, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return nil, err
	}
	return data, nil
}

func sanitizeConfigForSingbox(raw []byte) ([]byte, error) {
	var value any
	if err := json.Unmarshal(raw, &value); err != nil {
		return nil, err
	}
	value = unwrapConfigEnvelope(value)

	root, ok := asMap(value)
	if !ok {
		return normalizeJSONConfigBytes(value)
	}

	stripNonSingboxMetadata(root)
	normalizeOutboundsCompatibility(root)
	optimizeRemoteRuleSetForNative(root)
	stripUnsupportedWindowsOptions(root)
	applyRouteABMode(root)
	// Windows tun platform compatibility: must come after all other transforms.
	applyWindowsTunCompatibility(root)
	return json.MarshalIndent(root, "", "  ")
}

type windowsConfigValidation struct {
	fatal    string
	warnings []string
}

func validateWindowsConfigCompatibilityBytes(raw []byte) (string, []string) {
	if runtime.GOOS != "windows" {
		return "", nil
	}

	var root map[string]any
	if err := json.Unmarshal(raw, &root); err != nil {
		return "", nil
	}
	result := assessWindowsConfigCompatibility(root)
	return result.fatal, result.warnings
}

func assessWindowsConfigCompatibility(root map[string]any) windowsConfigValidation {
	var result windowsConfigValidation

	inbounds, _ := root["inbounds"].([]any)
	tunAutoRoute := false
	for _, ib := range inbounds {
		ibm, ok := asMap(ib)
		if !ok || !strings.EqualFold(getString(ibm, "type"), "tun") {
			continue
		}
		if v, ok := ibm["auto_route"].(bool); ok && v {
			tunAutoRoute = true
		}
		if issue := findTunAddressOverlapIssue(ibm); issue != "" && result.fatal == "" {
			result.fatal = issue
		}
	}
	if !tunAutoRoute {
		return result
	}

	if issue := findSniffHijackOrderingIssue(root); issue != "" {
		result.warnings = append(result.warnings, issue)
	}
	if issue := findDNSStrategyIssue(root); issue != "" {
		result.warnings = append(result.warnings, issue)
	}
	if issue := findAutoDetectInterfaceIssue(root); issue != "" {
		result.warnings = append(result.warnings, issue)
	}

	return result
}

// applyWindowsTunCompatibility ensures route.auto_detect_interface=true whenever the config
// contains a tun inbound with auto_route:true.
//
// On macOS, the NetworkExtension host layer handles default-interface detection automatically.
// On Windows, sing-box native tun requires this flag to correctly determine the physical
// default outbound interface; without it, outbound connections silently mis-route.
//
// This is a pure platform-compatibility patch — it does not alter which outbound handles
// which traffic class, and it does not change any rule semantics.
func applyWindowsTunCompatibility(root map[string]any) {
	if runtime.GOOS != "windows" {
		return
	}

	issues := assessWindowsConfigCompatibility(root)
	if issues.fatal != "" {
		debugLog("applyWindowsTunCompatibility: fatal compatibility issue detected: %s", issues.fatal)
	}
	for _, warning := range issues.warnings {
		debugLog("applyWindowsTunCompatibility: warning: %s", warning)
	}
}

// warnIfDNSStrategyNeedsAttention keeps profile intent explicit.
// Windows should not silently rewrite dns.strategy at runtime.
func findDNSStrategyIssue(root map[string]any) string {
	dns, _ := asMap(root["dns"])
	if dns == nil {
		return ""
	}
	existing := strings.TrimSpace(getString(dns, "strategy"))
	if strings.EqualFold(existing, "ipv4_only") {
		return ""
	}
	if existing == "" {
		return "dns.strategy is empty; fix the provider/profile instead of relying on runtime rewrite"
		// Profile already specifies a custom strategy — don't override it silently.
		return ""
	}
	return fmt.Sprintf("dns.strategy=%q; keep it explicit in the provider/profile", existing)
}

func findTunAddressOverlapIssue(inbound map[string]any) string {
	addresses, ok := inbound["address"].([]any)
	if !ok || len(addresses) == 0 {
		return ""
	}
	excludes := parsePrefixesFromAny(inbound["route_exclude_address"])
	if len(excludes) == 0 {
		return ""
	}

	for i, rawAddr := range addresses {
		addrText, ok := rawAddr.(string)
		if !ok {
			continue
		}
		prefix, err := netip.ParsePrefix(strings.TrimSpace(addrText))
		if err != nil {
			continue
		}
		if !prefix.Addr().Is4() {
			continue
		}
		if !prefixOverlapsAny(prefix, excludes) {
			continue
		}
		return fmt.Sprintf("tun address[%d]=%q overlaps route_exclude_address; Windows native tun DNS will bypass the tunnel; fix the profile", i, addrText)
	}
	return ""
}

// warnIfSniffAfterHijackDNS validates route rule ordering without mutating it.
// "action: hijack-dns" in route.rules.
//
// sing-box evaluates rules top-to-bottom without re-evaluation. The "protocol: dns"
// predicate on hijack-dns requires protocol sniffing to have already run; if the
// sniff action follows hijack-dns, DNS traffic is never detected and falls through
// to other rules (ip_is_private→direct or the final outbound).
func findSniffHijackOrderingIssue(root map[string]any) string {
	route, _ := asMap(root["route"])
	if route == nil {
		return ""
	}
	rules, _ := route["rules"].([]any)
	if len(rules) == 0 {
		return ""
	}

	sniffIdx := -1
	hijackIdx := -1
	for i, rule := range rules {
		rm, ok := asMap(rule)
		if !ok {
			continue
		}
		action := strings.ToLower(strings.TrimSpace(getString(rm, "action")))
		if action == "sniff" && sniffIdx < 0 {
			sniffIdx = i
		}
		if action == "hijack-dns" && hijackIdx < 0 {
			hijackIdx = i
		}
	}

	if hijackIdx < 0 {
		return ""
	}

	if sniffIdx >= 0 && sniffIdx < hijackIdx {
		return ""
	}

	if sniffIdx < 0 {
		return "route.rules has hijack-dns but no prior sniff action; fix rule order in the profile"
	}
	return "route.rules action=sniff appears after hijack-dns; fix rule order in the profile"
}

func findAutoDetectInterfaceIssue(root map[string]any) string {
	route, _ := asMap(root["route"])
	if route == nil {
		return ""
	}
	if v, ok := route["auto_detect_interface"].(bool); ok && v {
		return ""
	}
	return "route.auto_detect_interface is not true; Windows native tun may mis-detect the physical default interface"
}

func parsePrefixesFromAny(value any) []netip.Prefix {
	items, ok := value.([]any)
	if !ok {
		return nil
	}
	prefixes := make([]netip.Prefix, 0, len(items))
	for _, item := range items {
		text, ok := item.(string)
		if !ok {
			continue
		}
		prefix, err := netip.ParsePrefix(strings.TrimSpace(text))
		if err != nil {
			continue
		}
		prefixes = append(prefixes, prefix)
	}
	return prefixes
}

func prefixOverlapsAny(target netip.Prefix, excludes []netip.Prefix) bool {
	targetAddr := target.Addr()
	for _, exclude := range excludes {
		if exclude.Bits() == 0 {
			if exclude.Addr().Is4() == targetAddr.Is4() || exclude.Addr().Is6() == targetAddr.Is6() {
				return true
			}
			continue
		}
		if exclude.Addr().Is4() != targetAddr.Is4() || exclude.Addr().Is6() != targetAddr.Is6() {
			continue
		}
		if exclude.Contains(targetAddr) || target.Contains(exclude.Addr()) {
			return true
		}
	}
	return false
}

func logWindowsNetworkSnapshot() {
	if runtime.GOOS != "windows" {
		return
	}

	commands := []struct {
		name    string
		command string
	}{
		{
			name:    "dns-servers",
			command: "Get-DnsClientServerAddress | Select-Object InterfaceAlias,AddressFamily,ServerAddresses | ConvertTo-Json -Compress",
		},
		{
			name:    "default-routes",
			command: "Get-NetRoute -DestinationPrefix '0.0.0.0/0','::/0' | Select-Object ifIndex,InterfaceAlias,DestinationPrefix,NextHop,RouteMetric | Sort-Object DestinationPrefix,RouteMetric | ConvertTo-Json -Compress",
		},
	}

	for _, item := range commands {
		cmd := exec.Command("powershell", "-NoProfile", "-Command", item.command)
		cmd.SysProcAttr = &syscall.SysProcAttr{HideWindow: true}
		output, err := cmd.CombinedOutput()
		if err != nil {
			debugLog("windows-net-diag: %s failed: %v output=%s", item.name, err, strings.TrimSpace(string(output)))
			continue
		}
		text := strings.TrimSpace(string(output))
		if text == "" {
			text = "<empty>"
		}
		debugLog("windows-net-diag: %s=%s", item.name, text)
	}
}

func unwrapConfigEnvelope(value any) any {
	for {
		root, ok := asMap(value)
		if !ok {
			return value
		}

		next := extractEmbeddedConfigValue(root)
		if next == nil {
			return root
		}

		if text, ok := next.(string); ok {
			parsed, parsedOK := parseJSONLikeString(text)
			if parsedOK {
				value = parsed
				continue
			}
			return text
		}

		value = next
	}
}

func parseJSONLikeString(text string) (any, bool) {
	trimmed := strings.TrimSpace(text)
	if trimmed == "" {
		return nil, false
	}
	if !strings.HasPrefix(trimmed, "{") && !strings.HasPrefix(trimmed, "[") {
		if decoded, err := base64.StdEncoding.DecodeString(trimmed); err == nil {
			trimmed = strings.TrimSpace(string(decoded))
		}
	}
	var out any
	if err := json.Unmarshal([]byte(trimmed), &out); err != nil {
		return nil, false
	}
	return out, true
}

func asMap(value any) (map[string]any, bool) {
	if value == nil {
		return nil, false
	}
	if m, ok := value.(map[string]any); ok {
		return m, true
	}
	if m, ok := value.(map[string]interface{}); ok {
		out := make(map[string]any, len(m))
		for k, v := range m {
			out[k] = v
		}
		return out, true
	}
	return nil, false
}

func stripNonSingboxMetadata(root map[string]any) {
	for _, key := range []string{
		"author",
		"name",
		"title",
		"description",
		"version",
		"updated_at",
		"created_at",
		"package_hash",
		"provider_id",
		"provider_name",
		"tags",
		"x402",
		"wallet",
	} {
		delete(root, key)
	}
}

func normalizeOutboundsCompatibility(root map[string]any) {
	rawOutbounds, ok := root["outbounds"].([]any)
	if !ok {
		if outIface, ok2 := root["outbounds"].([]interface{}); ok2 {
			rawOutbounds = make([]any, 0, len(outIface))
			for _, item := range outIface {
				rawOutbounds = append(rawOutbounds, item)
			}
		} else {
			return
		}
	}
	for _, outbound := range rawOutbounds {
		obj, ok := outbound.(map[string]any)
		if !ok {
			if objIface, ok2 := outbound.(map[string]interface{}); ok2 {
				obj = make(map[string]any, len(objIface))
				for k, v := range objIface {
					obj[k] = v
				}
			} else {
				continue
			}
		}
		t, _ := obj["type"].(string)
		if strings.EqualFold(t, "selector") || strings.EqualFold(t, "urltest") {
			delete(obj, "selected")
		}
	}
}

func optimizeRemoteRuleSetForNative(root map[string]any) {
	route, routeOK := asMap(root["route"])
	if !routeOK {
		return
	}

	ruleSets, ok := route["rule_set"].([]any)
	if !ok {
		if ruleSetsIface, ok2 := route["rule_set"].([]interface{}); ok2 {
			ruleSets = make([]any, 0, len(ruleSetsIface))
			for _, item := range ruleSetsIface {
				ruleSets = append(ruleSets, item)
			}
		} else {
			return
		}
	}

	remoteCount := 0
	updatedCount := 0
	for _, item := range ruleSets {
		rs, ok := asMap(item)
		if !ok {
			continue
		}
		rsType, _ := rs["type"].(string)
		if !strings.EqualFold(rsType, "remote") {
			continue
		}
		remoteCount++

		if _, ok := rs["update_interval"]; !ok {
			rs["update_interval"] = "24h"
			updatedCount++
		}
		if _, ok := rs["download_interval"]; ok {
			delete(rs, "download_interval")
			updatedCount++
		}
	}

	if remoteCount > 0 {
		debugLog("sanitizeConfigForSingbox: native remote rule_set mode, total=%d updated=%d", remoteCount, updatedCount)
	}
}

func dropRuleSetBoundRules(rulesAny any) any {
	rules, ok := rulesAny.([]any)
	if !ok {
		if rulesIface, ok2 := rulesAny.([]interface{}); ok2 {
			rules = make([]any, 0, len(rulesIface))
			for _, item := range rulesIface {
				rules = append(rules, item)
			}
		} else {
			return rulesAny
		}
	}
	filtered := make([]any, 0, len(rules))
	for _, item := range rules {
		rule, ok := asMap(item)
		if !ok {
			filtered = append(filtered, item)
			continue
		}
		if hasAnyKey(rule,
			"rule_set",
			"rule_set_ipcidr_match_source",
			"rule_set_ip_cidr_match_source",
			"rule_set_source",
		) {
			// If rule_set is removed but rule remains, it may become a broad/unconditional rule.
			// Drop such rules entirely to preserve safe routing semantics.
			continue
		}
		filtered = append(filtered, rule)
	}
	return filtered
}

func hasAnyKey(m map[string]any, keys ...string) bool {
	for _, k := range keys {
		if _, ok := m[k]; ok {
			return true
		}
	}
	return false
}

func stripInboundRuleSetReferences(root map[string]any) {
	rawInbounds, ok := root["inbounds"].([]any)
	if !ok {
		if inboundsIface, ok2 := root["inbounds"].([]interface{}); ok2 {
			rawInbounds = make([]any, 0, len(inboundsIface))
			for _, item := range inboundsIface {
				rawInbounds = append(rawInbounds, item)
			}
		} else {
			return
		}
	}

	for _, inbound := range rawInbounds {
		obj, ok := asMap(inbound)
		if !ok {
			continue
		}
		// These fields can reference named rule_set entries (e.g. geoip-cn).
		delete(obj, "route_address_set")
		delete(obj, "route_exclude_address_set")
		delete(obj, "route_include_address_set")
		delete(obj, "route_address_set_ipcidr_match_source")
		delete(obj, "route_address_set_ip_cidr_match_source")
	}
}

func dropRuleSetBoundEntries(entriesAny any) any {
	entries, ok := entriesAny.([]any)
	if !ok {
		if entriesIface, ok2 := entriesAny.([]interface{}); ok2 {
			entries = make([]any, 0, len(entriesIface))
			for _, item := range entriesIface {
				entries = append(entries, item)
			}
		} else {
			return entriesAny
		}
	}

	filtered := make([]any, 0, len(entries))
	for _, item := range entries {
		entry, ok := asMap(item)
		if !ok {
			filtered = append(filtered, item)
			continue
		}
		if hasAnyKey(entry,
			"rule_set",
			"rule_set_ipcidr_match_source",
			"rule_set_ip_cidr_match_source",
			"rule_set_source",
		) {
			continue
		}
		filtered = append(filtered, entry)
	}
	return filtered
}

func stripDNSRuleSetReferences(root map[string]any) {
	dnsObj, ok := asMap(root["dns"])
	if !ok {
		return
	}

	if rulesAny, ok := dnsObj["rules"]; ok {
		dnsObj["rules"] = dropRuleSetBoundEntries(rulesAny)
	}
	root["dns"] = dnsObj
}

func stripRouteRuleSetReferences(root map[string]any) {
	routeObj, ok := asMap(root["route"])
	if !ok {
		return
	}

	delete(routeObj, "rule_set")
	if rulesAny, ok := routeObj["rules"]; ok {
		routeObj["rules"] = dropRuleSetBoundEntries(rulesAny)
	}
	root["route"] = routeObj
}

func stripUnsupportedWindowsOptions(root map[string]any) {
	experimental, ok := asMap(root["experimental"])
	if !ok {
		return
	}
	// sing-box cache_file path may trigger chown workflow, which is unsupported on Windows.
	delete(experimental, "cache_file")
	if len(experimental) == 0 {
		delete(root, "experimental")
		return
	}
	root["experimental"] = experimental
}

func applyRouteABMode(root map[string]any) {
	mode := strings.ToLower(strings.TrimSpace(os.Getenv("OPENMESH_WIN_ROUTE_MODE")))
	if mode == "" || mode == "a" || mode == "profile" {
		return
	}

	if mode != "b" && mode != "force_proxy" {
		return
	}

	// B mode: minimize policy complexity and force outbound through proxy.
	route, _ := asMap(root["route"])
	if route == nil {
		route = map[string]any{}
	}
	route["final"] = "proxy"
	route["auto_detect_interface"] = true
	route["rules"] = []any{
		map[string]any{
			"action":   "hijack-dns",
			"protocol": "dns",
		},
	}
	delete(route, "rule_set")
	root["route"] = route

	// Force DNS through proxy too, reduce DNS split-side effects during diagnosis.
	dns, _ := asMap(root["dns"])
	if dns != nil {
		dns["final"] = "google-dns"
		dns["rules"] = []any{}
		root["dns"] = dns
	}
}

func readLastNonEmptyLine(path string) string {
	if strings.TrimSpace(path) == "" {
		return ""
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return ""
	}
	lines := strings.Split(string(data), "\n")
	for i := len(lines) - 1; i >= 0; i-- {
		line := strings.TrimSpace(lines[i])
		if line != "" {
			return line
		}
	}
	return ""
}

func sanitizeProviderID(id string) string {
	s := strings.ToLower(strings.TrimSpace(id))
	if s == "" {
		return "imported"
	}
	replacer := strings.NewReplacer(" ", "-", "/", "-", "\\", "-", ":", "-", "*", "-", "?", "-", "\"", "-", "<", "-", ">", "-", "|", "-")
	return replacer.Replace(s)
}

func shortHash(data []byte) string {
	sum := sha256.Sum256(data)
	return fmt.Sprintf("%x", sum[:])
}

func resolveRuntimeRoot() string {
	if explicit := strings.TrimSpace(os.Getenv("OPENMESH_WIN_RUNTIME_DIR")); explicit != "" {
		return explicit
	}
	if localAppData := strings.TrimSpace(os.Getenv("LOCALAPPDATA")); localAppData != "" {
		return filepath.Join(localAppData, "OpenMeshWin", "runtime")
	}
	exe, _ := os.Executable()
	base := filepath.Dir(exe)
	return filepath.Join(base, "runtime")
}

func restoreInstalledProvidersFromDisk(root string) {
	entries, err := os.ReadDir(root)
	if err != nil {
		return
	}
	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}
		name := strings.ToLower(entry.Name())
		if !strings.HasPrefix(name, "provider-") || !strings.HasSuffix(name, ".json") {
			continue
		}
		path := filepath.Join(root, entry.Name())
		raw, err := os.ReadFile(path)
		if err != nil || len(raw) == 0 {
			continue
		}
		pid := strings.TrimSuffix(strings.TrimPrefix(entry.Name(), "provider-"), ".json")
		pHash := ""
		pName := ""
		if rootObj := parseJSONMap(raw); rootObj != nil {
			if providerObj, ok := rootObj["provider"].(map[string]any); ok {
				if v, ok := providerObj["id"].(string); ok && strings.TrimSpace(v) != "" {
					pid = strings.TrimSpace(v)
				}
				if v, ok := providerObj["name"].(string); ok {
					pName = strings.TrimSpace(v)
				}
				if v, ok := providerObj["package_hash"].(string); ok {
					pHash = strings.TrimSpace(v)
				}
			}
		}
		pid = strings.TrimSpace(pid)
		if pid == "" {
			continue
		}
		installed[pid] = true
		if pHash != "" {
			installedHash[pid] = pHash
		}
		if pName == "" {
			pName = pid
		}
		upsertProviderOffer(market.ProviderOffer{
			ID:          pid,
			Name:        pName,
			Region:      "installed",
			PackageHash: pHash,
			Description: "Installed from local profile.",
		})
	}
}

func restoreEffectiveConfigState(path string) {
	raw, err := os.ReadFile(path)
	if err != nil || len(raw) == 0 {
		return
	}
	selectedPath = path
	lastConfig = string(raw)
	lastHash = shortHash(raw)
	if injectedRules == 0 {
		injectedRules = 3
	}
}

func parseJSONMap(raw []byte) map[string]any {
	var out map[string]any
	if err := json.Unmarshal(raw, &out); err != nil {
		return nil
	}
	return out
}

// ensureWintunOnPath prepends the directory containing wintun.dll to the process PATH
// so that sing-box can find it when starting the tun inbound on Windows.
// wintun.dll is loaded by the wintun Go package using Windows LoadLibraryEx with default
// DLL search, which respects PATH. This must be called before box.New() / box.Start().
func ensureWintunOnPath(dllPath string) {
	dllPath = strings.TrimSpace(dllPath)
	if dllPath == "" {
		return
	}
	dir := strings.TrimSpace(filepath.Dir(dllPath))
	if dir == "" || dir == "." {
		return
	}
	cur := os.Getenv("PATH")
	// Check if the dir is already present to avoid duplicate prepends.
	for _, part := range strings.Split(cur, ";") {
		if strings.EqualFold(strings.TrimSpace(part), dir) {
			return
		}
	}
	newPath := dir + ";" + cur
	_ = os.Setenv("PATH", newPath)
	debugLog("ensureWintunOnPath: prepended %s to PATH", dir)
}

// logConfigDiagnostics writes key sections of the sanitized sing-box config to core_debug.log
// so that DNS / route / tun issues can be diagnosed without reading the full JSON file.
func logConfigDiagnostics(configData []byte) {
	var root map[string]any
	if err := json.Unmarshal(configData, &root); err != nil {
		debugLog("config-diag: parse failed: %v", err)
		return
	}

	// ---------- inbounds ----------
	inbounds, _ := root["inbounds"].([]any)
	hasTun := false
	tunAutoRoute := false
	for i, ib := range inbounds {
		ibm, ok := asMap(ib)
		if !ok {
			continue
		}
		typ := getString(ibm, "type")
		tag := getString(ibm, "tag")
		debugLog("config-diag: inbounds[%d] type=%q tag=%q", i, typ, tag)
		if strings.EqualFold(typ, "tun") {
			hasTun = true
			autoRoute, _ := ibm["auto_route"].(bool)
			strictRoute, _ := ibm["strict_route"].(bool)
			stack, _ := ibm["stack"].(string)
			sniff, _ := ibm["sniff"].(bool)
			tunAutoRoute = autoRoute
			debugLog("config-diag:   tun auto_route=%v strict_route=%v stack=%q sniff=%v",
				autoRoute, strictRoute, stack, sniff)
			if addrs, ok := ibm["address"].([]any); ok {
				for _, a := range addrs {
					if s, ok := a.(string); ok {
						debugLog("config-diag:   tun address=%q", s)
					}
				}
			}
			if excludeSet, ok := ibm["route_exclude_address_set"].([]any); ok && len(excludeSet) > 0 {
				for _, item := range excludeSet {
					if s, ok := item.(string); ok {
						debugLog("config-diag:   tun route_exclude_address_set=%q", s)
					}
				}
			}
		}
	}
	if !hasTun {
		debugLog("config-diag: WARN no tun inbound found in config")
	} else if !tunAutoRoute {
		debugLog("config-diag: WARN tun found but auto_route=false — traffic may not be captured")
	}

	// ---------- DNS ----------
	if dns, ok := asMap(root["dns"]); ok {
		servers, _ := dns["servers"].([]any)
		rules, _ := dns["rules"].([]any)
		finalServer, _ := dns["final"].(string)
		fakeip, _ := dns["fakeip"].(map[string]any)
		debugLog("config-diag: dns servers=%d rules=%d final=%q fakeip=%v",
			len(servers), len(rules), finalServer, fakeip != nil)
		for i, s := range servers {
			if sm, ok := asMap(s); ok {
				tag := getString(sm, "tag")
				addr := getString(sm, "address")
				detour := getString(sm, "detour")
				debugLog("config-diag:   dns.servers[%d] tag=%q addr=%q detour=%q", i, tag, addr, detour)
			}
		}
		if len(rules) == 0 {
			debugLog("config-diag:   dns.rules: (empty — all DNS traffic uses final server)")
		}
		for i, r := range rules {
			if rm, ok := asMap(r); ok {
				server := getString(rm, "server")
				action := getString(rm, "action")
				// Compact-encode the full rule for inspection without reading log files.
				ruleJSON, _ := json.Marshal(rm)
				debugLog("config-diag:   dns.rules[%d] server=%q action=%q raw=%s", i, server, action, ruleJSON)
			}
		}
	} else {
		debugLog("config-diag: WARN no dns section in config")
	}

	// ---------- route ----------
	hasDNSHijack := false
	hasProtocolDNS := false
	if route, ok := asMap(root["route"]); ok {
		rules, _ := route["rules"].([]any)
		ruleSets, _ := route["rule_set"].([]any)
		finalOut, _ := route["final"].(string)
		autoDetect, _ := route["auto_detect_interface"].(bool)
		debugLog("config-diag: route rules=%d rule_set=%d final=%q auto_detect_interface=%v",
			len(rules), len(ruleSets), finalOut, autoDetect)
		if hasTun && tunAutoRoute && !autoDetect {
			debugLog("config-diag: WARN tun auto_route=true but route.auto_detect_interface=false — outbound interface may mis-route")
		}
		for i, rs := range ruleSets {
			if rsm, ok := asMap(rs); ok {
				debugLog("config-diag:   route.rule_set[%d] tag=%q type=%q format=%q url=%q detour=%q",
					i,
					getString(rsm, "tag"),
					getString(rsm, "type"),
					getString(rsm, "format"),
					getString(rsm, "url"),
					getString(rsm, "download_detour"))
			}
		}
		if len(rules) == 0 {
			debugLog("config-diag:   route.rules: (empty)")
		}
		for i, r := range rules {
			if rm, ok := asMap(r); ok {
				proto := getString(rm, "protocol")
				outbound := getString(rm, "outbound")
				action := getString(rm, "action")
				network := getString(rm, "network")
				ruleJSON, _ := json.Marshal(rm)
				debugLog("config-diag:   route.rules[%d] proto=%q outbound=%q action=%q network=%q raw=%s",
					i, proto, outbound, action, network, ruleJSON)
				if strings.EqualFold(action, "hijack-dns") {
					hasDNSHijack = true
				}
				if strings.EqualFold(proto, "dns") {
					hasProtocolDNS = true
				}
			}
		}
	} else {
		debugLog("config-diag: WARN no route section in config")
	}

	if !hasDNSHijack && !hasProtocolDNS {
		debugLog("config-diag: WARN no hijack-dns action or dns protocol route rule — DNS traffic will bypass tun and resolve via system DNS")
	} else if hasDNSHijack {
		debugLog("config-diag: OK hijack-dns rule present")
	} else {
		debugLog("config-diag: OK dns protocol route rule present")
	}

	// ---------- outbounds summary ----------
	outbounds, _ := root["outbounds"].([]any)
	proxy := 0
	direct := 0
	blocked := 0
	selector := 0
	urltest := 0
	other := 0
	for _, ob := range outbounds {
		if obm, ok := asMap(ob); ok {
			switch strings.ToLower(getString(obm, "type")) {
			case "direct":
				direct++
			case "block":
				blocked++
			case "selector":
				selector++
			case "urltest", "url_test":
				urltest++
			case "":
				other++
			default:
				proxy++
			}
		}
	}
	debugLog("config-diag: outbounds total=%d proxy=%d direct=%d block=%d selector=%d urltest=%d other=%d",
		len(outbounds), proxy, direct, blocked, selector, urltest, other)
}

// analyseConfigForDiagnosis returns a human-readable summary map for the diagnose_config action.
func analyseConfigForDiagnosis() map[string]any {
	mu.Lock()
	raw := lastConfig
	path := selectedPath
	effPath := effectivePath
	mu.Unlock()

	result := map[string]any{
		"profilePath":   path,
		"effectivePath": effPath,
		"wintunPath":    wintunPath,
		"wintunOnPath":  wintunPath != "",
		"configLoaded":  raw != "",
	}

	if raw == "" {
		result["error"] = "no config loaded"
		return result
	}

	var root map[string]any
	if err := json.Unmarshal([]byte(raw), &root); err != nil {
		result["error"] = "parse failed: " + err.Error()
		return result
	}

	// Tun analysis
	tunInfo := map[string]any{"found": false}
	if inbounds, ok := root["inbounds"].([]any); ok {
		for _, ib := range inbounds {
			if ibm, ok := asMap(ib); ok && strings.EqualFold(getString(ibm, "type"), "tun") {
				tunInfo["found"] = true
				tunInfo["auto_route"], _ = ibm["auto_route"].(bool)
				tunInfo["strict_route"], _ = ibm["strict_route"].(bool)
				tunInfo["stack"], _ = ibm["stack"].(string)
				tunInfo["sniff"], _ = ibm["sniff"].(bool)
				break
			}
		}
	}
	result["tun"] = tunInfo

	// DNS analysis
	dnsInfo := map[string]any{"found": false}
	if dns, ok := asMap(root["dns"]); ok {
		dnsInfo["found"] = true
		dnsInfo["final"] = getString(dns, "final")
		if servers, ok := dns["servers"].([]any); ok {
			ss := make([]map[string]any, 0, len(servers))
			for _, s := range servers {
				if sm, ok := asMap(s); ok {
					ss = append(ss, map[string]any{
						"tag":     getString(sm, "tag"),
						"address": getString(sm, "address"),
						"detour":  getString(sm, "detour"),
					})
				}
			}
			dnsInfo["servers"] = ss
		}
		if rules, ok := dns["rules"].([]any); ok {
			dnsInfo["ruleCount"] = len(rules)
		}
	}
	result["dns"] = dnsInfo

	// Route analysis
	routeInfo := map[string]any{"found": false, "hasDNSHijack": false, "hasProtocolDNS": false}
	if route, ok := asMap(root["route"]); ok {
		autoDetect, _ := route["auto_detect_interface"].(bool)
		routeInfo["found"] = true
		routeInfo["final"] = getString(route, "final")
		routeInfo["auto_detect_interface"] = autoDetect
		if ruleSets, ok := route["rule_set"].([]any); ok {
			routeInfo["ruleSetCount"] = len(ruleSets)
		}
		if rules, ok := route["rules"].([]any); ok {
			routeInfo["ruleCount"] = len(rules)
			rulesSummary := make([]map[string]any, 0, len(rules))
			for _, r := range rules {
				if rm, ok := asMap(r); ok {
					if strings.EqualFold(getString(rm, "action"), "hijack-dns") {
						routeInfo["hasDNSHijack"] = true
					}
					if strings.EqualFold(getString(rm, "protocol"), "dns") {
						routeInfo["hasProtocolDNS"] = true
					}
					rulesSummary = append(rulesSummary, map[string]any{
						"action":   getString(rm, "action"),
						"protocol": getString(rm, "protocol"),
						"outbound": getString(rm, "outbound"),
						"network":  getString(rm, "network"),
					})
				}
			}
			routeInfo["rules"] = rulesSummary
		}
		// Surface actionable warnings.
		if tunFound, _ := result["tun"].(map[string]any); tunFound != nil {
			if tunAutoRouteVal, _ := tunFound["auto_route"].(bool); tunAutoRouteVal && !autoDetect {
				routeInfo["warn_auto_detect_missing"] = true
			}
		}
	}
	result["route"] = routeInfo

	return result
}

func mergeProviderOffers(base []market.ProviderOffer, incoming []market.ProviderOffer) []market.ProviderOffer {
	if len(incoming) == 0 {
		return base
	}
	out := make([]market.ProviderOffer, 0, len(base)+len(incoming))
	index := map[string]int{}
	for _, p := range base {
		key := strings.ToLower(strings.TrimSpace(p.ID))
		if key == "" {
			continue
		}
		index[key] = len(out)
		out = append(out, p)
	}
	for _, p := range incoming {
		key := strings.ToLower(strings.TrimSpace(p.ID))
		if key == "" {
			continue
		}
		if i, ok := index[key]; ok {
			out[i] = p
		} else {
			index[key] = len(out)
			out = append(out, p)
		}
	}
	return out
}

func debugLog(format string, args ...interface{}) {
	msg := fmt.Sprintf(format, args...)
	line := time.Now().Format("2006-01-02 15:04:05.000") + " " + msg + "\n"

	// Prefer writing to runtimeRoot/logs/core_debug.log so the C# host can find it.
	mu.Lock()
	root := runtimeRoot
	mu.Unlock()

	var candidates []string
	if root != "" {
		candidates = append(candidates, filepath.Join(root, "logs", "core_debug.log"))
	} else {
		// runtimeRoot not yet initialised – derive path directly so early logs aren't lost.
		if lad := strings.TrimSpace(os.Getenv("LOCALAPPDATA")); lad != "" {
			candidates = append(candidates, filepath.Join(lad, "OpenMeshWin", "runtime", "logs", "core_debug.log"))
		}
	}
	candidates = append(candidates, "core_debug.log")
	candidates = append(candidates, filepath.Join(os.TempDir(), "openmesh_core_debug.log"))

	for _, p := range candidates {
		_ = os.MkdirAll(filepath.Dir(p), 0o755)
		if f, err := os.OpenFile(p, os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644); err == nil {
			_, _ = f.WriteString(line)
			_ = f.Close()
			return
		}
	}
}

//export om_request
func om_request(requestJSON *C.char) (ret *C.char) {
	defer func() {
		if r := recover(); r != nil {
			debugLog("PANIC in om_request: %v", r)
			ret = encodePayload(snapshot(false, fmt.Sprintf("embedded panic: %v", r)))
		}
	}()
	// debugLog("om_request called") // Too noisy
	initState()
	if requestJSON == nil {
		return encodePayload(snapshot(false, "embedded: nil request"))
	}

	raw := C.GoString(requestJSON)
	req := request{}
	if err := json.Unmarshal([]byte(raw), &req); err != nil {
		return encodePayload(snapshot(false, "embedded: invalid request json: "+err.Error()))
	}

	action := strings.ToLower(strings.TrimSpace(req.Action))
	if action != "status" && action != "connections" {
		debugLog("Action: %s", action)
	}

	switch action {
	case "ping":
		return encodePayload(snapshot(true, "pong (embedded)"))
	case "status":
		return encodePayload(snapshot(true, "status (embedded)"))
	case "set_profile":
		return encodePayload(actionSetProfile(req))
	case "select_outbound":
		return encodePayload(actionSelectOutbound(req))
	case "urltest":
		return encodePayload(actionURLTest(req))
	case "start_vpn":
		return encodePayload(actionStartVpn(req))
	case "stop_vpn":
		debugLog("Calling actionStopVpn")
		res := actionStopVpn()
		debugLog("actionStopVpn returned")
		return encodePayload(res)
	case "reload":
		mu.Lock()
		if strings.TrimSpace(lastConfig) != "" {
			cfgBytes := []byte(lastConfig)
			if fixed, err := sanitizeConfigForSingbox(cfgBytes); err == nil {
				cfgBytes = fixed
				lastConfig = string(fixed)
			}
			_ = os.WriteFile(effectivePath, cfgBytes, 0o644)
		}
		mu.Unlock()
		return encodePayload(snapshot(true, "reload ok (embedded)"))
	case "provider_market_list":
		return encodePayload(actionProviderMarketList())
	case "provider_import_install":
		return encodePayload(actionImportInstall(req.ImportContent))
	case "provider_install":
		return encodePayload(actionProviderInstall(req.ProviderID))
	case "provider_activate":
		return encodePayload(actionProviderActivate(req.ProviderID))
	case "provider_uninstall":
		return encodePayload(actionProviderUninstall(req.ProviderID))
	case "provider_upgrade":
		return encodePayload(actionProviderUpgrade(req.ProviderID))
	case "diagnose_config":
		diag := analyseConfigForDiagnosis()
		diag["ok"] = true
		diag["message"] = "config diagnosed (embedded)"
		return encodePayload(diag)
	case "p3_network_preflight":
		// Report wintun / admin state without touching anything.
		out := snapshot(true, "p3_network_preflight ok (embedded)")
		out["elevated"] = isProcessElevated()
		out["wintunReady"] = strings.TrimSpace(wintunPath) != ""
		return encodePayload(out)
	case "p3_network_prepare":
		// Idempotent: ensure wintun is on PATH and runtime dirs exist.
		if wintunPath != "" {
			ensureWintunOnPath(wintunPath)
		}
		return encodePayload(snapshot(true, "p3_network_prepare ok (embedded)"))
	case "p3_network_rollback":
		// Nothing to roll back in embedded mode (no external processes).
		return encodePayload(snapshot(true, "p3_network_rollback ok (embedded, no-op)"))
	case "p3_engine_probe":
		out := snapshot(true, "p3_engine_probe ok (embedded)")
		out["embedded"] = true
		out["elevated"] = isProcessElevated()
		return encodePayload(out)
	case "p3_engine_start":
		return encodePayload(actionStartVpn(req))
	case "p3_engine_stop":
		return encodePayload(actionStopVpn())
	case "p3_engine_health":
		mu.Lock()
		healthy := engineHealthy
		errMsg := engineError
		mu.Unlock()
		out := snapshot(healthy, "p3_engine_health (embedded)")
		out["healthy"] = healthy
		out["engineError"] = errMsg
		return encodePayload(out)
	case "connections":
		mu.Lock()
		items := make([]recentConnection, len(recentConnLog))
		copy(items, recentConnLog)
		mu.Unlock()
		out := snapshot(true, "connections (embedded)")
		out["connections"] = items
		return encodePayload(out)
	case "close_connection":
		return encodePayload(snapshot(true, "close_connection ok (embedded, no-op)"))
	case "wallet_generate_mnemonic", "wallet_create", "wallet_unlock", "wallet_balance", "x402_pay":
		return encodePayload(snapshot(false, "embedded: wallet/x402 not supported: "+req.Action))
	default:
		debugLog("om_request: unknown action %q", req.Action)
		return encodePayload(snapshot(false, "embedded: unsupported action: "+req.Action))
	}
}

//export om_free_string
func om_free_string(p *C.char) {
	if p == nil {
		return
	}
	C.free(unsafe.Pointer(p))
}

func main() {}

func findWintunPath() string {
	if explicit := strings.TrimSpace(os.Getenv("OPENMESH_WIN_WINTUN_DLL")); explicit != "" && fileExists(explicit) {
		return explicit
	}

	roots := collectSearchRoots()
	for _, root := range roots {
		for _, rel := range []string{
			"wintun.dll",
			filepath.Join("deps", "wintun.dll"),
			filepath.Join("deps", "wintun", "wintun.dll"),
		} {
			if p := filepath.Join(root, rel); fileExists(p) {
				return p
			}
		}
	}

	// Fallback: Use system path
	for _, c := range []string{
		filepath.Join(os.Getenv("WINDIR"), "System32", "wintun.dll"),
		filepath.Join(os.Getenv("WINDIR"), "SysWOW64", "wintun.dll"),
	} {
		if fileExists(c) {
			return c
		}
	}

	// Last Resort: Extract embedded wintun.dll to runtime working directory
	if len(embeddedWintun) > 0 {
		extractDir := filepath.Join(resolveRuntimeRoot(), "working")
		_ = os.MkdirAll(extractDir, 0o755)
		targetPath := filepath.Join(extractDir, "wintun.dll")
		// Always overwrite to ensure we use the version embedded in the binary
		if err := os.WriteFile(targetPath, embeddedWintun, 0o644); err == nil {
			debugLog("findWintunPath: Extracted embedded wintun.dll to %s", targetPath)
			return targetPath
		}
	}

	return ""
}

func collectSearchRoots() []string {
	seen := map[string]struct{}{}
	out := make([]string, 0, 24)
	add := func(path string) {
		path = strings.TrimSpace(path)
		if path == "" {
			return
		}
		abs := path
		if !filepath.IsAbs(abs) {
			if resolved, err := filepath.Abs(abs); err == nil {
				abs = resolved
			}
		}
		abs = filepath.Clean(abs)
		if _, ok := seen[abs]; ok {
			return
		}
		seen[abs] = struct{}{}
		out = append(out, abs)
	}

	if repoRoot := strings.TrimSpace(os.Getenv("OPENMESH_WIN_REPO_ROOT")); repoRoot != "" {
		add(repoRoot)
	}

	cwd, _ := os.Getwd()
	exe, _ := os.Executable()
	exeDir := filepath.Dir(exe)
	add(cwd)
	add(strings.TrimSpace(os.Getenv("PWD")))
	add(exeDir)

	seeds := []string{cwd, exeDir}
	for _, seed := range seeds {
		cur := strings.TrimSpace(seed)
		for i := 0; i < 8 && cur != ""; i++ {
			add(cur)
			parent := filepath.Dir(cur)
			if parent == cur {
				break
			}
			cur = parent
		}
	}
	return out
}

func fileExists(path string) bool {
	if strings.TrimSpace(path) == "" {
		return false
	}
	info, err := os.Stat(path)
	return err == nil && !info.IsDir()
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
