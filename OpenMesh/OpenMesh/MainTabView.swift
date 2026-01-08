import SwiftUI

struct MainTabView: View {
        var body: some View {
                TabView {
                        NavigationView {
                                HomeTabView()
                        }
                        .navigationViewStyle(.stack)
                        .tabItem {
                                Label("Home", systemImage: "house.fill")
                        }
                        
                        NavigationView {
                                MarketTabView()
                        }
                        .navigationViewStyle(.stack)
                        .tabItem {
                                Label("流量市场", systemImage: "cart.fill")
                        }
                        
                        NavigationView {
                                MeTabView()   // 来自新文件 MeTabView.swift
                        }
                        .navigationViewStyle(.stack)
                        .tabItem {
                                Label("我的", systemImage: "person.crop.circle")
                        }
                }
        }
}

private struct HomeTabView: View {
        var body: some View {
                VStack(spacing: 12) {
                        Text("Home")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                        Text("TODO: 这里放钱包首页内容")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                }
                .padding()
                .navigationTitle("Home")
        }
}

private struct MarketTabView: View {
        var body: some View {
                VStack(spacing: 12) {
                        Text("流量市场")
                                .font(.system(size: 28, weight: .heavy, design: .rounded))
                        Text("TODO: 这里放市场内容")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                }
                .padding()
                .navigationTitle("流量市场")
        }
}
