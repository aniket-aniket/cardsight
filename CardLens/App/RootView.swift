import SwiftUI

struct RootView: View {
    enum Tab: Hashable { case scan, collection, history }

    @State private var selection: Tab = .scan
    @State private var scanModel = ScanFlowModel()

    var body: some View {
        TabView(selection: $selection) {
            ScanTabView(model: scanModel, showHistory: { selection = .history })
                .tabItem { Label("Scan", systemImage: "camera.viewfinder") }
                .tag(Tab.scan)

            CollectionView()
                .tabItem { Label("Collection", systemImage: "rectangle.stack.fill") }
                .tag(Tab.collection)

            HistoryView()
                .tabItem { Label("Recent Scans", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)
        }
    }
}
