import SwiftUI
import PhotosUI

// MARK: - Journal row

struct JournalRow: View {
    let entry: JournalEntry
    var plantName: String?
    var showPlant: Bool = true
    var photos: [PlantPhoto] = []

    @Environment(AppEnvironment.self) private var env

    var body: some View {
        HStack(alignment: .top, spacing: FivoSpacing.sm) {
            Image(systemName: entry.kind.symbolName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FivoColor.textPrimary)
                .frame(width: 36, height: 36)
                .background(
                    Circle().fill(FivoColor.accentStart.opacity(0.35))
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(FivoColor.textPrimary)
                    if entry.isManual {
                        StatusPill(text: "手动", tint: FivoColor.textSecondary)
                    }
                }
                if !entry.body.isEmpty {
                    Text(entry.body)
                        .font(FivoFont.callout)
                        .foregroundStyle(FivoColor.textSecondary)
                        .lineLimit(3)
                }
                HStack(spacing: 6) {
                    if showPlant, let plantName {
                        Text(plantName)
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textPrimary)
                        Text("·")
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                    Text(FivoDate.dateTime(entry.occurredAt))
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                    if entry.sourceType == nil && !entry.isManual {
                        Text("来源已删除")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.danger)
                    }
                }
            }
            Spacer(minLength: 0)
            if let firstPhoto = photos.first {
                StoredImage(relativePath: firstPhoto.thumbnailRelativePath, imageStore: env.imageStore)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        if photos.count > 1 {
                            Text("\(photos.count) 张")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(.black.opacity(0.6), in: Capsule())
                                .padding(4)
                        }
                    }
                    .accessibilityLabel(photos.count > 1 ? "日志图片，共 \(photos.count) 张" : "日志图片")
            }
        }
        .softCard(padding: FivoSpacing.sm)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Global journal

