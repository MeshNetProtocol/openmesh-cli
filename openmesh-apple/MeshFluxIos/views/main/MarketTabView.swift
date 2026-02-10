import SwiftUI

struct MarketTabView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.blue)
            Text("Market")
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("供应商市场功能将在后续模块逐步上线。")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .navigationTitle("Market")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MarketTabView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            MarketTabView()
        }
    }
}
