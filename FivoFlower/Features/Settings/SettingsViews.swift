import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var notificationStatus: NotificationAuthorization = .notDetermined
    @State private var showPrivacy = false
    @State private var showClearConfirm = false
    @State private var exportFile: ExportFile?
    @State private var message: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FivoSpacing.md) {
                    settingsCard(title: "提醒") {
                        HStack {
                            Text("系统通知")
                                .font(FivoFont.callout)
                                .foregroundStyle(FivoColor.textPrimary)
                            Spacer()
                            StatusPill(
                                text: notificationText,
                                tint: notificationStatus == .authorized ? FivoColor.success : FivoColor.textSecondary
                            )
                        }
                        if notificationStatus == .denied {
                            Button("打开系统设置") {
                                if let url = URL(string: UIApplication.openSettingsURLString) {
                                    UIApplication.shared.open(url)
                                }
                            }
                            .font(FivoFont.captionStrong)
                            .foregroundStyle(FivoColor.textPrimary)
                        }
                        Text("未开启通知时不会推送提醒，待办仍可在「养护日历」查看。")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }

                    settingsCard(title: "自定义类型") {
                        NavigationLink {
                            CareTypeManagementView()
                        } label: {
                            settingsRow(title: "养护类型", systemImage: "drop")
                        }
                        .buttonStyle(.plain)
                        NavigationLink {
                            GrowthStageManagementView()
                        } label: {
                            settingsRow(title: "生长状态", systemImage: "camera.macro")
                        }
                        .buttonStyle(.plain)
                    }

                    settingsCard(title: "数据管理") {
                        NavigationLink {
                            BackupRestoreView()
                        } label: {
                            settingsRow(title: "备份与恢复", systemImage: "externaldrive")
                        }
                        .buttonStyle(.plain)
                        Button {
                            exportPlants()
                        } label: {
                            settingsRow(title: "导出植物 CSV", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)
                        Button {
                            exportLedger()
                        } label: {
                            settingsRow(title: "导出账本 CSV", systemImage: "square.and.arrow.up.on.square")
                        }
                        .buttonStyle(.plain)
                        Button {
                            do {
                                try env.imports.clearUnfinishedImports()
                                message = "已清除未完成的识别缓存。"
                            } catch {
                                message = error.localizedDescription
                            }
                        } label: {
                            settingsRow(title: "清除未完成导入缓存", systemImage: "arrow.counterclockwise")
                        }
                        .buttonStyle(.plain)
                        Button {
                            showClearConfirm = true
                        } label: {
                            settingsRow(title: "清空全部数据", systemImage: "trash", destructive: true)
                        }
                        .buttonStyle(.plain)
                        Text("CSV 使用 UTF-8 编码，可正确处理中文、逗号、引号和换行。")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }

                    settingsCard(title: "隐私与关于") {
                        Button {
                            showPrivacy = true
                        } label: {
                            settingsRow(title: "隐私说明", systemImage: "lock.shield")
                        }
                        .buttonStyle(.plain)
                        Button {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            settingsRow(title: "系统权限设置", systemImage: "gear.badge")
                        }
                        .buttonStyle(.plain)
                        settingsRow(
                            title: "版本",
                            systemImage: "info.circle",
                            detail: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
                        )
                        if let warning = env.persistenceWarning {
                            Label(warning, systemImage: "exclamationmark.triangle")
                                .font(FivoFont.caption)
                                .foregroundStyle(FivoColor.danger)
                        }
                        #if DEBUG
                        NavigationLink {
                            DesignSystemGalleryView()
                        } label: {
                            settingsRow(title: "设计系统预览", systemImage: "paintpalette")
                        }
                        .buttonStyle(.plain)
                        #endif
                        Text("FIVO 的花花 · 本地优先，无账号，无第三方行为分析 SDK。")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }

                    if let message {
                        Text(message)
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                }
                .padding(FivoSpacing.page)
                .padding(.bottom, 40)
            }
            .background(FivoColor.surfaceBase)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .task {
                notificationStatus = await env.notifications.authorizationStatus()
            }
            .sheet(isPresented: $showPrivacy) {
                NavigationStack { PrivacyPolicyView() }
            }
            .sheet(item: $exportFile) { file in
                ShareSheet(url: file.url)
            }
            .confirmationDialog("清空全部数据？", isPresented: $showClearConfirm, titleVisibility: .visible) {
                Button("清空全部数据", role: .destructive) { clearAll() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将删除所有植物、照片、日志、养护、提醒、工具和账目，并清理本地媒体文件。建议先创建备份。此操作不可撤销。")
            }
        }
    }

    private var notificationText: String {
        switch notificationStatus {
        case .notDetermined: return "未询问"
        case .denied: return "已拒绝"
        case .authorized: return "已开启"
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            Text(title)
                .font(FivoFont.sectionTitle)
                .foregroundStyle(FivoColor.textPrimary)
            VStack(alignment: .leading, spacing: FivoSpacing.xs) {
                content()
            }
        }
        .softCard()
    }

    private func settingsRow(
        title: String,
        systemImage: String,
        detail: String? = nil,
        destructive: Bool = false
    ) -> some View {
        HStack(spacing: FivoSpacing.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(destructive ? FivoColor.danger : FivoColor.textPrimary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(FivoColor.surfaceInset))
            Text(title)
                .font(FivoFont.callout)
                .foregroundStyle(destructive ? FivoColor.danger : FivoColor.textPrimary)
            Spacer()
            if let detail {
                Text(detail)
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FivoColor.textSecondary.opacity(0.6))
        }
        .frame(minHeight: 40)
        .contentShape(Rectangle())
    }

    private func exportPlants() {
        do {
            let plants = try env.plants.fetchPlants()
            let now = Date()
            let categories = Dictionary(uniqueKeysWithValues: plants.map {
                ($0.id, env.gardenQuery.category(for: $0, now: now))
            })
            let url = try env.csv.exportPlantsCSV(plants: plants, categories: categories)
            exportFile = ExportFile(url: url)
        } catch {
            message = error.localizedDescription
        }
    }

    private func exportLedger() {
        do {
            let entries = try env.ledger.entries()
            let plants = try env.plants.fetchPlants()
            let tools = try env.tools.tools()
            let plantNames = Dictionary(uniqueKeysWithValues: plants.map { ($0.id, $0.name) })
            let toolNames = Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0.name) })
            let url = try env.csv.exportLedgerCSV(
                entries: entries,
                plantNames: plantNames,
                toolNames: toolNames
            )
            exportFile = ExportFile(url: url)
        } catch {
            message = error.localizedDescription
        }
    }

    private func clearAll() {
        do {
            try env.dataStore.clearAllData()
            Task { await env.notifications.reconcile([]) }
            env.showToast("已清空全部数据")
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Care type management

struct CareTypeManagementView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var types: [CareActionType] = []
    @State private var showAdd = false
    @State private var newName = ""
    @State private var editing: CareActionType?
    @State private var editName = ""
    @State private var pendingDelete: CareActionType?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                ForEach(types) { type in
                    HStack(spacing: FivoSpacing.sm) {
                        Image(systemName: type.systemImage)
                            .foregroundStyle(FivoColor.textPrimary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(type.name)
                                .font(FivoFont.callout)
                                .foregroundStyle(FivoColor.textPrimary)
                            if type.isBuiltIn {
                                Text("内置")
                                    .font(FivoFont.caption)
                                    .foregroundStyle(FivoColor.textSecondary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { type.isEnabled },
                            set: { newValue in
                                do {
                                    try env.care.setActionTypeEnabled(id: type.id, enabled: newValue)
                                    load()
                                } catch {
                                    message = error.localizedDescription
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(FivoColor.accentEnd)
                    }
                    .swipeActions {
                        if !type.isBuiltIn {
                            Button(role: .destructive) {
                                pendingDelete = type
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                editing = type
                                editName = type.name
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                        }
                    }
                }
                .onMove(perform: move)
            } footer: {
                Text("内置类型可停用但不能删除；自定义类型删除后，历史记录仍保留当时的名称。长按拖动或点击右上角“编辑”可调整顺序。")
                    .font(FivoFont.caption)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FivoColor.surfaceBase)
        .navigationTitle("养护类型")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增养护类型")
            }
        }
        .task { load() }
        .alert("新增养护类型", isPresented: $showAdd) {
            TextField("名称", text: $newName)
            Button("添加") {
                do {
                    _ = try env.care.addActionType(name: newName)
                    load()
                } catch {
                    message = error.localizedDescription
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名", isPresented: Binding(
            get: { editing != nil },
            set: { if !$0 { editing = nil } }
        )) {
            TextField("名称", text: $editName)
            Button("保存") {
                if let editing {
                    do {
                        try env.care.renameActionType(id: editing.id, name: editName)
                        load()
                    } catch {
                        message = error.localizedDescription
                    }
                }
                editing = nil
            }
            Button("取消", role: .cancel) { editing = nil }
        }
        .confirmationDialog("删除养护类型？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let type = pendingDelete {
                    do {
                        try env.care.deleteActionType(id: type.id)
                        load()
                    } catch {
                        message = error.localizedDescription
                    }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
        .alert("操作失败", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func load() {
        types = (try? env.care.actionTypes(includeDisabled: true)) ?? []
    }

    private func move(from source: IndexSet, to destination: Int) {
        let previous = types
        var updated = types
        updated.move(fromOffsets: source, toOffset: destination)
        types = updated
        do {
            try env.care.reorderActionTypes(ids: updated.map(\.id))
            load()
        } catch {
            types = previous
            message = error.localizedDescription
        }
    }
}

// MARK: - Growth stage management

struct GrowthStageManagementView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var stages: [GrowthStage] = []
    @State private var showAdd = false
    @State private var newName = ""
    @State private var editing: GrowthStage?
    @State private var editName = ""
    @State private var pendingDelete: GrowthStage?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                ForEach(stages) { stage in
                    HStack(spacing: FivoSpacing.sm) {
                        Image(systemName: "camera.macro")
                            .foregroundStyle(FivoColor.textPrimary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stage.name)
                                .font(FivoFont.callout)
                                .foregroundStyle(FivoColor.textPrimary)
                            if stage.isBuiltIn {
                                Text("内置")
                                    .font(FivoFont.caption)
                                    .foregroundStyle(FivoColor.textSecondary)
                            }
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { stage.isEnabled },
                            set: { newValue in
                                do {
                                    try env.growth.setStageEnabled(key: stage.key, enabled: newValue)
                                    load()
                                } catch {
                                    message = error.localizedDescription
                                }
                            }
                        ))
                        .labelsHidden()
                        .tint(FivoColor.accentEnd)
                    }
                    .swipeActions {
                        if !stage.isBuiltIn {
                            Button(role: .destructive) {
                                pendingDelete = stage
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                editing = stage
                                editName = stage.name
                            } label: {
                                Label("重命名", systemImage: "pencil")
                            }
                        }
                    }
                }
            } footer: {
                Text("同一株植物同一时间只有一个进行中状态；已有历史记录的自定义状态只能停用。")
                    .font(FivoFont.caption)
            }
        }
        .scrollContentBackground(.hidden)
        .background(FivoColor.surfaceBase)
        .navigationTitle("生长状态")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    showAdd = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("新增生长状态")
            }
        }
        .task { load() }
        .alert("新增生长状态", isPresented: $showAdd) {
            TextField("名称", text: $newName)
            Button("添加") {
                do {
                    _ = try env.growth.addStage(name: newName)
                    load()
                } catch {
                    message = error.localizedDescription
                }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("重命名", isPresented: Binding(
            get: { editing != nil },
            set: { if !$0 { editing = nil } }
        )) {
            TextField("名称", text: $editName)
            Button("保存") {
                if let editing {
                    do {
                        try env.growth.renameStage(key: editing.key, name: editName)
                        load()
                    } catch {
                        message = error.localizedDescription
                    }
                }
                editing = nil
            }
            Button("取消", role: .cancel) { editing = nil }
        }
        .confirmationDialog("删除生长状态？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let stage = pendingDelete {
                    do {
                        try env.growth.deleteStage(key: stage.key)
                        load()
                    } catch {
                        message = error.localizedDescription
                    }
                }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
        }
        .alert("操作失败", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func load() {
        stages = (try? env.growth.stages(includeDisabled: true)) ?? []
    }
}

// MARK: - Privacy

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                section(
                    title: "本地优先",
                    text: "FIVO 的花花不需要账号。植物、照片、日志、工具和账目默认仅保存在本机，不接入第三方行为分析 SDK。iCloud 云盘备份为可选功能，需你主动开启。"
                )
                section(
                    title: "照片与相机",
                    text: "仅在拍摄植物或记录养护时申请相机权限；优先使用 PhotosPicker 选择照片，避免申请完整相册权限。选择的照片保存在 App 沙盒内。"
                )
                section(
                    title: "通知",
                    text: "在创建第一条养护提醒时申请通知权限。未授权时不会推送提醒，待办仍可在「养护日历」查看，并引导你到系统设置开启。"
                )
                section(
                    title: "网络与第三方服务",
                    text: "除你主动启用的 iCloud 云盘备份外，本 App 不发起任何网络请求，不接入第三方行为分析 SDK，不上传植物、照片、日志或账目数据。"
                )
                section(
                    title: "备份",
                    text: "备份包含业务数据、照片和版本信息，不包含系统通知标识。本地备份文件由你自行保管；启用 iCloud 云盘备份后，备份包只写入你本人的 iCloud，可在「文件」App 中查看与删除。"
                )
                Text("如需删除全部本地数据，可在设置中执行“清空全部数据”。")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
            }
            .padding(FivoSpacing.page)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle("隐私说明")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
    }

    private func section(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: FivoSpacing.xs) {
            Text(title)
                .font(FivoFont.cardTitle)
                .foregroundStyle(FivoColor.textPrimary)
            Text(text)
                .font(FivoFont.callout)
                .foregroundStyle(FivoColor.textSecondary)
                .lineSpacing(3)
        }
        .softCard()
    }
}
