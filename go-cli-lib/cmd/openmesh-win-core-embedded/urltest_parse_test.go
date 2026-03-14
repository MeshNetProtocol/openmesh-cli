//go:build cgo
// +build cgo

package main

import (
	"testing"
)

func TestOutboundGroupCacheParsing(t *testing.T) {
	cfg := `{
  "outbounds": [
    { "type": "shadowsocks", "tag": "node-a", "server": "1.1.1.1", "server_port": 10086 },
    { "type": "selector", "tag": "proxy", "outbounds": ["node-a"], "default": "node-a" }
  ]
}`

	mu.Lock()
	lastConfig = cfg
	lastHash = ""
	groupsCacheHash = ""
	groupsCache = nil
	endpointByTag = map[string]string{}
	typeByTag = map[string]string{}
	mu.Unlock()

	s := snapshot(true, "test")
	rawGroups, ok := s["outboundGroups"].([]any)
	if !ok {
		t.Fatalf("outboundGroups type mismatch: %T", s["outboundGroups"])
	}
	if len(rawGroups) != 1 {
		t.Fatalf("expected 1 group, got %d", len(rawGroups))
	}

	group, ok := rawGroups[0].(map[string]any)
	if !ok {
		t.Fatalf("group type mismatch: %T", rawGroups[0])
	}
	if tag, _ := group["tag"].(string); tag != "proxy" {
		t.Fatalf("expected group tag proxy, got %v", group["tag"])
	}

	items, ok := group["items"].([]any)
	if !ok || len(items) != 1 {
		t.Fatalf("expected 1 item, got %T len=%d", group["items"], len(items))
	}

	item, ok := items[0].(map[string]any)
	if !ok {
		t.Fatalf("item type mismatch: %T", items[0])
	}
	if itag, _ := item["tag"].(string); itag != "node-a" {
		t.Fatalf("expected item tag node-a, got %v", item["tag"])
	}

	mu.Lock()
	endpoint := endpointByTag["node-a"]
	mu.Unlock()
	if endpoint != "1.1.1.1:10086" {
		t.Fatalf("expected endpoint 1.1.1.1:10086, got %q", endpoint)
	}
}
