import SwiftUI
import UIKit
import PhotosUI

// MARK: - Stored image loading

@MainActor
final class StoredImageCache {
    static let shared = StoredImageCache()
    private let cache = NSCache<NSString, UIImage>()
    private var inFlight: Set<String> = []

    private init() {
        cache.countLimit = 300
    }

    func cached(path: String) -> UIImage? {
        cache.object(forKey: path as NSString)
    }

    func load(path: String, absoluteURL: URL) async -> UIImage? {
        if let cached = cached(path: path) { return cached }
        guard !inFlight.contains(path) else { return nil }
        inFlight.insert(path)
        defer { inFlight.remove(path) }
        let image = await Task.detached(priority: .utility) { () -> UIImage? in
            guard let data = try? Data(contentsOf: absoluteURL) else { return nil }
            return UIImage(data: data)
        }.value
        if let image {
            cache.setObject(image, forKey: path as NSString)
        }
        return image
    }

    func clear() {
        cache.removeAllObjects()
    }
}

/// 从本地相对路径异步加载图片；列表使用缩略图路径。
struct StoredImage: View {
    let relativePath: String?
    let imageStore: ImageStore
    var contentMode: ContentMode = .fill

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        // 始终由 Color.clear 接受父视图给出的布局尺寸，
        // 图片只作为 overlay 绘制并裁切，避免竖图/横图的固有尺寸把卡片撑宽。
        Color.clear
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else if failed || relativePath == nil {
                    placeholder
                } else {
                    ProgressView()
                        .tint(FivoColor.textSecondary)
                }
            }
            .clipped()
            .task(id: relativePath) {
                await load()
            }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [
                    FivoColor.accentStart.opacity(0.28),
                    FivoColor.surfaceInset,
                    FivoColor.accentEnd.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "leaf")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(FivoColor.textSecondary.opacity(0.65))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func load() async {
        guard let relativePath else {
            image = nil
            failed = true
            return
        }
        if let cached = StoredImageCache.shared.cached(path: relativePath) {
            image = cached
            return
        }
        let url = imageStore.absoluteURL(for: relativePath)
        let loaded = await StoredImageCache.shared.load(path: relativePath, absoluteURL: url)
        image = loaded
        failed = loaded == nil
    }
}

// MARK: - Thumbnails

/// 固定宽高比的本地图片缩略图，避免原图固有尺寸撑破网格布局。
struct LocalImageThumbnail: View {
    let data: Data
    var aspectRatio: CGFloat = 1
    var cornerRadius: CGFloat = 12

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                if let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    FivoColor.surfaceInset
                        .overlay {
                            Image(systemName: "photo")
                                .foregroundStyle(FivoColor.textSecondary)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .clipped()
            .accessibilityLabel("已选图片")
    }
}

/// 固定宽高比的本地文件缩略图（照片墙等）。
struct StoredImageThumbnail: View {
    let relativePath: String?
    let imageStore: ImageStore
    var aspectRatio: CGFloat = 1
    var cornerRadius: CGFloat = 12

    var body: some View {
        Color.clear
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                StoredImage(relativePath: relativePath, imageStore: imageStore, contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .clipped()
    }
}

// MARK: - Photo picking

enum PhotoPayloadLoader {
    static func payloads(from items: [PhotosPickerItem]) async -> [ImagePayload] {
        var result: [ImagePayload] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self) {
                result.append(ImagePayload(data: data, capturedAt: Date()))
            }
        }
        return result
    }
}

struct PhotoPickerRow: View {
    let title: String
    @Binding var items: [PhotosPickerItem]
    var maxSelection: Int = 9
    var existingCount: Int = 0

    var body: some View {
        PhotosPicker(
            selection: $items,
            maxSelectionCount: max(1, maxSelection - existingCount),
            matching: .images
        ) {
            HStack(spacing: FivoSpacing.xs) {
                Image(systemName: "photo.on.rectangle.angled")
                Text(title)
                Spacer()
                Text("\(existingCount + items.count) 张")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.textSecondary)
            }
            .font(FivoFont.callout.weight(.semibold))
            .foregroundStyle(FivoColor.textPrimary)
            .padding(.horizontal, FivoSpacing.md)
            .frame(minHeight: 46)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(FivoColor.separator.opacity(0.7), lineWidth: 1)
                    }
            }
        }
    }
}

// MARK: - Cover crop

/// 方形封面裁剪，可选设备端自动抠图；抠图后背景替换为柔和底色。
struct CoverCropView: View {
    let image: UIImage
    var onSave: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isSaving = false

