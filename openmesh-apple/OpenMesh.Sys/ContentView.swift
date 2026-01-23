
import SwiftUI

struct ContentView: View {
    @ObservedObject var installer = SystemExtensionInstaller()

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("OpenMesh System Extension")
                .font(.headline)
            
            Text(installer.status)
                .foregroundColor(.secondary)
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding()

            Button("Install Extension") {
                installer.install()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

#Preview {
    ContentView()
}
