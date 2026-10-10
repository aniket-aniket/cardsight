import SwiftUI

struct IdentifyingView: View {
    let image: UIImage
    let step: IdentificationStep
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 0)
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { if !reduceMotion { scanLine } }
                .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text(step.rawValue)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.default, value: step)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)

            Spacer(minLength: 0)

            Button("Cancel", role: .cancel, action: onCancel)
                .buttonStyle(SecondaryButtonStyle())
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Identifying")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { sweep = true }
    }

    private var scanLine: some View {
        GeometryReader { proxy in
            LinearGradient(colors: [.clear, Color.accentColor.opacity(0.55), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 60)
                .offset(y: sweep ? proxy.size.height - 30 : -30)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: sweep)
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct IdentificationFailedView: View {
    let image: UIImage
    let error: AppError
    let onAdjustCrop: () -> Void
    let onScanAnother: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .accessibilityHidden(true)

                VStack(spacing: 8) {
                    Image(systemName: error.isRetryable ? "wifi.exclamationmark" : "questionmark.square.dashed")
                        .font(.system(size: 40))
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
                    Text(error.title)
                        .font(.title3.bold())
                        .multilineTextAlignment(.center)
                    if let message = error.errorDescription {
                        Text(message)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .accessibilityElement(children: .combine)

                VStack(spacing: 12) {
                    Button(action: onAdjustCrop) {
                        Label(error.isRetryable ? "Try Again" : "Adjust Crop", systemImage: error.isRetryable ? "arrow.clockwise" : "crop")
                    }
                    .buttonStyle(ProminentButtonStyle())

                    Button(action: onScanAnother) {
                        Label("Scan Another Card", systemImage: "camera")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("No Match")
        .navigationBarTitleDisplayMode(.inline)
    }
}
