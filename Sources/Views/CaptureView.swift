import SwiftUI
import PhotosUI
import CoreImage

/// Screen 3 — capture or import a photo. Camera (AVFoundation) is wired on-device later;
/// library import via PhotosPicker works now (also how we exercise the flow in the simulator).
struct CaptureView: View {
    var onPhoto: (CIImage) -> Void

    @State private var pickerItem: PhotosPickerItem?
    @State private var loading = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Take or choose a photo")
                .font(.title3.bold())
            Text("Plain wall, soft even light, no flash. Face the camera straight on.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Spacer()

            // Camera capture opens on a real device (added in the on-device build).
            Button {
                // no-op placeholder until AVFoundation camera is wired on-device
            } label: {
                Label("Take photo", systemImage: "camera")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.borderedProminent)

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose from library", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
                    .padding()
            }
            .buttonStyle(.bordered)

            if loading { ProgressView() }
        }
        .padding()
        .navigationTitle("Capture")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: pickerItem) { _ in
            Task { await loadSelectedPhoto() }
        }
    }

    private func loadSelectedPhoto() async {
        guard let pickerItem else { return }
        loading = true
        defer { loading = false }
        if let data = try? await pickerItem.loadTransferable(type: Data.self),
           let ciImage = CIImage(data: data) {
            onPhoto(ciImage)
        }
    }
}

#Preview {
    NavigationStack { CaptureView(onPhoto: { _ in }) }
}
