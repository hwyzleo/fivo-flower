import SwiftUI

struct LedgerEntryEditor: View {
    let entryID: UUID?
    let preselectPlantID: UUID?
    let preselectToolID: UUID?
    var onFinish: (() -> Void)?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var draft = LedgerDraft()
    @State private var plants: [Plant] = []
    @State private var tools: [ToolItem] = []
    @State private var expenses: [LedgerEntry] = []
    @State private var errors: [LedgerFieldError] = []
    @State private var generalError: String?
    @State private var isSaving = false
    @State private var loaded = false
    @State private var showPlantDetail = false
    @State private var showToolDetail = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    Picker("类型", selection: $draft.kind) {
                        ForEach(LedgerKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: draft.kind) { _, kind in
                        if !LedgerCategory.categories(for: kind).contains(draft.category) {
                            draft.category = LedgerCategory.categories(for: kind).first ?? .otherExpense
                        }
                        if kind != .refund {
                            draft.relatedEntryID = nil
                        }
                    }

                    SoftTextField(label: "标题", text: $draft.title, placeholder: "例如：白锦龟背竹采购", identifier: "ledger.titleField")
                    Picker("分类", selection: $draft.category) {
                        ForEach(LedgerCategory.categories(for: draft.kind)) { category in
                            Text(category.title).tag(category)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(FivoColor.textPrimary)

                    SoftTextField(
                        label: "金额（元）",
                        text: $draft.amountText,
                        placeholder: "大于 0，最多两位小数",
                        keyboard: .decimalPad,
                        error: errors.contains(.amountInvalid) ? LedgerFieldError.amountInvalid.message : nil,
                        identifier: "ledger.amountField"
                    )

                    DatePicker("日期", selection: $draft.occurredAt, in: ...Date(), displayedComponents: .date)
                        .font(FivoFont.callout)
                }
                .softCard()

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    SoftTextField(label: "平台", text: $draft.platform, placeholder: "选填")
                    SoftTextField(label: "店铺", text: $draft.storeName, placeholder: "选填")
                    Picker("关联植物", selection: $draft.plantID) {
                        Text("不关联").tag(UUID?.none)
                        ForEach(plants) { plant in
                            Text(plant.name).tag(UUID?.some(plant.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(FivoColor.textPrimary)
                    Picker("关联工具", selection: $draft.toolID) {
                        Text("不关联").tag(UUID?.none)
                        ForEach(tools) { tool in
                            Text(tool.name).tag(UUID?.some(tool.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(FivoColor.textPrimary)
                }
                .softCard()

                if draft.kind == .refund {
                    VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                        Text("关联原支出")
                            .font(FivoFont.captionStrong)
                            .foregroundStyle(FivoColor.textSecondary)
                        Picker("原支出", selection: $draft.relatedEntryID) {
                            Text("请选择原支出").tag(UUID?.none)
                            ForEach(expenses) { entry in
                                Text("\(entry.title) · \(FivoMoney.display(entry.amount)) · \(FivoDate.day(entry.occurredAt))")
                                    .tag(UUID?.some(entry.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(FivoColor.textPrimary)
                        if errors.contains(.refundNeedsSource) {
                            Label(LedgerFieldError.refundNeedsSource.message, systemImage: "exclamationmark.circle")
                                .font(FivoFont.caption)
                                .foregroundStyle(FivoColor.danger)
                        }
                        Text("只有关联原支出的退款才会冲减累计投入。")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                    .softCard()
                }

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    SoftTextField(
                        label: "备注",
                        text: $draft.note,
                        placeholder: "选填",
                        axis: .vertical,
                        lineLimit: 2...4
                    )
                }
                .softCard()

                if let plantID = draft.plantID {
                    Button {
                        showPlantDetail = true
                    } label: {
                        relatedArchiveRow(title: "查看关联植物档案", systemImage: "leaf")
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showPlantDetail) {
                        NavigationStack { PlantDetailView(plantID: plantID) }
                    }
                }
                if let toolID = draft.toolID {
                    Button {
                        showToolDetail = true
                    } label: {
                        relatedArchiveRow(title: "查看关联工具档案", systemImage: "shippingbox")
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showToolDetail) {
                        NavigationStack { ToolDetailView(toolID: toolID) }
                    }
                }

                if errors.contains(.titleRequired) {
                    Label(LedgerFieldError.titleRequired.message, systemImage: "exclamationmark.circle")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.danger)
                }
            }
            .padding(FivoSpacing.page)
            .padding(.bottom, 80)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle(entryID == nil ? "记一笔" : "编辑账目")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GoldPrimaryButton(title: "保存账目", systemImage: "checkmark", isLoading: isSaving) {
                save()
            }
            .padding(.horizontal, FivoSpacing.page)
            .padding(.vertical, FivoSpacing.xs)
            .background(.ultraThinMaterial)
            .accessibilityIdentifier("ledger.save")
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
    }

    private func relatedArchiveRow(title: String, systemImage: String) -> some View {
        HStack(spacing: FivoSpacing.sm) {
            Image(systemName: systemImage)
                .foregroundStyle(FivoColor.textPrimary)
            Text(title)
                .font(FivoFont.callout)
                .foregroundStyle(FivoColor.textPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(FivoColor.textSecondary)
        }
        .softCard(padding: FivoSpacing.sm)
    }

    private func load() {
        guard !loaded else { return }
        plants = (try? env.plants.fetchPlants()) ?? []
        tools = (try? env.tools.tools()) ?? []
        expenses = ((try? env.ledger.entries()) ?? []).filter { $0.kind == .expense }
        if let entryID, let entry = try? env.ledger.entry(id: entryID) {
            var draft = LedgerDraft()
            draft.kind = entry.kind
            draft.title = entry.title
            draft.category = entry.category
            draft.amountText = FivoMoney.plainString(entry.amount)
            draft.occurredAt = entry.occurredAt
            draft.platform = entry.platform ?? ""
            draft.storeName = entry.storeName ?? ""
            draft.plantID = entry.plantID
            draft.toolID = entry.toolID
            draft.relatedEntryID = entry.relatedEntryID
            draft.note = entry.note ?? ""
            self.draft = draft
        } else {
            draft.plantID = preselectPlantID
            draft.toolID = preselectToolID
            if preselectPlantID != nil {
                draft.category = .plantPurchase
                if let plant = plants.first(where: { $0.id == preselectPlantID }) {
                    draft.title = "植物采购：\(plant.name)"
                }
            } else if preselectToolID != nil {
                draft.category = .toolPurchase
                if let tool = tools.first(where: { $0.id == preselectToolID }) {
                    draft.title = "工具采购：\(tool.name)"
                }
            }
        }
        loaded = true
    }

    private func save() {
        errors = LedgerValidator.validate(draft, now: Date())
        guard errors.isEmpty else { return }
        isSaving = true
        do {
            if let entryID {
                _ = try env.ledger.updateEntry(id: entryID, draft: draft)
                env.showToast("已保存账目")
            } else {
                _ = try env.ledger.createEntry(draft)
                env.showToast("已记一笔")
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
