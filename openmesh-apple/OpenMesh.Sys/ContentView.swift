
import SwiftUI

import SwiftUI

struct ContentView: View {
    @StateObject private var extensionManager = SystemExtensionManager.shared

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tram.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("OpenMesh System Extension")
                .font(.largeTitle)
            
            Text("Status: \(extensionManager.status)")
                .font(.body)
                .multilineTextAlignment(.center)
                .padding()

            HStack(spacing: 15) {
                Button("Install / Start") {
                    extensionManager.install()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Uninstall") {
                    extensionManager.uninstall()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(40)
        .frame(minWidth: 450, minHeight: 300)
    }
}

#Preview {
    ContentView()
}

