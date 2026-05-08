import PhotosUI
import SwiftUI
import LongScreenshotShared

struct ContentView: View {
    @State private var statusText = "请选择要拼接的截图，并按从上到下的顺序选择。"
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var manifests: [ImportSessionManifest] = []
    private let photoSaver = PhotoSaver()

    var body: some View {
        NavigationStack {
            Form {
                Section("截图") {
                    PhotosPicker(selection: $selectedItems, maxSelectionCount: 8, selectionBehavior: .ordered, matching: .images) {
                        Text("选择截图")
                    }
                    Text("请按长图从上到下的顺序选择，建议一次选择 2 到 8 张截图。")
                        .font(.footnote)
                    Button("导入所选截图") {
                        Task { await importSelectedImages() }
                    }
                }

                Section("处理") {
                    Button("授权保存到相册") {
                        Task { await grantPhotoPermission() }
                    }
                    Button("本地拼接并保存最新任务") {
                        Task { await processNewestReadySession() }
                    }
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

    private func grantPhotoPermission() async {
        let granted = await photoSaver.requestAddOnlyAuthorization()
        statusText = granted ? "已获得相册保存权限。" : "未获得相册保存权限，请在系统设置中允许保存照片。"
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
                statusText = "还没有选择截图。"
                return
            }
            guard imageData.count >= 2 else {
                statusText = "请至少选择 2 张有重叠区域的截图。"
                return
            }
            let store = try SandboxSessionStore()
            let manifest = try ImageImportStore(store: store).createSession(from: imageData)
            refreshSessions()
            statusText = "已导入 \(manifest.images.count) 张截图。"
        } catch {
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

    private func processNewestReadySession() async {
        var processingManifest: ImportSessionManifest?
        do {
            let store = try SandboxSessionStore()
            guard var manifest = try store.listManifests().first(where: { manifest in
                let hasSavedResult = manifest.resultFileName != nil && (manifest.status == .stitched || manifest.status == .failed)
                return ((manifest.status == .ready || manifest.status == .failed) && !manifest.images.isEmpty) || hasSavedResult
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
