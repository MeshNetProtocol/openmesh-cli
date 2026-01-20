package openmesh

// NOTE: These types are intentionally kept "gomobile friendly":
// - avoid unsigned ints / slices / maps in exported fields where possible
// - keep fields simple so they can be bridged to Swift/ObjC across iOS+macOS builds

// PacketInfo contains minimal information about a network packet.
// It is used by the Swift layer for lightweight routing decisions.
type PacketInfo struct {
	SourceIP   string
	DestIP     string
	SourcePort int32
	DestPort   int32
	Length     int64
}

// RouteDecision determines how a packet should be routed.
type RouteDecision struct {
	ShouldRouteToVpn bool
	ErrorMessage     string
}

// VpnStatus represents current VPN status information.
type VpnStatus struct {
	Connected bool
	Server    string
	BytesIn   int64
	BytesOut  int64
}
