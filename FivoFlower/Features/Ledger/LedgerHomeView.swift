import SwiftUI

enum LedgerSegment: String, CaseIterable, Identifiable {
    case entries = "账目"
    case tools = "工具库"

    var id: String { rawValue }
}

enum LedgerRoute: Hashable {
    case entry(UUID)
    case tool(UUID)
}

struct LedgerHomeView: View {
    @Environment(AppEnvironment.self) private var env

    @State private var segment: LedgerSegment = .entries
    @State private var entries: [LedgerEntry] = []
    @State private var tools: [ToolItem] = []
    @State private var plants: [Plant] = []
    @State private var period: LedgerPeriod = .month(Date())
    @State private var searchText = ""
    @State private var category: LedgerCategory?
    @State private var showCreateEntry = false
    @State private var showCreateTool = false
    @State private var showStats = false
    @State private var pendingDelete: LedgerEntry?
    @State private var errorMessage: String?

    private var plantNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: plants.map { ($0.id, $0.name) })
    }

    private var toolNames: [UUID: String] {
        Dictionary(uniqueKeysWithValues: tools.map { ($0.id, $0.name) })
    }

    private var summary: LedgerSummary {
        LedgerCalculator.summary(entries: entries, period: period, now: Date(), calendar: env.calendar)
    }

    private var filteredEntries: [LedgerEntry] {
        var result = entries.filter { period.contains($0.occurredAt, calendar: env.calendar) }
        if let category {
            result = result.filter { $0.category == category }
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { entry in
                let haystacks = [
                    entry.title,
                    entry.platform ?? "",
                    entry.storeName ?? "",
                    entry.note ?? "",
                    entry.plantID.flatMap { plantNames[$0] } ?? "",
                    entry.toolID.flatMap { toolNames[$0] } ?? ""
                ]
                return haystacks.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        return result.sorted { $0.occurredAt > $1.occurredAt }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: FivoSpacing.md) {
                    Picker("账本分段", selection: $segment) {
                        ForEach(LedgerSegment.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("ledger.segment")

                    if let errorMessage {
                        ErrorStateView(message: errorMessage) { load() }
                    } else if segment == .entries {
                        ledgerContent
                    } else {
                        toolsContent
                    }
                }
                .fivoPagePadding()
                .padding(.bottom, 110)
            }
            .background(FivoColor.surfaceBase)
            .navigationTitle("花园账本")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: LedgerRoute.self) { route in
                switch route {
                case .entry(let id):
                    LedgerEntryEditor(entryID: id, preselectPlantID: nil, preselectToolID: nil)
                case .tool(let id):
                    ToolDetailView(toolID: id)
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showStats = true
                    } label: {
                        Image(systemName: "chart.bar.xaxis")
                    }
                    .accessibilityLabel("生长统计")
                    Button {
                        if segment == .entries {
                            showCreateEntry = true
                        } else {
                            showCreateTool = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(segment == .entries ? "记一笔" : "添加工具")
                    .accessibilityIdentifier("ledger.add")
                }
            }
            .refreshable { load() }
            .task { load() }
            .onChange(of: env.dataRevision) { _, _ in load() }
            .sheet(isPresented: $showCreateEntry, onDismiss: load) {
                NavigationStack {
                    LedgerEntryEditor(entryID: nil, preselectPlantID: nil, preselectToolID: nil)
                }
            }
            .sheet(isPresented: $showCreateTool, onDismiss: load) {
                NavigationStack { ToolEditView(toolID: nil) }
            }
            .sheet(isPresented: $showStats, onDismiss: load) {
                NavigationStack { GardenStatisticsView() }
            }
            .confirmationDialog("删除这条账目？", isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ), titleVisibility: .visible) {
                Button("删除账目", role: .destructive) {
                    if let entry = pendingDelete { delete(entry) }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("关联到这条支出的退款会解除关联，汇总将重新计算。")
            }
        }
    }

    // MARK: - Ledger content

    private var ledgerContent: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.md) {
            summaryCard
            periodBar
            categorySummary
            trendCard
            searchBar
            entryList
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            HStack {
                Text("累计投入")
                    .font(FivoFont.captionStrong)
                    .foregroundStyle(FivoColor.textSecondary)
                Spacer()
                Text(period.title)
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
            }
            Text(FivoMoney.display(summary.totalInvestment))
                .font(FivoFont.numberLarge)
                .foregroundStyle(FivoColor.textPrimary)
                .accessibilityIdentifier("ledger.totalInvestment")
            HStack(spacing: FivoSpacing.sm) {
                miniStat(title: "植物投入", value: FivoMoney.display(summary.plantInvestment))
                miniStat(title: "工具资材", value: FivoMoney.display(summary.toolInvestment))
            }
            DividerSoft()
            HStack(spacing: FivoSpacing.sm) {
                miniStat(title: "所选周期支出", value: FivoMoney.display(summary.periodExpense))
                miniStat(title: "收入", value: FivoMoney.display(summary.totalIncome))
            }
            Text("累计投入 = 支出 − 关联退款，不代表当前资产估值。")
                .font(FivoFont.caption)
                .foregroundStyle(FivoColor.textSecondary)
        }
        .softCard(radius: FivoRadius.largeCard)
    }

    private func miniStat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(FivoFont.caption)
                .foregroundStyle(FivoColor.textSecondary)
            Text(value)
                .font(FivoFont.callout.weight(.semibold))
                .foregroundStyle(FivoColor.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var periodBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                periodChip("全部", isSelected: isAllPeriod) { period = .all }
                periodChip("本月", isSelected: isCurrentMonth) { period = .month(Date()) }
                periodChip("今年", isSelected: isCurrentYear) { period = .year(env.calendar.component(.year, from: Date())) }
                periodChip("去年", isSelected: isLastYear) {
                    period = .year(env.calendar.component(.year, from: Date()) - 1)
                }
            }
        }
    }

    private var isAllPeriod: Bool {
        if case .all = period { return true }
        return false
    }

    private var isCurrentMonth: Bool {
        if case .month(let date) = period {
            return env.calendar.isDate(date, equalTo: Date(), toGranularity: .month)
        }
        return false
    }

    private var isCurrentYear: Bool {
        if case .year(let year) = period {
            return year == env.calendar.component(.year, from: Date())
        }
        return false
    }

    private var isLastYear: Bool {
        if case .year(let year) = period {
            return year == env.calendar.component(.year, from: Date()) - 1
        }
        return false
    }

    private func periodChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(FivoFont.captionStrong)
                .foregroundStyle(FivoColor.textPrimary)
                .padding(.horizontal, 12)
                .frame(minHeight: 34)
                .background(
                    Capsule().fill(isSelected ? FivoColor.accentStart.opacity(0.65) : FivoColor.surfaceElevated)
                )
        }
        .buttonStyle(.plain)
    }

    private var categorySummary: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.xs) {
            Text("分类汇总")
                .font(FivoFont.cardTitle)
                .foregroundStyle(FivoColor.textPrimary)
            let totals = summary.categoryTotals
                .filter { $0.value != 0 }
                .sorted { $0.value > $1.value }
            if totals.isEmpty {
                Text("所选周期内还没有支出。")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
            } else {
                ForEach(totals, id: \.key) { item in
                    HStack {
                        Text(item.key.title)
                            .font(FivoFont.callout)
                            .foregroundStyle(FivoColor.textSecondary)
                        Spacer()
                        Text(FivoMoney.display(item.value))
                            .font(FivoFont.callout.weight(.semibold))
                            .foregroundStyle(FivoColor.textPrimary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .softCard()
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.xs) {
            Text("月度趋势")
                .font(FivoFont.cardTitle)
                .foregroundStyle(FivoColor.textPrimary)
            let year = trendYear
            let points = monthlyPoints(for: year)
            let maxValue = points.map(\.amount).max() ?? 0
            HStack(alignment: .bottom, spacing: 5) {
                ForEach(points) { point in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [FivoColor.accentStart, FivoColor.accentEnd],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(height: maxValue > 0
                                   ? max(3, CGFloat(NSDecimalNumber(decimal: point.amount).doubleValue / NSDecimalNumber(decimal: maxValue).doubleValue) * 70)
                                   : 3)
                        Text("\(point.month)")
                            .font(.system(size: 8))
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 92, alignment: .bottom)
            Text("\(year) 年支出（含关联退款冲减）")
                .font(FivoFont.caption)
                .foregroundStyle(FivoColor.textSecondary)
        }
        .softCard()
    }

    private var trendYear: Int {
        switch period {
        case .all: return env.calendar.component(.year, from: Date())
        case .month(let date): return env.calendar.component(.year, from: date)
        case .year(let year): return year
        }
    }

    private func monthlyPoints(for year: Int) -> [YearlySpendPoint] {
        let allMonths = LedgerCalculator.summary(
            entries: entries.filter { env.calendar.component(.year, from: $0.occurredAt) == year },
            period: .year(year),
            now: Date(),
            calendar: env.calendar
        ).monthlyTrend
        return (1...12).map { month in
            YearlySpendPoint(
                month: month,
                amount: allMonths.first(where: { $0.month == month })?.amount ?? 0
            )
        }
    }

    private var searchBar: some View {
        VStack(spacing: FivoSpacing.xs) {
            InsetSearchField(placeholder: "搜索账目、平台、店铺、备注", text: $searchText, accessibilityIdentifier: "ledger.search")
            HStack(spacing: 8) {
                Menu {
                    Button("全部分类") { category = nil }
                    ForEach(LedgerCategory.allCases) { item in
                        Button(item.title) { category = item }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(category?.title ?? "全部分类")
                            .font(FivoFont.captionStrong)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(FivoColor.textPrimary)
                    .padding(.horizontal, 10)
                    .frame(minHeight: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(category != nil ? FivoColor.accentStart.opacity(0.55) : FivoColor.surfaceElevated)
                    )
                }
                Spacer()
                Text("\(filteredEntries.count) 笔")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
            }
        }
    }

    private var entryList: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.xs) {
            if filteredEntries.isEmpty {
                EmptyStateView(
                    systemImage: "creditcard",
                    title: "没有匹配的账目",
                    message: "记录一笔支出、收入或退款，或调整筛选条件。",
                    actions: [
                        EmptyStateAction(title: "记一笔", systemImage: "plus", isPrimary: true) {
                            showCreateEntry = true
                        }
                    ]
                )
            } else {
                ForEach(filteredEntries) { entry in
                    NavigationLink(value: LedgerRoute.entry(entry.id)) {
                        LedgerEntryRow(
                            entry: entry,
                            plantName: entry.plantID.flatMap { plantNames[$0] },
                            toolName: entry.toolID.flatMap { toolNames[$0] }
                        )
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            pendingDelete = entry
                        } label: {
                            Label("删除账目", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tools content

    private var toolsContent: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.md) {
            lowStockCard
            HStack {
                Text("工具资材")
                    .font(FivoFont.sectionTitle)
                    .foregroundStyle(FivoColor.textPrimary)
                Spacer()
                Button("添加") { showCreateTool = true }
                    .font(FivoFont.captionStrong)
                    .foregroundStyle(FivoColor.textPrimary)
            }
            if tools.isEmpty {
                EmptyStateView(
                    systemImage: "shippingbox",
                    title: "工具库是空的",
                    message: "登记花盆、植料、补光灯等工具资材，掌握库存与设备状态。",
                    actions: [
                        EmptyStateAction(title: "添加工具", systemImage: "plus", isPrimary: true) {
                            showCreateTool = true
                        }
                    ]
                )
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    ForEach(tools) { tool in
                        NavigationLink(value: LedgerRoute.tool(tool.id)) {
                            ToolCardView(tool: tool)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var lowStockCard: some View {
        let lowStock = tools.filter(\.isLowStock)
        return Group {
            if lowStock.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: FivoSpacing.xs) {
                    Label("低库存提醒", systemImage: "exclamationmark.triangle")
                        .font(FivoFont.cardTitle)
                        .foregroundStyle(FivoColor.danger)
                    ForEach(lowStock) { tool in
                        HStack {
                            Text(tool.name)
                                .font(FivoFont.callout)
                                .foregroundStyle(FivoColor.textPrimary)
                            Spacer()
                            Text("\(FivoMoney.plainString(tool.stock)) \(tool.stockUnit)")
                                .font(FivoFont.captionStrong)
                                .foregroundStyle(FivoColor.textSecondary)
                        }
                    }
                }
                .softCard()
            }
        }
    }

    // MARK: - Data

    private func load() {
        do {
            entries = try env.ledger.entries()
            tools = try env.tools.tools()
            plants = try env.plants.fetchPlants()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ entry: LedgerEntry) {
        do {
            try env.ledger.deleteEntry(id: entry.id)
            env.showToast("已删除账目")
            load()
        } catch {
            env.showToast(error.localizedDescription)
        }
    }
}

// MARK: - Rows

struct LedgerEntryRow: View {
    let entry: LedgerEntry
    var plantName: String?
    var toolName: String?

    private var amountText: String {
        switch entry.kind {
        case .expense: return "−" + FivoMoney.display(entry.amount)
        case .income: return "+" + FivoMoney.display(entry.amount)
        case .refund: return "+" + FivoMoney.display(entry.amount)
        }
    }

    private var amountColor: Color {
        entry.kind == .expense ? FivoColor.textPrimary : FivoColor.success
    }

    var body: some View {
        HStack(alignment: .top, spacing: FivoSpacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(FivoFont.cardTitle)
                        .foregroundStyle(FivoColor.textPrimary)
                        .lineLimit(1)
                    if entry.sourceType != nil && entry.sourceType != .manual {
                        StatusPill(text: "自动", tint: FivoColor.textSecondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(entry.category.title)
                    if let plantName {
                        Text("·")
                        Text(plantName)
                    } else if let toolName {
                        Text("·")
                        Text(toolName)
                    }
                }
                .font(FivoFont.caption)
                .foregroundStyle(FivoColor.textSecondary)
                .lineLimit(1)
                HStack(spacing: 6) {
                    if let platform = entry.platform, !platform.isEmpty {
                        Text(platform)
                    }
                    if let store = entry.storeName, !store.isEmpty {
                        Text(store)
                    }
                    Text(FivoDate.day(entry.occurredAt))
                }
                .font(FivoFont.caption)
                .foregroundStyle(FivoColor.textSecondary)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                Text(amountText)
                    .font(FivoFont.callout.weight(.bold))
                    .foregroundStyle(amountColor)
                Text(entry.kind.title)
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
            }
        }
        .softCard(padding: FivoSpacing.sm)
    }
}

struct ToolCardView: View {
    let tool: ToolItem
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StoredImage(relativePath: tool.photoRelativePath, imageStore: env.imageStore)
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            HStack(spacing: 5) {
                Image(systemName: tool.category.symbolName)
                    .font(.system(size: 10, weight: .semibold))
                Text(tool.category.title)
                    .font(FivoFont.caption)
            }
            .foregroundStyle(FivoColor.textSecondary)
            Text(tool.name)
                .font(FivoFont.cardTitle)
                .foregroundStyle(FivoColor.textPrimary)
                .lineLimit(1)
            HStack {
                if tool.isConsumable {
                    Text("\(FivoMoney.plainString(tool.stock)) \(tool.stockUnit)")
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(tool.isLowStock ? FivoColor.danger : FivoColor.textPrimary)
                } else {
                    Text("×\(tool.quantity)")
                        .font(FivoFont.captionStrong)
                        .foregroundStyle(FivoColor.textPrimary)
                }
                Spacer()
                if let price = tool.purchasePrice {
                    Text(FivoMoney.display(price))
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
            }
            if tool.isDevice {
                Text(tool.isPoweredOn ? "使用中（仅记录）" : "已关闭（仅记录）")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
            }
        }
        .softCard(padding: FivoSpacing.sm)
        .accessibilityIdentifier("toolCard.\(tool.name)")
    }
}
