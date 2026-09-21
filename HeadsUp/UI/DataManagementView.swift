import SwiftUI
import UniformTypeIdentifiers
import UIKit

@MainActor
private final class DataManagementModel: ObservableObject {
    @Published private(set) var prepared: UsageDataExport?
    @Published private(set) var isPreparing = false
    @Published private(set) var isClearing = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    var isBusy: Bool { isPreparing || isClearing }

    func prepare() async {
        guard !isBusy else { return }
        isPreparing = true
        prepared = nil
        statusMessage = nil
        defer { isPreparing = false }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        do {
            let source = try await UsageStore.shared.exportSnapshot()
            prepared = try await Task.detached(priority: .userInitiated) {
                try UsageDataExporter.make(
                    database: source.database,
                    preferences: source.preferences,
                    pausedUntil: source.pausedUntil,
                    exportedAt: source.exportedAt,
                    timeZoneIdentifier: source.timeZoneIdentifier,
                    appVersion: version,
                    buildNumber: build
                )
            }.value
        } catch {
            errorMessage = "暂时无法准备数据：\(error.localizedDescription)"
        }
    }

    func copy() {
        guard !isBusy, let text = prepared?.copyText else { return }
        UIPasteboard.general.setItems(
            [[UTType.utf8PlainText.identifier: text]],
            options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(10 * 60)]
        )
        statusMessage = "已复制，可粘贴给 AI 分析。剪贴板内容 10 分钟后失效。"
    }

    func clearRecords() async {
        guard !isBusy else { return }
        isClearing = true
        do {
            try await UsageStore.shared.reset()
            prepared = nil
            isClearing = false
            await prepare()
            statusMessage = "本机使用记录已清空，计时设置与界面选择已保留。"
        } catch {
            isClearing = false
            prepared = nil
            errorMessage = "清空未完成：\(error.localizedDescription)"
        }
    }
}

/// Shared by both interfaces. This screen always operates on real local data.
struct DataManagementView: View {
    @StateObject private var model = DataManagementModel()
    @State private var showClearConfirmation = false
    @State private var showFileExporter = false
    @State private var document = UsageJSONDocument(data: Data())
    @State private var filename = "heads-up-data"

    var body: some View {
        List {
            Section {
                Label("本机真实记录", systemImage: "internaldrive")
                    .font(.headline)
                if let export = model.prepared {
                    LabeledContent("事件", value: "\(export.recordCounts.events) 条")
                    LabeledContent("使用时段", value: "\(export.recordCounts.segments) 段")
                    LabeledContent("计时轮次", value: "\(export.recordCounts.rounds) 轮")
                    LabeledContent("导出大小", value: sizeText(export.byteCount))
                    LabeledContent("快照时间", value: export.exportedAt.formatted(date: .abbreviated, time: .standard))
                } else if model.isPreparing {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在准备数据…").foregroundStyle(.secondary)
                    }
                } else {
                    Text("尚未准备导出数据，请点右上角刷新。")
                        .foregroundStyle(.secondary)
                }
            } header: { Text("数据概览") } footer: {
                Text("仅本机真实记录，不含未来版示例。点刷新可获取最新快照。")
            }

            Section {
                Button { model.copy() } label: {
                    Label("复制数据", systemImage: "doc.on.doc")
                        .foregroundStyle(model.prepared?.canCopy == true && !model.isBusy ? Color.accentColor : Color.secondary)
                }
                .disabled(model.isBusy || model.prepared?.canCopy != true)
                .accessibilityIdentifier("data.copy")

                Button {
                    guard let export = model.prepared, !model.isBusy else { return }
                    document = UsageJSONDocument(data: export.data)
                    filename = (export.suggestedFilename as NSString).deletingPathExtension
                    showFileExporter = true
                } label: {
                    Label("导出 JSON 文件", systemImage: "square.and.arrow.up")
                }
                .disabled(model.isBusy || model.prepared == nil)
                .accessibilityIdentifier("data.export")
            } header: { Text("导出给 AI") } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    if model.prepared?.canCopy == false {
                        Text("数据较多，无法直接复制。请导出 JSON 文件后上传给 AI。")
                            .foregroundStyle(.primary)
                    } else {
                        Text("复制后可直接粘贴给 AI；也可以导出文件保存或上传。")
                    }
                    Text("JSON（UTF-8）包含完整记录、字段说明与数据局限。应用内复制上限为 100 KB，文件导出不截断数据。")
                    Text("数据只在本机准备，不会自动上传。复制仅限本机，10 分钟后失效；上传前请确认内容可以分享。")
                }
            }

            if let message = model.statusMessage {
                Section {
                    Label(message, systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("data.status")
                }
            }

            Section {
                Button(role: .destructive) { showClearConfirmation = true } label: {
                    Label(model.isClearing ? "正在清空…" : "清空使用数据", systemImage: "trash")
                }
                .disabled(model.isBusy || showFileExporter)
                .accessibilityIdentifier("data.clear")
            } header: { Text("重置数据") } footer: {
                Text("删除本机使用记录、当前计时轮次与自动保存的恢复副本，并移除提醒。保留计时设置、暂停状态、界面选择和快捷指令。已复制或自行导出的副本不会删除。")
            }
        }
        .navigationTitle("数据管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await model.prepare() } } label: {
                    Label("刷新数据", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy || showFileExporter)
                .accessibilityIdentifier("data.refresh")
            }
        }
        .task { await model.prepare() }
        .confirmationDialog("清空所有使用数据？", isPresented: $showClearConfirmation, titleVisibility: .visible) {
            Button("清空使用数据", role: .destructive) { Task { await model.clearRecords() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销，建议先导出备份。将删除本机记录、当前计时轮次和恢复副本，并移除提醒；计时设置、暂停状态和界面选择保留。\n\n清空后，快捷指令仍可继续产生新记录。")
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: document,
            contentType: .json,
            defaultFilename: filename
        ) { result in
            switch result {
            case .success:
                model.statusMessage = "JSON 文件已导出，可上传给 AI 分析。"
            case .failure(let error):
                if (error as NSError).code != CocoaError.userCancelled.rawValue {
                    model.errorMessage = "文件未导出：\(error.localizedDescription)"
                }
            }
        }
        .alert("数据管理", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) { Button("好", role: .cancel) { model.errorMessage = nil } }
        message: { Text(model.errorMessage ?? "") }
    }

    private func sizeText(_ bytes: Int) -> String {
        "\(ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .decimal))（\(bytes) 字节）"
    }
}

private struct UsageJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
