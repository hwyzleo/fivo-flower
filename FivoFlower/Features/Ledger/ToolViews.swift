import SwiftUI
import PhotosUI

// MARK: - Tool editor

struct ToolEditView: View {
    let toolID: UUID?
    var onFinish: (() -> Void)?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ToolDraft()
    @State private var hasPurchasedDate = false
    @State private var photoItem: PhotosPickerItem?
    @State private var photoPayload: ImagePayload?
    @State private var existingPhotoPath: String?
    @State private var errors: [ToolFieldError] = []
    @State private var generalError: String?
    @State private var isSaving = false
    @State private var loaded = false

    private var isEditing: Bool { toolID != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    Picker("分类", selection: $draft.category) {
                        ForEach(ToolCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(FivoColor.textPrimary)

                    SoftTextField(
                        label: "名称",
                        text: $draft.name,
                        placeholder: "必填",
                        error: errors.contains(.nameRequired) ? ToolFieldError.nameRequired.message : nil,
                        identifier: "tool.nameField"
                    )
                    SoftTextField(label: "品牌", text: $draft.brand, placeholder: "选填")
                    SoftTextField(label: "规格", text: $draft.specification, placeholder: "选填")
                    SoftTextField(label: "数量", text: $draft.quantityText, placeholder: "1", keyboard: .numberPad)
                    SoftTextField(label: "位置", text: $draft.location, placeholder: "选填")
                }
                .softCard()

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    Toggle("填写购买日期", isOn: $hasPurchasedDate)
                        .font(FivoFont.callout)
                        .tint(FivoColor.accentEnd)
                    if hasPurchasedDate {
                        DatePicker(
                            "购买日期",
                            selection: Binding(
                                get: { draft.purchasedAt ?? Date() },
                                set: { draft.purchasedAt = $0 }
                            ),
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        .font(FivoFont.callout)
                    }
                    SoftTextField(
                        label: "价格（元）",
                        text: $draft.purchasePriceText,
                        placeholder: "选填，最多两位小数",
                        keyboard: .decimalPad,
                        error: errors.contains(.priceInvalid) ? ToolFieldError.priceInvalid.message : nil
                    )
                    if !isEditing {
                        Toggle("同时生成采购账目", isOn: $draft.generateLedger)
                            .font(FivoFont.callout)
                            .tint(FivoColor.accentEnd)
                    }
                }
                .softCard()

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    Toggle("消耗品（管理库存）", isOn: $draft.isConsumable)
                        .font(FivoFont.callout)
                        .tint(FivoColor.accentEnd)
                    if draft.isConsumable {
                        HStack(spacing: 8) {
                            SoftTextField(label: "当前库存", text: $draft.stockText, placeholder: "0", keyboard: .decimalPad)
                            SoftTextField(label: "单位", text: $draft.stockUnit, placeholder: "包")
                        }
                        Toggle("低库存提醒", isOn: $draft.lowStockEnabled)
                            .font(FivoFont.callout)
                            .tint(FivoColor.accentEnd)
                        if draft.lowStockEnabled {
                            SoftTextField(
                                label: "低库存阈值",
                                text: $draft.lowStockThresholdText,
                                placeholder: "例如：2",
                                keyboard: .decimalPad
                            )
                        }
                    }
                    if draft.category.isDeviceCandidate {
                        Toggle("作为设备记录状态", isOn: $draft.isDevice)
                            .font(FivoFont.callout)
                            .tint(FivoColor.accentEnd)
                        Text("仅记录本地使用中/关闭状态，不连接或控制真实设备。")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                }
                .softCard()

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    SoftTextField(
                        label: "备注",
                        text: $draft.notes,
                        placeholder: "选填",
                        axis: .vertical,
                        lineLimit: 2...5
                    )
                }
                .softCard()

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    Text("照片")
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(FivoColor.textSecondary)
                    HStack(spacing: FivoSpacing.md) {
                        Group {
                            if let photoPayload {
                                StoredImagePreview(data: photoPayload.data)
                            } else if let existingPhotoPath {
                                StoredImage(relativePath: existingPhotoPath, imageStore: env.imageStore)
                            } else {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(FivoColor.surfaceInset)
                                    .overlay {
                                        Image(systemName: "camera")
                                            .foregroundStyle(FivoColor.textSecondary)
                                    }
                            }
                        }
                        .frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Text(photoPayload == nil && existingPhotoPath == nil ? "选择照片" : "更换照片")
                                .font(FivoFont.callout.weight(.semibold))
                                .foregroundStyle(FivoColor.textPrimary)
                                .padding(.horizontal, FivoSpacing.md)
                                .frame(minHeight: 40)
                                .background(FivoColor.surfaceElevated, in: Capsule())
                        }
                        Spacer()
                    }
                }
                .softCard()
            }
            .padding(FivoSpacing.page)
            .padding(.bottom, 80)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle(isEditing ? "编辑工具" : "添加工具资材")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GoldPrimaryButton(title: isEditing ? "保存工具" : "添加工具", systemImage: "checkmark", isLoading: isSaving) {
                save()
            }
            .padding(.horizontal, FivoSpacing.page)
            .padding(.vertical, FivoSpacing.xs)
            .background(.ultraThinMaterial)
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
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    photoPayload = ImagePayload(data: data, capturedAt: Date())
                }
            }
        }
        .onChange(of: hasPurchasedDate) { _, newValue in
            if !newValue {
                draft.purchasedAt = nil
            } else if draft.purchasedAt == nil {
                draft.purchasedAt = Date()
            }
        }
    }


    private func load() {
        guard !loaded else { return }
        if let toolID, let tool = try? env.tools.tool(id: toolID) {
            draft = ToolDraft(tool: tool)
            hasPurchasedDate = tool.purchasedAt != nil
            existingPhotoPath = tool.photoRelativePath
        }
        loaded = true
    }

    private func save() {
        errors = ToolValidator.validate(draft)
        guard errors.isEmpty else { return }
        if draft.lowStockEnabled && draft.lowStockThreshold == nil {
            generalError = "开启低库存提醒时需要填写阈值。"
            return
        }
        isSaving = true
        do {
            if let toolID {
                _ = try env.tools.updateTool(id: toolID, draft: draft)
                if let photoPayload {
                    try env.tools.replacePhoto(toolID: toolID, payload: photoPayload)
                }
                env.showToast("已保存工具")
            } else {
                var ledger: LedgerDraft?
                if draft.generateLedger, let price = draft.purchasePrice, price > 0 {
                    var draftLedger = LedgerDraft()
                    draftLedger.kind = .expense
                    draftLedger.title = "工具采购：\(draft.trimmedName)"
                    draftLedger.amountText = FivoMoney.plainString(price)
                    draftLedger.occurredAt = draft.purchasedAt ?? Date()
                    draftLedger.category = draft.category == .medium ? .medium : .toolPurchase
                    ledger = draftLedger
                }
                _ = try env.tools.createTool(draft: draft, photo: photoPayload, ledgerDraft: ledger)
                env.showToast("已添加工具")
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

// MARK: - Tool detail

struct ToolDetailView: View {
    let toolID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var tool: ToolItem?
    @State private var adjustments: [StockAdjustment] = []
    @State private var ledgerEntries: [LedgerEntry] = []
    @State private var photos: [ToolPhoto] = []
    @State private var showEdit = false
    @State private var showStockAdjust = false
    @State private var showAddPhotos = false
    @State private var selectedPhoto: ToolPhoto?
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            if let tool {
                VStack(alignment: .leading, spacing: FivoSpacing.md) {
                    toolHeader(tool)
                    if tool.isDevice {
                        deviceSection(tool)
                    }
                    if tool.isConsumable {
                        stockSection(tool)
                    }
                    infoSection(tool)
                    photosSection
                    if tool.isConsumable && !adjustments.isEmpty {
                        historySection(tool)
                    }
                    ledgerSection(tool)
                }
                .fivoPagePadding()
                .padding(.bottom, 110)
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { load() }
                    .padding(FivoSpacing.page)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle(tool?.name ?? "工具详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { showEdit = true } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("编辑工具")
                Menu {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除工具", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .task { load() }
        .sheet(isPresented: $showEdit, onDismiss: load) {
            NavigationStack { ToolEditView(toolID: toolID) }
        }
        .sheet(isPresented: $showStockAdjust, onDismiss: load) {
            NavigationStack { StockAdjustmentSheet(toolID: toolID) }
        }
        .sheet(isPresented: $showAddPhotos, onDismiss: load) {
            NavigationStack { AddToolPhotosSheet(toolID: toolID) }
        }
        .fullScreenCover(item: $selectedPhoto, onDismiss: load) { photo in
            ToolPhotoViewer(toolID: toolID, initialPhotoID: photo.id)
        }
        .confirmationDialog("删除工具？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除工具", role: .destructive) { deleteTool() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("库存历史会删除；关联账目会保留并解除关联。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private func toolHeader(_ tool: ToolItem) -> some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            StoredImage(relativePath: tool.photoRelativePath, imageStore: env.imageStore)
                .frame(height: 230)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: FivoRadius.largeCard, style: .continuous))

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(tool.name)
                        .font(FivoFont.pageTitle)
                        .foregroundStyle(FivoColor.textPrimary)
                    Label(tool.category.title, systemImage: tool.category.symbolName)
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
                Spacer()
                if tool.isLowStock {
                    StatusPill(text: "低库存", systemImage: "exclamationmark.triangle", tint: FivoColor.danger)
                }
            }
        }
    }

    private func deviceSection(_ tool: ToolItem) -> some View {
        Toggle(isOn: Binding(
            get: { tool.isPoweredOn },
            set: { newValue in setPower(newValue) }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.isPoweredOn ? "使用中" : "已关闭")
                    .font(FivoFont.cardTitle)
                    .foregroundStyle(FivoColor.textPrimary)
                Text("仅记录本地状态，不连接或控制真实设备")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
            }
        }
        .tint(FivoColor.accentEnd)
        .softCard()
    }

    private func stockSection(_ tool: ToolItem) -> some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("当前库存")
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(FivoColor.textSecondary)
                    Text("\(FivoMoney.plainString(tool.stock)) \(tool.stockUnit)")
                        .font(FivoFont.number)
                        .foregroundStyle(tool.isLowStock ? FivoColor.danger : FivoColor.textPrimary)
                }
                Spacer()
                if let threshold = tool.lowStockThreshold, tool.lowStockEnabled {
                    Text("阈值 \(FivoMoney.plainString(threshold)) \(tool.stockUnit)")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
            }
            GoldPrimaryButton(title: "调整库存", systemImage: "plus.forwardslash.minus") {
                showStockAdjust = true
            }
        }
        .softCard()
    }

    private func infoSection(_ tool: ToolItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("档案信息")
                .font(FivoFont.cardTitle)
                .foregroundStyle(FivoColor.textPrimary)
            FieldRow(label: "品牌", value: tool.brand ?? "未填写")
            FieldRow(label: "规格", value: tool.specification ?? "未填写")
            FieldRow(label: "购买日期", value: tool.purchasedAt.map(FivoDate.day) ?? "未填写")
            FieldRow(label: "价格", value: tool.purchasePrice.map { FivoMoney.display($0) } ?? "未填写")
            FieldRow(label: "数量", value: "×\(tool.quantity)")
            FieldRow(label: "位置", value: tool.location ?? "未填写")
            FieldRow(label: "备注", value: tool.notes ?? "未填写")
        }
        .softCard()
    }

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("相关照片")
                        .font(FivoFont.cardTitle)
                        .foregroundStyle(FivoColor.textPrimary)
                    Text("记录工具的使用方法、细节和摆放效果")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
                Spacer()
                Button {
                    showAddPhotos = true
                } label: {
                    Label("加照片", systemImage: "photo.badge.plus")
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(FivoColor.textPrimary)
                        .padding(.horizontal, FivoSpacing.sm)
                        .frame(minHeight: 34)
                        .background(FivoColor.surfaceElevated, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tool.addPhotos")
            }

            if photos.isEmpty {
                EmptyStateView(
                    systemImage: "photo.on.rectangle",
                    title: "还没有相关照片",
                    message: "添加功能说明或使用效果照片，方便随时查看。"
                )
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3),
                    spacing: 6
                ) {
                    ForEach(photos) { photo in
                        Button {
                            selectedPhoto = photo
                        } label: {
                            StoredImageThumbnail(
                                relativePath: photo.thumbnailRelativePath,
                                imageStore: env.imageStore
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("查看工具照片")
                    }
                }
            }
        }
        .softCard()
    }

    private func historySection(_ tool: ToolItem) -> some View {
        VStack(alignment: .leading, spacing: FivoSpacing.xs) {
            Text("库存历史")
                .font(FivoFont.cardTitle)
                .foregroundStyle(FivoColor.textPrimary)
            ForEach(adjustments) { adjustment in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(adjustment.mode.title) · \(FivoMoney.plainString(adjustment.resultingStock)) \(tool.stockUnit)")
                            .font(FivoFont.callout)
                            .foregroundStyle(FivoColor.textPrimary)
                        Text(FivoDate.dateTime(adjustment.occurredAt))
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                    Spacer()
                    if let note = adjustment.note, !note.isEmpty {
                        Text(note)
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .softCard()
    }

    private func ledgerSection(_ tool: ToolItem) -> some View {
        VStack(alignment: .leading, spacing: FivoSpacing.xs) {
            Text("关联账目")
                .font(FivoFont.cardTitle)
                .foregroundStyle(FivoColor.textPrimary)
            if ledgerEntries.isEmpty {
                Text("暂无关联账目。")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
            } else {
                ForEach(ledgerEntries) { entry in
                    NavigationLink(value: LedgerRoute.entry(entry.id)) {
                        LedgerEntryRow(entry: entry, plantName: nil, toolName: tool.name)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .softCard()
    }

    private func load() {
        do {
            tool = try env.tools.tool(id: toolID)
            adjustments = try env.tools.stockAdjustments(toolID: toolID)
            ledgerEntries = try env.ledger.entries(toolID: toolID)
            photos = try env.tools.toolPhotos(toolID: toolID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setPower(_ isOn: Bool) {
        do {
            try env.tools.setPowerState(id: toolID, isOn: isOn)
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTool() {
        do {
            try env.tools.deleteTool(id: toolID)
            env.showToast("已删除工具")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Tool photos

struct AddToolPhotosSheet: View {
    let toolID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var items: [PhotosPickerItem] = []
    @State private var pickedPayloads: [ImagePayload] = []
    @State private var cameraPayloads: [ImagePayload] = []
    @State private var showCamera = false
    @State private var caption = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var payloads: [ImagePayload] { pickedPayloads + cameraPayloads }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                PhotosPicker(
                    selection: $items,
                    maxSelectionCount: 9,
                    matching: .images
                ) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("从相册选择照片")
                        Spacer()
                        Text("\(items.count)/9")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                    .font(FivoFont.callout.weight(.semibold))
                    .foregroundStyle(FivoColor.textPrimary)
                    .padding(FivoSpacing.md)
                    .softCard(padding: 0)
                }

                if CameraAvailability.isAvailable {
                    SecondaryButton(title: "拍摄照片", systemImage: "camera") {
                        showCamera = true
                    }
                }

                if !payloads.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(Array(payloads.enumerated()), id: \.offset) { _, payload in
                            LocalImageThumbnail(data: payload.data)
                        }
                    }
                }

                SoftTextField(
                    label: "照片说明",
                    text: $caption,
                    placeholder: "选填，例如：补光灯安装效果",
                    axis: .vertical,
                    lineLimit: 2...4
                )

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.danger)
                }
            }
            .padding(FivoSpacing.page)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle("添加工具照片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GoldPrimaryButton(
                title: "保存 \(payloads.count) 张照片",
                systemImage: "checkmark",
                isLoading: isSaving,
                isEnabled: !payloads.isEmpty
            ) {
                save()
            }
            .padding(.horizontal, FivoSpacing.page)
            .padding(.vertical, FivoSpacing.xs)
            .background(.ultraThinMaterial)
        }
        .onChange(of: items) { _, newItems in
            Task {
                pickedPayloads = await PhotoPayloadLoader.payloads(from: newItems)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                cameraPayloads.append(ImagePayload(data: data, capturedAt: Date()))
            }
            .ignoresSafeArea()
        }
    }

    private func save() {
        guard !payloads.isEmpty else { return }
        isSaving = true
        do {
            _ = try env.tools.addToolPhotos(
                toolID: toolID,
                payloads: payloads,
                caption: PlantValidator.normalized(caption)
            )
            env.showToast("已添加工具照片")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

struct ToolPhotoViewer: View {
    let toolID: UUID
    let initialPhotoID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var photos: [ToolPhoto] = []
    @State private var index = 0
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?

    private var current: ToolPhoto? {
        guard photos.indices.contains(index) else { return nil }
        return photos[index]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if photos.isEmpty {
                ProgressView().tint(.white)
            } else {
                TabView(selection: $index) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                        StoredImage(
                            relativePath: photo.originalRelativePath,
                            imageStore: env.imageStore,
                            contentMode: .fit
                        )
                        .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                    .accessibilityLabel("关闭照片")
                    Spacer()
                    if !photos.isEmpty {
                        Text("\(index + 1) / \(photos.count)")
                            .font(FivoFont.captionStrong)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.35), in: Capsule())
                    }
                }
                .padding(FivoSpacing.md)

                Spacer()

                if let photo = current {
                    VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(FivoDate.dateTime(photo.capturedAt))
                                    .font(FivoFont.captionStrong)
                                    .foregroundStyle(.white)
                                if let caption = photo.caption, !caption.isEmpty {
                                    Text(caption)
                                        .font(FivoFont.caption)
                                        .foregroundStyle(.white.opacity(0.85))
                                }
                            }
                            Spacer()
                        }

                        Button {
                            showDeleteConfirm = true
                        } label: {
                            Label("删除照片", systemImage: "trash")
                                .font(FivoFont.captionStrong)
                                .foregroundStyle(Color(hex: 0xFFB4A6))
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(.white.opacity(0.12), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(FivoSpacing.md)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(FivoSpacing.md)
                }
            }
        }
        .task { load() }
        .confirmationDialog("删除这张照片？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除照片", role: .destructive) { deleteCurrent() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func load() {
        photos = (try? env.tools.toolPhotos(toolID: toolID)) ?? []
        if let firstIndex = photos.firstIndex(where: { $0.id == initialPhotoID }) {
            index = firstIndex
        }
    }

    private func deleteCurrent() {
        guard let photo = current else { return }
        do {
            try env.tools.deleteToolPhoto(id: photo.id)
            photos.removeAll { $0.id == photo.id }
            index = min(index, max(0, photos.count - 1))
            if photos.isEmpty {
                dismiss()
            } else {
                env.showToast("已删除照片")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Stock adjustment

struct StockAdjustmentSheet: View {
    let toolID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var tool: ToolItem?
    @State private var draft = StockDraft()
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var preview: String {
        guard let tool, let amount = draft.amount else { return "—" }
        do {
            let result = try StockCalculator.resultingStock(current: tool.stock, mode: draft.mode, amount: amount)
            return "\(FivoMoney.plainString(result)) \(tool.stockUnit)"
        } catch {
            return "库存不足"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    HStack {
                        Text("当前库存")
                            .font(FivoFont.captionStrong)
                            .foregroundStyle(FivoColor.textSecondary)
                        Spacer()
                        Text("\(FivoMoney.plainString(tool?.stock ?? 0)) \(tool?.stockUnit ?? "")")
                            .font(FivoFont.callout.weight(.semibold))
                            .foregroundStyle(FivoColor.textPrimary)
                    }
                    Picker("方式", selection: $draft.mode) {
                        ForEach(StockAdjustmentMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    SoftTextField(
                        label: "数量",
                        text: $draft.amountText,
                        placeholder: "填写调整数量",
                        keyboard: .decimalPad
                    )
                    SoftTextField(
                        label: "备注",
                        text: $draft.note,
                        placeholder: "选填",
                        axis: .vertical,
                        lineLimit: 2...3
                    )
                    HStack {
                        Text("调整后库存")
                            .font(FivoFont.captionStrong)
                            .foregroundStyle(FivoColor.textSecondary)
                        Spacer()
                        Text(preview)
                            .font(FivoFont.cardTitle)
                            .foregroundStyle(FivoColor.textPrimary)
                    }
                }
                .softCard()

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.danger)
                }

                GoldPrimaryButton(title: "保存库存调整", systemImage: "checkmark", isLoading: isSaving) {
                    save()
                }
            }
            .padding(FivoSpacing.page)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle("调整库存")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .task {
            tool = try? env.tools.tool(id: toolID)
        }
    }

    private func save() {
        isSaving = true
        do {
            try env.tools.adjustStock(toolID: toolID, draft: draft, at: Date())
            env.showToast("已调整库存")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
