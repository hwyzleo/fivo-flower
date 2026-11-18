import SwiftUI
import PhotosUI

extension CareActionType {
    var systemImage: String {
        switch key {
        case "repot": return "arrow.triangle.2.circlepath"
        case "prune": return "scissors"
        case "water": return "drop"
        case "fertilize": return "leaf"
        case "pest": return "ant"
        case "fungus": return "allergens"
        default: return "sparkles"
        }
    }
}

// MARK: - Record care

struct CareRecordView: View {
    let preselectedPlantIDs: [UUID]
    var onFinish: (() -> Void)?

    init(
        preselectedPlantID: UUID? = nil,
        preselectedPlantIDs: [UUID] = [],
        onFinish: (() -> Void)? = nil
    ) {
        self.preselectedPlantIDs = preselectedPlantIDs + (preselectedPlantID.map { [$0] } ?? [])
        self.onFinish = onFinish
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var actionTypes: [CareActionType] = []
    @State private var plants: [Plant] = []
    @State private var selectedActionID: UUID?
    @State private var selectedPlantIDs: Set<UUID> = []
    @State private var occurredAt = Date()
    @State private var note = ""
    @State private var dosage = ""
    @State private var unit = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    Text("养护动作")
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(FivoColor.textSecondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(actionTypes) { action in
                            Button {
                                selectedActionID = action.id
                            } label: {
                                VStack(spacing: 5) {
                                    Image(systemName: action.systemImage)
                                        .font(.system(size: 17, weight: .semibold))
                                    Text(action.name)
                                        .font(FivoFont.captionStrong)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(FivoColor.textPrimary)
                                .frame(maxWidth: .infinity, minHeight: 60)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(selectedActionID == action.id
                                              ? FivoColor.accentStart.opacity(0.65)
                                              : Color.white.opacity(0.5))
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("care.action.\(action.name)")
                        }
                    }
                }
                .softCard()

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    HStack {
                        Text("选择植物")
                            .font(FivoFont.captionStrong)
                            .foregroundStyle(FivoColor.textSecondary)
                        Spacer()
                        Text("已选 \(selectedPlantIDs.count) 株")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(plants) { plant in
                            Button {
                                if selectedPlantIDs.contains(plant.id) {
                                    selectedPlantIDs.remove(plant.id)
                                } else {
                                    selectedPlantIDs.insert(plant.id)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: selectedPlantIDs.contains(plant.id) ? "checkmark.circle.fill" : "circle")
                                    Text(plant.name)
                                        .font(FivoFont.captionStrong)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(FivoColor.textPrimary)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(selectedPlantIDs.contains(plant.id)
                                              ? FivoColor.accentStart.opacity(0.45)
                                              : Color.white.opacity(0.45))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if plants.isEmpty {
                        Text("还没有植物档案，请先添加植物。")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                }
                .softCard()

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    DatePicker("时间", selection: $occurredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .font(FivoFont.callout)
                    HStack(spacing: 8) {
                        SoftTextField(label: "用量", text: $dosage, placeholder: "选填", keyboard: .decimalPad)
                        SoftTextField(label: "单位", text: $unit, placeholder: "如 ml / g")
                    }
                    SoftTextField(
                        label: "备注",
                        text: $note,
                        placeholder: "选填，例如：沿盆边浇透",
                        axis: .vertical,
                        lineLimit: 2...4
                    )
                    PhotoPickerRow(title: "添加照片", items: $photoItems)
                }
                .softCard()

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.danger)
                }
            }
            .padding(FivoSpacing.page)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle("记养护")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GoldPrimaryButton(title: "保存养护记录", systemImage: "checkmark", isLoading: isSaving) {
                save()
            }
            .padding(.horizontal, FivoSpacing.page)
            .padding(.vertical, FivoSpacing.xs)
            .background(.ultraThinMaterial)
            .accessibilityIdentifier("care.recordButton")
        }
        .task { load() }
    }

    private func load() {
        actionTypes = (try? env.care.actionTypes(includeDisabled: false)) ?? []
        plants = (try? env.plants.fetchPlants()) ?? []
        selectedActionID = selectedActionID ?? actionTypes.first?.id
        let availableIDs = Set(plants.map(\.id))
        selectedPlantIDs.formUnion(preselectedPlantIDs.filter { availableIDs.contains($0) })
    }

