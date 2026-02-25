package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unsafe"

	libbox "github.com/sagernet/sing-box/experimental/libbox"
)

type request struct {
	Action        string `json:"action"`
	ImportContent string `json:"importContent"`
	ProviderID    string `json:"providerId"`
}

type providerOffer struct {
	ID                   string  `json:"id"`
	Name                 string  `json:"name"`
	Region               string  `json:"region"`
	PricePerGB           float64 `json:"pricePerGb"`
	PackageHash          string  `json:"packageHash"`
	Description          string  `json:"description"`
	InstalledPackageHash string  `json:"installedPackageHash"`
	UpgradeAvailable     bool    `json:"upgradeAvailable"`
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
	mu            sync.Mutex
	coreOnline    = true
	vpnOnline     = false
	startedAt     = time.Now()
	runtimeRoot   = ""
	profilesRoot  = ""
	effectivePath = ""
	selectedPath  = ""
	lastConfig    = ""
	lastHash      = ""
	injectedRules = 0
	providers     []providerOffer
	installed     = map[string]bool{}
	installedHash = map[string]string{}
	wintunPath    = ""
	singboxPath   = ""
	engineCmd     *exec.Cmd
	enginePID     = 0
	engineRunning = false
	engineHealthy = false
	engineError   = ""
	marketCache   = ""
	libService    *libbox.BoxService
	libSetupDone  = false
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
	providers = loadProviderOffers(runtimeRoot)
	restoreInstalledProvidersFromDisk(profilesRoot)
	restoreEffectiveConfigState(effectivePath)
	wintunPath = findWintunPath()
	singboxPath = findSingboxPath()
}

func snapshot(ok bool, message string) map[string]any {
	mu.Lock()
	defer mu.Unlock()
	outProviders := make([]providerOffer, 0, len(providers))
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
		"outboundGroups":       []any{},
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
	}
}

func encodePayload(payload map[string]any) *C.char {
	data, _ := json.Marshal(payload)
	return C.CString(string(data))
}

