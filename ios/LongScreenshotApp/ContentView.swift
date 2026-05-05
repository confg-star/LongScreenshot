import PhotosUI
import SwiftUI
import LongScreenshotShared

struct ContentView: View {
    @State private var serverURLText = LongScreenshotConstants.defaultServerURL.absoluteString
    @State private var statusText = "Select screenshots in order, upload them, then save the stitched result."
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var manifests: [ImportSessionManifest] = []
    private let photoSaver = PhotoSaver()

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    TextField("Stitch endpoint", text: $serverURLText)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                    Text("For device testing, 127.0.0.1 means the iPhone itself; enter your computer's LAN IP.")
                        .font(.footnote)
                }

                Section("Images") {
                    PhotosPicker(selection: $selectedItems, maxSelectionCount: 0, selectionBehavior: .ordered, matching: .images) {
                        Text("Choose screenshots")
                    }
                    Text("Selected order is the upload order.")
                        .font(.footnote)
                    Button("Import selected screenshots") {
                        Task { await importSelectedImages() }
                    }
                }

                Section("Process") {
                    Button("Grant photo save permission") {
                        Task { await grantPhotoPermission() }
                    }
                    Button("Upload newest imported session and save") {
                        Task { await processNewestReadySession() }
                    }
                    Text(statusText).font(.footnote)
                }

                Section("Recent sessions") {
                    ForEach(manifests, id: \.sessionID) { manifest in
                        VStack(alignment: .leading) {
                            Text(manifest.sessionID).font(.caption)
                            Text("Status: \(manifest.status.rawValue), images: \(manifest.images.count)").font(.caption2)
                        }
                    }
                }
            }
            .navigationTitle("LongScreenshot")
            .onAppear { refreshSessions() }
        }
    }

    private func grantPhotoPermission() async {
        let granted = await photoSaver.requestAddOnlyAuthorization()
        statusText = granted ? "Photo save permission granted." : "Photo save permission not granted."
    }

    private func importSelectedImages() async {
        do {
            var imageData: [Data] = []
            for item in selectedItems {
                if let data = try await item.loadTransferable(type: Data.self) {
                    imageData.append(data)
                }
            }
            guard !imageData.isEmpty else {
                statusText = "No images selected."
                return
            }
            let store = try SandboxSessionStore()
            let manifest = try ImageImportStore(store: store).createSession(from: imageData)
            refreshSessions()
            statusText = "Imported \(manifest.images.count) images."
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func refreshSessions() {
        do {
            let store = try SandboxSessionStore()
            manifests = try store.listManifests()
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func processNewestReadySession() async {
        var processingManifest: ImportSessionManifest?
        do {
            guard let stitchURL = URL(string: serverURLText) else {
                statusText = "Invalid stitch endpoint URL."
                return
            }
            let store = try SandboxSessionStore()
            guard var manifest = try store.listManifests().first(where: { ($0.status == .ready || $0.status == .failed) && !$0.images.isEmpty }) else {
                statusText = "No imported session is ready or failed."
                return
            }
            processingManifest = manifest

            manifest.status = .uploading
            manifest.failureReason = nil
            try store.save(manifest)
            processingManifest = manifest
            let resultData = try await UploadClient(stitchURL: stitchURL).upload(manifest: manifest, store: store)
            try await photoSaver.saveJPEG(resultData)
            let resultFileName = "result.jpg"
            try resultData.write(to: store.resultURL(sessionID: manifest.sessionID, fileName: resultFileName), options: [.atomic])
            manifest.resultFileName = resultFileName
            manifest.status = .saved
            try store.save(manifest)
            refreshSessions()
            statusText = "Saved long screenshot for \(manifest.sessionID)."
        } catch {
            if var failedManifest = processingManifest, let store = try? SandboxSessionStore() {
                failedManifest.status = .failed
                failedManifest.failureReason = error.localizedDescription
                try? store.save(failedManifest)
                refreshSessions()
            }
            statusText = error.localizedDescription
        }
    }
}
