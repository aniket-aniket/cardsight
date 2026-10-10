import PhotosUI
import SwiftData
import SwiftUI

struct ScanHomeView: View {
    let onImage: (UIImage) -> Void
    let showHistory: () -> Void

    @Environment(NetworkMonitor.self) private var network
    @Environment(\.openURL) private var openURL
    @Query(sort: \ScanRecord.scannedAt, order: .reverse) private var recent: [ScanRecord]

    @State private var pickerItem: PhotosPickerItem?
    /// A fresh value per tap, so a presentation iOS dropped (e.g. while another sheet was
    /// still closing) never leaves the camera stuck "open" and ignoring later taps.
    @State private var cameraRequest: CameraRequest?
    @State private var photoLoadTask: Task<Void, Never>?
    @State private var cameraAlert: CameraAccess.Result?
    @State private var loadingPhoto = false
    @State private var photoLoadFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !network.isOnline { OfflineBanner() }

                header

                VStack(spacing: 12) {
                    Button {
                        Task { await openCamera() }
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                    }
                    .buttonStyle(ProminentButtonStyle())
                    .accessibilityHint(CameraAccess.isAvailable ? "Opens the camera to photograph a card" : "The camera isn't available on this device")

                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(loadingPhoto ? "Loading Photo…" : "Choose from Library", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(loadingPhoto)
                    .accessibilityHint("Pick an existing photo of a card")

                    if loadingPhoto {
                        Button("Cancel Loading", role: .cancel, action: cancelPhotoLoad)
                            .frame(minHeight: 44)
                    }
                }

                tips

                if !recent.isEmpty { recentSection }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Cardsight")
        .fullScreenCover(item: $cameraRequest) { _ in
            CameraPicker(onCapture: { image in
                cameraRequest = nil
                onImage(image)
            }, onCancel: { cameraRequest = nil })
            .ignoresSafeArea()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            photoLoadTask?.cancel()
            photoLoadTask = Task { await loadPhoto(item) }
        }
        .onDisappear(perform: cancelPhotoLoad)
        .alert(cameraAlertTitle, isPresented: Binding(get: { cameraAlert != nil }, set: { if !$0 { cameraAlert = nil } })) {
            if cameraAlert == .denied {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }
            Button("OK", role: .cancel) {}
        } message: {
            Text(cameraAlertMessage)
        }
        .alert("Couldn't open that photo", isPresented: $photoLoadFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Try a different photo. iCloud photos need to download first, which requires a connection.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "rectangle.portrait.on.rectangle.portrait.angled.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor.gradient)
                .accessibilityHidden(true)
            Text("Identify a Pokémon card")
                .font(.title2.bold())
            Text("Photograph a card to see what it is and what it's worth right now.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("For the best match")
                .font(.headline)
            TipRow(symbol: "rectangle.dashed", text: "Fill the frame with one card, edges visible.")
            TipRow(symbol: "sun.max", text: "Use even light and tilt slightly to avoid glare on holos.")
            TipRow(symbol: "number", text: "Keep the name at the top and the card number at the bottom readable.")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent Scans").font(.headline)
                Spacer()
                Button("See All", action: showHistory)
                    .frame(minHeight: 44)
            }
            ForEach(recent.prefix(3)) { record in
                HistoryRow(record: record)
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }

    // MARK: Actions

    private func openCamera() async {
        // A library photo still loading must not take over the screen after the camera opens.
        cancelPhotoLoad()
        switch await CameraAccess.request() {
        case .granted: cameraRequest = CameraRequest()
        case .denied: cameraAlert = .denied
        case .unavailable: cameraAlert = .unavailable
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem) async {
        loadingPhoto = true
        let result = await Result(catching: { try await item.loadTransferable(type: Data.self) })
        // Cancelled (user chose the camera, or cancelled loading): drop the late result.
        guard !Task.isCancelled else { return }
        loadingPhoto = false
        pickerItem = nil
        photoLoadTask = nil
        if case .success(let data?) = result, let image = UIImage(data: data) {
            onImage(image)
        } else {
            photoLoadFailed = true
        }
    }

    private func cancelPhotoLoad() {
        photoLoadTask?.cancel()
        photoLoadTask = nil
        loadingPhoto = false
        pickerItem = nil
    }

    private var cameraAlertTitle: String {
        cameraAlert == .denied ? "Camera access is off" : "Camera unavailable"
    }

    private var cameraAlertMessage: String {
        cameraAlert == .denied
            ? "To photograph cards, allow camera access for Cardsight in Settings. You can still choose a photo from your library."
            : "This device doesn't have a camera available (the Simulator never does). Choose a photo from your library instead."
    }
}

private struct TipRow: View {
    let symbol: String
    let text: String

    var body: some View {
        Label {
            Text(text).font(.subheadline)
        } icon: {
            Image(systemName: symbol).foregroundStyle(Color.accentColor)
        }
    }
}

private struct CameraRequest: Identifiable {
    let id = UUID()
}

private extension Result where Failure == Error {
    init(catching body: () async throws -> Success) async {
        do { self = .success(try await body()) } catch { self = .failure(error) }
    }
}
