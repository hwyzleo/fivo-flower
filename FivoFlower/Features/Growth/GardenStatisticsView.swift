import SwiftUI

struct GardenStatisticsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var plants: [Plant] = []
    @State private var sessions: [GrowthSession] = []
    @State private var selectedPlantID: UUID?
    @State private var year: Int = Calendar.current.component(.year, from: Date())
    @State private var statsByPlant: [UUID: PlantStatistics] = [:]

    private var service: PlantStatisticsService {
        PlantStatisticsService(calendar: env.calendar)
    }

    private var selectedStats: PlantStatistics? {
        selectedPlantID.flatMap { statsByPlant[$0] }
    }

    private var trend: [YearlyGrowthPoint] {
        let filtered = selectedPlantID.map { id in sessions.filter { $0.plantID == id } } ?? sessions
        return service.yearlyTrend(sessions: filtered, year: year, now: Date())
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                HStack(spacing: 8) {
                    Picker("植物", selection: $selectedPlantID) {
                        Text("全部植物").tag(UUID?.none)
                        ForEach(plants) { plant in
                            Text(plant.name).tag(UUID?.some(plant.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(FivoColor.textPrimary)

                    Picker("年份", selection: $year) {
                        ForEach(yearOptions, id: \.self) { value in
                            Text("\(value) 年").tag(value)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(FivoColor.textPrimary)
                    Spacer()
                }
                .softCard(padding: FivoSpacing.sm)

                trendCard

                if let selectedStats {
                    PlantStatisticsView(statistics: selectedStats)
                } else {
                    VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                        Text("各株统计")
                            .font(FivoFont.sectionTitle)
                            .foregroundStyle(FivoColor.textPrimary)
                        if plants.isEmpty {
                            Text("还没有植物档案。")
                                .font(FivoFont.caption)
                                .foregroundStyle(FivoColor.textSecondary)
                        } else {
                            ForEach(plants) { plant in
                                let stats = statsByPlant[plant.id] ?? .empty
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(plant.name)
                                            .font(FivoFont.callout.weight(.semibold))
                                            .foregroundStyle(FivoColor.textPrimary)
                                        Spacer()
                                        Text("出花梗 \(stats.spikeCount) · 开花 \(stats.bloomCount)")
                                            .font(FivoFont.caption)
                                            .foregroundStyle(FivoColor.textSecondary)
                                    }
                                    Text(
                                        stats.averageBloomDurationDays.map { String(format: "平均开花 %.1f 天", $0) }
                                        ?? "暂无已结束的开花记录"
                                    )
                                    .font(FivoFont.caption)
                                    .foregroundStyle(FivoColor.textSecondary)
                                }
                                .softCard(padding: FivoSpacing.sm)
                            }
                        }
                    }
                }
            }
            .padding(FivoSpacing.page)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle("生长统计")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("关闭") { dismiss() }
            }
        }
        .task { load() }
    }

    private var yearOptions: [Int] {
        let current = env.calendar.component(.year, from: Date())
        let years = Set(sessions.map { env.calendar.component(.year, from: $0.startedAt) } + [current])
        return years.sorted(by: >)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: FivoSpacing.xs) {
            Text("\(year) 年趋势")
                .font(FivoFont.cardTitle)
                .foregroundStyle(FivoColor.textPrimary)
            let maxValue = max(1, trend.map { max($0.spikeCount, $0.bloomCount) }.max() ?? 1)
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(trend) { point in
                    VStack(spacing: 3) {
                        VStack(spacing: 2) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(FivoColor.success)
                                .frame(height: CGFloat(point.spikeCount) / CGFloat(maxValue) * 34)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(FivoColor.accentEnd)
                                .frame(height: CGFloat(point.bloomCount) / CGFloat(maxValue) * 34)
                        }
                        .frame(height: 70, alignment: .bottom)
                        Text("\(point.month)")
                            .font(.system(size: 8))
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            HStack(spacing: FivoSpacing.md) {
                Label("出花梗", systemImage: "square.fill")
                    .foregroundStyle(FivoColor.success)
                Label("开花", systemImage: "square.fill")
                    .foregroundStyle(FivoColor.accentEnd)
            }
            .font(FivoFont.caption)
        }
        .softCard()
    }

    private func load() {
        plants = (try? env.plants.fetchPlants()) ?? []
        sessions = (try? env.dataStore.allSessions()) ?? []
        var result: [UUID: PlantStatistics] = [:]
        for plant in plants {
            let plantSessions = sessions.filter { $0.plantID == plant.id }
            result[plant.id] = service.statistics(sessions: plantSessions, now: Date())
        }
        statsByPlant = result
    }
}
