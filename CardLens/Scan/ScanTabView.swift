import SwiftData
import SwiftUI

struct ScanTabView: View {
    @Bindable var model: ScanFlowModel
    let showHistory: () -> Void

    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .home:
                    ScanHomeView(onImage: model.begin(with:), showHistory: showHistory)
                case .review(let image):
                    CropReviewView(image: image,
                                   onConfirm: { model.identify($0, context: context) },
                                   onCancel: model.reset)
                case .identifying(let image, let step):
                    IdentifyingView(image: image, step: step, onCancel: model.reset)
                case .result(let session):
                    ResultView(session: session,
                               onSelect: { model.select($0, context: context) },
                               onPriceLoaded: { quote, match in model.priceLoaded(quote, for: match, context: context) },
                               onScanAnother: model.reset)
                case .failed(let image, let error):
                    IdentificationFailedView(image: image, error: error,
                                             onAdjustCrop: {
                                                 // Network problems retry directly; unreadable photos go back to cropping.
                                                 if error.isRetryable { model.identify(image, context: context) } else { model.retry() }
                                             },
                                             onScanAnother: model.reset)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: stageKey)
        }
    }

    private var stageKey: String {
        switch model.stage {
        case .home: "home"
        case .review: "review"
        case .identifying: "identifying"
        case .result: "result"
        case .failed: "failed"
        }
    }
}
