//
//  NavigationPage.swift
//  MeshFluxMac
//
//  与 sing-box ApplicationLibrary/Views/NavigationPage.swift 对齐。
//

import SwiftUI
import VPNLibrary

enum NavigationPage: String, CaseIterable, Identifiable {
    case dashboard
    case groups
    case logs
    case profiles
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .groups: return "出站组"
        case .logs: return "日志"
        case .profiles: return "配置列表"
        case .settings: return "设置"
        }
    }

    private var iconImage: String {
        switch self {
        case .dashboard: return "text.and.command.macwindow"
        case .groups: return "rectangle.3.group.fill"
        case .logs: return "doc.text.fill"
        case .profiles: return "list.bullet.rectangle.fill"
        case .settings: return "gear.circle.fill"
        }
    }

    var label: some View {
        Label(title, systemImage: iconImage)
            .tint(.primary)
    }

    /// 与 sing-box visible(extensionProfile) 一致：groups 仅 VPN 已连接时显示。
    func visible(vpnConnected: Bool) -> Bool {
        switch self {
        case .groups: return vpnConnected
        case .logs: return AppConfig.showLogsInUI
        default: return true
        }
    }

    /// 侧栏「默认页」：Dashboard 区 + Groups，然后 Profiles / Settings。商业化版本隐藏日志入口。
    static var dashboardSectionTitle: String { "Dashboard" }
    static var defaultPages: [NavigationPage] { [.logs, .profiles, .settings].filter { $0 != .logs || AppConfig.showLogsInUI } }

    @ViewBuilder
    func contentView(vpnController: VPNController) -> some View {
        switch self {
        case .dashboard:
            DashboardView(vpnController: vpnController)
        case .groups:
            GroupsView(vpnController: vpnController)
        case .logs:
            LogsView(vpnController: vpnController)
        case .profiles:
            ProfilesView()
        case .settings:
            SettingsView()
        }
    }
}
