import SwiftUI
import PhotosUI

// MARK: - Switch stage

struct GrowthSwitchView: View {
    let plantID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var stages: [GrowthStage] = []
    @State private var selectedKey: String = GrowthStageKey.leafRoot
    @State private var date = Date()
    @State private var note = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("切换为")
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(FivoColor.textSecondary)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(stages) { stage in
                            Button {
                                selectedKey = stage.key
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "camera.macro")
                                    Text(stage.name)
                                        .font(FivoFont.callout.weight(.semibold))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    if selectedKey == stage.key {
                                        Image(systemName: "checkmark.circle.fill")
                                    }
                                }
                                .foregroundStyle(FivoColor.textPrimary)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 46)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(selectedKey == stage.key
                                              ? FivoColor.accentStart.opacity(0.6)
                                              : Color.white.opacity(0.55))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .softCard()

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    DatePicker(
                        "开始日期",
                        selection: $date,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(FivoFont.callout)
                    Text("上一段状态会用同一时间结束，历史记录不会被覆盖。")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                    SoftTextField(
                        label: "备注",
                        text: $note,
                        placeholder: "选填，例如：抽出第二支花梗",
                        axis: .vertical,
                        lineLimit: 2...5
                    )
                    PhotoPickerRow(title: "添加状态照片", items: $photoItems)
                }
                .softCard()

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.danger)
                }

                GoldPrimaryButton(title: "保存状态切换", systemImage: "checkmark", isLoading: isSaving) {
                    save()
                }
            }
            .padding(FivoSpacing.page)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle("切换生长状态")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .task { load() }
    }

    private func load() {
        stages = (try? env.growth.stages(includeDisabled: false)) ?? []
        if let current = try? env.growth.currentSession(plantID: plantID) {
            selectedKey = current.stageKey
        }
    }

    private func save() {
        isSaving = true
        Task {
            let payloads = await PhotoPayloadLoader.payloads(from: photoItems)
            do {
                try env.growth.switchStage(
                    plantID: plantID,
                    to: selectedKey,
                    at: date,
                    note: note,
                    photos: payloads
                )
                env.showToast("已切换为\(env.stageName(key: selectedKey))")
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

// MARK: - History

struct GrowthHistoryView: View {
    let plantID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var sessions: [GrowthSession] = []
    @State private var stages: [String: GrowthStage] = [:]
    @State private var editing: GrowthSession?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                if sessions.isEmpty {
                    EmptyStateView(
                        systemImage: "clock",
                        title: "还没有状态历史",
                        message: "切换生长状态后，这里会记录每一段起止时间。"
                    )
                } else {
                    ForEach(sessions) { session in
                        Button {
                            editing = session
                        } label: {
                            sessionCard(session)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(FivoSpacing.page)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle("状态历史")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .task { load() }
        .sheet(item: $editing, onDismiss: load) { session in
            NavigationStack {
                SessionEditView(sessionID: session.id)
            }
        }
    }

    private func sessionCard(_ session: GrowthSession) -> some View {
        let stage = stages[session.stageKey]
        let days = PlantDurationCalculator(calendar: env.calendar)
            .stageDays(startedAt: session.startedAt, endedAt: session.endedAt, now: Date())
        return HStack(alignment: .top, spacing: FivoSpacing.sm) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(stage?.name ?? env.stageName(key: session.stageKey))
                        .font(FivoFont.cardTitle)
                        .foregroundStyle(FivoColor.textPrimary)
                    if session.endedAt == nil {
                        StatusPill(text: "进行中", tint: FivoColor.success)
                    }
                }
                Text("\(FivoDate.day(session.startedAt)) → \(session.endedAt.map(FivoDate.day) ?? "今天")")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
                if let note = session.note, !note.isEmpty {
                    Text(note)
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(days ?? 1) 天")
                    .font(FivoFont.number)
                    .foregroundStyle(FivoColor.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(FivoColor.textSecondary)
            }
        }
        .softCard()
    }

    private func load() {
        sessions = (try? env.growth.sessions(plantID: plantID)) ?? []
        let list = (try? env.growth.stages(includeDisabled: true)) ?? []
        stages = Dictionary(uniqueKeysWithValues: list.map { ($0.key, $0) })
    }
}

struct SessionEditView: View {
    let sessionID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var startedAt = Date()
    @State private var endedAt = Date()
    @State private var hasEnded = true
    @State private var note = ""
    @State private var loaded = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    DatePicker(
                        "开始时间",
                        selection: $startedAt,
                        in: ...Date(),
                        displayedComponents: [.date, .hourAndMinute]
                    )
                    .font(FivoFont.callout)
                    Toggle("已结束", isOn: $hasEnded)
                        .font(FivoFont.callout)
                        .tint(FivoColor.accentEnd)
                    if hasEnded {
                        DatePicker(
                            "结束时间",
                            selection: $endedAt,
                            in: startedAt...max(startedAt, Date()),
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .font(FivoFont.callout)
                    }
                    SoftTextField(
                        label: "备注",
                        text: $note,
                        placeholder: "选填",
                        axis: .vertical,
                        lineLimit: 2...5
                    )
                }
                .softCard()

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.danger)
                }

                GoldPrimaryButton(title: "保存更正", systemImage: "checkmark") {
                    save()
                }
            }
            .padding(FivoSpacing.page)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle("更正状态记录")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .task { load() }
    }

    private func load() {
        guard !loaded else { return }
        let all = (try? env.dataStore.allRecords(GrowthSessionRecord.self)) ?? []
        if let record = all.first(where: { $0.id == sessionID }) {
            startedAt = record.startedAt
            hasEnded = record.endedAt != nil
            endedAt = record.endedAt ?? Date()
            note = record.note ?? ""
            loaded = true
        }
    }

    private func save() {
        do {
            try env.growth.updateSession(
                id: sessionID,
                startedAt: startedAt,
                endedAt: hasEnded ? endedAt : nil,
                note: note
            )
            env.showToast("已保存状态记录")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Statistics

struct PlantStatisticsView: View {
    let statistics: PlantStatistics

    var body: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.md) {
            statSection(
                title: "出花梗",
                rows: [
                    ("出花梗次数", statistics.spikeCount > 0 ? "\(statistics.spikeCount) 次" : "暂无记录"),
                    ("最近出花梗", statistics.mostRecentSpikeAt.map(FivoDate.day) ?? "暂无记录"),
                    ("平均间隔", statistics.averageSpikeIntervalDays.map { String(format: "%.1f 天", $0) } ?? "需要至少两次出花梗记录")
                ]
            )
            statSection(
                title: "开花",
                rows: [
                    ("开花次数", statistics.bloomCount > 0 ? "\(statistics.bloomCount) 次" : "暂无记录"),
                    ("最近开花", statistics.mostRecentBloomAt.map(FivoDate.day) ?? "暂无记录"),
                    ("平均开花时长", statistics.averageBloomDurationDays.map { String(format: "%.1f 天", $0) } ?? "暂无已结束的开花记录"),
                    ("最长开花时长", statistics.longestBloomDurationDays.map { "\($0) 天" } ?? "暂无已结束的开花记录"),
                    ("进行中开花", statistics.ongoingBloomDurationDays.map { "\($0) 天" } ?? "无进行中开花")
                ]
            )
            Text("统计基于已保存的状态记录，未来日期不会参与计算。")
                .font(FivoFont.caption)
                .foregroundStyle(FivoColor.textSecondary)
        }
    }

    private func statSection(title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(FivoFont.cardTitle)
                .foregroundStyle(FivoColor.textPrimary)
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.0)
                        .font(FivoFont.callout)
                        .foregroundStyle(FivoColor.textSecondary)
                    Spacer()
                    Text(row.1)
                        .font(FivoFont.callout.weight(.semibold))
                        .foregroundStyle(FivoColor.textPrimary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 2)
            }
        }
        .softCard()
    }
}
