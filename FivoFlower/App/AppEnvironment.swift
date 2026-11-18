import Foundation
import SwiftData
import Observation
import UIKit

enum RootTab: String, CaseIterable, Identifiable {
    case garden
    case journal
    case ledger
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .garden: return "花房"
        case .journal: return "档案日志"
        case .ledger: return "花园账本"
        case .calendar: return "日历"
        }
    }

    var systemImage: String {
        switch self {
        case .garden: return "leaf"
        case .journal: return "book.closed"
        case .ledger: return "creditcard"
        case .calendar: return "calendar"
        }
    }
}

@MainActor
@Observable
final class AppEnvironment {
    let container: ModelContainer
    let dataStore: FivoDataStore
    let imageStore: ImageStore
    let notifications: NotificationScheduling
    let ocr: OCRServicing
    let backup: BackupServicing
    let csv: CSVExporting
    let calendar: Calendar
    let isUITestMode: Bool
    let persistenceWarning: String?
    let gardenQuery: GardenQuery

    var selectedTab: RootTab = .garden
    var toast: String?
    var dataRevision: Int = 0

    private var toastTask: Task<Void, Never>?

    init(
        container: ModelContainer,
        dataStore: FivoDataStore,
        imageStore: ImageStore,
        notifications: NotificationScheduling,
        ocr: OCRServicing,
        backup: BackupServicing,
        csv: CSVExporting,
        calendar: Calendar,
        isUITestMode: Bool,
        persistenceWarning: String?
    ) {
        self.container = container
        self.dataStore = dataStore
        self.imageStore = imageStore
        self.notifications = notifications
        self.ocr = ocr
        self.backup = backup
        self.csv = csv
        self.calendar = calendar
        self.isUITestMode = isUITestMode
        self.persistenceWarning = persistenceWarning
        self.gardenQuery = GardenQuery(calendar: calendar)
    }

    // MARK: - Repositories (protocol boundaries for feature views)

    var plants: PlantRepository { dataStore }
    var growth: GrowthRepository { dataStore }
    var photos: PhotoRepository { dataStore }
    var journal: JournalRepository { dataStore }
    var care: CareRepository { dataStore }
    var reminders: ReminderRepository { dataStore }
    var tools: ToolRepository { dataStore }
    var ledger: LedgerRepository { dataStore }
    var imports: ImportRepository { dataStore }

    // MARK: - Bootstrap

    static func bootstrap() -> AppEnvironment {
        let arguments = ProcessInfo.processInfo.arguments
        let isUITest = arguments.contains("-fivoUITestMode")
        var warning: String?

        let container: ModelContainer
        do {
            container = try PersistenceController.makeContainer(inMemory: isUITest)
        } catch {
            warning = "本地数据库打开失败，已切换到临时内存数据库：\(error.localizedDescription)"
            do {
                container = try PersistenceController.makeContainer(inMemory: true)
            } catch {
                fatalError("无法创建数据容器：\(error.localizedDescription)")
            }
        }
        container.mainContext.autosaveEnabled = false

        let imageStore: ImageStore
        if isUITest {
            let temp = FileManager.default.temporaryDirectory
                .appendingPathComponent("FivoUITestMedia-\(UUID().uuidString)", isDirectory: true)
            imageStore = LocalImageStore(baseDirectory: temp)
        } else {
            imageStore = LocalImageStore()
        }

        let dataStore = FivoDataStore(
            context: container.mainContext,
            imageStore: imageStore,
            now: { Date() },
            calendar: FivoDate.defaultCalendar
        )

        if isUITest {
            try? dataStore.clearAllData()
            MockSeedData.seedIfRequested(store: dataStore, arguments: arguments)
        }
        if arguments.contains("-resetData") {
            try? dataStore.clearAllData()
        }

        let environment = AppEnvironment(
            container: container,
            dataStore: dataStore,
            imageStore: imageStore,
            notifications: LocalNotificationService(),
            ocr: VisionOCRService(),
            backup: FileBackupService(store: dataStore, imageStore: imageStore),
            csv: FileCSVExporter(),
            calendar: FivoDate.defaultCalendar,
            isUITestMode: isUITest,
            persistenceWarning: warning
        )
        return environment
    }

    // MARK: - Helpers

