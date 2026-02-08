//
//  SharedPreferences.swift
//  VPNLibrary
//
//  Aligned with sing-box Library/Database/SharedPreferences.swift.
//

import Foundation

public enum SharedPreferences {
    public static let language = Preference<String>("language", defaultValue: "")

    public static let selectedProfileID = Preference<Int64>("selected_profile_id", defaultValue: -1)

    #if os(macOS)
        private static let ignoreMemoryLimitByDefault = true
    #else
        private static let ignoreMemoryLimitByDefault = false
    #endif

    public static let ignoreMemoryLimit = Preference<Bool>("ignore_memory_limit", defaultValue: ignoreMemoryLimitByDefault)

    /// 本地网络不走 VPN：默认 true（商用/用户友好：打印机、NAS、投屏等直连）
    public static let excludeLocalNetworksByDefault = true

    #if !os(tvOS)
        public static let includeAllNetworks = Preference<Bool>("include_all_networks", defaultValue: false)
        public static let excludeAPNs = Preference<Bool>("exclude_apns", defaultValue: true)
        public static let excludeLocalNetworks = Preference<Bool>("exclude_local_networks", defaultValue: excludeLocalNetworksByDefault)
        public static let excludeCellularServices = Preference<Bool>("exclude_celluar_services", defaultValue: true)
        public static let enforceRoutes = Preference<Bool>("enforce_routes", defaultValue: false)
    #endif

    public static func resetPacketTunnel() async {
        await ignoreMemoryLimit.set(nil)
        #if !os(tvOS)
            await includeAllNetworks.set(nil)
            await excludeAPNs.set(nil)
            await excludeLocalNetworks.set(nil)
            await excludeCellularServices.set(nil)
            await enforceRoutes.set(nil)
        #endif
    }

    public static let maxLogLines = Preference<Int>("max_log_lines", defaultValue: 300)

    #if os(macOS)
        public static let showMenuBarExtra = Preference<Bool>("show_menu_bar_extra", defaultValue: true)
        public static let menuBarExtraInBackground = Preference<Bool>("menu_bar_extra_in_background", defaultValue: false)
        public static let startedByUser = Preference<Bool>("started_by_user", defaultValue: false)

        public static func resetMacOS() async {
            await showMenuBarExtra.set(nil)
            await menuBarExtraInBackground.set(nil)
        }
    #endif

    #if os(iOS)
        public static let networkPermissionRequested = Preference<Bool>("network_permission_requested", defaultValue: false)
    #endif

    public static let systemProxyEnabled = Preference<Bool>("system_proxy_enabled", defaultValue: true)

    /// Stores user's preferred outbound tag per profile for offline selection + replay on next connect.
    /// Key: profileID (string), Value: outbound tag.
    public static let selectedOutboundTagByProfile = Preference<[String: String]>(
        "selected_outbound_tag_by_profile",
        defaultValue: [:]
    )

    /// Fallback outbound for traffic not matched by explicit rules.
    /// Allowed values: "proxy" | "direct"
    public static let unmatchedTrafficOutbound = Preference<String>(
        "unmatched_traffic_outbound",
        defaultValue: "direct"
    )

    public static let installedProviderIDByProfile = Preference<[String: String]>(
        "installed_provider_id_by_profile",
        defaultValue: [:]
    )

    public static let installedProviderPackageHash = Preference<[String: String]>(
        "installed_provider_package_hash",
        defaultValue: [:]
    )

    // Profile Override
    public static let excludeDefaultRoute = Preference<Bool>("exclude_default_route", defaultValue: false)
    public static let autoRouteUseSubRangesByDefault = Preference<Bool>("auto_route_use_sub_ranges_by_default", defaultValue: false)
    public static let excludeAPNsRoute = Preference<Bool>("exclude_apple_push_notification_services", defaultValue: false)

    public static func resetProfileOverride() async {
        await excludeDefaultRoute.set(nil)
        await autoRouteUseSubRangesByDefault.set(nil)
        await excludeAPNsRoute.set(nil)
    }

    // Connections Filter
    public static let connectionStateFilter = Preference<Int>("connection_state_filter", defaultValue: 0)
    public static let connectionSort = Preference<Int>("connection_sort", defaultValue: 0)

    // On Demand Rules
    public static let alwaysOn = Preference<Bool>("always_on", defaultValue: false)

    public static func resetOnDemandRules() async {
        await alwaysOn.set(nil)
    }

    // Core
    public static let disableDeprecatedWarnings = Preference<Bool>("disable_deprecated_warnings", defaultValue: false)

    #if DEBUG
        public static let inDebug = true
    #else
        public static let inDebug = false
    #endif
}
