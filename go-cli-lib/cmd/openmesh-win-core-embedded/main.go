package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unsafe"

	"github.com/MeshNetProtocol/openmesh-cli/go-cli-lib/market"
	box "github.com/sagernet/sing-box"
	"github.com/sagernet/sing-box/adapter"
	sburltest "github.com/sagernet/sing-box/common/urltest"
	"github.com/sagernet/sing-box/include"
	"github.com/sagernet/sing-box/option"
	sjson "github.com/sagernet/sing/common/json"
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
	}

	mu.Unlock()

	if cfgPath == "" || !fileExists(cfgPath) {
		if err := ensureEffectiveConfigAvailable(); err != nil {
			return snapshot(false, "start_vpn failed: no config available: "+err.Error())
		}
		// effective config was restored to effectivePath
		cfgPath = effectivePath
	}

	configData, err := os.ReadFile(cfgPath)
	if err != nil {
		return snapshot(false, "start_vpn failed: read config error: "+err.Error())
	}
	if fixed, fixErr := sanitizeConfigForSingbox(configData); fixErr == nil {
		configData = fixed
	}
	debugLog("actionStartVpn: Config loaded: %s (size=%d)", cfgPath, len(configData))

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
	singboxPath     = ""
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
	wintunPath = findWintunPath()
	singboxPath = findSingboxPath()
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
			TotalUploadBytes:        0,
			TotalDownloadBytes:      0,
			UploadRateBytesPerSec:   0,
			DownloadRateBytesPerSec: 0,
			MemoryMb:                0.0,
			ThreadCount:             1,
			UptimeSeconds:           int64(time.Since(startedAt).Seconds()),
			ConnectionCount:         0,
		},
		"p3EngineMode":      "embedded",
		"p3WintunFound":     strings.TrimSpace(wintunPath) != "",
		"p3WintunPath":      wintunPath,
		"p3SingboxFound":    strings.TrimSpace(singboxPath) != "",
		"p3SingboxPath":     singboxPath,
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
		return ""
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
		}
	}

	if len(delays) == 0 {
		// Fallback: do an actual URLTest per outbound, always returning results on demand.
		delays = directURLTestDelays(urlTestCtx, serviceNow, tags)
	}

	if len(delays) == 0 {
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
				return
			}
			if _, isGroup := itemOutbound.(adapter.OutboundGroup); isGroup {
				return
			}
			t, err := sburltest.URLTest(ctx, "", itemOutbound)
			if err != nil {
				return
			}
			delaysMu.Lock()
			if realTags[tag] {
				delays[tag] = int(t)
			}
			delaysMu.Unlock()
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

	raw, err := os.ReadFile(profilePath)
	if err != nil {
		return snapshot(false, "profile not found: "+profilePath)
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
	raw := strings.TrimSpace(lastConfig)
	currentProfilePath := strings.TrimSpace(selectedPath)
	mu.Unlock()

	// If VPN is running, switch the selector live (mac behavior) instead of rewriting config + restart.
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
		return snapshot(true, fmt.Sprintf("selected %s in %s", outboundTag, groupTag))
	}

	// Otherwise, persist selection to config defaults for next start.
	if raw == "" {
		return snapshot(false, "no active config loaded")
	}

	updated, err := setGroupDefaultOutbound([]byte(raw), groupTag, outboundTag)
	if err != nil {
		return snapshot(false, err.Error())
	}
	if fixed, fixErr := sanitizeConfigForSingbox(updated); fixErr == nil {
		updated = fixed
	}

	mu.Lock()
	lastConfig = string(updated)
	lastHash = shortHash(updated)
	groupsCacheHash = ""
	if injectedRules <= 0 {
		injectedRules = 3
	}
	if currentProfilePath != "" {
		_ = os.WriteFile(currentProfilePath, updated, 0o644)
	}
	_ = os.WriteFile(effectivePath, updated, 0o644)
	mu.Unlock()

	return snapshot(true, fmt.Sprintf("selected %s in %s", outboundTag, groupTag))
}

