package main

import (
	"fmt"
	"os"
	"strings"
	"time"

	libbox "github.com/sagernet/sing-box/experimental/libbox"
)

type embeddedLibboxPlatform struct {
	logger func(string)
}

func newEmbeddedLibboxPlatform(logger func(string)) *embeddedLibboxPlatform {
	return &embeddedLibboxPlatform{logger: logger}
}

func (p *embeddedLibboxPlatform) LocalDNSTransport() libbox.LocalDNSTransport { return nil }
func (p *embeddedLibboxPlatform) UsePlatformAutoDetectInterfaceControl() bool { return false }
func (p *embeddedLibboxPlatform) AutoDetectInterfaceControl(_ int32) error    { return nil }

func (p *embeddedLibboxPlatform) OpenTun(_ libbox.TunOptions) (int32, error) {
	return 0, fmt.Errorf("windows embedded OpenTun is not implemented yet")
}

func (p *embeddedLibboxPlatform) WriteLog(message string) {
	if p.logger == nil {
		return
	}
	trimmed := strings.TrimSpace(message)
	if trimmed == "" {
		return
	}
	p.logger("[libbox] " + trimmed)
}

func (p *embeddedLibboxPlatform) UseProcFS() bool { return false }

func (p *embeddedLibboxPlatform) FindConnectionOwner(_ int32, _ string, _ int32, _ string, _ int32) (int32, error) {
	return -1, fmt.Errorf("not implemented")
}

func (p *embeddedLibboxPlatform) PackageNameByUid(_ int32) (string, error) { return "", nil }
func (p *embeddedLibboxPlatform) UIDByPackageName(_ string) (int32, error) { return -1, nil }

func (p *embeddedLibboxPlatform) StartDefaultInterfaceMonitor(_ libbox.InterfaceUpdateListener) error {
	return nil
}

func (p *embeddedLibboxPlatform) CloseDefaultInterfaceMonitor(_ libbox.InterfaceUpdateListener) error {
	return nil
}

func (p *embeddedLibboxPlatform) GetInterfaces() (libbox.NetworkInterfaceIterator, error) {
	return &emptyNetworkInterfaceIterator{}, nil
}

func (p *embeddedLibboxPlatform) UnderNetworkExtension() bool { return false }
func (p *embeddedLibboxPlatform) IncludeAllNetworks() bool    { return false }
func (p *embeddedLibboxPlatform) ReadWIFIState() *libbox.WIFIState {
	return nil
}
func (p *embeddedLibboxPlatform) SystemCertificates() libbox.StringIterator {
	return &emptyStringIterator{}
}
func (p *embeddedLibboxPlatform) ClearDNSCache() {}
func (p *embeddedLibboxPlatform) SendNotification(_ *libbox.Notification) error {
	return nil
}

type emptyStringIterator struct{}

func (i *emptyStringIterator) Len() int32    { return 0 }
func (i *emptyStringIterator) HasNext() bool { return false }
func (i *emptyStringIterator) Next() string  { return "" }

type emptyNetworkInterfaceIterator struct{}

func (i *emptyNetworkInterfaceIterator) HasNext() bool                  { return false }
func (i *emptyNetworkInterfaceIterator) Next() *libbox.NetworkInterface { return nil }

func appendRuntimeLogLine(runtimeRoot string, line string) {
	if strings.TrimSpace(runtimeRoot) == "" || strings.TrimSpace(line) == "" {
		return
	}
	logLine := fmt.Sprintf("%s %s\n", time.Now().Format("2006-01-02 15:04:05"), line)
	logPath := runtimeRoot + "\\logs\\libbox.runtime.log"
	file, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer file.Close()
	_, _ = file.WriteString(logLine)
}