func actionProviderMarketList() map[string]any {
	if fresh, err := loadProviderOffersFromURL(strings.TrimSpace(os.Getenv("OPENMESH_WIN_PROVIDER_MARKET_URL"))); err == nil && len(fresh) > 0 {
		mu.Lock()
		providers = mergeProviderOffers(providers, fresh)
		mu.Unlock()
		_ = saveProviderOffersToFile(marketCache, providers)
		return snapshot(true, "provider market listed (embedded, source=server)")
	}
	if cached, err := loadProviderOffersFromFile(marketCache); err == nil && len(cached) > 0 {
		mu.Lock()
		providers = mergeProviderOffers(providers, cached)
		mu.Unlock()
		return snapshot(true, "provider market listed (embedded, source=cache)")
	}
	return snapshot(true, "provider market listed (embedded, source=empty)")
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
			offer := providerOffer{
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

	mu.Lock()
	var offer *providerOffer
	for i := range providers {
		if strings.EqualFold(providers[i].ID, providerID) {
			offer = &providers[i]
			break
		}
	}
	if offer == nil {
		mu.Unlock()
		return snapshot(false, "provider not found in market: "+providerID)
	}
	offerCopy := *offer
	safe := sanitizeProviderID(providerID)
	profilePath := filepath.Join(profilesRoot, "provider-"+safe+".json")
	mu.Unlock()

	template := map[string]any{
		"provider": map[string]any{
			"id":           offerCopy.ID,
			"name":         offerCopy.Name,
			"region":       offerCopy.Region,
			"package_hash": offerCopy.PackageHash,
		},
		"outbounds": []map[string]any{
			{
				"type":      "selector",
				"tag":       "proxy",
				"outbounds": []string{"direct"},
			},
			{
				"type": "direct",
				"tag":  "direct",
			},
		},
		"route": map[string]any{
			"rules": []map[string]any{
				{"action": "sniff"},
			},
		},
	}
	data, err := json.MarshalIndent(template, "", "  ")
	if err != nil {
		return snapshot(false, "build provider profile failed: "+err.Error())
	}

	if err := os.MkdirAll(profilesRoot, 0o755); err != nil {
		return snapshot(false, "create profiles dir failed: "+err.Error())
	}
	if err := os.WriteFile(profilePath, data, 0o644); err != nil {
		return snapshot(false, "write provider profile failed: "+err.Error())
	}

	mu.Lock()
	installed[providerID] = true
	installedHash[providerID] = offerCopy.PackageHash
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

func actionStartVpn() map[string]any {
	mu.Lock()
	if engineRunning {
		vpnOnline = true
		mu.Unlock()
		return snapshot(true, "vpn already running (embedded)")
	}
	cfgPath := strings.TrimSpace(effectivePath)
	mu.Unlock()

	if cfgPath == "" || !fileExists(cfgPath) {
		if err := ensureEffectiveConfigAvailable(); err != nil {
			mu.Lock()
			engineError = "effective config missing: " + err.Error()
			engineRunning = false
			engineHealthy = false
			enginePID = 0
			vpnOnline = false
			mu.Unlock()
			return snapshot(false, "start_vpn failed: effective config missing")
		}
	}

	if cfgPath == "" || !fileExists(cfgPath) {
		mu.Lock()
		engineError = "effective config missing"
		engineRunning = false
		engineHealthy = false
		enginePID = 0
		vpnOnline = false
		mu.Unlock()
		return snapshot(false, "start_vpn failed: effective config missing")
	}

	configData, err := os.ReadFile(cfgPath)
	if err != nil {
		mu.Lock()
		engineError = "read config failed: " + err.Error()
		mu.Unlock()
		return snapshot(false, "start_vpn failed: read config failed")
	}
	configData, err = sanitizeConfigForSingbox(configData)
	if err != nil {
		mu.Lock()
		engineError = "sanitize config failed: " + err.Error()
		mu.Unlock()
		return snapshot(false, "start_vpn failed: sanitize config failed")
	}

	if err := initEmbeddedLibboxLocked(); err != nil {
		mu.Lock()
		engineError = "libbox setup failed: " + err.Error()
		engineRunning = false
		engineHealthy = false
		enginePID = 0
		vpnOnline = false
		mu.Unlock()
		return snapshot(false, "start_vpn failed: libbox setup failed: "+err.Error())
	}

	platform := newEmbeddedLibboxPlatform(func(line string) {
		appendRuntimeLogLine(runtimeRoot, line)
	})

	service, err := libbox.NewService(string(configData), platform)
	if err != nil {
		mu.Lock()
		engineError = "libbox new service failed: " + err.Error()
		engineRunning = false
		engineHealthy = false
		enginePID = 0
		vpnOnline = false
		mu.Unlock()
		return snapshot(false, "start_vpn failed: "+engineError)
	}
	if err := service.Start(); err != nil {
		_ = service.Close()
		mu.Lock()
		engineError = "libbox start failed: " + err.Error()
		engineRunning = false
		engineHealthy = false
		enginePID = 0
		vpnOnline = false
		mu.Unlock()
		return snapshot(false, "start_vpn failed: "+engineError)
	}

	mu.Lock()
	libService = service
	engineError = ""
	engineRunning = true
	engineHealthy = true
	enginePID = 1
	vpnOnline = true
	mu.Unlock()
	return snapshot(true, "vpn started (embedded in-process libbox)")
}

func actionStopVpn() map[string]any {
	mu.Lock()
	service := libService
	if service == nil || !engineRunning {
		vpnOnline = false
		engineHealthy = false
		mu.Unlock()
		return snapshot(true, "vpn stopped (embedded)")
	}
	mu.Unlock()

	_ = service.Close()
	mu.Lock()
	libService = nil
	vpnOnline = false
	engineRunning = false
	engineHealthy = false
	enginePID = 0
	mu.Unlock()
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

func initEmbeddedLibboxLocked() error {
	mu.Lock()
	defer mu.Unlock()
	if libSetupDone {
		return nil
	}
	setupOptions := &libbox.SetupOptions{
		BasePath:    runtimeRoot,
		WorkingPath: filepath.Join(runtimeRoot, "working"),
		TempPath:    filepath.Join(runtimeRoot, "temp"),
	}
	if err := libbox.Setup(setupOptions); err != nil {
		return err
	}
	libbox.SetLocale("en-US")
	libSetupDone = true
	return nil
}

func upsertProviderOffer(offer providerOffer) {
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
			delete(obj, "default")
			delete(obj, "selected")
		}
	}
}

func stripRemoteRuleSetDependencies(root map[string]any) {
	route, routeOK := asMap(root["route"])
	if routeOK {
		// Embedded bootstrap may fail before tunnel is up if remote rule_set download is required.
		delete(route, "rule_set")
		stripRuleSetFieldsFromRules(route["rules"])
		root["route"] = route
	}

	dns, dnsOK := asMap(root["dns"])
	if dnsOK {
		stripRuleSetFieldsFromRules(dns["rules"])
		root["dns"] = dns
	}

	stripInboundRuleSetReferences(root)
}

func stripRuleSetFieldsFromRules(rulesAny any) {
	rules, ok := rulesAny.([]any)
	if !ok {
		if rulesIface, ok2 := rulesAny.([]interface{}); ok2 {
			rules = make([]any, 0, len(rulesIface))
			for _, item := range rulesIface {
				rules = append(rules, item)
			}
		} else {
			return
		}
	}
	for _, item := range rules {
		rule, ok := asMap(item)
		if !ok {
			continue
		}
		delete(rule, "rule_set")
		delete(rule, "rule_set_ipcidr_match_source")
		delete(rule, "rule_set_ip_cidr_match_source")
		delete(rule, "rule_set_source")
	}
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

func loadProviderOffers(runtimeRoot string) []providerOffer {
	if offers, err := loadProviderOffersFromURL(strings.TrimSpace(os.Getenv("OPENMESH_WIN_PROVIDER_MARKET_URL"))); err == nil && len(offers) > 0 {
		_ = saveProviderOffersToFile(filepath.Join(runtimeRoot, "provider_market_cache.json"), offers)
		return offers
	}
	cachePath := filepath.Join(runtimeRoot, "provider_market_cache.json")
	if offers, err := loadProviderOffersFromFile(cachePath); err == nil && len(offers) > 0 {
		return offers
	}
	return []providerOffer{}
}

func loadProviderOffersFromURL(url string) ([]providerOffer, error) {
	if url == "" {
		return nil, fmt.Errorf("empty url")
	}
	client := &http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return nil, fmt.Errorf("http status %d", resp.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, 2*1024*1024))
	if err != nil {
		return nil, err
	}
	return parseProviderOffers(body)
}

func loadProviderOffersFromFile(path string) ([]providerOffer, error) {
	if strings.TrimSpace(path) == "" {
		return nil, fmt.Errorf("empty path")
	}
	body, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return parseProviderOffers(body)
}

func parseProviderOffers(body []byte) ([]providerOffer, error) {
	var root map[string]any
	if err := json.Unmarshal(body, &root); err != nil {
		return nil, err
	}
	rawProviders, ok := root["providers"].([]any)
	if !ok {
		return nil, fmt.Errorf("providers not found")
	}
	out := make([]providerOffer, 0, len(rawProviders))
	for _, p := range rawProviders {
		obj, ok := p.(map[string]any)
		if !ok {
			continue
		}
		id, _ := obj["id"].(string)
		name, _ := obj["name"].(string)
		if strings.TrimSpace(id) == "" || strings.TrimSpace(name) == "" {
			continue
		}
		region, _ := obj["region"].(string)
		pkg, _ := obj["package_hash"].(string)
		desc, _ := obj["description"].(string)
		price, _ := obj["price_per_gb"].(float64)
		out = append(out, providerOffer{
			ID:          strings.TrimSpace(id),
			Name:        strings.TrimSpace(name),
			Region:      strings.TrimSpace(region),
			PricePerGB:  price,
			PackageHash: strings.TrimSpace(pkg),
			Description: strings.TrimSpace(desc),
		})
	}
	if len(out) == 0 {
		return nil, fmt.Errorf("no valid providers")
	}
	return out, nil
}

func saveProviderOffersToFile(path string, offers []providerOffer) error {
	if strings.TrimSpace(path) == "" {
		return fmt.Errorf("empty path")
	}
	payload := map[string]any{
		"providers": offers,
	}
	data, err := json.MarshalIndent(payload, "", "  ")
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, data, 0o644)
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
		upsertProviderOffer(providerOffer{
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

func mergeProviderOffers(base []providerOffer, incoming []providerOffer) []providerOffer {
	if len(incoming) == 0 {
		return base
	}
	out := make([]providerOffer, 0, len(base)+len(incoming))
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

//export om_request
func om_request(requestJSON *C.char) (ret *C.char) {
	defer func() {
		if r := recover(); r != nil {
			ret = encodePayload(snapshot(false, fmt.Sprintf("embedded panic: %v", r)))
		}
	}()
	initState()
	if requestJSON == nil {
		return encodePayload(snapshot(false, "embedded: nil request"))
	}

	raw := C.GoString(requestJSON)
	req := request{}
	if err := json.Unmarshal([]byte(raw), &req); err != nil {
		return encodePayload(snapshot(false, "embedded: invalid request json: "+err.Error()))
	}

	switch strings.ToLower(strings.TrimSpace(req.Action)) {
	case "ping":
		return encodePayload(snapshot(true, "pong (embedded)"))
	case "status":
		return encodePayload(snapshot(true, "status (embedded)"))
	case "start_vpn":
		return encodePayload(actionStartVpn())
	case "stop_vpn":
		return encodePayload(actionStopVpn())
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
