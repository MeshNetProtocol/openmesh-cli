package openmesh

func parsePacketInfo(packet []byte) PacketInfo {
	// TODO: implement real parsing (IP version/proto/ports) if needed for routing decisions.
	// For now we keep this minimal so the unified Apple XCFramework can be built reliably.
	return PacketInfo{
		Length: int64(len(packet)),
	}
}
