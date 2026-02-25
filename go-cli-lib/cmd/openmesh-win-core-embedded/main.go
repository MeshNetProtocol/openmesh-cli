package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"strings"
	"sync"
	"time"
	"unsafe"
)

type request struct {
	Action string `json:"action"`
}

type response struct {
	Ok           bool   `json:"ok"`
	Message      string `json:"message"`
	CoreRunning  bool   `json:"coreRunning"`
	VpnRunning   bool   `json:"vpnRunning"`
	P3EngineMode string `json:"p3EngineMode,omitempty"`
}

var (
	mu         sync.Mutex
	coreOnline = true
	vpnOnline  = false
)

func makeResponse(action string) response {
	mu.Lock()
	defer mu.Unlock()

	switch strings.ToLower(strings.TrimSpace(action)) {
	case "ping":
		return response{Ok: true, Message: "pong (embedded)", CoreRunning: coreOnline, VpnRunning: vpnOnline, P3EngineMode: "embedded"}
	case "status":
		return response{Ok: true, Message: "status (embedded)", CoreRunning: coreOnline, VpnRunning: vpnOnline, P3EngineMode: "embedded"}
	case "start_vpn":
		vpnOnline = true
		return response{Ok: true, Message: "vpn started (embedded stub)", CoreRunning: coreOnline, VpnRunning: vpnOnline, P3EngineMode: "embedded"}
	case "stop_vpn":
		vpnOnline = false
		return response{Ok: true, Message: "vpn stopped (embedded stub)", CoreRunning: coreOnline, VpnRunning: vpnOnline, P3EngineMode: "embedded"}
	case "reload":
		return response{Ok: true, Message: "reload ok (embedded stub)", CoreRunning: coreOnline, VpnRunning: vpnOnline, P3EngineMode: "embedded"}
	default:
		return response{
			Ok:           false,
			Message:      "embedded stub: unsupported action: " + action,
			CoreRunning:  coreOnline,
			VpnRunning:   vpnOnline,
			P3EngineMode: "embedded",
		}
	}
}

func encodeResponse(resp response) *C.char {
	payload := map[string]any{
		"ok":           resp.Ok,
		"message":      resp.Message,
		"coreRunning":  resp.CoreRunning,
		"vpnRunning":   resp.VpnRunning,
		"p3EngineMode": resp.P3EngineMode,
		"runtime": map[string]any{
			"totalUploadBytes":        0,
			"totalDownloadBytes":      0,
			"uploadRateBytesPerSec":   0,
			"downloadRateBytesPerSec": 0,
			"memoryMb":                0.0,
			"threadCount":             1,
			"uptimeSeconds":           time.Now().Unix(),
			"connectionCount":         0,
		},
		"providers":            []any{},
		"installedProviderIds": []string{},
		"outboundGroups":       []any{},
		"connections":          []any{},
	}
	data, _ := json.Marshal(payload)
	return C.CString(string(data))
}

//export om_request
func om_request(requestJSON *C.char) *C.char {
	if requestJSON == nil {
		return encodeResponse(response{
			Ok:           false,
			Message:      "embedded: nil request",
			CoreRunning:  coreOnline,
			VpnRunning:   vpnOnline,
			P3EngineMode: "embedded",
		})
	}

	raw := C.GoString(requestJSON)
	req := request{}
	if err := json.Unmarshal([]byte(raw), &req); err != nil {
		return encodeResponse(response{
			Ok:           false,
			Message:      "embedded: invalid request json: " + err.Error(),
			CoreRunning:  coreOnline,
			VpnRunning:   vpnOnline,
			P3EngineMode: "embedded",
		})
	}

	return encodeResponse(makeResponse(req.Action))
}

//export om_free_string
func om_free_string(p *C.char) {
	if p == nil {
		return
	}
	C.free(unsafe.Pointer(p))
}

func main() {}