    func showToast(_ message: String) {
        dataRevision += 1
        toastTask?.cancel()
        toast = message
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }

    func coverPath(for plant: Plant) -> String? {
        guard let coverID = plant.coverPhotoID else { return nil }
        if let cover = imageStore.coverRelativePath(forPhotoID: coverID) {
            return cover
        }
        return (try? dataStore.photo(id: coverID))?.thumbnailRelativePath
    }

    func thumbnailPath(for photo: PlantPhoto) -> String {
        photo.thumbnailRelativePath
    }

    func stage(key: String) -> GrowthStage? {
        (try? dataStore.stage(key: key))
    }

    func stageName(key: String) -> String {
        stage(key: key)?.name ?? GrowthStageKey.builtInName(for: key) ?? key
    }

    func plant(id: UUID) -> Plant? {
        try? dataStore.plant(id: id)
    }

    func reconcileNotifications() async {
        let all = (try? dataStore.reminders()) ?? []
        await notifications.reconcile(all)
    }

    func requestNotificationAuthorizationIfNeeded() async -> Bool {
        let status = await notifications.authorizationStatus()
        switch status {
        case .notDetermined:
            return await notifications.requestAuthorization()
        case .authorized:
            return true
        case .denied:
            return false
        }
    }
}

// MARK: - UI test seeding

@MainActor
enum MockSeedData {
    static func seedIfRequested(store: FivoDataStore, arguments: [String]) {
        guard arguments.contains("-seedMockPlants") else { return }
        let now = Date()
        let calendar = FivoDate.defaultCalendar
        let stages = (try? store.stages(includeDisabled: true)) ?? []
        let stageKeys = stages.map(\.key)
        let samples: [(String, Int, String)] = [
            ("白锦龟背竹", 400, GrowthStageKey.leafRoot),
            ("蝴蝶兰", 800, GrowthStageKey.bloom),
            ("月季", 40, GrowthStageKey.flowerSpike)
        ]
        for (index, sample) in samples.enumerated() {
            var draft = PlantDraft()
            draft.name = sample.0
            draft.acquiredAt = calendar.date(byAdding: .day, value: -sample.1, to: now)
            draft.purchasePriceText = "\(120 + index * 15)"
            draft.platform = "淘宝"
            draft.location = "阳台"
            var options = PlantCreationOptions()
            options.initialStageKey = stageKeys.contains(sample.2) ? sample.2 : GrowthStageKey.leafRoot
            options.coverPhoto = sampleImage(index: index, now: now)
            guard let plant = try? store.createPlant(draft: draft, options: options) else { continue }
            if index == 0 {
                let payloads = (0..<4).compactMap { offset in
                    sampleImage(index: index + offset + 1, now: now)
                }
                _ = try? store.addPhotos(
                    plantID: plant.id,
                    payloads: payloads,
                    source: .plant,
                    sourceID: nil,
                    caption: "示例照片"
                )
                if arguments.contains("-seedCalendarReminders"),
                   let action = try? store.actionTypes(includeDisabled: false).first(where: { $0.key == "water" }) {
                    let dayStart = calendar.startOfDay(for: now)
                    for hour in [8, 9] {
                        guard let dueAt = calendar.date(byAdding: .hour, value: hour, to: dayStart) else { continue }
                        _ = try? store.createReminders(ReminderDraft(
                            plantIDs: [plant.id],
                            actionTypeID: action.id,
                            title: "浇水",
                            dueAt: dueAt,
                            recurrence: .everyNDays(4)
                        ))
                    }
                }
            }
        }
    }

    private static func sampleImage(index: Int, now: Date) -> ImagePayload? {
        let colors: [UIColor] = [.systemGreen, .systemOrange, .systemPink, .systemTeal, .systemYellow, .systemPurple]
        // 故意交替极宽/极高比例，用于回归卡片与详情页的图片布局
        let size = index % 2 == 0 ? CGSize(width: 900, height: 300) : CGSize(width: 300, height: 900)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let color = colors[index % colors.count]
            color.withAlphaComponent(0.35).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            color.setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 40, y: 70, width: 220, height: 260))
        }
        guard let data = image.jpegData(compressionQuality: 0.8) else { return nil }
        return ImagePayload(data: data, capturedAt: now)
    }
}
