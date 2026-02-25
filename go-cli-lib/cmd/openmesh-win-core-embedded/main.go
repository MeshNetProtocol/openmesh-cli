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
	cfg := strings.TrimSpace(effectivePath)
	sb := strings.TrimSpace(singboxPath)
	mu.Unlock()

	if sb == "" {
		mu.Lock()
		engineError = "sing-box executable not found"
		mu.Unlock()
		return snapshot(false, "start_vpn failed: sing-box executable not found")
	}
	if cfg == "" || !fileExists(cfg) {
		mu.Lock()
		engineError = "effective config missing"
		mu.Unlock()
		return snapshot(false, "start_vpn failed: effective config missing")
	}

	stdoutPath := filepath.Join(runtimeRoot, "logs", "singbox.stdout.log")
	stderrPath := filepath.Join(runtimeRoot, "logs", "singbox.stderr.log")
	stdoutFile, _ := os.OpenFile(stdoutPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	stderrFile, _ := os.OpenFile(stderrPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)

	cmd := exec.Command(sb, "run", "-c", cfg)
	if stdoutFile != nil {
		cmd.Stdout = stdoutFile
	}
	if stderrFile != nil {
		cmd.Stderr = stderrFile
	}

	if err := cmd.Start(); err != nil {
		if stdoutFile != nil {
			_ = stdoutFile.Close()
		}
		if stderrFile != nil {
			_ = stderrFile.Close()
		}
		mu.Lock()
		engineError = "start sing-box failed: " + err.Error()
		mu.Unlock()
		return snapshot(false, "start_vpn failed: "+err.Error())
	}

	mu.Lock()
	engineCmd = cmd
	enginePID = cmd.Process.Pid
	engineRunning = true
	engineHealthy = false
	engineError = ""
	mu.Unlock()

	go func(c *exec.Cmd, outF, errF *os.File) {
		waitErr := c.Wait()
		mu.Lock()
		engineRunning = false
		engineHealthy = false
		engineCmd = nil
		enginePID = 0
		if waitErr != nil {
			engineError = "sing-box exited: " + waitErr.Error()
		}
		vpnOnline = false
		mu.Unlock()
		if outF != nil {
			_ = outF.Close()
		}
		if errF != nil {
			_ = errF.Close()
		}
	}(cmd, stdoutFile, stderrFile)

	time.Sleep(450 * time.Millisecond)
	mu.Lock()
	running := engineRunning
	mu.Unlock()
	if !running {
		detail := readLastNonEmptyLine(stderrPath)
		if strings.TrimSpace(detail) == "" {
			detail = "engine process exited early"
		}
		mu.Lock()
		engineError = detail
		mu.Unlock()
		return snapshot(false, "start_vpn failed: "+detail)
	}

	mu.Lock()
	engineHealthy = true
	vpnOnline = true
	mu.Unlock()
	return snapshot(true, "vpn started (embedded real engine)")
}

func actionStopVpn() map[string]any {
	mu.Lock()
	pid := enginePID
	running := engineRunning
	if !running || pid <= 0 {
		vpnOnline = false
		engineHealthy = false
		mu.Unlock()
		return snapshot(true, "vpn stopped (embedded)")
	}
	mu.Unlock()

	_ = terminateProcessTree(pid)
	time.Sleep(120 * time.Millisecond)
	mu.Lock()
	vpnOnline = false
	engineRunning = false
	engineHealthy = false
	enginePID = 0
	engineCmd = nil
	mu.Unlock()
	return snapshot(true, "vpn stopped (embedded)")
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
	configData, err = json.MarshalIndent(root, "", "  ")
	return
}

func sanitizeConfigForSingbox(raw []byte) ([]byte, error) {
	var root map[string]any
	if err := json.Unmarshal(raw, &root); err != nil {
		return nil, err
	}
	normalizeOutboundsCompatibility(root)
	return json.MarshalIndent(root, "", "  ")
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
	exe, _ := os.Executable()
	base := filepath.Dir(exe)
	cwd := strings.TrimSpace(os.Getenv("PWD"))
	if cwd == "" {
		cwd, _ = os.Getwd()
	}
	candidates := []string{
		filepath.Join(base, "wintun.dll"),
		filepath.Join(base, "deps", "wintun.dll"),
		filepath.Join(cwd, "openmesh-win", "deps", "wintun.dll"),
		filepath.Join(cwd, "go-cli-lib", "cmd", "openmesh-win-core", "deps", "wintun.dll"),
		filepath.Join(os.Getenv("WINDIR"), "System32", "wintun.dll"),
		filepath.Join(os.Getenv("WINDIR"), "SysWOW64", "wintun.dll"),
	}
	for _, c := range candidates {
		if !filepath.IsAbs(c) {
			if abs, err := filepath.Abs(c); err == nil {
				c = abs
			}
		}
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
	exe, _ := os.Executable()
	base := filepath.Dir(exe)
	cwd := strings.TrimSpace(os.Getenv("PWD"))
	if cwd == "" {
		cwd, _ = os.Getwd()
	}
	candidates := []string{
		filepath.Join(base, "sing-box.exe"),
		filepath.Join(base, "deps", "sing-box.exe"),
		filepath.Join(cwd, "sing-box", "sing-box.exe"),
		filepath.Join(cwd, "go-cli-lib", "cmd", "openmesh-win-core", "deps", "sing-box.exe"),
		filepath.Join(base, "..", "..", "..", "sing-box", "sing-box.exe"),
		filepath.Join("C:\\", "Program Files", "sing-box", "sing-box.exe"),
	}
	for _, c := range candidates {
		if !filepath.IsAbs(c) {
			if abs, err := filepath.Abs(c); err == nil {
				c = abs
			}
		}
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