struct JournalHomeView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var entries: [JournalEntry] = []
    @State private var plants: [Plant] = []
    @State private var allPhotos: [PlantPhoto] = []
    @State private var filter = JournalFilter()
    @State private var showFilter = false
    @State private var showManual = false
    @State private var errorMessage: String?

    private var plantNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: plants.map { ($0.id, $0.name) })
    }

    private var grouped: [(String, [JournalEntry])] {
        let formatter = FivoDate.dayFormatter
        let groups = Dictionary(grouping: entries) { formatter.string(from: $0.occurredAt) }
        return groups
            .sorted { $0.key > $1.key }
            .map { ($0.key, $0.value.sorted { $0.occurredAt > $1.occurredAt }) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FivoSpacing.md) {
                    filterBar

                    if let errorMessage {
                        ErrorStateView(message: errorMessage) { load() }
                    } else if entries.isEmpty {
                        EmptyStateView(
                            systemImage: "book.closed",
                            title: "还没有档案日志",
                            message: "状态切换、养护、照片和资料修改都会自动记录。",
                            actions: [
                                EmptyStateAction(title: "写一条日志", systemImage: "square.and.pencil", isPrimary: true) {
                                    showManual = true
                                }
                            ]
                        )
                        .padding(.top, FivoSpacing.lg)
                    } else {
                        ForEach(grouped, id: \.0) { day, dayEntries in
                            VStack(alignment: .leading, spacing: FivoSpacing.xs) {
                                Text(day)
                                    .font(FivoFont.captionStrong)
                                    .foregroundStyle(FivoColor.textSecondary)
                                    .padding(.top, 4)
                                ForEach(dayEntries) { entry in
                                    NavigationLink(value: entry) {
                                        JournalRow(
                                            entry: entry,
                                            plantName: plantNames[entry.plantID],
                                            showPlant: true,
                                            photos: JournalPhotoAssociation.photos(for: entry, in: allPhotos)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("journal.entry.\(entry.id.uuidString)")
                                }
                            }
                        }
                    }
                }
                .fivoPagePadding()
                .padding(.bottom, 110)
            }
            .background(FivoColor.surfaceBase)
            .navigationTitle("档案日志")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: JournalEntry.self) { entry in
                JournalDetailView(entry: entry, plantName: plantNames[entry.plantID])
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showFilter = true
                    } label: {
                        Image(systemName: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("筛选日志")
                    Button {
                        showManual = true
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("写日志")
                    .accessibilityIdentifier("journal.add")
                }
            }
            .refreshable { load() }
            .task { load() }
            .onChange(of: env.dataRevision) { _, _ in load() }
            .sheet(isPresented: $showFilter, onDismiss: load) {
                JournalFilterSheet(filter: $filter)
            }
            .sheet(isPresented: $showManual, onDismiss: load) {
                NavigationStack { ManualJournalView(plantID: nil) }
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("全部植物") { filter.plantID = nil }
                ForEach(plants) { plant in
                    Button(plant.name) { filter.plantID = plant.id }
                }
            } label: {
                chip(
                    title: filter.plantID.flatMap { plantNames[$0] } ?? "植物",
                    active: filter.plantID != nil
                )
            }

            Menu {
                Button("全部类型") { filter.kind = nil }
                ForEach(JournalKind.allCases) { kind in
                    Button(kind.title) { filter.kind = kind }
                }
            } label: {
                chip(title: filter.kind?.title ?? "类型", active: filter.kind != nil)
            }

            if filter.startDate != nil || filter.endDate != nil {
                Button {
                    filter.startDate = nil
                    filter.endDate = nil
                } label: {
                    chip(title: "日期已筛选", active: true)
                }
            } else {
                Button {
                    showFilter = true
                } label: {
                    chip(title: "日期", active: false)
                }
            }

            if filter.isActive {
                Button {
                    filter = JournalFilter()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FivoColor.textSecondary)
                }
                .accessibilityLabel("清除日志筛选")
            }
            Spacer(minLength: 0)
        }
    }

    private func chip(title: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(FivoFont.captionStrong)
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(FivoColor.textPrimary)
        .padding(.horizontal, 10)
        .frame(minHeight: 34)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(active ? FivoColor.accentStart.opacity(0.55) : FivoColor.surfaceElevated)
        )
    }

    private func load() {
        do {
            plants = try env.plants.fetchPlants()
            entries = try env.journal.filtered(filter)
            allPhotos = try plants.flatMap { try env.photos.photos(plantID: $0.id) }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Filter sheet

struct JournalFilterSheet: View {
    @Binding var filter: JournalFilter

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var useStart = false
    @State private var start = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var useEnd = false
    @State private var end = Date()
    @State private var plants: [Plant] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FivoSpacing.md) {
                    VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                        Picker("植物", selection: Binding(
                            get: { filter.plantID },
                            set: { filter.plantID = $0 }
                        )) {
                            Text("全部植物").tag(UUID?.none)
                            ForEach(plants) { plant in
                                Text(plant.name).tag(UUID?.some(plant.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(FivoColor.textPrimary)

                        Picker("类型", selection: Binding(
                            get: { filter.kind },
                            set: { filter.kind = $0 }
                        )) {
                            Text("全部类型").tag(JournalKind?.none)
                            ForEach(JournalKind.allCases) { kind in
                                Text(kind.title).tag(JournalKind?.some(kind))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(FivoColor.textPrimary)
                    }
                    .softCard()

                    VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                        Toggle("指定开始日期", isOn: $useStart)
                            .font(FivoFont.callout)
                            .tint(FivoColor.accentEnd)
                        if useStart {
                            DatePicker("开始", selection: $start, in: ...Date(), displayedComponents: .date)
                                .font(FivoFont.callout)
                        }
                        Toggle("指定结束日期", isOn: $useEnd)
                            .font(FivoFont.callout)
                            .tint(FivoColor.accentEnd)
                        if useEnd {
                            DatePicker("结束", selection: $end, in: ...Date(), displayedComponents: .date)
                                .font(FivoFont.callout)
                        }
                    }
                    .softCard()

                    GoldPrimaryButton(title: "应用筛选", systemImage: "line.3.horizontal.decrease") {
                        filter.startDate = useStart ? start : nil
                        filter.endDate = useEnd ? end : nil
                        dismiss()
                    }

                    Button("清除全部筛选") {
                        filter = JournalFilter()
                        dismiss()
                    }
                    .font(FivoFont.callout)
                    .foregroundStyle(FivoColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(FivoSpacing.page)
            }
            .background(FivoColor.surfaceBase)
            .navigationTitle("筛选日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .task {
                plants = (try? env.plants.fetchPlants()) ?? []
                useStart = filter.startDate != nil
                useEnd = filter.endDate != nil
                if let startDate = filter.startDate { start = startDate }
                if let endDate = filter.endDate { end = endDate }
            }
        }
    }
}

// MARK: - Manual journal

struct ManualJournalView: View {
    let plantID: UUID?

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var plants: [Plant] = []
    @State private var selectedPlantID: UUID?
    @State private var occurredAt = Date()
    @State private var text = ""
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    if plantID == nil {
                        Picker("植物", selection: $selectedPlantID) {
                            Text("请选择植物").tag(UUID?.none)
                            ForEach(plants) { plant in
                                Text(plant.name).tag(UUID?.some(plant.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .tint(FivoColor.textPrimary)
                    } else if let plant = plants.first(where: { $0.id == plantID }) {
                        FieldRow(label: "植物", value: plant.name)
                    }
                    DatePicker("时间", selection: $occurredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                        .font(FivoFont.callout)
                }
                .softCard()

                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    SoftTextField(
                        label: "日志内容",
                        text: $text,
                        placeholder: "记录今天的观察、变化或心情",
                        axis: .vertical,
                        lineLimit: 4...10
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
        .navigationTitle("写日志")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GoldPrimaryButton(title: "保存日志", systemImage: "checkmark", isLoading: isSaving) {
                save()
            }
            .padding(.horizontal, FivoSpacing.page)
            .padding(.vertical, FivoSpacing.xs)
            .background(.ultraThinMaterial)
        }
        .task { load() }
    }

    private func load() {
        plants = (try? env.plants.fetchPlants()) ?? []
        selectedPlantID = plantID ?? plants.first?.id
    }

    private func save() {
        guard let selectedPlantID else {
            errorMessage = "请选择一株植物。"
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !photoItems.isEmpty else {
            errorMessage = "请填写文字或添加照片。"
            return
        }
        isSaving = true
        Task {
            let payloads = await PhotoPayloadLoader.payloads(from: photoItems)
            do {
                try env.plants.addManualJournal(
                    plantID: selectedPlantID,
                    occurredAt: occurredAt,
                    text: trimmed,
                    photos: payloads
                )
                env.showToast("已保存日志")
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
