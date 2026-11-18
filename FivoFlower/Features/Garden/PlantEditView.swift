import SwiftUI
import PhotosUI

enum PlantEditMode {
    case create
    case edit(UUID)

    var isEditing: Bool {
        if case .edit = self { return true }
        return false
    }
}

struct PlantEditView: View {
    let mode: PlantEditMode
    var initialName: String = ""
    var onFinish: (() -> Void)?

    init(mode: PlantEditMode, initialName: String = "", onFinish: (() -> Void)? = nil) {
        self.mode = mode
        self.initialName = initialName
        self.onFinish = onFinish
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var draft = PlantDraft()
    @State private var originalDraft = PlantDraft()
    @State private var hasAcquiredDate = false
    @State private var hasInitialStageDate = false
    @State private var coverItem: PhotosPickerItem?
    @State private var coverPayload: ImagePayload?
    @State private var coverEditorImage: UIImage?
    @State private var showCoverEditor = false
    @State private var existingCoverPath: String?
    @State private var stages: [GrowthStage] = []
    @State private var errors: [PlantFieldError] = []
    @State private var generalError: String?
    @State private var isSaving = false
    @State private var showDiscardConfirm = false
    @State private var hasAutoLedger = false
    @State private var generatePurchaseLedger = false
    @State private var syncPurchaseLedger = false
    @State private var originalPlant: Plant?

    private var hasChanges: Bool {
        draft != originalDraft || coverPayload != nil || generatePurchaseLedger
    }

    private var nameError: String? {
        errors.contains(.nameRequired) ? PlantFieldError.nameRequired.message : nil
    }

    private var priceError: String? {
        errors.contains(.priceInvalid) ? PlantFieldError.priceInvalid.message : nil
    }

    private var urlError: String? {
        errors.contains(.urlInvalid) ? PlantFieldError.urlInvalid.message : nil
    }

    private var dateError: String? {
        errors.contains(.dateInFuture) ? PlantFieldError.dateInFuture.message : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: FivoSpacing.md) {
                if mode.isEditing && hasAutoLedger && originalPlant?.purchasePrice != draft.purchasePrice {
                    infoBanner(
                        text: "修改入手价不会自动改账本。需要同步时请打开下方开关。",
                        systemImage: "info.circle"
                    )
                }

                basicCard
                purchaseCard
                if !mode.isEditing {
                    initialStageCard
                }
                environmentCard
                otherCard
                coverCard
            }
            .padding(FivoSpacing.page)
            .padding(.bottom, 90)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle(mode.isEditing ? "编辑植物" : "添加植物")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("取消") {
                    if hasChanges {
                        showDiscardConfirm = true
                    } else {
                        dismiss()
                    }
                }
                .accessibilityIdentifier("plant.cancel")
            }
        }
        .safeAreaInset(edge: .bottom) {
            GoldPrimaryButton(
                title: mode.isEditing ? "保存修改" : "创建植物档案",
                systemImage: "checkmark",
                isLoading: isSaving
            ) {
                save()
            }
            .padding(.horizontal, FivoSpacing.page)
            .padding(.vertical, FivoSpacing.xs)
            .background(.ultraThinMaterial)
            .accessibilityIdentifier("plant.saveButton")
        }
        .interactiveDismissDisabled(hasChanges)
        .confirmationDialog("放弃未保存的修改？", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("放弃修改", role: .destructive) { dismiss() }
            Button("继续编辑", role: .cancel) {}
        }
        .alert("保存失败", isPresented: Binding(
            get: { generalError != nil },
            set: { if !$0 { generalError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(generalError ?? "")
        }
        .task { load() }
        .onChange(of: coverItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    coverItem = nil
                    coverEditorImage = image
                    showCoverEditor = true
                }
            }
        }
        .fullScreenCover(isPresented: $showCoverEditor, onDismiss: { coverEditorImage = nil }) {
            if let coverEditorImage {
                CoverCropView(image: coverEditorImage) { data in
                    coverPayload = ImagePayload(data: data, capturedAt: Date())
                }
            }
        }
        .onChange(of: hasAcquiredDate) { _, newValue in
            if !newValue {
                draft.acquiredAt = nil
            } else if draft.acquiredAt == nil {
                draft.acquiredAt = Date()
            }
        }
        .onChange(of: hasInitialStageDate) { _, newValue in
            if newValue {
                draft.initialStageStartedAt = draft.initialStageStartedAt ?? Date()
            } else {
                draft.initialStageStartedAt = nil
            }
        }
    }

    // MARK: - Sections

    private var basicCard: some View {
        formCard(title: "基本信息") {
            SoftTextField(
                label: "品种名称",
                text: $draft.name,
                placeholder: "必填，例如：白锦龟背竹",
                error: nameError,
                identifier: "plant.nameField"
            )
            SoftTextField(label: "别名", text: $draft.alias, placeholder: "选填")
            SoftTextField(label: "植物编号", text: $draft.plantCode, placeholder: "选填，如 F-001")
            SoftTextField(label: "规格", text: $draft.specification, placeholder: "选填，如 14cm 盆")
        }
    }

    private var purchaseCard: some View {
        formCard(title: "购买信息") {
            Toggle("填写购买日期", isOn: $hasAcquiredDate)
                .font(FivoFont.callout)
                .tint(FivoColor.accentEnd)
            if hasAcquiredDate {
                DatePicker(
                    "购买日期",
                    selection: Binding(
                        get: { draft.acquiredAt ?? Date() },
                        set: { draft.acquiredAt = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .font(FivoFont.callout)
                .datePickerStyle(.compact)
            }
            if let dateError {
                Label(dateError, systemImage: "exclamationmark.circle")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.danger)
            }
            SoftTextField(
                label: "入手价（元）",
                text: $draft.purchasePriceText,
                placeholder: "选填，最多两位小数",
                keyboard: .decimalPad,
                error: priceError,
                identifier: "plant.priceField"
            )
            SoftTextField(label: "平台", text: $draft.platform, placeholder: "选填，如 淘宝 / 闲鱼")
            SoftTextField(label: "店铺", text: $draft.storeName, placeholder: "选填")
            SoftTextField(
                label: "来源链接",
                text: $draft.sourceURL,
                placeholder: "选填，以 http:// 或 https:// 开头",
                keyboard: .URL,
                error: urlError
            )

            if !mode.isEditing {
                Toggle("同时生成采购账目", isOn: $generatePurchaseLedger)
                    .font(FivoFont.callout)
                    .tint(FivoColor.accentEnd)
                    .accessibilityIdentifier("plant.generatePurchaseLedger")
                if generatePurchaseLedger {
                    Text((draft.purchasePrice ?? 0) > 0
                         ? "将按购买日期、入手价、平台和店名生成植物采购支出。"
                         : "请填写大于 0 的入手价；金额为空或为 0 时不会生成账目。")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
            }

            if mode.isEditing && hasAutoLedger && originalPlant?.purchasePrice != draft.purchasePrice {
                Toggle("同步更新关联采购账目", isOn: $syncPurchaseLedger)
                    .font(FivoFont.callout)
                    .tint(FivoColor.accentEnd)
            }
        }
    }

    private var initialStageCard: some View {
        formCard(title: "初始生长状态") {
            Text("新档案默认从养叶养根开始，可在详情页随时切换。")
                .font(FivoFont.caption)
                .foregroundStyle(FivoColor.textSecondary)
            Picker("初始状态", selection: $draft.initialStageKey) {
                ForEach(stages) { stage in
                    Text(stage.name).tag(stage.key)
                }
            }
            .pickerStyle(.menu)
            .tint(FivoColor.textPrimary)

            Toggle("设置开始日期", isOn: $hasInitialStageDate)
                .font(FivoFont.callout)
                .tint(FivoColor.accentEnd)
                .accessibilityIdentifier("plant.hasInitialStageDate")
            if hasInitialStageDate {
                DatePicker(
                    "开始日期",
                    selection: Binding(
                        get: { draft.initialStageStartedAt ?? Date() },
                        set: { draft.initialStageStartedAt = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .font(FivoFont.callout)
                .datePickerStyle(.compact)
                .accessibilityIdentifier("plant.initialStageDate")
            } else {
                Text("开始日期为创建当天")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
            }
        }
    }

    private var environmentCard: some View {
        formCard(title: "养护环境") {
            SoftTextField(label: "植料", text: $draft.medium, placeholder: "选填，如 水苔 / 泥炭")
            SoftTextField(label: "摆放位置", text: $draft.location, placeholder: "选填，如 阳台东侧")
        }
    }

    private var otherCard: some View {
        formCard(title: "其他信息") {
            SoftTextField(
                label: "备注",
                text: $draft.notes,
                placeholder: "选填",
                axis: .vertical,
                lineLimit: 3...8
            )
        }
    }

    private var coverCard: some View {
        formCard(title: "封面照片") {
            HStack(spacing: FivoSpacing.md) {
                Group {
                    if let coverPayload {
                        StoredImagePreview(data: coverPayload.data)
                    } else if let existingCoverPath {
                        StoredImage(relativePath: existingCoverPath, imageStore: env.imageStore)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(FivoColor.surfaceInset)
                            .overlay {
                                Image(systemName: "leaf")
                                    .foregroundStyle(FivoColor.textSecondary)
                            }
                    }
                }
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: FivoSpacing.xs) {
                    PhotosPicker(selection: $coverItem, matching: .images) {
                        Text(coverPayload == nil && existingCoverPath == nil ? "选择封面" : "更换封面")
                            .font(FivoFont.callout.weight(.semibold))
                            .foregroundStyle(FivoColor.textPrimary)
                            .padding(.horizontal, FivoSpacing.md)
                            .frame(minHeight: 40)
                            .background(FivoColor.surfaceElevated, in: Capsule())
                    }
                    if coverPayload != nil {
                        Button("取消更换") {
                            coverPayload = nil
                            coverItem = nil
                        }
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                    }
                    Text("选择后可拖动裁剪，或使用本地自动抠图；不会修改原图。")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func formCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            Text(title)
                .font(FivoFont.sectionTitle)
                .foregroundStyle(FivoColor.textPrimary)
            VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                content()
            }
        }
        .softCard()
    }

    private func infoBanner(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(FivoFont.caption)
            .foregroundStyle(FivoColor.textSecondary)
            .padding(FivoSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(FivoColor.accentStart.opacity(0.25), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: - Data

    private func load() {
        guard stages.isEmpty else { return }
        stages = (try? env.growth.stages(includeDisabled: false)) ?? []
        if case .edit(let id) = mode, let plant = env.plant(id: id) {
            originalPlant = plant
            draft = PlantDraft(plant: plant)
            originalDraft = draft
            hasAcquiredDate = plant.acquiredAt != nil
            existingCoverPath = env.coverPath(for: plant)
            let entries = (try? env.ledger.entries(plantID: id)) ?? []
            hasAutoLedger = entries.contains { $0.sourceType == .plant }
        } else {
            if draft.name.isEmpty && !initialName.isEmpty {
                draft.name = initialName
            }
            originalDraft = draft
        }
    }

    private func save() {
        errors = PlantValidator.validate(draft, now: Date())
        guard errors.isEmpty else { return }
        isSaving = true
        do {
            switch mode {
            case .create:
                var options = PlantCreationOptions()
                options.initialStageKey = draft.initialStageKey
                options.initialStageStartedAt = draft.initialStageStartedAt
                options.coverPhoto = coverPayload
                if generatePurchaseLedger, let price = draft.purchasePrice, price > 0 {
                    var ledger = LedgerDraft()
                    ledger.amountText = draft.purchasePriceText
                    ledger.occurredAt = draft.acquiredAt ?? Date()
                    ledger.platform = draft.platform
                    ledger.storeName = draft.storeName
                    ledger.generateLedger = true
                    options.ledgerDraft = ledger
                }
                _ = try env.plants.createPlant(draft: draft, options: options)
                if generatePurchaseLedger && (draft.purchasePrice ?? 0) <= 0 {
                    env.showToast("已创建植物档案，未生成零金额采购账目")
                } else {
                    env.showToast("已创建植物档案")
                }
            case .edit(let id):
                _ = try env.plants.updatePlant(id: id, draft: draft, syncPurchaseLedger: syncPurchaseLedger)
                if let coverPayload {
                    _ = try env.photos.replaceCover(plantID: id, payload: coverPayload)
                }
                env.showToast("已保存修改")
            }
            if let onFinish {
                onFinish()
            } else {
                dismiss()
            }
        } catch {
            generalError = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Preview helper

struct StoredImagePreview: View {
    let data: Data

    var body: some View {
        Color.clear
            .overlay {
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    FivoColor.surfaceInset
                }
            }
            .clipped()
    }
}
