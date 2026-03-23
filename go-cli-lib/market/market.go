package market

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	"github.com/google/uuid"
)

// ProviderOffer represents a market provider entry
type ProviderOffer struct {
	ID                   string  `json:"id"`
	Name                 string  `json:"name"`
	Region               string  `json:"region"`
	PricePerGB           float64 `json:"pricePerGb"`
	PackageHash          string  `json:"packageHash"`
	Description          string  `json:"description"`
	InstalledPackageHash string  `json:"installedPackageHash,omitempty"`
	UpgradeAvailable     bool    `json:"upgradeAvailable,omitempty"`
	DetailURL            string  `json:"detailUrl,omitempty"`
	ConfigURL            string  `json:"configUrl,omitempty"`
}

type ProviderDetailResponse struct {
	Ok       bool             `json:"ok"`
	Provider *ProviderOffer   `json:"provider"`
	Package  *ProviderPackage `json:"package"`
	Error    string           `json:"error"`
}

type ProviderPackage struct {
	PackageHash string                `json:"package_hash"`
	Files       []ProviderPackageFile `json:"files"`
}

type ProviderPackageFile struct {
	Type string `json:"type"`
	URL  string `json:"url"`
	Tag  string `json:"tag"`
}

// Service manages market operations
type Service struct {
	BaseURL     string
	RuntimeRoot string
	ProfilesDir string
	MarketCache string
	Client      *http.Client
	mu          sync.Mutex
}

// NewService creates a new market service
func NewService(runtimeRoot string) *Service {
	return &Service{
		BaseURL:     "https://openmesh-api.ribencong.workers.dev/api/v1",
		RuntimeRoot: runtimeRoot,
		ProfilesDir: filepath.Join(runtimeRoot, "profiles"),
		MarketCache: filepath.Join(runtimeRoot, "provider_market_cache.json"),
		Client: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
}

// FetchProviders returns the list of available providers
func (s *Service) FetchProviders(installedHash map[string]string) ([]ProviderOffer, error) {
	// Try fetching from network
	offers, err := s.fetchFromNetwork()
	if err == nil {
		s.saveToCache(offers)
	} else {
		// Fallback to cache
		offers, _ = s.loadFromCache()
	}

	if len(offers) == 0 {
		if err != nil {
			return nil, err
		}
		// If no error but empty, return empty
		return []ProviderOffer{}, nil
	}

	// Enrich with installed status
	s.mu.Lock()
	defer s.mu.Unlock()

	result := make([]ProviderOffer, len(offers))
	for i, offer := range offers {
		cp := offer
		if hash, ok := installedHash[offer.ID]; ok {
			cp.InstalledPackageHash = hash
			cp.UpgradeAvailable = cp.PackageHash != "" && !strings.EqualFold(cp.PackageHash, hash)
		}
		result[i] = cp
	}

	return result, nil
}

func (s *Service) fetchFromNetwork() ([]ProviderOffer, error) {
	endpoints := []string{
		s.BaseURL + "/market/manifest",
		s.BaseURL + "/market/recommended",
		s.BaseURL + "/providers",
	}

	var lastErr error
	for _, endpoint := range endpoints {
		offers, err := s.fetchEndpoint(endpoint)
		if err == nil && len(offers) > 0 {
			return offers, nil
		}
		if err != nil {
			lastErr = err
		}
	}
	return nil, lastErr
}

func (s *Service) fetchEndpoint(urlStr string) ([]ProviderOffer, error) {
	resp, err := s.Client.Get(urlStr)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("http status %d", resp.StatusCode)
	}

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	// Try parsing as MarketManifestResponse first
	var manifest struct {
		Providers []ProviderOffer `json:"providers"`
	}
	if err := json.Unmarshal(body, &manifest); err == nil && len(manifest.Providers) > 0 {
		return manifest.Providers, nil
	}

	// Try parsing as raw list or wrapped data
	return ParseProviderOffers(body)
}

func (s *Service) loadFromCache() ([]ProviderOffer, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	data, err := os.ReadFile(s.MarketCache)
	if err != nil {
		return nil, err
	}

	var wrapper struct {
		Providers []ProviderOffer `json:"providers"`
	}
	if err := json.Unmarshal(data, &wrapper); err == nil {
		return wrapper.Providers, nil
	}
	return nil, fmt.Errorf("invalid cache format")
}

func (s *Service) saveToCache(offers []ProviderOffer) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if err := os.MkdirAll(filepath.Dir(s.MarketCache), 0755); err != nil {
		return err
	}

	wrapper := map[string]interface{}{
		"providers": offers,
		"updatedAt": time.Now(),
	}

	data, err := json.MarshalIndent(wrapper, "", "  ")
	if err != nil {
		return err
	}

	return os.WriteFile(s.MarketCache, data, 0644)
}

