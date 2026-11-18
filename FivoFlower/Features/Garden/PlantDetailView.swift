import SwiftUI

enum DetailSegment: String, CaseIterable, Identifiable {
    case overview = "概览"
    case journal = "日志"
    case photos = "照片"
    case stats = "统计"

    var id: String { rawValue }
}

enum LifeEventKind: String, Identifiable {
    case dead
    case gifted

    var id: String { rawValue }

    var title: String {
        self == .dead ? "标记死亡" : "标记赠送"
    }

    var status: PlantLifeStatus {
        self == .dead ? .dead : .gifted
    }
}

struct PlantDetailView: View {
    let plantID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var plant: Plant?
    @State private var sessions: [GrowthSession] = []
    @State private var photos: [PlantPhoto] = []
    @State private var journals: [JournalEntry] = []
    @State private var stages: [String: GrowthStage] = [:]
    @State private var statistics = PlantStatistics.empty
    @State private var careActionTypes: [CareActionType] = []
    @State private var careLogs: [CareLog] = []
    @State private var careReminders: [CareReminder] = []
    @State private var segment: DetailSegment = .overview

    @State private var showEdit = false
    @State private var showStageSwitch = false
    @State private var showHistory = false
    @State private var showAddJournal = false
    @State private var showCare = false
    @State private var showAddPhotos = false
    @State private var showDeleteConfirm = false
    @State private var showRestoreConfirm = false
    @State private var lifeEvent: LifeEventKind?
    @State private var careReminderStatus: PlantCareStatus?
    @State private var selectedPhoto: PlantPhoto?
    @State private var selectedJournal: JournalEntry?
    @State private var errorMessage: String?

    private var currentSession: GrowthSession? {
        sessions.first(where: { $0.endedAt == nil })
    }

    private var currentStage: GrowthStage? {
        currentSession.flatMap { stages[$0.stageKey] }
    }

    private var durationCalculator: PlantDurationCalculator {
        PlantDurationCalculator(calendar: env.calendar)
    }

    private var careStatuses: [PlantCareStatus] {
        PlantCareStatusCalculator.statuses(
            actionTypes: careActionTypes,
            logs: careLogs,
            reminders: careReminders.filter { $0.plantID == plantID }
        )
    }

