import SwiftUI

struct GardenHomeView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase

    @State private var plants: [Plant] = []
    @State private var sessions: [UUID: GrowthSession] = [:]
    @State private var stages: [String: GrowthStage] = [:]
    @State private var filter = PlantFilter()
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showAddPlant = false
    @State private var showImport = false
    @State private var showBatchCare = false
    @State private var detailPlantID: UUID?
    @State private var isSelectingPlants = false
    @State private var selectedPlantIDs: Set<UUID> = []

    private var query: GardenQuery { env.gardenQuery }

    private var categories: [UUID: PlantCategory] {
        var result: [UUID: PlantCategory] = [:]
        let now = Date()
        for plant in plants {
            result[plant.id] = query.category(for: plant, now: now)
        }
        return result
    }

    private var visiblePlants: [Plant] {
        let keys = sessions.mapValues(\.stageKey)
        return query.filter(plants: plants, filter: filter, currentStageKeys: keys)
    }

    private var counts: [PlantCategory: Int] {
        query.counts(plants: plants, now: Date())
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 14, alignment: .top),
        GridItem(.flexible(), spacing: 14, alignment: .top)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FivoSpacing.md) {
                    InsetSearchField(
                        placeholder: "搜索品种、别名、编号、店名",
                        text: $filter.query,
                        accessibilityIdentifier: "garden.search"
                    )

                    categoryChips
                    filterBar
                    if isSelectingPlants {
                        selectionBar
                    }

                    if let errorMessage {
                        ErrorStateView(message: errorMessage) {
                            load()
                        }
                    } else if plants.isEmpty {
                        EmptyStateView(
                            systemImage: "leaf",
                            title: "花房还是空的",
                            message: "先为一株植物建立档案，或从订单截图快速导入。",
                            actions: [
                                EmptyStateAction(title: "添加植物", systemImage: "plus", isPrimary: true) {
                                    showAddPlant = true
                                },
                                EmptyStateAction(title: "订单导入", systemImage: "doc.text.viewfinder") {
                                    showImport = true
                                }
                            ]
                        )
                        .padding(.top, FivoSpacing.lg)
                    } else if visiblePlants.isEmpty {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: "没有符合条件的植物",
                            message: "试试更换分类、筛选条件或搜索关键词。",
                            actions: [
                                EmptyStateAction(title: "清除筛选", systemImage: "xmark.circle") {
                                    clearFilters()
                                }
                            ]
                        )
                    } else {
                        LazyVGrid(columns: gridColumns, spacing: 16) {
                            ForEach(visiblePlants) { plant in
                                PlantCardView(
                                    plant: plant,
                                    category: categories[plant.id] ?? .unclassified,
                                    stage: sessions[plant.id].flatMap { stages[$0.stageKey] },
                                    companionDays: query.companionDays(for: plant, now: Date()),
                                    thumbnailPath: env.coverPath(for: plant),
                                    isSelecting: isSelectingPlants,
                                    isSelected: selectedPlantIDs.contains(plant.id)
                                )
                                .onTapGesture {
                                    if isSelectingPlants {
                                        toggleSelection(plant.id)
                                    } else {
                                        detailPlantID = plant.id
                                    }
                                }
                                .simultaneousGesture(
                                    LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                        beginSelection(plant.id)
                                    }
                                )
                                .accessibilityAddTraits(.isButton)
                            }
                        }
                    }
                }
                .fivoPagePadding()
                .padding(.top, FivoSpacing.xs)
                .padding(.bottom, 110)
            }
            .background(FivoColor.surfaceBase)
            .navigationTitle("Fivo的花花")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(item: $detailPlantID) { plantID in
                PlantDetailView(plantID: plantID)
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("设置")
                    .accessibilityIdentifier("garden.settings")
                }
            }
            .refreshable { load() }
            .task { load() }
            .onChange(of: scenePhase) { _, newValue in
                if newValue == .active { load() }
            }
            .onChange(of: env.dataRevision) { _, _ in
                load()
            }
            .sheet(isPresented: $showSettings, onDismiss: load) {
                SettingsView()
            }
            .sheet(isPresented: $showBatchCare, onDismiss: {
                exitSelection()
                load()
            }) {
                NavigationStack {
                    CareRecordView(preselectedPlantIDs: Array(selectedPlantIDs))
                }
            }
            .sheet(isPresented: $showAddPlant, onDismiss: load) {
                NavigationStack {
                    PlantEditView(mode: .create)
                }
            }
            .sheet(isPresented: $showImport, onDismiss: load) {
                NavigationStack {
                    OrderImportView()
                }
            }
        }
    }

    // MARK: - Sections

    private var selectionBar: some View {
        VStack(spacing: FivoSpacing.sm) {
            HStack {
                Text("已选 \(selectedPlantIDs.count) 株")
                    .font(FivoFont.callout.weight(.semibold))
                    .foregroundStyle(FivoColor.textPrimary)
                Spacer()
                Button("取消") { exitSelection() }
                    .font(FivoFont.captionStrong)
                    .accessibilityIdentifier("garden.cancelSelection")
            }
            HStack(spacing: FivoSpacing.sm) {
                Button(selectedPlantIDs.count == visiblePlants.count ? "取消全选" : "全选") {
                    if selectedPlantIDs.count == visiblePlants.count {
                        selectedPlantIDs.removeAll()
                    } else {
                        selectedPlantIDs = Set(visiblePlants.map(\.id))
                    }
                }
                .font(FivoFont.captionStrong)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(FivoColor.surfaceInset, in: Capsule())

                Button {
                    showBatchCare = true
                } label: {
                    Label("批量养护", systemImage: "drop")
                        .font(FivoFont.captionStrong)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(FivoColor.accentStart.opacity(0.65), in: Capsule())
                }
                .disabled(selectedPlantIDs.isEmpty)
                .accessibilityIdentifier("garden.batchCare")
            }
            .foregroundStyle(FivoColor.textPrimary)
        }
        .softCard(padding: FivoSpacing.sm)
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(
                    title: "全部",
                    count: plants.count,
                    isSelected: filter.category == nil
                ) {
                    filter.category = nil
                }
                ForEach(PlantCategory.allCases) { category in
                    FilterChip(
                        title: category.title,
                        count: counts[category] ?? 0,
                        isSelected: filter.category == category
                    ) {
                        filter.category = filter.category == category ? nil : category
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityIdentifier("garden.categories")
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button("全部状态") { filter.stageKey = nil }
                ForEach(stages.values.sorted(by: { $0.sortOrder < $1.sortOrder })) { stage in
                    Button(stage.name) { filter.stageKey = stage.key }
                }
            } label: {
                filterLabel(
                    title: filter.stageKey.map { stages[$0]?.name ?? env.stageName(key: $0) } ?? "状态",
                    active: filter.stageKey != nil,
                    systemImage: "camera.macro"
                )
            }

            Menu {
                Button("全部平台") { filter.platform = nil }
                ForEach(query.platforms(plants: plants), id: \.self) { platform in
                    Button(platform) { filter.platform = platform }
                }
            } label: {
                filterLabel(title: filter.platform ?? "平台", active: filter.platform != nil, systemImage: "bag")
            }

            Menu {
                Button("全部位置") { filter.location = nil }
                ForEach(query.locations(plants: plants), id: \.self) { location in
                    Button(location) { filter.location = location }
                }
            } label: {
                filterLabel(title: filter.location ?? "位置", active: filter.location != nil, systemImage: "mappin.and.ellipse")
            }

            Menu {
                ForEach(PlantSort.allCases) { sort in
                    Button {
                        filter.sort = sort
                    } label: {
                        if filter.sort == sort {
                            Label(sort.title, systemImage: "checkmark")
                        } else {
                            Text(sort.title)
                        }
                    }
                }
            } label: {
                filterLabel(title: "排序", active: filter.sort != .recentlyUpdated, systemImage: "arrow.up.arrow.down")
            }

            if filter.hasConditions {
                Button {
                    clearFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(FivoColor.textSecondary)
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("清除筛选")
            }
            Spacer(minLength: 0)
        }
    }

    private func filterLabel(title: String, active: Bool, systemImage: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
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

    private func clearFilters() {
        filter = PlantFilter()
    }

    private func beginSelection(_ plantID: UUID) {
        guard !isSelectingPlants else { return }
        isSelectingPlants = true
        selectedPlantIDs = [plantID]
    }

    private func toggleSelection(_ plantID: UUID) {
        if selectedPlantIDs.contains(plantID) {
            selectedPlantIDs.remove(plantID)
        } else {
            selectedPlantIDs.insert(plantID)
        }
    }

    private func exitSelection() {
        isSelectingPlants = false
        selectedPlantIDs.removeAll()
    }

    private func load() {
        do {
            plants = try env.plants.fetchPlants()
            sessions = try env.dataStore.currentSessionMap()
            let stageList = try env.growth.stages(includeDisabled: true)
            stages = Dictionary(uniqueKeysWithValues: stageList.map { ($0.key, $0) })
            selectedPlantIDs = selectedPlantIDs.intersection(plants.map(\.id))
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Plant card

struct PlantCardView: View {
    let plant: Plant
    let category: PlantCategory
    let stage: GrowthStage?
    let companionDays: Int?
    let thumbnailPath: String?
    var isSelecting = false
    var isSelected = false

    @Environment(AppEnvironment.self) private var env

    private var categoryTint: Color {
        switch category {
        case .dead, .gifted: return FivoColor.danger
        case .unclassified: return FivoColor.textSecondary
        default: return FivoColor.success
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            StoredImage(relativePath: thumbnailPath, imageStore: env.imageStore)
                .frame(height: 142)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .saturation(plant.isArchived ? 0.25 : 1)
                .overlay(alignment: .topLeading) {
                    StatusPill(text: category.title, systemImage: "leaf.fill", tint: categoryTint)
                        .padding(7)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelecting {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(isSelected ? FivoColor.accentEnd : FivoColor.textSecondary)
                            .background(Circle().fill(FivoColor.surfaceElevated))
                            .padding(10)
                    }
                }
                .padding(6)

            VStack(alignment: .leading, spacing: 6) {
                Text(plant.name)
                    .font(FivoFont.cardTitle)
                    .foregroundStyle(FivoColor.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if let stage {
                        StatusPill(
                            text: stage.name,
                            systemImage: "camera.macro",
                            tint: stageTint(stage)
                        )
                    } else {
                        StatusPill(text: "无状态", systemImage: "questionmark", tint: FivoColor.textSecondary)
                    }
                    Spacer(minLength: 0)
                }

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    if let companionDays {
                        Text("陪伴 \(companionDays) 天")
                            .font(FivoFont.captionStrong)
                            .foregroundStyle(FivoColor.textPrimary)
                    } else if plant.lifeStatus == .active {
                        Text("未填购买日期")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    } else {
                        Text(plant.lifeStatus.title)
                            .font(FivoFont.captionStrong)
                            .foregroundStyle(categoryTint)
                    }
                    Spacer(minLength: 0)
                    if let location = plant.location, !location.isEmpty {
                        Label(location, systemImage: "mappin")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 11)
            .padding(.top, 2)
        }
        .softCard(padding: 0)
        .contentShape(RoundedRectangle(cornerRadius: FivoRadius.card, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint(isSelecting ? (isSelected ? "已选中，点击取消选择" : "点击选择") : "点击查看详情，长按可多选")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("plantCard.\(plant.name)")
    }

    private func stageTint(_ stage: GrowthStage) -> Color {
        switch stage.colorToken {
        case "leaf": return FivoColor.success
        case "bloom": return Color(hex: 0xB05A86)
        case "spike": return Color(hex: 0xB0782A)
        default: return FivoColor.textSecondary
        }
    }
}