// ParseProviderOffers parses various JSON formats into provider list
func ParseProviderOffers(body []byte) ([]ProviderOffer, error) {
	var root map[string]interface{}
	if err := json.Unmarshal(body, &root); err != nil {
		return nil, err
	}

	var rawProviders []interface{}
	if p, ok := root["providers"].([]interface{}); ok {
		rawProviders = p
	} else if d, ok := root["data"].([]interface{}); ok {
		rawProviders = d
	} else {
		return nil, fmt.Errorf("providers not found in json")
	}

	out := make([]ProviderOffer, 0, len(rawProviders))
	for _, p := range rawProviders {
		obj, ok := p.(map[string]interface{})
		if !ok {
			continue
		}

		offer := ProviderOffer{}
		if id, ok := obj["id"].(string); ok {
			offer.ID = strings.TrimSpace(id)
		}
		if name, ok := obj["name"].(string); ok {
			offer.Name = strings.TrimSpace(name)
		}

		if offer.ID == "" || offer.Name == "" {
			continue
		}

		if region, ok := obj["region"].(string); ok {
			offer.Region = strings.TrimSpace(region)
		}
		if pkg, ok := obj["package_hash"].(string); ok {
			offer.PackageHash = strings.TrimSpace(pkg)
		}
		if desc, ok := obj["description"].(string); ok {
			offer.Description = strings.TrimSpace(desc)
		}
		if price, ok := obj["price_per_gb"].(float64); ok {
			offer.PricePerGB = price
		} else if price, ok := obj["price_per_gb_usd"].(float64); ok {
			offer.PricePerGB = price
		}
		if u, ok := obj["config_url"].(string); ok {
			offer.ConfigURL = u
		}
		if u, ok := obj["detail_url"].(string); ok {
			offer.DetailURL = u
		}

		out = append(out, offer)
	}

	return out, nil
}

// InstallProvider downloads and installs a provider
func (s *Service) InstallProvider(providerID string, reportProgress func(string)) error {
	reportProgress(fmt.Sprintf("Starting installation for %s", providerID))

	// 1. Fetch provider details
	detail, err := s.fetchProviderDetail(providerID)
	if err != nil {
		return fmt.Errorf("failed to fetch provider detail: %w", err)
	}

	// 2. Prepare directories
	providersRoot := filepath.Join(s.RuntimeRoot, "providers")
	stagingDir := filepath.Join(providersRoot, ".staging", fmt.Sprintf("%s-%s", providerID, uuid.New().String()))
	if err := os.MkdirAll(stagingDir, 0755); err != nil {
		return fmt.Errorf("failed to create staging dir: %w", err)
	}
	defer os.RemoveAll(stagingDir) // Cleanup on exit (success or fail) - wait, if success we move it. So handle carefully.

	// 3. Identify config URL
	var configURL string
	if detail.Package != nil {
		for _, f := range detail.Package.Files {
			if f.Type == "config" {
				configURL = f.URL
				break
			}
		}
	}
	if configURL == "" && detail.Provider != nil {
		configURL = detail.Provider.ConfigURL
	}
	if configURL == "" {
		return fmt.Errorf("no config url found for provider %s", providerID)
	}

	// 4. Download Config
	reportProgress(fmt.Sprintf("Downloading config from %s", configURL))
	configData, err := s.fetchData(configURL)
	if err != nil {
		return fmt.Errorf("failed to download config: %w", err)
	}

	// 5. Collect remote rule-set metadata (no pre-download; native runtime manages updates)
	var ruleSetFiles []ProviderPackageFile
	if detail.Package != nil {
		for _, f := range detail.Package.Files {
			if f.Type == "rule_set" {
				ruleSetFiles = append(ruleSetFiles, f)
			}
		}
	}
	ruleSetURLMap := make(map[string]string)
	for _, f := range ruleSetFiles {
		if f.Tag == "" || f.URL == "" {
			continue
		}
		ruleSetURLMap[f.Tag] = f.URL
	}
	if len(ruleSetURLMap) > 0 {
		reportProgress(fmt.Sprintf("Skipping rule-set pre-download, native update enabled (%d sets)", len(ruleSetURLMap)))
	} else {
		reportProgress("No remote rule-set declared in provider package")
	}

	// 6. Download Routing Rules (force_proxy)
	if detail.Package != nil {
		for _, f := range detail.Package.Files {
			if f.Type == "force_proxy" && f.URL != "" {
				reportProgress("Downloading routing_rules.json")
				rrData, err := s.fetchData(f.URL)
				if err == nil {
					if err := os.WriteFile(filepath.Join(stagingDir, "routing_rules.json"), rrData, 0644); err != nil {
						reportProgress(fmt.Sprintf("Warning: failed to write routing_rules.json: %v", err))
					}
				} else {
					reportProgress(fmt.Sprintf("Warning: failed to download routing_rules.json: %v", err))
				}
			}
		}
	}

	// 7. Patch Config
	reportProgress("Patching configuration")
	finalConfigData, err := s.patchConfig(configData, providerID, ruleSetURLMap, detail.Provider)
	if err != nil {
		return fmt.Errorf("failed to patch config: %w", err)
	}

	if err := os.WriteFile(filepath.Join(stagingDir, "config.json"), finalConfigData, 0644); err != nil {
		return fmt.Errorf("failed to write config.json: %w", err)
	}

	// 8. Move to Final Destination
	finalDir := filepath.Join(providersRoot, providerID)
	// Remove existing if any
	os.RemoveAll(finalDir)
	// Ensure parent exists
	os.MkdirAll(filepath.Dir(finalDir), 0755)

	// Move staging to final
	// Note: os.Rename might fail across volumes, but here we assume same volume.
	// Windows Rename is atomic if destination doesn't exist?
	// Go's os.Rename replaces if destination exists on some platforms, but on Windows it might fail if exists.
	// Safest is to remove destination first (done above).
	if err := os.Rename(stagingDir, finalDir); err != nil {
		// Fallback: copy if rename fails (e.g. cross-drive) - unlikely here but possible
		return fmt.Errorf("failed to move provider to final dir: %w", err)
	}

	// 9. Register Profile (Copy config to profiles directory)
	if err := os.MkdirAll(s.ProfilesDir, 0755); err != nil {
		return fmt.Errorf("failed to create profiles dir: %w", err)
	}
	profilePath := filepath.Join(s.ProfilesDir, fmt.Sprintf("provider-%s.json", providerID))
	finalConfigPath := filepath.Join(finalDir, "config.json")

	// Read the final config
	finalConfigData, err = os.ReadFile(finalConfigPath)
	if err != nil {
		return fmt.Errorf("failed to read final config: %w", err)
	}

	// Write to profiles
	if err := os.WriteFile(profilePath, finalConfigData, 0644); err != nil {
		return fmt.Errorf("failed to write profile: %w", err)
	}

	reportProgress("Installation complete")
	return nil
}

