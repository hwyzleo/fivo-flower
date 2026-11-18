import SwiftUI

struct JournalDetailView: View {
    let entry: JournalEntry
    var plantName: String?

    @Environment(AppEnvironment.self) private var env
    @State private var photos: [PlantPhoto] = []
    @State private var selectedPhoto: PlantPhoto?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.md) {
                VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                    HStack {
                        Label(entry.kind.title, systemImage: entry.kind.symbolName)
                            .font(FivoFont.captionStrong)
                            .foregroundStyle(FivoColor.textSecondary)
                        Spacer()
                        if entry.isManual {
                            StatusPill(text: "手动", tint: FivoColor.textSecondary)
                        }
                    }
                    Text(entry.title)
                        .font(FivoFont.pageTitle)
                        .foregroundStyle(FivoColor.textPrimary)
                    if !entry.body.isEmpty {
                        Text(entry.body)
                            .font(FivoFont.callout)
                            .foregroundStyle(FivoColor.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    FieldRow(label: "时间", value: FivoDate.dateTime(entry.occurredAt))
                    if let plantName {
                        FieldRow(label: "植物", value: plantName)
                    }
                    if entry.sourceIsDeleted {
                        Label("来源已删除", systemImage: "exclamationmark.circle")
                            .font(FivoFont.caption)
                            .foregroundStyle(FivoColor.danger)
                    }
                }
                .softCard(radius: FivoRadius.largeCard)

                if let errorMessage {
                    ErrorStateView(message: errorMessage) { load() }
                } else if !photos.isEmpty {
                    VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                        Text("图片 · \(photos.count) 张")
                            .font(FivoFont.sectionTitle)
                            .foregroundStyle(FivoColor.textPrimary)
                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                            spacing: 8
                        ) {
                            ForEach(photos) { photo in
                                Button {
                                    selectedPhoto = photo
                                } label: {
                                    StoredImageThumbnail(
                                        relativePath: photo.thumbnailRelativePath,
                                        imageStore: env.imageStore
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("查看日志图片")
                                .accessibilityIdentifier("journalDetail.photo.\(photo.id.uuidString)")
                            }
                        }
                    }
                    .softCard()
                }
            }
            .fivoPagePadding()
            .padding(.bottom, 110)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle("日志详情")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
        .fullScreenCover(item: $selectedPhoto, onDismiss: load) { photo in
            PhotoViewer(plantID: entry.plantID, initialPhotoID: photo.id)
        }
    }

    private func load() {
        do {
            let plantPhotos = try env.photos.photos(plantID: entry.plantID)
            photos = JournalPhotoAssociation.photos(for: entry, in: plantPhotos)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
