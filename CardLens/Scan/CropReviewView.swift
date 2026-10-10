import SwiftUI

/// Lets the user check the photo and adjust the card outline before identification.
struct CropReviewView: View {
    let onConfirm: (UIImage) -> Void
    let onCancel: () -> Void

    @State private var image: UIImage
    @State private var quad: CardQuad = .fullImage
    @State private var detecting = true
    @State private var autoDetected = false
    @State private var dragStart: CardQuad?

    init(image: UIImage, onConfirm: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
        _image = State(initialValue: image)
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .accessibilityAddTraits(.updatesFrequently)

            GeometryReader { proxy in
                let frame = fittedRect(for: image.size, in: proxy.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .accessibilityLabel("Your photo")

                    CropOverlay(quad: quad, frame: frame)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)

                    ForEach(Corner.allCases) { corner in
                        handle(for: corner, in: frame)
                    }
                }
                .overlay {
                    if detecting { ProgressView().controlSize(.large) }
                }
            }
            .frame(maxHeight: .infinity)

            controls
        }
        .padding()
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Review Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", action: onCancel)
            }
        }
        .task(id: ObjectIdentifier(image)) { await detect() }
    }

    private var statusText: String {
        if detecting { return "Finding the card edges…" }
        if autoDetected { return "Card edges found. Drag the corners to adjust if needed." }
        return "Drag the corners so the outline matches the card's edges."
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                if let cropped = CardRectifier.extract(quad, from: image) {
                    onConfirm(cropped)
                } else {
                    onConfirm(image)
                }
            } label: {
                Label("Identify Card", systemImage: "sparkle.magnifyingglass")
            }
            .buttonStyle(ProminentButtonStyle())
            .disabled(detecting)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { secondaryButtons }
                VStack(spacing: 8) { secondaryButtons }
            }
        }
    }

    @ViewBuilder
    private var secondaryButtons: some View {
        Button {
            image = image.rotatedClockwise()
        } label: {
            Label("Rotate", systemImage: "rotate.right")
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityHint("Turns the photo a quarter turn clockwise")

        Button {
            Task { await detect() }
        } label: {
            Label("Auto", systemImage: "viewfinder")
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityLabel("Auto-detect card edges")

        Button {
            quad = .fullImage
            autoDetected = false
        } label: {
            Label("Full Photo", systemImage: "arrow.up.left.and.arrow.down.right")
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityLabel("Use the whole photo")
        .accessibilityHint("Use this if your photo is already cropped to the card")
    }

    // MARK: Corner handles

    enum Corner: Int, CaseIterable, Identifiable {
        case topLeft, topRight, bottomRight, bottomLeft
        var id: Int { rawValue }
        var name: String {
            switch self {
            case .topLeft: "Top left"
            case .topRight: "Top right"
            case .bottomRight: "Bottom right"
            case .bottomLeft: "Bottom left"
            }
        }
        /// The image corner this handle moves toward when "outward".
        var outward: CGPoint {
            switch self {
            case .topLeft: CGPoint(x: 0, y: 0)
            case .topRight: CGPoint(x: 1, y: 0)
            case .bottomRight: CGPoint(x: 1, y: 1)
            case .bottomLeft: CGPoint(x: 0, y: 1)
            }
        }
    }

    private func handle(for corner: Corner, in frame: CGRect) -> some View {
        let point = quad.corners[corner.rawValue]
        let position = CGPoint(x: frame.minX + point.x * frame.width, y: frame.minY + point.y * frame.height)
        return Circle()
            .fill(.white)
            .overlay(Circle().stroke(Color.accentColor, lineWidth: 3))
            .frame(width: 24, height: 24)
            .shadow(radius: 2)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStart == nil { dragStart = quad }
                        guard let start = dragStart else { return }
                        var corners = start.corners
                        let origin = corners[corner.rawValue]
                        corners[corner.rawValue] = CGPoint(
                            x: clamp(origin.x + value.translation.width / frame.width),
                            y: clamp(origin.y + value.translation.height / frame.height))
                        quad.corners = corners
                        autoDetected = false
                    }
                    .onEnded { _ in dragStart = nil }
            )
            .accessibilityElement()
            .accessibilityLabel("\(corner.name) crop corner")
            .accessibilityValue("\(Int(point.x * 100)) percent across, \(Int(point.y * 100)) percent down")
            .accessibilityHint("Swipe up to move outward, down to move inward")
            .accessibilityAdjustableAction { direction in
                nudge(corner, outward: direction == .increment)
            }
    }

    private func nudge(_ corner: Corner, outward: Bool) {
        var corners = quad.corners
        let p = corners[corner.rawValue]
        let target = outward ? corner.outward : CGPoint(x: 0.5, y: 0.5)
        let step: CGFloat = 0.03
        corners[corner.rawValue] = CGPoint(x: clamp(p.x + (target.x - p.x).sign(step)),
                                           y: clamp(p.y + (target.y - p.y).sign(step)))
        quad.corners = corners
    }

    private func clamp(_ value: CGFloat) -> CGFloat { min(1, max(0, value)) }

    // MARK: Detection

    private func detect() async {
        detecting = true
        if let found = await CardRectifier.detectCard(in: image) {
            quad = found
            autoDetected = true
            AccessibilityNotification.Announcement("Card edges found").post()
        } else {
            quad = .centeredCard(imageSize: image.size)
            autoDetected = false
            AccessibilityNotification.Announcement("Couldn't find the card edges automatically. Adjust the corners, or use the whole photo.").post()
        }
        detecting = false
    }

    private func fittedRect(for imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (container.width - size.width) / 2, y: (container.height - size.height) / 2,
                      width: size.width, height: size.height)
    }
}

private extension CGFloat {
    /// Moves by at most `step` toward the sign of self.
    func sign(_ step: CGFloat) -> CGFloat {
        Swift.min(Swift.abs(self), step) * (self < 0 ? -1 : 1)
    }
}

/// Dims everything outside the card outline and draws the outline.
private struct CropOverlay: View {
    let quad: CardQuad
    let frame: CGRect

    var body: some View {
        Canvas { context, size in
            let points = quad.corners.map {
                CGPoint(x: frame.minX + $0.x * frame.width, y: frame.minY + $0.y * frame.height)
            }
            var outline = Path()
            outline.addLines(points)
            outline.closeSubpath()

            var dim = Path(frame)
            dim.addPath(outline)
            context.fill(dim, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))
            context.stroke(outline, with: .color(.accentColor), lineWidth: 3)
        }
    }
}
