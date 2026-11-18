import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct BackupRestoreView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var backups: [URL] = []
    @State private var lastCreated: URL?
    @State private var pendingRestore: PendingRestore?
    @State private var cloudItems: [CloudBackupItem] = []
    @State private var cloudAvailability: CloudBackupAvailability = .ready
    @State private var pendingCloudDelete: CloudBackupItem?
    @State private var isCloudWorking = false
    @State private var isWorking = false
    @State private var showImporter = false
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isSuccess = false

    private var backupType: UTType {
        UTType(filenameExtension: "fivoflower") ?? .data
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    Text("创建备份")
                        .font(FivoFont.sectionTitle)
                        .foregroundStyle(FivoColor.textPrimary)
                    Text("备份包含全部业务数据、照片和 manifest 版本信息，不包含系统通知标识。")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                    GoldPrimaryButton(title: "生成 .fivoflower 备份", systemImage: "externaldrive.badge.plus", isLoading: isWorking) {
                        createBackup()
                    }
                    if let lastCreated {
                        ShareLink(item: lastCreated) {
                            Label("分享最新备份", systemImage: "square.and.arrow.up")
                                .font(FivoFont.callout.weight(.semibold))
                                .foregroundStyle(FivoColor.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(FivoColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        Text(lastCreated.lastPathComponent)
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                }
                .softCard()

                cloudBackupSection

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    Text("恢复备份")
                        .font(FivoFont.sectionTitle)
                        .foregroundStyle(FivoColor.textPrimary)
                    Text("恢复前会完整校验文件与版本，展示内容摘要，并自动生成当前数据的安全备份。首版采用整体替换，不做智能合并。")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                    SecondaryButton(title: "从文件选择备份", systemImage: "doc.badge.plus") {
                        showImporter = true
                    }
                }
                .softCard()

                if !backups.isEmpty {
                    VStack(alignment: .leading, spacing: FivoSpacing.xs) {
                        Text("本机备份")
                            .font(FivoFont.sectionTitle)
                            .foregroundStyle(FivoColor.textPrimary)
                        ForEach(backups, id: \.self) { url in
                            Button {
                                inspect(url: url)
                            } label: {
                                HStack(spacing: FivoSpacing.sm) {
                                    Image(systemName: "doc.zipper")
                                        .foregroundStyle(FivoColor.textPrimary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(url.lastPathComponent)
                                            .font(FivoFont.captionStrong)
                                            .foregroundStyle(FivoColor.textPrimary)
                                            .lineLimit(1)
                                        Text(fileInfo(url))
                                            .font(FivoFont.caption)
                                            .foregroundStyle(FivoColor.textSecondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundStyle(FivoColor.textSecondary)
                                }
                                .softCard(padding: FivoSpacing.sm)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.danger)
                        .softCard(padding: FivoSpacing.sm)
                }
                if let message {
                    Label(message, systemImage: isSuccess ? "checkmark.circle" : "info.circle")
                        .font(FivoFont.caption)
                        .foregroundStyle(isSuccess ? FivoColor.success : FivoColor.textSecondary)
                        .softCard(padding: FivoSpacing.sm)
                }
            }
            .padding(FivoSpacing.page)
            .padding(.bottom, 40)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isWorking || isCloudWorking {
                Color.black.opacity(0.12).ignoresSafeArea()
                ProgressView("处理中…")
                    .padding(FivoSpacing.lg)
                    .background(FivoColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .task {
            loadBackups()
            loadCloudBackups()
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [backupType, .zip],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                importExternal(url)
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "恢复此备份？",
            isPresented: Binding(
                get: { pendingRestore != nil },
                set: { if !$0 { pendingRestore = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("恢复并替换现有数据", role: .destructive) {
                if let pending = pendingRestore {
                    performRestore(pending)
                }
                pendingRestore = nil
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            if let pending = pendingRestore {
                Text(summaryText(pending.summary))
            }
        }
        .confirmationDialog(
            "删除这个云端备份？",
            isPresented: Binding(
                get: { pendingCloudDelete != nil },
                set: { if !$0 { pendingCloudDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let item = pendingCloudDelete { deleteCloud(item) }
                pendingCloudDelete = nil
            }
            Button("取消", role: .cancel) { pendingCloudDelete = nil }
        } message: {
            if let item = pendingCloudDelete {
                Text("将从 iCloud 云盘删除 \(item.fileName)，本机数据不受影响。")
            }
        }
    }

    // MARK: - iCloud 云盘备份

    @ViewBuilder
    private var cloudBackupSection: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            Text("iCloud 云盘备份")
                .font(FivoFont.sectionTitle)
                .foregroundStyle(FivoColor.textPrimary)
            Text("把同一份 .fivoflower 备份包写入你的 iCloud 云盘，可在「文件」App 查看，支持历史版本回滚与换机搬数据。只写入你本人的 iCloud，不经过任何服务端。")
                .font(FivoFont.caption)
                .foregroundStyle(FivoColor.textSecondary)

            if case .ready = cloudAvailability {
                Toggle(isOn: Binding(
                    get: { env.cloudBackup.isAutoBackupEnabled },
                    set: { env.cloudBackup.isAutoBackupEnabled = $0 }
                )) {
                    Text("退到后台时自动备份（每 24 小时最多一次）")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textPrimary)
                }
                .tint(FivoColor.textPrimary)

                GoldPrimaryButton(
                    title: "立即备份到 iCloud",
                    systemImage: "icloud.and.arrow.up",
                    isLoading: isCloudWorking
                ) {
                    createCloudBackup()
                }

                if let last = env.cloudBackup.lastBackupDate() {
                    Text("上次成功：\(FivoDate.dateTime(last))")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                } else {
                    Text("尚未成功备份到 iCloud。")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
            } else {
                Label(cloudUnavailableText, systemImage: "exclamationmark.icloud")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.danger)
                SecondaryButton(title: "打开系统设置", systemImage: "gearshape") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }

            if cloudAvailability == .ready, !cloudItems.isEmpty {
                Text("云端备份")
                    .font(FivoFont.captionStrong)
                    .foregroundStyle(FivoColor.textPrimary)
                    .padding(.top, FivoSpacing.xs)
                ForEach(cloudItems) { item in
                    HStack(spacing: FivoSpacing.sm) {
                        Button {
                            inspectCloud(item)
                        } label: {
                            HStack(spacing: FivoSpacing.sm) {
                                Image(systemName: item.isDownloaded ? "icloud" : "icloud.and.arrow.down")
                                    .foregroundStyle(FivoColor.textPrimary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.fileName)
                                        .font(FivoFont.captionStrong)
                                        .foregroundStyle(FivoColor.textPrimary)
                                        .lineLimit(1)
                                    Text(cloudItemInfo(item))
                                        .font(FivoFont.caption)
                                        .foregroundStyle(FivoColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(FivoColor.textSecondary)
                            }
                        }
                        .buttonStyle(.plain)

                        Button {
                            pendingCloudDelete = item
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(FivoColor.danger)
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除云端备份")
                    }
                    .softCard(padding: FivoSpacing.sm)
                }
            }
        }
        .softCard()
    }

    private var cloudUnavailableText: String {
        switch cloudAvailability {
        case .ready: return ""
        case .noAccount: return "未登录 iCloud，登录 Apple ID 后即可使用云端备份。本地备份不受影响。"
        case .driveDisabled: return "iCloud 云盘未开启，开启后即可使用云端备份。本地备份不受影响。"
        case .unavailable(let reason): return reason
        }
    }

    private func cloudItemInfo(_ item: CloudBackupItem) -> String {
        let date = FivoDate.dateTime(item.createdAt)
        let device = item.deviceName
        guard item.byteSize > 0 else { return "\(date) · \(device) · 待下载" }
        let size = ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file)
        return "\(date) · \(device) · \(size)"
    }

    private func loadCloudBackups() {
        cloudAvailability = env.cloudBackup.availability()
        guard cloudAvailability == .ready else {
            cloudItems = []
            return
        }
        do {
            cloudItems = try env.cloudBackup.listBackups()
        } catch {
            cloudItems = []
            errorMessage = error.localizedDescription
        }
    }

    private func createCloudBackup() {
        isCloudWorking = true
        errorMessage = nil
        do {
            let item = try env.cloudBackup.uploadBackup()
            loadCloudBackups()
            message = "已备份到 iCloud：\(item.fileName)"
            isSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            isSuccess = false
        }
        isCloudWorking = false
    }

    private func inspectCloud(_ item: CloudBackupItem) {
        isCloudWorking = true
        errorMessage = nil
        do {
            let local = try env.cloudBackup.prepareForRestore(item)
            let summary = try env.backup.inspectBackup(at: local)
            pendingRestore = PendingRestore(url: local, summary: summary)
        } catch {
            errorMessage = error.localizedDescription
        }
        isCloudWorking = false
    }

    private func deleteCloud(_ item: CloudBackupItem) {
        isCloudWorking = true
        do {
            try env.cloudBackup.deleteBackup(item)
            loadCloudBackups()
            message = "已删除云端备份：\(item.fileName)"
            isSuccess = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isCloudWorking = false
    }

    private func createBackup() {
        isWorking = true
        errorMessage = nil
        do {
            let url = try env.backup.createBackup()
            lastCreated = url
            loadBackups()
            message = "备份已生成：\(url.lastPathComponent)"
            isSuccess = true
        } catch {
            errorMessage = error.localizedDescription
            isSuccess = false
        }
        isWorking = false
    }

    private func inspect(url: URL) {
        isWorking = true
        errorMessage = nil
        do {
            let summary = try env.backup.inspectBackup(at: url)
            pendingRestore = PendingRestore(url: url, summary: summary)
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func importExternal(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("import-\(UUID().uuidString).fivoflower")
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: url, to: destination)
            inspect(url: destination)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performRestore(_ pending: PendingRestore) {
        isWorking = true
        errorMessage = nil
        do {
            let summary = try env.backup.restoreBackup(at: pending.url)
            Task { await env.reconcileNotifications() }
            message = "恢复完成：\(summary.plantCount) 株植物、\(summary.journalCount) 条日志、\(summary.photoCount) 张照片。"
            isSuccess = true
            loadBackups()
        } catch {
            errorMessage = error.localizedDescription
            isSuccess = false
        }
        isWorking = false
    }

    private func loadBackups() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let directory = documents?.appendingPathComponent("Backups", isDirectory: true)
        guard let directory,
              let contents = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
              ) else {
            backups = []
            return
        }
        backups = contents
            .filter { $0.pathExtension == "fivoflower" }
            .sorted { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    private func fileInfo(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let date = values?.contentModificationDate.map(FivoDate.dateTime) ?? ""
        let size = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
        return "\(date) · \(size)"
    }

    private func summaryText(_ summary: BackupSummary) -> String {
        """
        创建时间：\(FivoDate.dateTime(summary.createdAt))
        App 版本：\(summary.appVersion) · 备份格式 v\(summary.formatVersion)
        植物 \(summary.plantCount) 株 · 日志 \(summary.journalCount) 条 · 照片 \(summary.photoCount) 张 · 账目 \(summary.ledgerCount) 笔 · 工具 \(summary.toolCount) 个
        当前数据会先自动备份，再整体替换。
        """
    }
}

struct PendingRestore: Identifiable {
    let id = UUID()
    let url: URL
    let summary: BackupSummary
}
