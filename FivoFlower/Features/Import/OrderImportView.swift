import SwiftUI
import PhotosUI

struct OrderImportView: View {
    var onFinish: (() -> Void)?

    private enum Stage {
        case select
        case confirm
        case done
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var stage: Stage = .select
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var payloads: [ImagePayload] = []
    @State private var includedPayloads: [ImagePayload] = []
    @State private var ignoredImageCount = 0
    @State private var showCamera = false
    @State private var attachmentIDs: [UUID] = []
    @State private var importRecordID: UUID?
    @State private var draft = OrderDraft()
    @State private var hasAcquiredDate = false
    @State private var duplicates: [OrderImportRecord] = []
    @State private var isWorking = false
    @State private var progressText = ""
    @State private var errorMessage: String?
    @State private var rawOCRPreview = ""
    @State private var createdPlantName = ""
    @State private var createdPlantID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                switch stage {
                case .select:
                    selectContent
                case .confirm:
                    confirmContent
                case .done:
                    doneContent
                }
            }
            .padding(FivoSpacing.page)
            .padding(.bottom, 90)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle(stage == .done ? "导入完成" : "订单截图导入")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") {
                    env.dataStore.cleanupOrderAttachments(ids: attachmentIDs)
                    attachmentIDs = []
                    dismiss()
                }
            }
        }
        .overlay {
            if isWorking {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    VStack(spacing: FivoSpacing.sm) {
                        ProgressView()
                        Text(progressText.isEmpty ? "识别中…" : progressText)
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                        Button("取消识别") {
                            isWorking = false
                        }
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(FivoColor.danger)
                    }
                    .padding(FivoSpacing.lg)
                    .background(FivoColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
        }
        .onChange(of: pickerItems) { _, items in
            guard !items.isEmpty else { return }
            Task {
                let loaded = await PhotoPayloadLoader.payloads(from: items)
                var merged = payloads
                for item in loaded {
                    guard merged.count < 9 else { break }
                    if !merged.contains(where: { $0.data == item.data }) {
                        merged.append(item)
                    }
                }
                payloads = merged
                // 清空选择，保证下次打开相册是全新选择，不会把上次截图继续带进来
                pickerItems = []
                errorMessage = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                guard payloads.count < 9 else { return }
                payloads.append(ImagePayload(data: data, capturedAt: Date()))
            }
            .ignoresSafeArea()
        }
        .onDisappear {
            env.dataStore.cleanupOrderAttachments(ids: attachmentIDs)
            attachmentIDs = []
        }
    }

    // MARK: - Select

    private var selectContent: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.md) {
            stepHeader(
                current: 1,
                title: "选择订单截图",
                message: "支持一张或多张截图。文字识别与字段解析均在设备端完成，不联网。"
            )

            PhotosPicker(
                selection: $pickerItems,
                maxSelectionCount: 9,
                matching: .images
            ) {
                VStack(spacing: FivoSpacing.xs) {
                    Image(systemName: "doc.text.viewfinder")
                        .font(.system(size: 30, weight: .semibold))
                    Text("选择订单截图")
                        .font(FivoFont.cardTitle)
                    Text("最多 9 张，优先使用裁剪清晰的订单详情")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
                .foregroundStyle(FivoColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 180)
                .softCard(radius: FivoRadius.largeCard, padding: 0)
            }
            .accessibilityIdentifier("import.picker")

            if CameraAvailability.isAvailable {
                SecondaryButton(title: "拍摄订单截图", systemImage: "camera") {
                    showCamera = true
                }
            }

            if !payloads.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("已选择 \(payloads.count) 张截图")
                            .font(FivoFont.captionStrong)
                            .foregroundStyle(FivoColor.textSecondary)
                        Spacer()
                        Text("点右上角 × 可移除误选")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Array(payloads.enumerated()), id: \.offset) { index, payload in
                                ZStack(alignment: .topTrailing) {
                                    LocalImageThumbnail(data: payload.data, aspectRatio: 0.75, cornerRadius: 12)
                                        .frame(width: 92)
                                    Button {
                                        payloads.remove(at: index)
                                        includedPayloads = []
                                        ignoredImageCount = 0
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 20, weight: .semibold))
                                            .symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, Color.black.opacity(0.55))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 5, y: -5)
                                    .accessibilityLabel("移除第 \(index + 1) 张截图")
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .padding(.trailing, 6)
                    }
                }
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.danger)
                    .softCard(padding: FivoSpacing.sm)
            }

            GoldPrimaryButton(
                title: "识别截图内容",
                systemImage: "text.viewfinder",
                isLoading: isWorking,
                isEnabled: !payloads.isEmpty
            ) {
                recognize()
            }
            .accessibilityIdentifier("import.recognize")

            Button("识别不可用？直接手动填写") {
                manualFill()
            }
            .font(FivoFont.callout)
            .foregroundStyle(FivoColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: - Confirm

    private var confirmContent: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.md) {
            stepHeader(
                current: 2,
                title: "确认识别结果",
                message: "OCR 结果必须经你确认后才会创建档案。黄色提示表示需要重点核对。"
            )

            if ignoredImageCount > 0 {
                Label(
                    "已忽略 \(ignoredImageCount) 张与订单无关或未能识别的截图，仅使用 \(includedPayloads.count) 张截图解析。",
                    systemImage: "eye.slash"
                )
                .font(FivoFont.caption)
                .foregroundStyle(FivoColor.textSecondary)
                .padding(FivoSpacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(FivoColor.accentStart.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            if !duplicates.isEmpty {
                VStack(alignment: .leading, spacing: FivoSpacing.xs) {
                    Label("可能重复导入", systemImage: "exclamationmark.triangle")
                        .font(FivoFont.cardTitle)
                        .foregroundStyle(FivoColor.danger)
                    Text("已存在相同订单号或截图的导入记录（\(duplicates.count) 条）。你可以继续，但建议先检查现有档案。")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
                .softCard(padding: FivoSpacing.sm)
            }

            if !draft.lowConfidenceFields.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Label("需确认字段", systemImage: "exclamationmark.circle")
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(FivoColor.danger)
                    Text(draft.lowConfidenceFields.map(\.title).joined(separator: "、"))
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
                .softCard(padding: FivoSpacing.sm)
            }

            VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                SoftTextField(
                    label: "品种名称（必填）",
                    text: $draft.plantName,
                    placeholder: "可从 OCR 结果修改",
                    identifier: "import.nameField"
                )
                SoftTextField(label: "规格", text: $draft.specification, placeholder: "选填")
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
                }
                SoftTextField(
                    label: "支付金额（元）",
                    text: $draft.amountText,
                    placeholder: "选填，最多两位小数",
                    keyboard: .decimalPad
                )
                SoftTextField(label: "平台", text: $draft.platform, placeholder: "如 淘宝 / 闲鱼")
                SoftTextField(label: "店铺", text: $draft.storeName, placeholder: "选填")
                SoftTextField(label: "订单号", text: $draft.orderNumber, placeholder: "选填")
                SoftTextField(label: "来源链接", text: $draft.sourceURL, placeholder: "选填", keyboard: .URL)
            }
            .softCard()

            VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                Toggle("同时生成采购账目", isOn: $draft.createLedgerEntry)
                    .font(FivoFont.callout)
                    .tint(FivoColor.accentEnd)
                if draft.amount == nil || (draft.amount ?? 0) <= 0 {
                    Text("未填写有效金额，不会生成零金额账目。")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
            }
            .softCard()

            DisclosureGroup("查看 OCR 原文") {
                Text(rawOCRPreview.isEmpty ? "无 OCR 文本" : rawOCRPreview)
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
            .font(FivoFont.captionStrong)
            .foregroundStyle(FivoColor.textPrimary)
            .softCard(padding: FivoSpacing.sm)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.danger)
            }

            GoldPrimaryButton(title: "确认并创建植物档案", systemImage: "checkmark", isLoading: isWorking) {
                createPlant()
            }
            .accessibilityIdentifier("import.createPlant")

            Button("返回重选截图") {
                resetSelection()
                stage = .select
            }
            .font(FivoFont.callout)
            .foregroundStyle(FivoColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
        }
    }

    // MARK: - Done

    private var doneContent: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.md) {
            VStack(spacing: FivoSpacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46))
                    .foregroundStyle(FivoColor.success)
                Text("已创建「\(createdPlantName)」")
                    .font(FivoFont.sectionTitle)
                    .foregroundStyle(FivoColor.textPrimary)
                Text("订单截图已保存到植物档案，日志和采购账目已同步生成。")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .softCard(radius: FivoRadius.largeCard)

            if let createdPlantID {
                NavigationLink(value: createdPlantID) {
                    Text("查看植物档案")
                        .font(FivoFont.cardTitle)
                        .foregroundStyle(FivoColor.textPrimary)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(FivoColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            GoldPrimaryButton(title: "完成", systemImage: "checkmark") {
                if let onFinish {
                    onFinish()
                } else {
                    dismiss()
                }
            }
        }
        .navigationDestination(for: UUID.self) { plantID in
            PlantDetailView(plantID: plantID)
        }
    }

    // MARK: - Flow

    private func stepHeader(current: Int, title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("步骤 \(current)/2")
                .font(FivoFont.captionStrong)
                .foregroundStyle(FivoColor.textSecondary)
            Text(title)
                .font(FivoFont.sectionTitle)
                .foregroundStyle(FivoColor.textPrimary)
            Text(message)
                .font(FivoFont.caption)
                .foregroundStyle(FivoColor.textSecondary)
        }
    }

    private func recognize() {
        guard !payloads.isEmpty else { return }
        isWorking = true
        errorMessage = nil
        let images = payloads
        Task {
            do {
                var recognizedTexts: [String] = []
                for (index, image) in images.enumerated() {
                    progressText = "识别第 \(index + 1)/\(images.count) 张…"
                    do {
                        recognizedTexts.append(try await env.ocr.recognizeText(in: image.data))
                    } catch {
                        recognizedTexts.append("")
                    }
                }

                // 多张截图时，只把“像订单”的文本交给解析，避免误选的 App 截图污染字段
                let selector = OrderOCRTextSelector(calendar: env.calendar, now: Date())
                let selection = selector.select(from: recognizedTexts)
                rawOCRPreview = selection.text
                ignoredImageCount = selection.ignoredCount

                guard !selection.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    errorMessage = ignoredImageCount > 0
                        ? "识别到的内容更像 App 页面而不是订单截图。请移除误选截图后重试，或直接手动填写。"
                        : "未能识别到订单文字。可以重试、更换截图，或直接手动填写。"
                    isWorking = false
                    return
                }

                let selectedImages = selection.includedIndices.compactMap { index -> ImagePayload? in
                    guard images.indices.contains(index) else { return nil }
                    return images[index]
                }
                includedPayloads = selectedImages.isEmpty ? images : selectedImages

                if attachmentIDs.isEmpty {
                    for image in includedPayloads {
                        let record = try env.dataStore.saveOrderAttachment(payload: image)
                        attachmentIDs.append(record.id)
                    }
                }

                var parsed = LocalOrderParser(calendar: env.calendar).parse(ocrText: selection.text, now: Date())
                parsed.attachmentIDs = attachmentIDs

                draft = parsed
                hasAcquiredDate = parsed.acquiredAt != nil
                importRecordID = try env.imports.createImportRecord(rawOCRText: selection.text, draft: parsed)
                duplicates = try env.imports.duplicateCandidates(
                    orderNumber: parsed.orderNumber,
                    attachmentIDs: attachmentIDs,
                    rawOCRText: selection.text
                )
                stage = .confirm
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func manualFill() {
        Task {
            do {
                includedPayloads = payloads
                ignoredImageCount = 0
                if attachmentIDs.isEmpty {
                    for image in payloads {
                        let record = try env.dataStore.saveOrderAttachment(payload: image)
                        attachmentIDs.append(record.id)
                    }
                }
                draft = OrderDraft()
                draft.createLedgerEntry = true
                rawOCRPreview = ""
                importRecordID = try env.imports.createImportRecord(rawOCRText: "", draft: draft)
                duplicates = []
                hasAcquiredDate = true
                draft.acquiredAt = Date()
                stage = .confirm
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resetSelection() {
        env.dataStore.cleanupOrderAttachments(ids: attachmentIDs)
        attachmentIDs = []
        payloads = []
        includedPayloads = []
        pickerItems = []
        ignoredImageCount = 0
        duplicates = []
        errorMessage = nil
        importRecordID = nil
        draft = OrderDraft()
        rawOCRPreview = ""
        hasAcquiredDate = false
    }

    private func createPlant() {
        let name = draft.plantName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "请填写品种名称。"
            return
        }
        if !draft.amountText.trimmingCharacters(in: .whitespaces).isEmpty && draft.amount == nil {
            errorMessage = "金额需为最多两位小数的非负数。"
            return
        }
        if let acquiredAt = draft.acquiredAt, FivoDate.isFutureDay(acquiredAt, now: Date(), calendar: env.calendar) {
            errorMessage = "购买日期不能晚于今天。"
            return
        }
        isWorking = true
        errorMessage = nil
        Task {
            do {
                var plantDraft = PlantDraft()
                plantDraft.name = name
                plantDraft.specification = draft.specification
                plantDraft.acquiredAt = draft.acquiredAt
                plantDraft.purchasePriceText = draft.amountText
                plantDraft.platform = draft.platform
                plantDraft.storeName = draft.storeName
                plantDraft.sourceURL = draft.sourceURL

                var options = PlantCreationOptions()
                options.orderAttachments = includedPayloads.isEmpty ? payloads : includedPayloads
                options.importRecordID = importRecordID
                options.initialJournalBody = draft.orderNumber.isEmpty
                    ? "通过订单截图导入"
                    : "通过订单截图导入，订单号：\(draft.orderNumber)"

                var ledger: LedgerDraft?
                if draft.canCreateLedger {
                    var ledgerDraft = LedgerDraft()
                    ledgerDraft.kind = .expense
                    ledgerDraft.title = "植物采购：\(name)"
                    ledgerDraft.category = .plantPurchase
                    ledgerDraft.amountText = draft.amountText
                    ledgerDraft.occurredAt = draft.acquiredAt ?? Date()
                    ledgerDraft.platform = draft.platform
                    ledgerDraft.storeName = draft.storeName
                    ledgerDraft.generateLedger = true
                    ledger = ledgerDraft
                }
                options.ledgerDraft = ledger

                let plant = try env.plants.createPlant(draft: plantDraft, options: options)
                env.dataStore.cleanupOrderAttachments(ids: attachmentIDs)
                attachmentIDs = []
                payloads = []
                includedPayloads = []
                createdPlantName = plant.name
                createdPlantID = plant.id
                stage = .done
                env.showToast("已导入植物档案")
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }
}