func setGroupDefaultOutbound(raw []byte, groupTag string, outboundTag string) ([]byte, error) {
	var root map[string]any
	if err := json.Unmarshal(raw, &root); err != nil {
		return nil, fmt.Errorf("decode config failed: %w", err)
	}

	outboundsAny, ok := root["outbounds"].([]any)
	if !ok {
		return nil, fmt.Errorf("outbounds not found in config")
	}

	groupIndex := -1
	groupType := ""
	groupItems := []any{}
	for i, node := range outboundsAny {
		ob, ok := asMap(node)
		if !ok {
			continue
		}
		tag := strings.TrimSpace(getString(ob, "tag"))
		if !strings.EqualFold(tag, groupTag) {
			continue
		}
		groupIndex = i
		groupType = strings.ToLower(strings.TrimSpace(getString(ob, "type")))
		if outs, ok := ob["outbounds"].([]any); ok {
			groupItems = outs
		}
		break
	}

	if groupIndex < 0 {
		return nil, fmt.Errorf("group not found: %s", groupTag)
	}
	if groupType != "selector" && groupType != "urltest" && groupType != "url_test" {
		return nil, fmt.Errorf("group not selectable: %s", groupTag)
	}

	found := false
	for _, item := range groupItems {
		if s, ok := item.(string); ok && strings.EqualFold(strings.TrimSpace(s), outboundTag) {
			found = true
			break
		}
	}
	if !found {
		return nil, fmt.Errorf("outbound not in group: %s", outboundTag)
	}

	ob, ok := asMap(outboundsAny[groupIndex])
	if !ok {
		return nil, fmt.Errorf("invalid group payload: %s", groupTag)
	}
	ob["default"] = outboundTag
	outboundsAny[groupIndex] = ob
	root["outbounds"] = outboundsAny

	updated, err := json.MarshalIndent(root, "", "  ")
	if err != nil {
		return nil, fmt.Errorf("encode config failed: %w", err)
	}
	return updated, nil
}

func pickPreferredGroupTag(groups []any) string {
	for _, preferred := range []string{"proxy", "auto"} {
		for _, g := range groups {
			m, ok := g.(map[string]any)
			if !ok {
				continue
			}
			if strings.EqualFold(strings.TrimSpace(getString(m, "tag")), preferred) {
				return preferred
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
	return snapshot(true, "vpn stopped (embedded)")
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
	stripRemoteRuleSetDependencies(root)
	stripUnsupportedWindowsOptions(root)
	applyRouteABMode(root)
	return json.MarshalIndent(root, "", "  ")
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

func stripRemoteRuleSetDependencies(root map[string]any) {
	route, routeOK := asMap(root["route"])
	if routeOK {
		// Embedded bootstrap may fail before tunnel is up if remote rule_set download is required.
		delete(route, "rule_set")
		route["rules"] = dropRuleSetBoundRules(route["rules"])
		root["route"] = route
	}

	dns, dnsOK := asMap(root["dns"])
	if dnsOK {
		dns["rules"] = dropRuleSetBoundRules(dns["rules"])
		root["dns"] = dns
	}

	stripInboundRuleSetReferences(root)
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
	// Try writing to current directory first
	f, err := os.OpenFile("core_debug.log", os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
	if err != nil {
		// Fallback to temp dir
		f, err = os.OpenFile(filepath.Join(os.TempDir(), "openmesh_core_debug.log"), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0644)
		if err != nil {
			return
		}
	}
	defer f.Close()
	msg := fmt.Sprintf(format, args...)
	f.WriteString(time.Now().Format("15:04:05.000") + " " + msg + "\n")
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
	default:
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
			filepath.Join("openmesh-win", "deps", "wintun.dll"),
			filepath.Join("go-cli-lib", "cmd", "openmesh-win-core", "deps", "wintun.dll"),
			filepath.Join("go-cli-lib", "cmd", "openmesh-win-core-embedded", "deps", "wintun.dll"),
		} {
			if p := filepath.Join(root, rel); fileExists(p) {
				return p
			}
		}
	}
	for _, c := range []string{
		filepath.Join(os.Getenv("WINDIR"), "System32", "wintun.dll"),
		filepath.Join(os.Getenv("WINDIR"), "SysWOW64", "wintun.dll"),
	} {
		if fileExists(c) {
			return c
		}
	}
	return ""
}

func findSingboxPath() string {
	if explicit := strings.TrimSpace(os.Getenv("OPENMESH_WIN_SINGBOX_EXE")); explicit != "" && fileExists(explicit) {
		return explicit
	}
	roots := collectSearchRoots()
	for _, root := range roots {
		for _, rel := range []string{
			"sing-box.exe",
			filepath.Join("deps", "sing-box.exe"),
			filepath.Join("sing-box", "sing-box.exe"),
			filepath.Join("openmesh-win", "deps", "sing-box.exe"),
			filepath.Join("go-cli-lib", "cmd", "openmesh-win-core", "deps", "sing-box.exe"),
			filepath.Join("go-cli-lib", "cmd", "openmesh-win-core-embedded", "deps", "sing-box.exe"),
		} {
			if p := filepath.Join(root, rel); fileExists(p) {
				return p
			}
		}
	}
	for _, c := range []string{
		filepath.Join("C:\\", "Program Files", "sing-box", "sing-box.exe"),
		filepath.Join("C:\\", "Program Files (x86)", "sing-box", "sing-box.exe"),
	} {
		if fileExists(c) {
			return c
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
