import SwiftUI
import PhotosUI

// MARK: - Add photos

struct AddPhotosSheet: View {
    let plantID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var items: [PhotosPickerItem] = []
    @State private var pickedPayloads: [ImagePayload] = []
    @State private var cameraPayloads: [ImagePayload] = []
    @State private var showCamera = false
    @State private var caption = ""

    private var payloads: [ImagePayload] { pickedPayloads + cameraPayloads }
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                PhotosPicker(
                    selection: $items,
                    maxSelectionCount: 9,
                    matching: .images
                ) {
                    HStack {
                        Image(systemName: "photo.on.rectangle.angled")
                        Text("从相册选择照片")
                        Spacer()
                        Text("\(items.count)/9")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.textSecondary)
                    }
                    .font(FivoFont.callout.weight(.semibold))
                    .foregroundStyle(FivoColor.textPrimary)
                    .padding(FivoSpacing.md)
                    .softCard(padding: 0)
                }

                if CameraAvailability.isAvailable {
                    SecondaryButton(title: "拍摄照片", systemImage: "camera") {
                        showCamera = true
                    }
                }

                if !payloads.isEmpty {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                        ForEach(Array(payloads.enumerated()), id: \.offset) { _, payload in
                            LocalImageThumbnail(data: payload.data)
                        }
                    }
                }

                SoftTextField(
                    label: "照片说明",
                    text: $caption,
                    placeholder: "选填，例如：新叶展开",
                    axis: .vertical,
                    lineLimit: 2...4
                )

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.circle")
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.danger)
                }
            }
            .padding(FivoSpacing.page)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle("添加照片")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            GoldPrimaryButton(
                title: "保存 \(payloads.count) 张照片",
                systemImage: "checkmark",
                isLoading: isSaving,
                isEnabled: !payloads.isEmpty
            ) {
                save()
            }
            .padding(.horizontal, FivoSpacing.page)
            .padding(.vertical, FivoSpacing.xs)
            .background(.ultraThinMaterial)
        }
        .onChange(of: items) { _, newItems in
            Task {
                pickedPayloads = await PhotoPayloadLoader.payloads(from: newItems)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { data in
                cameraPayloads.append(ImagePayload(data: data, capturedAt: Date()))
            }
            .ignoresSafeArea()
        }
    }

    private func save() {
        guard !payloads.isEmpty else { return }
        isSaving = true
        do {
            _ = try env.photos.addPhotos(
                plantID: plantID,
                payloads: payloads,
                source: .plant,
                sourceID: nil,
                caption: PlantValidator.normalized(caption)
            )
            env.showToast("已添加照片")
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - Viewer

struct PhotoViewer: View {
    let plantID: UUID
    let initialPhotoID: UUID

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var photos: [PlantPhoto] = []
    @State private var index = 0
    @State private var showDeleteConfirm = false
    @State private var cropImage: UIImage?
    @State private var cropPhotoID: UUID?
    @State private var errorMessage: String?

    private var current: PlantPhoto? {
        guard photos.indices.contains(index) else { return nil }
        return photos[index]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if photos.isEmpty {
                ProgressView().tint(.white)
            } else {
                TabView(selection: $index) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { offset, photo in
                        StoredImage(relativePath: photo.originalRelativePath, imageStore: env.imageStore, contentMode: .fit)
                            .tag(offset)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 40, height: 40)
                            .background(.black.opacity(0.35), in: Circle())
                    }
                    .accessibilityLabel("关闭照片")
                    Spacer()
                    if !photos.isEmpty {
                        Text("\(index + 1) / \(photos.count)")
                            .font(FivoFont.captionStrong)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.35), in: Capsule())
                    }
                }
                .padding(FivoSpacing.md)

                Spacer()

                if let photo = current {
                    VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(FivoDate.dateTime(photo.capturedAt))
                                    .font(FivoFont.captionStrong)
                                    .foregroundStyle(.white)
                                Text("来源：\(photo.sourceType.title)")
                                    .font(FivoFont.caption)
                                    .foregroundStyle(.white.opacity(0.7))
                            }
                            Spacer()
                            if let caption = photo.caption, !caption.isEmpty {
                                Text(caption)
                                    .font(FivoFont.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }

                        HStack(spacing: FivoSpacing.sm) {
                            viewerButton(title: "裁剪设封面", systemImage: "crop") {
                                prepareCrop(photo)
                            }
                            viewerButton(title: "删除照片", systemImage: "trash", destructive: true) {
                                showDeleteConfirm = true
                            }
                        }
                    }
                    .padding(FivoSpacing.md)
                    .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(FivoSpacing.md)
                }
            }
        }
        .task { load() }
        .onChange(of: index) { _, _ in }
        .sheet(item: Binding(
            get: { cropImage.map { CropPayload(image: $0) } },
            set: { if $0 == nil { cropImage = nil; cropPhotoID = nil } }
        )) { payload in
            CoverCropView(image: payload.image) { data in
                applyCrop(data)
            }
        }
        .confirmationDialog("删除这张照片？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除照片", role: .destructive) { deleteCurrent() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复；如果它是封面，会恢复为占位图。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func viewerButton(title: String, systemImage: String, destructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(FivoFont.captionStrong)
                .foregroundStyle(destructive ? Color(hex: 0xFFB4A6) : .white)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func load() {
        photos = (try? env.photos.photos(plantID: plantID)) ?? []
        if let firstIndex = photos.firstIndex(where: { $0.id == initialPhotoID }) {
            index = firstIndex
        }
    }

    private func prepareCrop(_ photo: PlantPhoto) {
        let url = env.imageStore.absoluteURL(for: photo.originalRelativePath)
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else {
            errorMessage = "无法读取原图。"
            return
        }
        cropPhotoID = photo.id
        cropImage = image
    }

    private func applyCrop(_ data: Data) {
        guard let photoID = cropPhotoID else { return }
        do {
            try env.photos.setCover(plantID: plantID, photoID: photoID, croppedImageData: data)
            env.showToast("已更新封面")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteCurrent() {
        guard let photo = current else { return }
        do {
            try env.photos.deletePhoto(id: photo.id)
            photos.removeAll { $0.id == photo.id }
            index = min(index, max(0, photos.count - 1))
            if photos.isEmpty {
                dismiss()
            } else {
                env.showToast("已删除照片")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// sheet(item:) 需要 Identifiable。
private struct CropPayload: Identifiable {
    let image: UIImage
    var id: ObjectIdentifier { ObjectIdentifier(image) }
}
