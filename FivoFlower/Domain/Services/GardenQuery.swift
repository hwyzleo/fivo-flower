import Foundation

/// 花房查询：搜索、分类、筛选与排序的纯 Swift 实现。
struct GardenQuery {
    var calendar: Calendar = FivoDate.defaultCalendar
    var classification = PlantClassificationService()

    func filter(
        plants: [Plant],
        filter: PlantFilter,
        currentStageKeys: [UUID: String]
    ) -> [Plant] {
        var result = plants
        if let category = filter.category {
            result = result.filter { classification.category(for: $0, now: Date()) == category }
        }
        if let stageKey = filter.stageKey {
            result = result.filter { currentStageKeys[$0.id] == stageKey }
        }
        if let platform = filter.platform {
            result = result.filter { ($0.platform ?? "") == platform }
        }
        if let location = filter.location {
            result = result.filter { ($0.location ?? "") == location }
        }
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { plant in
                let haystacks = [plant.name, plant.alias ?? "", plant.plantCode ?? "", plant.storeName ?? ""]
                return haystacks.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }
        switch filter.sort {
        case .recentlyUpdated:
            result.sort { $0.updatedAt > $1.updatedAt }
        case .purchaseDate:
            result.sort { lhs, rhs in
                switch (lhs.acquiredAt, rhs.acquiredAt) {
                case let (l?, r?): return l > r
                case (nil, nil): return lhs.updatedAt > rhs.updatedAt
                case (nil, _): return false
                case (_, nil): return true
                }
            }
        case .name:
            result.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return result
    }

    func category(for plant: Plant, now: Date) -> PlantCategory {
        classification.category(for: plant, now: now)
    }

    func counts(plants: [Plant], now: Date) -> [PlantCategory: Int] {
        classification.counts(for: plants, now: now)
    }

    func companionDays(for plant: Plant, now: Date) -> Int? {
        PlantDurationCalculator(calendar: calendar).companionDays(for: plant, now: now)
    }

    func platforms(plants: [Plant]) -> [String] {
        Array(Set(plants.compactMap { plant -> String? in
            guard let value = plant.platform, !value.isEmpty else { return nil }
            return value
        })).sorted()
    }

    func locations(plants: [Plant]) -> [String] {
        Array(Set(plants.compactMap { plant -> String? in
            guard let value = plant.location, !value.isEmpty else { return nil }
            return value
        })).sorted()
    }
}
