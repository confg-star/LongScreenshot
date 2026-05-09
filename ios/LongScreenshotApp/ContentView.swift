import PhotosUI
import SwiftUI
import UIKit
import LongScreenshotShared

struct ContentView: View {
    @State private var statusText = "点击“导入截图”，按从上到下的顺序选择截图。"
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var previewImages: [UIImage] = []
    @State private var manifests: [ImportSessionManifest] = []
    @State private var isImporting = false
    @State private var isProcessing = false
    @State private var importGeneration = 0
    private let photoSaver = PhotoSaver()

    var body: some View {
        NavigationStack {
            Form {
                Section("截图") {
                    PhotosPicker(selection: Binding(
                        get: { selectedItems },
                        set: { newItems in
                            selectedItems = newItems
                            guard !newItems.isEmpty else { return }
                            importGeneration += 1
                            let generation = importGeneration
                            Task { await importSelectedImages(from: newItems, generation: generation) }
                        }
                    ), maxSelectionCount: 8, selectionBehavior: .ordered, matching: .images) {
                        Label(isImporting ? "正在导入..." : "导入截图", systemImage: "photo.on.rectangle")
                    }
                    .disabled(isImporting || isProcessing)

                    Text("请选择 2 到 8 张截图，并按长图从上到下的顺序选择。两张图之间保留一小段重复区域，不要选择几乎完全相同的截图。")
                        .font(.footnote)

                    if previewImages.isEmpty {
                        Text("导入后会在这里预览所选截图。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(Array(previewImages.enumerated()), id: \.offset) { index, image in
                                    VStack(spacing: 4) {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 96, height: 160)
                                            .background(Color.secondary.opacity(0.08))
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.secondary.opacity(0.25))
                                            )
                                        Text("第 \(index + 1) 张")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("处理") {
                    Button {
                        Task { await processNewestReadySession() }
                    } label: {
                        Label(isProcessing ? "正在拼接..." : "拼接保存", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isImporting || isProcessing)

                    Text(statusText).font(.footnote)
                }

                Section("最近任务") {
                    ForEach(manifests, id: \.sessionID) { manifest in
                        VStack(alignment: .leading) {
                            Text(manifest.sessionID).font(.caption)
                            Text("状态：\(localizedStatus(manifest.status))，图片：\(manifest.images.count) 张").font(.caption2)
                        }
                    }
                }
            }
            .navigationTitle("长截图")
            .onAppear { refreshSessions() }
        }
    }

    @MainActor
    private func importSelectedImages(from items: [PhotosPickerItem], generation: Int) async {
        isImporting = true
        previewImages = []
        defer {
            if generation == importGeneration {
                isImporting = false
                selectedItems = []
            }
        }

        do {
            var imageData: [Data] = []
            for item in items {
                if let data = try await item.loadTransferable(type: Data.self) {
                    guard generation == importGeneration else { return }
                    imageData.append(data)
                }
            }
            guard generation == importGeneration else { return }
            guard !imageData.isEmpty else {
                statusText = "还没有选择截图。"
                return
            }
            guard imageData.count >= 2 else {
                statusText = "请至少选择 2 张有重叠区域的截图。"
                return
            }

            let store = try SandboxSessionStore()
            let manifest = try ImageImportStore(store: store).createSession(from: imageData)
            guard generation == importGeneration else { return }
            previewImages = imageData.compactMap { UIImage(data: $0) }
            refreshSessions()
            statusText = "已导入 \(manifest.images.count) 张截图，请确认预览顺序后点击“拼接保存”。"
        } catch {
            guard generation == importGeneration else { return }
            statusText = "导入失败：\(error.localizedDescription)"
        }
    }

    private func refreshSessions() {
        do {
            let store = try SandboxSessionStore()
            manifests = try store.listManifests()
        } catch {
            statusText = "读取任务失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func processNewestReadySession() async {
        isProcessing = true
        defer { isProcessing = false }

        var processingManifest: ImportSessionManifest?
        do {
            let granted = await photoSaver.requestAddOnlyAuthorization()
            guard granted else {
                statusText = "未获得相册保存权限，请在系统设置中允许保存照片。"
                return
            }

            let store = try SandboxSessionStore()
            guard var manifest = try store.listManifests().first(where: { manifest in
                let hasSavedResult = manifest.resultFileName != nil && (manifest.status == .stitched || manifest.status == .failed)
                return ((manifest.status == .ready || manifest.status == .failed) && manifest.images.count >= 2) || hasSavedResult
            }) else {
                statusText = "没有可处理的截图任务，请先导入截图。"
                return
            }

            processingManifest = manifest
            let resultData: Data
            var savedManifest: ImportSessionManifest

            if let resultFileName = manifest.resultFileName,
               manifest.status == .stitched || manifest.status == .failed {
                let resultURL = store.resultURL(sessionID: manifest.sessionID, fileName: resultFileName)
                if FileManager.default.fileExists(atPath: resultURL.path) {
                    resultData = try Data(contentsOf: resultURL)
                    savedManifest = manifest
                    statusText = "正在保存已拼接的长截图。"
                } else {
                    manifest.resultFileName = nil
                    let result = try await stitchLocally(manifest: manifest, store: store)
                    resultData = result.data
                    savedManifest = result.manifest
                    processingManifest = savedManifest
                }
            } else {
                let result = try await stitchLocally(manifest: manifest, store: store)
                resultData = result.data
                savedManifest = result.manifest
                processingManifest = savedManifest
            }

            try await photoSaver.saveJPEG(resultData)
            savedManifest.status = .saved
            try store.save(savedManifest)
            refreshSessions()
            statusText = "长截图已保存到相册。"
        } catch {
            if var failedManifest = processingManifest, let store = try? SandboxSessionStore() {
                failedManifest.status = .failed
                failedManifest.failureReason = error.localizedDescription
                try? store.save(failedManifest)
                refreshSessions()
            }
            statusText = "处理失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func stitchLocally(manifest: ImportSessionManifest, store: SandboxSessionStore) async throws -> (data: Data, manifest: ImportSessionManifest) {
        var processingManifest = manifest
        processingManifest.status = .uploading
        processingManifest.failureReason = nil
        try store.save(processingManifest)
        refreshSessions()
        statusText = "正在本地拼接，请稍候。"

        let rootDirectory = store.rootDirectory
        let manifestToStitch = processingManifest
        return try await Task.detached(priority: .userInitiated) {
            let detachedStore = try SandboxSessionStore(rootDirectory: rootDirectory)
            return try LocalSessionProcessor(store: detachedStore).stitch(manifest: manifestToStitch)
        }.value
    }

    private func localizedStatus(_ status: ImportSessionStatus) -> String {
        switch status {
        case .draft:
            return "草稿"
        case .ready:
            return "待处理"
        case .uploading:
            return "处理中"
        case .stitched:
            return "已拼接"
        case .saved:
            return "已保存"
        case .failed:
            return "失败"
        }
    }
}
