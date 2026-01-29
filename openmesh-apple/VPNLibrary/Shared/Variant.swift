//
//  Variant.swift
//  VPNLibrary
//
//  Aligned with sing-box Library/Shared/Variant.swift.
//

import Foundation

public enum Variant {
    #if os(macOS)
        public static var useSystemExtension = false
    #else
        public static let useSystemExtension = false
    #endif

    #if os(iOS)
        public static let applicationName = "OpenMesh"
    #elseif os(macOS)
        public static let applicationName = "MeshFlux"
    #elseif os(tvOS)
        public static let applicationName = "OpenMesh TV"
    #endif

    /// VPN extension bundle ID for NEVPNManager protocolConfiguration.providerBundleIdentifier.
    #if os(iOS)
        public static let extensionBundleIdentifier = "com.meshnetprotocol.OpenMesh.vpn-extension"
    #elseif os(macOS)
        public static let extensionBundleIdentifier = "com.meshnetprotocol.OpenMesh.mac.vpn-extension"
    #else
        public static let extensionBundleIdentifier = "com.meshnetprotocol.OpenMesh.vpn-extension"
    #endif

    /// System extension bundle ID when useSystemExtension is true.
    public static let systemExtensionBundleIdentifier = "com.meshnetprotocol.OpenMesh.macsys.vpn-extension"
}