    var body: some View {
        ScrollView {
            if let plant {
                VStack(alignment: .leading, spacing: FivoSpacing.md) {
                    coverSection(plant)
                    if plant.isArchived {
                        archivedBanner(plant)
                    }
                    companionCard(plant)
                    currentCareStatusCard
                    currentStageCard(plant)
                    quickActions
                    Picker("详情分段", selection: $segment) {
                        ForEach(DetailSegment.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("plant.segment")

                    segmentContent(plant)
                }
                .fivoPagePadding()
                .padding(.bottom, 110)
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { load() }
                    .padding(FivoSpacing.page)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            }
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle(plant?.name ?? "植物详情")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedJournal) { entry in
            JournalDetailView(entry: entry, plantName: plant?.name)
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showEdit = true
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("编辑植物")
                .accessibilityIdentifier("plant.edit")

                Menu {
                    Button {
                        duplicate()
                    } label: {
                        Label("复制档案", systemImage: "doc.on.doc")
                    }
                    if plant?.lifeStatus == .active {
                        Button {
                            lifeEvent = .dead
                        } label: {
                            Label("标记死亡", systemImage: "heart.slash")
                        }
                        Button {
                            lifeEvent = .gifted
                        } label: {
                            Label("标记赠送", systemImage: "gift")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除植物", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("更多操作")
            }
        }
        .task { load() }
        .onAppear { load() }
        .sheet(isPresented: $showEdit, onDismiss: load) {
            NavigationStack { PlantEditView(mode: .edit(plantID)) }
        }
        .sheet(isPresented: $showStageSwitch, onDismiss: load) {
            NavigationStack { GrowthSwitchView(plantID: plantID) }
        }
        .sheet(isPresented: $showHistory, onDismiss: load) {
            NavigationStack { GrowthHistoryView(plantID: plantID) }
        }
        .sheet(isPresented: $showAddJournal, onDismiss: load) {
            NavigationStack { ManualJournalView(plantID: plantID) }
        }
        .sheet(isPresented: $showCare, onDismiss: load) {
            NavigationStack { CareRecordView(preselectedPlantID: plantID) }
        }
        .sheet(item: $careReminderStatus, onDismiss: load) { status in
            NavigationStack {
                ReminderEditorView(
                    preselectedPlantIDs: [plantID],
                    preselectedActionTypeID: status.actionTypeID,
                    preselectedActionName: status.actionName,
                    editingReminder: currentReminder(for: status)
                )
            }
        }
        .sheet(isPresented: $showAddPhotos, onDismiss: load) {
            NavigationStack { AddPhotosSheet(plantID: plantID) }
        }
        .sheet(item: $lifeEvent, onDismiss: load) { kind in
            NavigationStack { LifeEventSheet(plantID: plantID, kind: kind) }
        }
        .fullScreenCover(item: $selectedPhoto) { photo in
            PhotoViewer(plantID: plantID, initialPhotoID: photo.id)
        }
        .confirmationDialog("删除植物档案？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除植物", role: .destructive) { deletePlant() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("照片、日志、养护记录和提醒会一并删除；相关账目会保留并解除关联。此操作不可撤销。")
        }
        .confirmationDialog("恢复这株植物？", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("恢复档案") { restore() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将清除死亡/赠送信息，并从养叶养根重新开始；原状态历史保留。")
        }
    }

    // MARK: - Sections

    private func coverSection(_ plant: Plant) -> some View {
        ZStack(alignment: .bottomLeading) {
            StoredImage(relativePath: env.coverPath(for: plant), imageStore: env.imageStore)
                .frame(height: 290)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: FivoRadius.largeCard, style: .continuous))
                .saturation(plant.isArchived ? 0.35 : 1)
            LinearGradient(
                colors: [.clear, .black.opacity(0.28)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: FivoRadius.largeCard, style: .continuous))
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: 4) {
                Text(plant.name)
                    .font(FivoFont.pageTitle)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if let alias = plant.displayAliasLine {
                    Text(alias)
                        .font(FivoFont.callout)
                        .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(FivoSpacing.lg)
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
        }
        .padding(.top, FivoSpacing.xs)
    }

    private func archivedBanner(_ plant: Plant) -> some View {
        HStack(spacing: FivoSpacing.sm) {
            Image(systemName: plant.lifeStatus == .dead ? "heart.slash" : "gift")
            VStack(alignment: .leading, spacing: 1) {
                Text("\(plant.lifeStatus.title) · \(plant.lifeEventAt.map(FivoDate.day) ?? "")")
                    .font(FivoFont.captionStrong)
                if let reason = plant.lifeEventReason, !reason.isEmpty {
                    Text(reason)
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
            }
            Spacer()
            Button("恢复") { showRestoreConfirm = true }
                .font(FivoFont.captionStrong)
                .foregroundStyle(FivoColor.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(FivoColor.surfaceElevated, in: Capsule())
        }
        .foregroundStyle(FivoColor.danger)
        .padding(FivoSpacing.sm)
        .background(FivoColor.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func companionCard(_ plant: Plant) -> some View {
        let days = durationCalculator.companionDays(for: plant, now: Date())
        let category = env.gardenQuery.category(for: plant, now: Date())
        return HStack(alignment: .center, spacing: FivoSpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("已陪伴")
                    .font(FivoFont.captionStrong)
                    .foregroundStyle(FivoColor.textSecondary)
                if let days {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(days)")
                            .font(FivoFont.numberLarge)
                            .foregroundStyle(FivoColor.textPrimary)
                        Text("天")
                            .font(FivoFont.callout.weight(.semibold))
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                } else {
                    Text("未填写购买日期")
                        .font(FivoFont.cardTitle)
                        .foregroundStyle(FivoColor.textSecondary)
                }
                if let acquiredAt = plant.acquiredAt {
                    Text("入手于 \(FivoDate.day(acquiredAt))")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                StatusPill(text: category.title, systemImage: "leaf.fill", tint: FivoColor.success)
                if let location = plant.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
                if let platform = plant.platform, !platform.isEmpty {
                    Label(platform, systemImage: "bag")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
            }
        }
        .softCard(radius: FivoRadius.largeCard)
        .accessibilityIdentifier("plant.companionCard")
    }

    private var currentCareStatusCard: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            Text("当前养护状态")
                .font(FivoFont.sectionTitle)
                .foregroundStyle(FivoColor.textPrimary)

            if careStatuses.isEmpty {
                Text("暂无可用的养护动作。")
                    .font(FivoFont.callout)
                    .foregroundStyle(FivoColor.textSecondary)
            } else {
                ForEach(careStatuses) { status in
                    HStack(alignment: .top, spacing: FivoSpacing.sm) {
                        Image(systemName: careActionTypes.first(where: { $0.id == status.actionTypeID })?.systemImage ?? "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(FivoColor.textPrimary)
                            .frame(width: 32, height: 32)
                            .background(FivoColor.accentStart.opacity(0.3), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(status.actionName)
                                .font(FivoFont.captionStrong)
                                .foregroundStyle(FivoColor.textPrimary)
                            Text("上次：\(status.lastOperatedAt.map(FivoDate.dateTime) ?? "未记录")")
                                .font(FivoFont.caption)
                                .foregroundStyle(FivoColor.textSecondary)
                            Text("下次：\(status.nextDueAt.map(FivoDate.dateTime) ?? "未设置下次待办")")
                                .font(FivoFont.caption)
                                .foregroundStyle(status.nextDueAt.map { $0 < Date() ? FivoColor.danger : FivoColor.textSecondary } ?? FivoColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                        Button {
                            careReminderStatus = status
                        } label: {
                            Text("设置周期")
                                .font(FivoFont.captionStrong)
                                .foregroundStyle(FivoColor.textPrimary)
                                .padding(.horizontal, 10)
                                .frame(minHeight: 36)
                                .background(FivoColor.accentStart.opacity(0.45), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("设置\(status.actionName)周期")
                        .accessibilityIdentifier("plant.setReminder.\(status.actionName)")
                    }
                    if status.id != careStatuses.last?.id {
                        Divider()
                    }
                }
            }
        }
        .softCard(radius: FivoRadius.largeCard)
        .accessibilityIdentifier("plant.careStatusCard")
    }

    private func currentReminder(for status: PlantCareStatus) -> CareReminder? {
        careReminders
            .filter { reminder in
                guard reminder.status == .pending else { return false }
                if let statusID = status.actionTypeID, let reminderID = reminder.actionTypeID {
                    return statusID == reminderID
                }
                return (reminder.actionNameSnapshot ?? reminder.title) == status.actionName
            }
            .sorted { $0.dueAt < $1.dueAt }
            .first
    }

    private func currentStageCard(_ plant: Plant) -> some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            HStack {
                Text("当前生长状态")
                    .font(FivoFont.sectionTitle)
                    .foregroundStyle(FivoColor.textPrimary)
                Spacer()
                if let currentStage {
                    StatusPill(text: currentStage.name, systemImage: "camera.macro", tint: FivoColor.success)
                }
            }
            if let session = currentSession, let stage = currentStage {
                let days = durationCalculator.stageDays(
                    startedAt: session.startedAt,
                    endedAt: session.endedAt,
                    now: Date()
                )
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(stage.name)
                        .font(FivoFont.cardTitle)
                        .foregroundStyle(FivoColor.textPrimary)
                    Text("· 第 \(days ?? 1) 天")
                        .font(FivoFont.callout)
                        .foregroundStyle(FivoColor.textSecondary)
                    Spacer()
                }
                Text("开始于 \(FivoDate.day(session.startedAt))")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
                if let note = session.note, !note.isEmpty {
                    Text(note)
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
                if plant.lifeStatus == .active {
                    GoldPrimaryButton(title: "切换状态", systemImage: "arrow.triangle.2.circlepath") {
                        showStageSwitch = true
                    }
                    .accessibilityIdentifier("plant.switchStage")
                }
            } else {
                Text("当前没有进行中的状态记录。")
                    .font(FivoFont.callout)
                    .foregroundStyle(FivoColor.textSecondary)
                if plant.lifeStatus == .active {
                    GoldPrimaryButton(title: "开始养叶养根", systemImage: "leaf") {
                        showStageSwitch = true
                    }
                }
            }
            Button {
                showHistory = true
            } label: {
                HStack {
                    Text("查看状态历史")
                    Spacer()
                    Image(systemName: "chevron.right")
                }
                .font(FivoFont.captionStrong)
                .foregroundStyle(FivoColor.textSecondary)
                .frame(minHeight: 32)
            }
        }
        .softCard(radius: FivoRadius.largeCard)
    }

    private var quickActions: some View {
        HStack(spacing: FivoSpacing.sm) {
            quickAction(title: "记养护", systemImage: "drop", identifier: "plant.care") { showCare = true }
            quickAction(title: "写日志", systemImage: "square.and.pencil", identifier: "plant.journal") { showAddJournal = true }
            quickAction(title: "加照片", systemImage: "photo", identifier: "plant.addPhotos") { showAddPhotos = true }
        }
    }

    private func quickAction(
        title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                Text(title)
                    .font(FivoFont.captionStrong)
            }
            .foregroundStyle(FivoColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 66)
            .softCard(radius: 18, padding: 8)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func segmentContent(_ plant: Plant) -> some View {
        switch segment {
        case .overview:
            overview(plant)
        case .journal:
            journalSection
        case .photos:
            photoSection(plant)
        case .stats:
            PlantStatisticsView(statistics: statistics)
        }
    }

    private func overview(_ plant: Plant) -> some View {
        VStack(alignment: .leading, spacing: FivoSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text("购买与来源")
                    .font(FivoFont.cardTitle)
                    .foregroundStyle(FivoColor.textPrimary)
                FieldRow(label: "购买日期", value: plant.acquiredAt.map(FivoDate.day) ?? "未填写")
                FieldRow(label: "入手价", value: plant.purchasePrice.map { FivoMoney.display($0, currency: plant.currency) } ?? "未填写")
                FieldRow(label: "平台", value: plant.platform ?? "未填写")
                FieldRow(label: "店铺", value: plant.storeName ?? "未填写")
                if let urlString = plant.sourceURL, let url = URL(string: urlString) {
                    HStack(alignment: .firstTextBaseline, spacing: FivoSpacing.sm) {
                        Text("来源链接")
                            .font(FivoFont.callout)
                            .foregroundStyle(FivoColor.textSecondary)
                            .frame(width: 82, alignment: .leading)
                        Link(urlString, destination: url)
                            .font(FivoFont.callout)
                            .lineLimit(1)
                    }
                } else {
                    FieldRow(label: "来源链接", value: "未填写")
                }
            }
            .softCard()

            VStack(alignment: .leading, spacing: 4) {
                Text("养护信息")
                    .font(FivoFont.cardTitle)
                    .foregroundStyle(FivoColor.textPrimary)
                FieldRow(label: "规格", value: plant.specification ?? "未填写")
                FieldRow(label: "植料", value: plant.medium ?? "未填写")
                FieldRow(label: "摆放位置", value: plant.location ?? "未填写")
                FieldRow(label: "备注", value: plant.notes ?? "未填写")
                FieldRow(label: "档案创建", value: FivoDate.day(plant.createdAt))
                FieldRow(label: "最近更新", value: FivoDate.dateTime(plant.updatedAt))
            }
            .softCard()

            let orderPhotos = photos.filter { $0.sourceType == .order }
            if !orderPhotos.isEmpty {
                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    Text("订单原始截图")
                        .font(FivoFont.cardTitle)
                        .foregroundStyle(FivoColor.textPrimary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: FivoSpacing.sm) {
                            ForEach(orderPhotos) { photo in
                                Button {
                                    selectedPhoto = photo
                                } label: {
                                    StoredImage(relativePath: photo.thumbnailRelativePath, imageStore: env.imageStore)
                                        .frame(width: 110, height: 110)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .softCard()
            }
        }
    }

    private var journalSection: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            if journals.isEmpty {
                EmptyStateView(
                    systemImage: "book.closed",
                    title: "还没有日志",
                    message: "状态切换、养护和照片会自动记录，也可以手动写一条。"
                )
            } else {
                ForEach(journals) { entry in
                    Button {
                        selectedJournal = entry
                    } label: {
                        JournalRow(
                            entry: entry,
                            plantName: plant?.name,
                            showPlant: false,
                            photos: JournalPhotoAssociation.photos(for: entry, in: photos)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("plant.journalEntry.\(entry.id.uuidString)")
                }
            }
        }
    }

    private func photoSection(_ plant: Plant) -> some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            if photos.isEmpty {
                EmptyStateView(
                    systemImage: "photo.on.rectangle",
                    title: "还没有照片",
                    message: "为这株植物添加生长记录照片。"
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
                        .accessibilityLabel("查看照片")
                        .accessibilityIdentifier("photoThumb.\(photo.id.uuidString)")
                    }
                }
            }
        }
    }

    // MARK: - Data

    private func load() {
        do {
            guard let loaded = try env.plants.plant(id: plantID) else {
                errorMessage = "植物档案不存在，可能已被删除。"
                plant = nil
                return
            }
            plant = loaded
            sessions = try env.growth.sessions(plantID: plantID)
            photos = try env.photos.photos(plantID: plantID)
            journals = try env.journal.entries(plantID: plantID)
            let stageList = try env.growth.stages(includeDisabled: true)
            stages = Dictionary(uniqueKeysWithValues: stageList.map { ($0.key, $0) })
            statistics = try env.growth.statistics(plantID: plantID)
            careActionTypes = try env.care.actionTypes(includeDisabled: false)
            careLogs = try env.care.logs(plantID: plantID)
            careReminders = try env.reminders.reminders().filter { $0.plantID == plantID }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func duplicate() {
        do {
            _ = try env.plants.duplicatePlant(id: plantID)
            env.showToast("已复制为新档案")
        } catch {
            env.showToast(error.localizedDescription)
        }
    }

    private func restore() {
        do {
            try env.plants.restore(plantID: plantID)
            env.showToast("已恢复档案")
            load()
        } catch {
            env.showToast(error.localizedDescription)
        }
    }

    private func deletePlant() {
        do {
            try env.plants.delete(plantID: plantID)
            env.showToast("已删除植物")
            dismiss()
        } catch {
            env.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Life event

struct LifeEventSheet: View {
    let plantID: UUID
    let kind: LifeEventKind

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var reason = ""
    @State private var recipient = ""
    @State private var errors: [String] = []
    @State private var isSaving = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                Text(kind == .dead ? "记录死亡日期，状态历史会在此结束，档案仍可查看和恢复。" : "记录赠送日期与接收人，档案仍可查看和恢复。")
                    .font(FivoFont.callout)
                    .foregroundStyle(FivoColor.textSecondary)

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    DatePicker(
                        "日期",
                        selection: $date,
                        in: purchaseDateRange,
                        displayedComponents: .date
                    )
                    .font(FivoFont.callout)
                    SoftTextField(
                        label: kind == .dead ? "原因" : "备注",
                        text: $reason,
                        placeholder: "选填",
                        axis: .vertical,
                        lineLimit: 2...4
                    )
                    if kind == .gifted {
                        SoftTextField(label: "接收人", text: $recipient, placeholder: "选填")
                    }
                    ForEach(errors, id: \.self) { message in
                        Label(message, systemImage: "exclamationmark.circle")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.danger)
                    }
                }
                .softCard()

                GoldPrimaryButton(title: kind.title, systemImage: kind == .dead ? "heart.slash" : "gift", isLoading: isSaving) {
                    save()
                }
            }
            .padding(FivoSpacing.page)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
    }

    private var purchaseDateRange: ClosedRange<Date> {
        let plant = env.plant(id: plantID)
        let lower = plant?.acquiredAt ?? Date.distantPast
        let upper = max(lower, Date())
        return lower...upper
    }

    private func save() {
        let acquiredAt = env.plant(id: plantID)?.acquiredAt
        let draft = LifeEventDraft(
            status: kind.status,
            date: date,
            reason: reason,
            recipient: recipient
        )
        errors = LifeEventValidator.errors(draft: draft, acquiredAt: acquiredAt, now: Date())
        guard errors.isEmpty else { return }
        isSaving = true
        do {
            try env.plants.setLifeStatus(
                plantID: plantID,
                status: kind.status,
                date: date,
                reason: PlantValidator.normalized(reason),
                recipient: PlantValidator.normalized(recipient)
            )
            env.showToast(kind == .dead ? "已标记死亡" : "已标记赠送")
            dismiss()
        } catch {
            errors = [error.localizedDescription]
        }
        isSaving = false
        }
}
