import Foundation
import SwiftData

extension FivoDataStore: JournalRepository {

    func entries(plantID: UUID?) throws -> [JournalEntry] {
        let records: [JournalEntryRecord]
        if let plantID {
            records = try journalRecords(plantID: plantID)
        } else {
            records = try context.fetch(FetchDescriptor<JournalEntryRecord>())
        }
        return records
            .sorted { $0.occurredAt > $1.occurredAt }
            .map(\.domain)
    }

    func filtered(_ filter: JournalFilter) throws -> [JournalEntry] {
        let records = try context.fetch(FetchDescriptor<JournalEntryRecord>())
        let start = filter.startDate.map { FivoDate.startOfDay($0) }
        let end = filter.endDate.map { calendar.date(byAdding: .day, value: 1, to: FivoDate.startOfDay($0)) ?? $0 }
        return records
            .filter { record in
                if let plantID = filter.plantID, record.plantID != plantID { return false }
                if let kind = filter.kind, record.kindRaw != kind.rawValue { return false }
                if let start, record.occurredAt < start { return false }
                if let end, record.occurredAt >= end { return false }
                return true
            }
            .sorted { $0.occurredAt > $1.occurredAt }
            .map(\.domain)
    }

    func deleteManualEntry(id: UUID) throws {
        let descriptor = FetchDescriptor<JournalEntryRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(descriptor).first else { return }
        guard record.isManual else {
            throw DataError.validation("自动日志不能单独删除，请处理对应记录")
        }
        let sourceID = record.sourceID
        if let sourceID {
            let photos = try photoRecords(plantID: record.plantID)
                .filter { $0.sourceTypeRaw == PhotoSourceType.journal.rawValue && $0.sourceID == sourceID }
            for photo in photos {
                deletePhotoFile(photo)
                context.delete(photo)
            }
        }
        context.delete(record)
        try save()
    }

    func journalRecords(plantID: UUID) throws -> [JournalEntryRecord] {
        let descriptor = FetchDescriptor<JournalEntryRecord>(predicate: #Predicate { $0.plantID == plantID })
        return try context.fetch(descriptor)
    }
}

extension FivoDataStore: PhotoRepository {

    func photos(plantID: UUID) throws -> [PlantPhoto] {
        try photoRecords(plantID: plantID)
            .sorted { $0.capturedAt > $1.capturedAt }
            .map(\.domain)
    }

    func photo(id: UUID) throws -> PlantPhoto? {
        let descriptor = FetchDescriptor<PlantPhotoRecord>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first?.domain
    }

    func addPhotos(
        plantID: UUID,
        payloads: [ImagePayload],
        source: PhotoSourceType,
        sourceID: UUID?,
        caption: String?
    ) throws -> [PlantPhoto] {
        _ = try plantRecord(id: plantID)
        var created: [PlantPhotoRecord] = []
        do {
            for payload in payloads {
                let photo = try insertPhoto(
                    plantID: plantID,
                    payload: payload,
                    source: source,
                    sourceID: sourceID,
                    caption: caption,
                    logPhoto: source != .order
                )
                created.append(photo)
            }
            try save()
            return created.map(\.domain)
        } catch {
            for photo in created {
                deletePhotoFile(photo)
                context.delete(photo)
            }
            throw error
        }
    }

    func setCover(plantID: UUID, photoID: UUID, croppedImageData: Data?) throws {
        let plant = try plantRecord(id: plantID)
        let descriptor = FetchDescriptor<PlantPhotoRecord>(predicate: #Predicate { $0.id == photoID })
        guard let photo = try context.fetch(descriptor).first else {
            throw DataError.notFound("照片")
        }
        if let croppedImageData {
            _ = try imageStore.saveCoverImage(data: croppedImageData, photoID: photoID)
        }
        plant.coverPhotoID = photoID
        plant.updatedAt = now()
        try save()
    }

    func replaceCover(plantID: UUID, payload: ImagePayload) throws -> PlantPhoto {
        let plant = try plantRecord(id: plantID)
        let photo = try insertPhoto(
            plantID: plantID,
            payload: payload,
            source: .plant,
            sourceID: plantID,
            caption: "封面",
            logPhoto: false
        )
        plant.coverPhotoID = photo.id
        plant.updatedAt = now()
        try save()
        return photo.domain
    }

    func deletePhoto(id: UUID) throws {
        let descriptor = FetchDescriptor<PlantPhotoRecord>(predicate: #Predicate { $0.id == id })
        guard let photo = try context.fetch(descriptor).first else { return }
        let plantID = photo.plantID
        let plantDescriptor = FetchDescriptor<PlantRecord>(predicate: #Predicate { $0.id == plantID })
        if let plant = try context.fetch(plantDescriptor).first, plant.coverPhotoID == id {
            plant.coverPhotoID = nil
            plant.updatedAt = now()
        }
        deletePhotoFile(photo)
        deleteJournal(sourceType: .photo, sourceID: id)
        context.delete(photo)
        try save()
    }

    func allPhotoCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<PlantPhotoRecord>())
    }

    func photoRecords(plantID: UUID) throws -> [PlantPhotoRecord] {
        let descriptor = FetchDescriptor<PlantPhotoRecord>(predicate: #Predicate { $0.plantID == plantID })
        return try context.fetch(descriptor)
    }
}
