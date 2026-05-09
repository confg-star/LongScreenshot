import PhotosUI
import SwiftUI
import UIKit
import LongScreenshotShared

struct ContentView: View {
    @State private var statusText = "点击“导入截图”，按从上到下的顺序选择截图。"
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var importedScreenshots: [ImportedScreenshot] = []
    @State private var manifests: [ImportSessionManifest] = []
    @State private var isImporting = false
    @State private var isProcessing = false
    @State private var importGeneration = 0
    @State private var showWidthMismatchAlert = false
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
                    ), maxSelectionCount: max(1, 8 - importedScreenshots.count), selectionBehavior: .ordered, matching: .images) {
                        Label(isImporting ? "正在导入..." : "导入截图", systemImage: "photo.on.rectangle")
                    }
                    .disabled(isImporting || isProcessing || importedScreenshots.count >= 8)

                    Text("请选择 2 到 8 张截图，并按长图从上到下的顺序选择。两张图之间保留一小段重复区域，不要选择几乎完全相同的截图。")
                        .font(.footnote)

                    if importedScreenshots.isEmpty {
                        Text("导入后会在这里预览所选截图。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 10) {
                                ForEach(Array(importedScreenshots.enumerated()), id: \.element.id) { index, screenshot in
                                    VStack(spacing: 4) {
                                        ZStack(alignment: .topTrailing) {
                                            Image(uiImage: screenshot.image)
                                                .resizable()
                                                .scaledToFit()
                                                .frame(width: 96, height: 160)
                                                .background(Color.secondary.opacity(0.08))
                                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(Color.secondary.opacity(0.25))
                                                )

                                            Button {
                                                removeScreenshot(id: screenshot.id)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.title3)
                                                    .symbolRenderingMode(.palette)
                                                    .foregroundStyle(.white, Color.black.opacity(0.65))
                                            }
                                            .buttonStyle(.plain)
                                            .padding(4)
                                            .disabled(isImporting || isProcessing)
                                        }
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
                        Task { await processCurrentScreenshots() }
                    } label: {
                        Label(isProcessing ? "正在拼接..." : "拼接保存", systemImage: "square.and.arrow.down")
                    }
                    .disabled(isImporting || isProcessing)

                    Text(statusText).font(.footnote)
                }

                Section("实验录屏") {
                    Label("控制中心录屏入口验证", systemImage: "record.circle")
                        .font(.headline)

                    Text("下拉控制中心，长按录屏按钮，尝试选择“长截图录屏”。当前实验只验证入口能否出现和启动，录屏结束后暂不会自动生成长截图。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
            .alert("截图宽度不一致", isPresented: $showWidthMismatchAlert) {
                Button("继续拼接") {
                    Task { await processCurrentScreenshots(resizeMismatchedWidthsToFirst: true) }
                }
                Button("取消", role: .cancel) {
                    statusText = "已取消拼接。你可以删除宽度不一致的图片后重新尝试。"
                }
            } message: {
                Text("继续后会按第一张截图的宽度等比缩放其它图片，可能影响拼接效果。")
            }
        }
    }

    @MainActor
    private func importSelectedImages(from items: [PhotosPickerItem], generation: Int) async {
        isImporting = true
        defer {
            if generation == importGeneration {
                isImporting = false
                selectedItems = []
            }
        }

        do {
            var newScreenshots: [ImportedScreenshot] = []
            for item in items {
                if let data = try await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    guard generation == importGeneration else { return }
                    newScreenshots.append(ImportedScreenshot(data: data, image: image))
                }
            }
            guard generation == importGeneration else { return }
            guard !newScreenshots.isEmpty else {
                statusText = "还没有选择截图。"
                return
            }

            let availableSlots = max(0, 8 - importedScreenshots.count)
            let screenshotsToAppend = Array(newScreenshots.prefix(availableSlots))
            importedScreenshots.append(contentsOf: screenshotsToAppend)
            statusText = "当前已导入 \(importedScreenshots.count) 张截图。请确认预览顺序后点击“拼接保存”。"
            if screenshotsToAppend.count < newScreenshots.count {
                statusText = "最多只能导入 8 张截图，已保留前 8 张。"
            }
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
    private func removeScreenshot(id: UUID) {
        importedScreenshots.removeAll { $0.id == id }
        statusText = importedScreenshots.isEmpty
            ? "已清空截图，请重新导入。"
            : "已删除截图，当前还有 \(importedScreenshots.count) 张。"
    }

    @MainActor
    private func processCurrentScreenshots(resizeMismatchedWidthsToFirst: Bool = false) async {
        guard importedScreenshots.count >= 2 else {
            statusText = "请至少导入 2 张有重叠区域的截图。"
            return
        }

        if hasMismatchedWidths(), !resizeMismatchedWidthsToFirst {
            showWidthMismatchAlert = true
            return
        }

        isProcessing = true
        defer { isProcessing = false }

        var processingManifest: ImportSessionManifest?
        do {
            let granted = await photoSaver.requestAddOnlyAuthorization()
            guard granted else {
                statusText = "未获得相册保存权限，请在系统设置中允许保存照片。"
                return
            }

            let imageData = importedScreenshots.map(\.data)
            let store = try SandboxSessionStore()
            var manifest = try ImageImportStore(store: store).createSession(from: imageData)
            processingManifest = manifest

            let result = try await stitchLocally(
                manifest: manifest,
                store: store,
                resizeMismatchedWidthsToFirst: resizeMismatchedWidthsToFirst
            )
            let resultData = result.data
            manifest = result.manifest
            processingManifest = manifest

            try await photoSaver.saveJPEG(resultData)
            manifest.status = .saved
            try store.save(manifest)
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

    private func hasMismatchedWidths() -> Bool {
        guard let firstImage = importedScreenshots.first?.image,
              let firstWidth = normalizedPixelWidth(of: firstImage) else {
            return false
        }
        return importedScreenshots.contains { screenshot in
            guard let width = normalizedPixelWidth(of: screenshot.image) else {
                return false
            }
            return width != firstWidth
        }
    }

    private func normalizedPixelWidth(of image: UIImage) -> Int? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        switch image.imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return cgImage.height
        default:
            return cgImage.width
        }
    }

    @MainActor
    private func stitchLocally(
        manifest: ImportSessionManifest,
        store: SandboxSessionStore,
        resizeMismatchedWidthsToFirst: Bool
    ) async throws -> (data: Data, manifest: ImportSessionManifest) {
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
            return try LocalSessionProcessor(store: detachedStore).stitch(
                manifest: manifestToStitch,
                resizeMismatchedWidthsToFirst: resizeMismatchedWidthsToFirst
            )
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

private struct ImportedScreenshot: Identifiable {
    let id = UUID()
    let data: Data
    let image: UIImage
}
