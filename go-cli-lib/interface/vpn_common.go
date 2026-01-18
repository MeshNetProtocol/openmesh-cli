package openmesh

import (
	"encoding/binary"
	"net"
)

// PacketProcessor defines the common interface for processing network packets
type PacketProcessor interface {
	ProcessPacket(data []byte) *RouteDecision
	GetVpnStatus() *VpnStatus
}

// PacketInfo contains information about a network packet
type PacketInfo struct {
	SourceIP   string `json:"source_ip"`
	DestIP     string `json:"dest_ip"`
	SourcePort uint16 `json:"source_port"`
	DestPort   uint16 `json:"dest_port"`
	Length     int    `json:"length"`
}

// VpnStatus represents current VPN status information
type VpnStatus struct {
	Connected bool   `json:"connected"`
	Server    string `json:"server"`
	BytesIn   int64  `json:"bytes_in"`
	BytesOut  int64  `json:"bytes_out"`
}

// RouteDecision determines how a packet should be routed
type RouteDecision struct {
	ShouldRouteToVpn bool   `json:"should_route_to_vpn"`
	ErrorMessage    string `json:"error_message,omitempty"`
}

// parsePacketInfo extracts basic information from a network packet
func parsePacketInfo(packet []byte) PacketInfo {
	// Default values
	packetInfo := PacketInfo{
		Length: len(packet),
	}

	// Check if packet has enough data for IP header
	if len(packet) < 20 {
		return packetInfo
	}

	// Parse IP version and header length from first byte
	versionAndIhl := packet[0]
	version := (versionAndIhl >> 4) & 0x0F
	ihl := (versionAndIhl & 0x0F) * 4 // Internet Header Length in bytes

	// Only handle IPv4 for now
	if version != 4 {
		return packetInfo
	}

	// Extract source and destination IPs
	if len(packet) >= 20 {
		srcIP := net.IP(packet[12:16])
		destIP := net.IP(packet[16:20])
		packetInfo.SourceIP = srcIP.String()
		packetInfo.DestIP = destIP.String()
	}

	// If there's transport layer data, parse ports
	if len(packet) > int(ihl)+4 {
		protocol := packet[9] // Don't store this in the struct to avoid binding issues

		// Parse ports for TCP/UDP
		if protocol == 6 || protocol == 17 { // TCP or UDP
			if len(packet) >= int(ihl)+4+4 { // At least 4 bytes after IP header
				packetInfo.SourcePort = binary.BigEndian.Uint16(packet[ihl : ihl+2])
				packetInfo.DestPort = binary.BigEndian.Uint16(packet[ihl+2 : ihl+4])
			}
		}
	}

	return packetInfo
}