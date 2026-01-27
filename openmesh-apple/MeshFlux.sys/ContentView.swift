import SwiftUI
import NetworkExtension

struct ContentView: View {
    @StateObject private var extensionManager = SystemExtensionManager.shared
    @State private var showingOnboarding = false

    var body: some View {
        VStack(spacing: 0) {
            // Check if we need to show onboarding
            if extensionManager.isFirstLaunch || extensionManager.extensionState == .notInstalled {
                OnboardingView(extensionManager: extensionManager)
                    .frame(width: 500, height: 650) // Larger frame for onboarding
            } else {
                MainView(extensionManager: extensionManager)
                    .frame(width: 350, height: 500) // Compact frame for main menu
            }
        }
    }
}

// MARK: - Onboarding View (First Launch Tutorial)
struct OnboardingView: View {
    @ObservedObject var extensionManager: SystemExtensionManager
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Top Bar with Quit
                HStack {
                    Spacer()
                    Button("Quit") {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                }
                .padding(.top, 10)
                .padding(.trailing, 20)
                
                // Header
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 60))
// ... (rest is same logic, just wrapped)

                    .foregroundStyle(.blue)
                    .padding(.top, 20)
                
                Text("Welcome to MeshFlux X")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("Secure VPN powered by System Extension")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                
                
                // Action Buttons based on state (moved to top for better UX)
                actionButtons
                    .padding(.bottom, 12)
                
                Divider()
                    .padding(.vertical, 8)
                
                Text("Setup Guide")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                
                // Setup Steps Guide
                VStack(alignment: .leading, spacing: 16) {
                    SetupStepView(
                        number: 1,
                        title: "Install Extension",
                        description: "Click the button above to install the VPN system extension.",
                        isCompleted: extensionManager.extensionState == .approved || extensionManager.extensionState == .ready
                    )
                    
                    SetupStepView(
                        number: 2,
                        title: "Approve in System Settings",
                        description: "macOS will ask you to approve the extension in System Settings → General → Login Items & Extensions.",
                        isCompleted: extensionManager.extensionState == .approved || extensionManager.extensionState == .ready
                    )
                    
                    SetupStepView(
                        number: 3,
                        title: "Enable Extension",
                        description: "Toggle the switch next to 'MeshFlux X' in the Network Extensions list.",
                        isCompleted: extensionManager.extensionState == .approved || extensionManager.extensionState == .ready
                    )
                    
                    SetupStepView(
                        number: 4,
                        title: "Ready to Connect",
                        description: "Once enabled, the status will update and you can connect.",
                        isCompleted: extensionManager.extensionState == .ready
                    )
                }
                .padding(.horizontal)
                
                Spacer()
                

                
                // Status Text
                Text(extensionManager.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
            }
            .padding(32)
        }
    }
    
    @ViewBuilder
    private var actionButtons: some View {
        switch extensionManager.extensionState {
        case .notInstalled:
            Button(action: {
                extensionManager.install()
            }) {
                Label("Install Extension", systemImage: "arrow.down.circle.fill")
                    .frame(maxWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            
        case .installing:
            ProgressView()
                .progressViewStyle(.circular)
            Text("Installing...")
                .foregroundStyle(.secondary)
            
        case .waitingForApproval:
            VStack(spacing: 12) {
                Button(action: {
                    extensionManager.openSystemSettings()
                }) {
                    Label("Open System Settings", systemImage: "gear")
                        .frame(maxWidth: 200)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: {
                    extensionManager.refreshStatus()
                }) {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                
                // Auto-check indicator
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking for approval...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
        case .approved, .ready:
            VStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("Extension Ready!")
                    .font(.headline)
                    .foregroundStyle(.green)
                
                Button("Continue") {
                    extensionManager.markFirstLaunchComplete()
                    // Close the setup window
                    NSApp.windows.first(where: { $0.title == "MeshFlux X Setup" })?.close()
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
            }
            
        case .failed(let errorMessage):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                Text("Installation Failed")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                Button("Try Again") {
                    extensionManager.install()
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

// MARK: - Setup Step View
struct SetupStepView: View {
    let number: Int
    let title: String
    let description: String
    let isCompleted: Bool
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Step number or checkmark
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.green : Color.blue.opacity(0.2))
                    .frame(width: 28, height: 28)
                
                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.blue)
                }
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(isCompleted ? .secondary : .primary)
                    .strikethrough(isCompleted)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                // Show instructional image if available for this step
                // (Step 1 is button click, Step 2 is System Settings, Step 3 is Connection)
                // We have images install_step1...4
                if !isCompleted {
                    // Direct mapping for 4 steps: install_step1, 2, 3, 4
                    let imageName = "install_step\(number)" 
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 400, maxHeight: 200)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                        )
                }
            }
        }
    }
}

// MARK: - Main View (After Setup)
struct MainView: View {
    @ObservedObject var extensionManager: SystemExtensionManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: 32))
                    .foregroundStyle(.blue)
                
                VStack(alignment: .leading) {
                    Text("MeshFlux X")
                        .font(.title2)
                        .fontWeight(.bold)
                    Text("VPN System Extension")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Status Badge
                statusBadge
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(12)
            
            Divider()
            
            // VPN Status
            VStack(spacing: 8) {
                Text("VPN Status")
                    .font(.headline)
                
                Text(extensionManager.vpnStatus.description)
                    .font(.title)
                    .fontWeight(.semibold)
                    .foregroundStyle(vpnStatusColor)
            }
            
            Spacer()
            
            // Control Buttons
            HStack(spacing: 15) {
                Button(action: {
                    extensionManager.startVPN()
                }) {
                    Label("Connect", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(extensionManager.extensionState != .ready)
                
                Button(action: {
                    extensionManager.stopVPN()
                }) {
                    Label("Disconnect", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            
            // Advanced Controls
            HStack(spacing: 12) {
                Button("Refresh") {
                    extensionManager.refreshStatus()
                }
                .buttonStyle(.bordered)
                
                Button("Quit") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(.bordered)
                
                Button("Uninstall") {
                    extensionManager.uninstall()
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
            
            // Status Footer
            Text(extensionManager.status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(extensionManager.extensionState == .ready ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            
            Text(extensionManager.extensionState == .ready ? "Ready" : "Setup Required")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var vpnStatusColor: Color {
        switch extensionManager.vpnStatus {
        case .connected:
            return .green
        case .connecting, .reasserting:
            return .orange
        case .disconnecting:
            return .yellow
        case .disconnected, .invalid:
            return .secondary
        @unknown default:
            return .secondary
        }
    }
}

#Preview {
    ContentView()
}