    @State private var useCutout = false
    @State private var cutoutImage: UIImage?
    @State private var isExtracting = false
    @State private var cutoutError: String?
    @State private var cutoutTask: Task<Void, Never>?

    private let cropSide: CGFloat = 320

    private var activeImage: UIImage {
        useCutout ? (cutoutImage ?? image) : image
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: FivoSpacing.lg) {
                    GeometryReader { _ in
                        ZStack {
                            Color.black.opacity(0.04)
                            ZStack {
                                if useCutout {
                                    FivoColor.coverBackdrop
                                }
                                Image(uiImage: activeImage)
                                    .resizable()
                                    .aspectRatio(contentMode: useCutout ? .fit : .fill)
                                    .frame(width: cropSide * scale, height: cropSide * scale)
                                    .offset(offset)
                            }
                            .frame(width: cropSide, height: cropSide)
                            .clipped()
                            .overlay {
                                Rectangle()
                                    .strokeBorder(Color.white, lineWidth: 2)
                            }
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in
                                        lastOffset = offset
                                    }
                            )
                            .simultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = max(1, min(4, lastScale * value))
                                    }
                                    .onEnded { _ in
                                        lastScale = scale
                                    }
                            )

                            if isExtracting {
                                Color.black.opacity(0.25)
                                ProgressView("正在提取主体…")
                                    .tint(.white)
                                    .foregroundStyle(.white)
                                    .padding(FivoSpacing.md)
                                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(height: 360)

                    VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                        Toggle(isOn: Binding(
                            get: { useCutout },
                            set: { setCutout($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("自动抠图（本地）")
                                    .font(FivoFont.callout.weight(.semibold))
                                    .foregroundStyle(FivoColor.textPrimary)
                                Text(cutoutToggleDescription)
                                    .font(FivoFont.caption)
                                    .foregroundStyle(FivoColor.textSecondary)
                            }
                        }
                        .disabled(isExtracting || !ForegroundCutoutService.isSupported)
                        .tint(FivoColor.accentEnd)

                        if let cutoutError {
                            Label(cutoutError, systemImage: "exclamationmark.circle")
                                .font(FivoFont.caption)
                                .foregroundStyle(FivoColor.danger)
                        }
                        if useCutout && cutoutImage != nil && !isExtracting {
                            Text("已抠图，可继续拖动/缩放调整封面构图。")
                                .font(FivoFont.caption)
                                .foregroundStyle(FivoColor.textSecondary)
                        }
                    }
                    .softCard(padding: FivoSpacing.sm)

                    Text("拖动调整位置，双指缩放；保存后仅影响封面，不修改原图。")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                        .multilineTextAlignment(.center)

                    GoldPrimaryButton(title: "保存封面", systemImage: "checkmark", isLoading: isSaving) {
                        save()
                    }
                    .disabled(isExtracting)
                }
                .padding(FivoSpacing.page)
            }
            .background(FivoColor.surfaceBase)
            .navigationTitle("编辑封面")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onDisappear {
                cutoutTask?.cancel()
            }
        }
    }

    private var cutoutToggleDescription: String {
        if ForegroundCutoutService.isSupported {
            return "只保留花朵/主体，背景替换为柔和底色。设备端处理，不联网。"
        }
        return "自动抠图依赖设备端主体分割，模拟器不支持，请在真机 iPhone 上使用。"
    }

    private func setCutout(_ enabled: Bool) {
        cutoutError = nil
        if !enabled {
            useCutout = false
            return
        }
        useCutout = true
        resetTransform()
        guard cutoutImage == nil else { return }
        isExtracting = true
        cutoutTask?.cancel()
        cutoutTask = Task {
            do {
                let result = try await ForegroundCutoutService().cutout(from: image)
                if Task.isCancelled { return }
                cutoutImage = result
            } catch {
                if !Task.isCancelled {
                    useCutout = false
                    cutoutError = error.localizedDescription
                }
            }
            isExtracting = false
        }
    }

    private func resetTransform() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }

    private func save() {
        isSaving = true
        let content = ZStack {
            if useCutout {
                FivoColor.coverBackdrop
            }
            Image(uiImage: activeImage)
                .resizable()
                .aspectRatio(contentMode: useCutout ? .fit : .fill)
                .frame(width: cropSide * scale, height: cropSide * scale)
                .offset(offset)
                .frame(width: cropSide, height: cropSide)
                .clipped()
        }
        .frame(width: cropSide, height: cropSide)
        .clipped()

        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        renderer.isOpaque = true
        if let uiImage = renderer.uiImage, let data = uiImage.jpegData(compressionQuality: 0.92) {
            onSave(data)
            dismiss()
        } else {
            isSaving = false
        }
    }
}