func (s *Service) fetchProviderDetail(providerID string) (*ProviderDetailResponse, error) {
	url := fmt.Sprintf("%s/providers/%s", s.BaseURL, providerID)
	resp, err := s.Client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	var detail ProviderDetailResponse
	if err := json.Unmarshal(body, &detail); err != nil {
		return nil, err
	}
	if !detail.Ok {
		return nil, fmt.Errorf("api error: %s", detail.Error)
	}
	return &detail, nil
}

func (s *Service) fetchData(url string) ([]byte, error) {
	resp, err := s.Client.Get(url)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("http status %d", resp.StatusCode)
	}
	return io.ReadAll(resp.Body)
}

func (s *Service) patchConfig(configData []byte, providerID string, ruleSetURLMap map[string]string, meta *ProviderOffer) ([]byte, error) {
	var config map[string]interface{}
	if err := json.Unmarshal(configData, &config); err != nil {
		return nil, err
	}

	// Inject metadata for restoration
	if meta != nil {
		existing, _ := config["provider"].(map[string]interface{})
		if existing == nil {
			existing = make(map[string]interface{})
		}
		existing["id"] = meta.ID
		existing["name"] = meta.Name
		existing["package_hash"] = meta.PackageHash
		if meta.Region != "" {
			existing["region"] = meta.Region
		}
		config["provider"] = existing
	}

	route, ok := config["route"].(map[string]interface{})
	if !ok {
		return configData, nil // No route section
	}

	ruleSets, ok := route["rule_set"].([]interface{})
	if !ok {
		return configData, nil // No rule_set section
	}

	_ = providerID
	_ = ruleSetURLMap
	changed := false
	for i, rsRaw := range ruleSets {
		rs, ok := rsRaw.(map[string]interface{})
		if !ok {
			continue
		}
		if rs["type"] != "remote" {
			continue
		}
		if _, ok := rs["update_interval"]; !ok {
			rs["update_interval"] = "24h"
			changed = true
		}
		if _, ok := rs["download_interval"]; ok {
			delete(rs, "download_interval")
			changed = true
		}

		ruleSets[i] = rs
	}

	if changed {
		route["rule_set"] = ruleSets
		config["route"] = route
		return json.MarshalIndent(config, "", "  ")
	}

	return configData, nil
}
