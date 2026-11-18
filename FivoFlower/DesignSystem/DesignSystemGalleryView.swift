import SwiftUI

/// 设计系统组件预览页（仅 Debug 菜单入口）。
struct DesignSystemGalleryView: View {
    @State private var search = ""
    @State private var text = ""
    @State private var selectedChip = 0
    @State private var showToast = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FivoSpacing.lg) {
                section("色彩 Token") {
                    HStack(spacing: 8) {
                        swatch("Base", FivoColor.surfaceBase)
                        swatch("Elevated", FivoColor.surfaceElevated)
                        swatch("Gold", FivoColor.accentEnd)
                        swatch("Primary", FivoColor.textPrimary)
                        swatch("Danger", FivoColor.danger)
                    }
                }

                section("字体") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("页面标题").font(FivoFont.pageTitle)
                        Text("区块标题").font(FivoFont.sectionTitle)
                        Text("卡片标题").font(FivoFont.cardTitle)
                        Text("正文 body").font(FivoFont.body)
                        Text("辅助说明 caption").font(FivoFont.caption)
                    }
                }

                section("按钮") {
                    VStack(spacing: FivoSpacing.sm) {
                        GoldPrimaryButton(title: "主操作按钮", systemImage: "plus") {}
                        GoldPrimaryButton(title: "加载中", isLoading: true) {}
                        GoldPrimaryButton(title: "禁用", isEnabled: false) {}
                        HStack {
                            SecondaryButton(title: "次要操作", systemImage: "leaf") {}
                            SecondaryButton(title: "危险操作", systemImage: "trash", destructive: true) {}
                        }
                    }
                }

                section("输入与筛选") {
                    VStack(alignment: .leading, spacing: FivoSpacing.sm) {
                        InsetSearchField(placeholder: "搜索植物", text: $search)
                        SoftTextField(label: "名称", text: $text, placeholder: "输入名称")
                        HStack {
                            FilterChip(title: "全部", count: 12, isSelected: selectedChip == 0) { selectedChip = 0 }
                            FilterChip(title: "开花", count: 3, isSelected: selectedChip == 1) { selectedChip = 1 }
                            FilterChip(title: "出花梗", count: 2, isSelected: selectedChip == 2) { selectedChip = 2 }
                        }
                        HStack {
                            StatusPill(text: "存活", systemImage: "leaf.fill", tint: FivoColor.success)
                            StatusPill(text: "低库存", systemImage: "exclamationmark.triangle", tint: FivoColor.danger)
                            StatusPill(text: "进行中", tint: FivoColor.textSecondary)
                        }
                    }
                    .softCard()
                }

                section("状态") {
                    EmptyStateView(
                        systemImage: "leaf",
                        title: "空状态标题",
                        message: "说明当前为空的原因以及下一步可以做什么。",
                        actions: [
                            EmptyStateAction(title: "主操作", systemImage: "plus", isPrimary: true) {}
                        ]
                    )
                    ErrorStateView(message: "示例错误：无法读取本地图片。") {}
                }

                section("Toast") {
                    SecondaryButton(title: showToast ? "已显示" : "显示 Toast", systemImage: "bell") {
                        showToast = true
                    }
                    if showToast {
                        ToastView(message: "已保存修改")
                    }
                }
            }
            .padding(FivoSpacing.page)
        }
        .background(FivoColor.surfaceBase)
        .navigationTitle("设计系统")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: FivoSpacing.sm) {
            Text(title)
                .font(FivoFont.sectionTitle)
                .foregroundStyle(FivoColor.textPrimary)
            content()
        }
    }

    private func swatch(_ title: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color)
                .frame(height: 52)
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(FivoColor.separator, lineWidth: 0.8)
                }
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(FivoColor.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    NavigationStack {
        DesignSystemGalleryView()
    }
}