    private func save() {
        guard let selectedActionID else {
            errorMessage = "请选择养护动作。"
            return
        }
        guard !selectedPlantIDs.isEmpty else {
            errorMessage = "请至少选择一株植物。"
            return
        }
        isSaving = true
        Task {
            let payloads = await PhotoPayloadLoader.payloads(from: photoItems)
            let draft = CareRecordDraft(
                plantIDs: Array(selectedPlantIDs),
                actionTypeID: selectedActionID,
                occurredAt: occurredAt,
                note: note,
                dosage: dosage,
                unit: unit,
                photos: payloads
            )
            do {
                let result = try env.care.recordCare(draft)
                Task { await env.reconcileNotifications() }
                env.showToast(result.logs.count > 1 ? "已记录 \(result.logs.count) 株植物的养护" : "已记录养护")
                if let onFinish {
                    onFinish()
                } else {
                    dismiss()
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - Add / edit cycle

struct ReminderEditorView: View {
    let preselectedPlantIDs: [UUID]
    let preselectedActionTypeID: UUID?
    let preselectedActionName: String?
    let editingReminder: CareReminder?

    init(
        preselectedPlantIDs: [UUID],
        preselectedActionTypeID: UUID? = nil,
        preselectedActionName: String? = nil,
        editingReminder: CareReminder? = nil
    ) {
        self.preselectedPlantIDs = preselectedPlantIDs
        self.preselectedActionTypeID = preselectedActionTypeID
        self.preselectedActionName = preselectedActionName
        self.editingReminder = editingReminder
    }

    private enum RecurrenceMode: String, CaseIterable, Identifiable {
        case days, weeks, months, years
        var id: String { rawValue }
        var title: String {
            switch self {
            case .days: return "每 N 天"
            case .weeks: return "每 N 周"
            case .months: return "每 N 月"
            case .years: return "每 N 年"
            }
        }
        var unit: String {
            switch self {
            case .days: return "天"
            case .weeks: return "周"
            case .months: return "月"
            case .years: return "年"
            }
        }
    }

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var actionTypes: [CareActionType] = []
    @State private var plants: [Plant] = []
    @State private var selectedActionID: UUID?
    @State private var selectedPlantIDs: Set<UUID> = []
    @State private var title = ""
    @State private var dueAt = Date().addingTimeInterval(3600 * 24)
    @State private var mode: RecurrenceMode = .days
    @State private var interval = 1
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var isEditing: Bool { editingReminder != nil }

    private var recurrence: ReminderRecurrence {
        let value = max(1, interval)
        switch mode {
        case .days: return .everyNDays(value)
        case .weeks: return .everyNWeeks(value)
        case .months: return .everyNMonths(value)
        case .years: return .everyNYears(value)
        }
    }

    private var editingAnchor: Date? {
        guard let editingReminder else { return nil }
        let logs = (try? env.care.logs(plantID: editingReminder.plantID)) ?? []
        let actionName = editingReminder.actionNameSnapshot ?? editingReminder.title
        return logs
            .filter { log in
                if let reminderActionID = editingReminder.actionTypeID, let logActionID = log.actionTypeID {
                    return reminderActionID == logActionID
                }
                return log.actionNameSnapshot == actionName
            }
            .map(\.occurredAt)
            .max() ?? editingReminder.createdAt
    }

    private var nextDuePreview: Date? {
        guard let editingReminder, let editingAnchor else { return nil }
        return recurrence.nextDue(after: editingAnchor, calendar: env.calendar) ?? editingReminder.dueAt
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    Picker("养护动作", selection: $selectedActionID) {
                        Text("自定义").tag(UUID?.none)
                        ForEach(actionTypes) { action in
                            Text(action.name).tag(UUID?.some(action.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(FivoColor.textPrimary)
                    .disabled(isEditing)
                    .accessibilityIdentifier("reminder.actionType")
                    .onChange(of: selectedActionID) { _, newValue in
                        if let newValue, let action = actionTypes.first(where: { $0.id == newValue }), title.isEmpty {
                            title = action.name
                        }
                    }
                    SoftTextField(
                        label: "周期标题",
                        text: $title,
                        placeholder: "例如：浇水 / 施肥",
                        identifier: "reminder.titleField"
                    )
                    if let nextDuePreview {
                        FieldRow(label: "下次待办", value: FivoDate.dateTime(nextDuePreview))
                        Text("修改周期后，将按最近养护时间自动调整；尚无养护记录时按周期创建时间计算。")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    } else {
                        DatePicker("首次待办", selection: $dueAt, displayedComponents: [.date, .hourAndMinute])
                            .font(FivoFont.callout)
                    }
                }
                .softCard()

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    Text("重复方式")
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(FivoColor.textSecondary)
                    Picker("重复方式", selection: $mode) {
                        ForEach(RecurrenceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("cycle.recurrenceMode")
                    Stepper("每 \(interval) \(mode.unit)", value: $interval, in: 1...365)
                        .font(FivoFont.callout)
                        .accessibilityIdentifier("cycle.interval")
                }
                .softCard()

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    HStack {
                        Text("周期植物")
                            .font(FivoFont.captionStrong)
                            .foregroundStyle(FivoColor.textSecondary)
                        Spacer()
                        Text("已选 \(selectedPlantIDs.count) 株")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                            .accessibilityIdentifier("reminder.selectedPlantCount")
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(plants) { plant in
                            Button {
                                guard !isEditing else { return }
                                if selectedPlantIDs.contains(plant.id) {
                                    selectedPlantIDs.remove(plant.id)
                                } else {
                                    selectedPlantIDs.insert(plant.id)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: selectedPlantIDs.contains(plant.id) ? "checkmark.circle.fill" : "circle")
                                    Text(plant.name)
                                        .font(FivoFont.captionStrong)
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                                .foregroundStyle(FivoColor.textPrimary)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(selectedPlantIDs.contains(plant.id)
                                              ? FivoColor.accentStart.opacity(0.45)
                                              : Color.white.opacity(0.45))
                                )
                            }
                            .buttonStyle(.plain)
                            .disabled(isEditing)
                        }
                    }
                }
                .softCard()

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.danger)
                }
            }
            .padding(FivoSpacing.page)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle(isEditing ? "修改周期" : "添加周期")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GoldPrimaryButton(title: "保存周期", systemImage: "checkmark", isLoading: isSaving) {
                save()
            }
            .padding(.horizontal, FivoSpacing.page)
            .padding(.vertical, FivoSpacing.xs)
            .background(.ultraThinMaterial)
            .accessibilityIdentifier("cycle.save")
        }
        .task { load() }
    }

    private func load() {
        actionTypes = (try? env.care.actionTypes(includeDisabled: false)) ?? []
        plants = (try? env.plants.fetchPlants()) ?? []
        if let editingReminder {
            selectedPlantIDs = [editingReminder.plantID]
            selectedActionID = editingReminder.actionTypeID
            title = editingReminder.title
            dueAt = editingReminder.dueAt
            switch editingReminder.recurrence {
            case .everyNDays(let value): mode = .days; interval = value
            case .everyNWeeks(let value): mode = .weeks; interval = value
            case .everyNMonths(let value): mode = .months; interval = value
            case .everyNYears(let value): mode = .years; interval = value
            }
            return
        }

        selectedPlantIDs.formUnion(preselectedPlantIDs)
        if let preselectedActionTypeID,
           actionTypes.contains(where: { $0.id == preselectedActionTypeID }) {
            selectedActionID = preselectedActionTypeID
        }
        if title.isEmpty {
            title = preselectedActionName
                ?? actionTypes.first(where: { $0.id == selectedActionID })?.name
                ?? ""
        }
    }

    private func save() {
        guard !selectedPlantIDs.isEmpty else {
            errorMessage = "请至少选择一株植物。"
            return
        }
        isSaving = true
        Task {
            let draft = ReminderDraft(
                plantIDs: Array(selectedPlantIDs),
                actionTypeID: selectedActionID,
                title: title,
                dueAt: nextDuePreview ?? dueAt,
                recurrence: recurrence
            )
            do {
                let saved: [CareReminder]
                if let editingReminder {
                    saved = [try env.reminders.updateReminder(id: editingReminder.id, draft: draft)]
                } else {
                    saved = try env.reminders.createReminders(draft)
                }
                let granted = await env.requestNotificationAuthorizationIfNeeded()
                if granted {
                    for reminder in saved {
                        await env.notifications.schedule(reminder)
                    }
                }
                env.showToast(isEditing ? "已修改周期" : "已添加周期")
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
