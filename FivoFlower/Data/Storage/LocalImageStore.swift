import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics

/// 本地文件图片存储：数据库只保存相对路径，原图与缩略图分离。
final class LocalImageStore: ImageStore {
    private let fileManager: FileManager
    let mediaDirectory: URL

    private let originalsDirectory: URL
    private let thumbnailsDirectory: URL
    private let coversDirectory: URL

    init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let base: URL
        if let baseDirectory {
            base = baseDirectory
        } else {
            let support = (try? fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )) ?? fileManager.temporaryDirectory
            base = support.appendingPathComponent("FivoFlowerMedia", isDirectory: true)
        }
        mediaDirectory = base
        originalsDirectory = base.appendingPathComponent("originals", isDirectory: true)
        thumbnailsDirectory = base.appendingPathComponent("thumbnails", isDirectory: true)
        coversDirectory = base.appendingPathComponent("covers", isDirectory: true)
        try? fileManager.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
    }

    func saveImage(data: Data) throws -> SavedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageStoreError.invalidImageData
        }
        let typeIdentifier = CGImageSourceGetType(source) as String?
        let ext: String
        if let typeIdentifier, let type = UTType(typeIdentifier), let preferred = type.preferredFilenameExtension {
            ext = preferred
        } else {
            ext = "jpg"
        }
        let identifier = UUID().uuidString
        let originalName = "\(identifier).\(ext)"
        let originalURL = originalsDirectory.appendingPathComponent(originalName)
        do {
            try data.write(to: originalURL, options: .atomic)
        } catch {
            throw ImageStoreError.writeFailed(error.localizedDescription)
        }

        let thumbnailName = "\(identifier).jpg"
        let thumbnailURL = thumbnailsDirectory.appendingPathComponent(thumbnailName)
        do {
            try makeThumbnail(from: source, to: thumbnailURL)
        } catch {
            try? fileManager.removeItem(at: originalURL)
            throw ImageStoreError.writeFailed(error.localizedDescription)
        }

        return SavedImage(
            originalRelativePath: "originals/\(originalName)",
            thumbnailRelativePath: "thumbnails/\(thumbnailName)"
        )
    }

    func saveCoverImage(data: Data, photoID: UUID) throws -> String {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageStoreError.invalidImageData
        }
        let name = "\(photoID.uuidString.lowercased()).jpg"
        let url = coversDirectory.appendingPathComponent(name)
        do {
            try writeJPEG(from: source, to: url, maxPixel: 1200, quality: 0.9)
        } catch {
            throw ImageStoreError.writeFailed(error.localizedDescription)
        }
        return "covers/\(name)"
    }

    func absoluteURL(for relativePath: String) -> URL {
        mediaDirectory.appendingPathComponent(relativePath)
    }

    func exists(relativePath: String) -> Bool {
        fileManager.fileExists(atPath: absoluteURL(for: relativePath).path)
    }

    func delete(relativePath: String) throws {
        let url = absoluteURL(for: relativePath)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func deleteAll() throws {
        guard fileManager.fileExists(atPath: mediaDirectory.path) else { return }
        try fileManager.removeItem(at: mediaDirectory)
        try fileManager.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: coversDirectory, withIntermediateDirectories: true)
    }

    func coverRelativePath(forPhotoID photoID: UUID) -> String? {
        let path = "covers/\(photoID.uuidString.lowercased()).jpg"
        return exists(relativePath: path) ? path : nil
    }

    func loadThumbnailData(relativePath: String) -> Data? {
        try? Data(contentsOf: absoluteURL(for: relativePath))
    }

    // MARK: - Private

    private func makeThumbnail(from source: CGImageSource, to url: URL) throws {
        try writeJPEG(from: source, to: url, maxPixel: 600, quality: 0.8, createThumbnail: true)
    }

    private func writeJPEG(
        from source: CGImageSource,
        to url: URL,
        maxPixel: Int,
        quality: CGFloat,
        createThumbnail: Bool = false
    ) throws {
        let image: CGImage?
        if createThumbnail {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ]
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        } else {
            image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        guard let image else {
            throw ImageStoreError.invalidImageData
        }
        // 缩放超大原图，控制封面体积
        var output = image
        let longest = max(image.width, image.height)
        if longest > maxPixel {
            let scale = CGFloat(maxPixel) / CGFloat(longest)
            let width = max(1, Int(CGFloat(image.width) * scale))
            let height = max(1, Int(CGFloat(image.height) * scale))
            if let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) {
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                if let scaled = context.makeImage() {
                    output = scaled
                }
            }
        }
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw ImageStoreError.writeFailed("无法创建图片输出")
        }
        CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw ImageStoreError.writeFailed("图片编码失败")
        }
    }
}
