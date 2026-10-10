import SwiftData
import SwiftUI

@main
struct CardLensApp: App {
    @State private var network = NetworkMonitor()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(network)
        }
        .modelContainer(for: [ScanRecord.self, CollectionItem.self, PriceSnapshot.self])
    }
}
