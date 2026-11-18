import SwiftUI

// MARK: - Colors

enum FivoColor {
    static let surfaceBase = Color(hex: 0xECEEF2)
    static let surfaceElevated = Color(hex: 0xEDEFF2)
    static let surfaceInset = Color(hex: 0xE4E7EC)
    static let accentStart = Color(hex: 0xFFE27D)
    static let accentEnd = Color(hex: 0xFFAE34)
    static let textPrimary = Color(hex: 0x30332F)
    static let textSecondary = Color(hex: 0x656B67)
    static let danger = Color(hex: 0xA23B2A)
    static let success = Color(hex: 0x3F7A4F)
    static let separator = Color(hex: 0xD9DDE3)
    static let cardHighlight = Color.white.opacity(0.95)
    static let coverBackdrop = Color(hex: 0xF7F5EF)
    static let cardShadow = Color(red: 190 / 255, green: 198 / 255, blue: 210 / 255).opacity(0.45)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }
}

// MARK: - Spacing / shape

enum FivoSpacing {
    static let xxs: CGFloat = 4
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
    static let page: CGFloat = 20
}

enum FivoRadius {
    static let largeCard: CGFloat = 26
    static let card: CGFloat = 20
    static let field: CGFloat = 16
    static let button: CGFloat = 18
}

enum FivoFont {
    static let pageTitle = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let sectionTitle = Font.system(.title3, design: .rounded).weight(.semibold)
    static let cardTitle = Font.system(.headline, design: .rounded).weight(.semibold)
    static let numberLarge = Font.system(.largeTitle, design: .rounded).weight(.bold)
    static let number = Font.system(.title2, design: .rounded).weight(.semibold)
    static let body = Font.system(.body)
    static let callout = Font.system(.callout)
    static let caption = Font.system(.caption)
    static let captionStrong = Font.system(.caption, design: .rounded).weight(.semibold)
}

// MARK: - Card style

struct SoftCardModifier: ViewModifier {
    var radius: CGFloat = FivoRadius.card
    var padding: CGFloat = FivoSpacing.md
    var elevated: Bool = true

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(FivoColor.surfaceElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.4), lineWidth: 0.8)
                    }
                    .shadow(
                        color: reducedMotion || !elevated ? .clear : FivoColor.cardHighlight,
                        radius: 9,
                        x: -7,
                        y: -7
                    )
                    .shadow(
                        color: reducedMotion || !elevated ? .clear : FivoColor.cardShadow,
                        radius: 10,
                        x: 7,
                        y: 7
                    )
            }
    }

    @Environment(\.accessibilityReduceMotion) private var reducedMotion
}

extension View {
    func softCard(
        radius: CGFloat = FivoRadius.card,
        padding: CGFloat = FivoSpacing.md,
        elevated: Bool = true
    ) -> some View {
        modifier(SoftCardModifier(radius: radius, padding: padding, elevated: elevated))
    }

    func fivoPagePadding() -> some View {
        padding(.horizontal, FivoSpacing.page)
    }
}

// MARK: - Buttons

struct GoldButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FivoFont.cardTitle)
            .foregroundStyle(FivoColor.textPrimary)
            .padding(.horizontal, FivoSpacing.lg)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background {
                RoundedRectangle(cornerRadius: FivoRadius.button, style: .continuous)
                    .fill(LinearGradient(
                        colors: [FivoColor.accentStart, FivoColor.accentEnd],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .shadow(color: FivoColor.accentEnd.opacity(isEnabled ? 0.35 : 0), radius: 8, x: 0, y: 5)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(reduceMotion ? 1 : (configuration.isPressed ? 0.98 : 1))
    }
}

struct GoldPrimaryButton: View {
    let title: String
    var systemImage: String?
    var isLoading: Bool = false
    var isEnabled: Bool = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: FivoSpacing.xs) {
                if isLoading {
                    ProgressView()
                        .tint(FivoColor.textPrimary)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
        }
        .buttonStyle(GoldButtonStyle())
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(title)
    }
}

struct SoftIconButton: View {
    let systemName: String
    var accessibilityLabel: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(FivoColor.textPrimary)
                .frame(width: 44, height: 44)
                .background {
                    Circle()
                        .fill(FivoColor.surfaceElevated)
                        .shadow(color: FivoColor.cardHighlight, radius: 5, x: -3, y: -3)
                        .shadow(color: FivoColor.cardShadow, radius: 6, x: 3, y: 3)
                }
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

struct SecondaryButton: View {
    let title: String
    var systemImage: String?
    var destructive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(FivoFont.callout.weight(.semibold))
            .foregroundStyle(destructive ? FivoColor.danger : FivoColor.textPrimary)
            .padding(.horizontal, FivoSpacing.md)
            .frame(minHeight: 44)
            .background {
                RoundedRectangle(cornerRadius: FivoRadius.field, style: .continuous)
                    .fill(FivoColor.surfaceElevated)
                    .overlay {
                        RoundedRectangle(cornerRadius: FivoRadius.field, style: .continuous)
                            .strokeBorder(FivoColor.separator.opacity(0.6), lineWidth: 1)
                    }
            }
        }
    }
}

// MARK: - Pills / chips

struct StatusPill: View {
    let text: String
    var systemImage: String?
    var tint: Color = FivoColor.textSecondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(text)
                .font(FivoFont.captionStrong)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

struct FilterChip: View {
    let title: String
    var count: Int?
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(FivoFont.captionStrong)
                if let count {
                    Text("\(count)")
                        .font(FivoFont.caption)
                        .foregroundStyle(isSelected ? FivoColor.textPrimary.opacity(0.7) : FivoColor.textSecondary)
                }
            }
            .foregroundStyle(FivoColor.textPrimary)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background {
                Capsule()
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(
                                colors: [FivoColor.accentStart.opacity(0.9), FivoColor.accentEnd.opacity(0.75)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                          : AnyShapeStyle(FivoColor.surfaceElevated))
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.white.opacity(isSelected ? 0.5 : 0.35), lineWidth: 0.8)
                    }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Search field

struct InsetSearchField: View {
    let placeholder: String
    @Binding var text: String
    var accessibilityIdentifier: String?

    var body: some View {
        HStack(spacing: FivoSpacing.xs) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(FivoColor.textSecondary)
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .foregroundStyle(FivoColor.textPrimary)
                .accessibilityIdentifier(accessibilityIdentifier ?? "searchField")
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FivoColor.textSecondary)
                }
                .accessibilityLabel("清除搜索")
            }
        }
        .font(FivoFont.body)
        .padding(.horizontal, FivoSpacing.md)
        .frame(minHeight: 46)
        .background {
            RoundedRectangle(cornerRadius: FivoRadius.field, style: .continuous)
                .fill(FivoColor.surfaceInset)
                .overlay {
                    RoundedRectangle(cornerRadius: FivoRadius.field, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 1)
                        .blur(radius: 1)
                        .offset(x: -1, y: -1)
                        .mask(RoundedRectangle(cornerRadius: FivoRadius.field, style: .continuous))
                }
        }
    }
}

struct SoftTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default
    var contentType: UITextContentType?
    var error: String?
    var axis: Axis = .horizontal
    var lineLimit: ClosedRange<Int>? = nil
    var identifier: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(FivoFont.captionStrong)
                .foregroundStyle(FivoColor.textSecondary)
            Group {
                if axis == .vertical, let lineLimit {
                    TextField(placeholder, text: $text, axis: .vertical)
                        .lineLimit(lineLimit)
                } else {
                    TextField(placeholder, text: $text)
                }
            }
            .font(FivoFont.body)
            .foregroundStyle(FivoColor.textPrimary)
            .keyboardType(keyboard)
            .textContentType(contentType)
            .accessibilityIdentifier(identifier ?? label)
            .padding(.horizontal, FivoSpacing.sm)
            .padding(.vertical, 11)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.55))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(error == nil ? FivoColor.separator.opacity(0.7) : FivoColor.danger, lineWidth: 1)
                    }
            }
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(FivoFont.caption)
                    .foregroundStyle(FivoColor.danger)
            }
        }
    }
}

// MARK: - States

struct EmptyStateView: View {
    var systemImage: String = "leaf"
    let title: String
    let message: String
    var actions: [EmptyStateAction] = []

    var body: some View {
        VStack(spacing: FivoSpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(FivoColor.textPrimary)
                .frame(width: 82, height: 82)
                .background {
                    Circle()
                        .fill(LinearGradient(
                            colors: [FivoColor.accentStart.opacity(0.65), FivoColor.accentEnd.opacity(0.35)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
                .accessibilityHidden(true)
            Text(title)
                .font(FivoFont.sectionTitle)
                .foregroundStyle(FivoColor.textPrimary)
            Text(message)
                .font(FivoFont.body)
                .foregroundStyle(FivoColor.textSecondary)
                .multilineTextAlignment(.center)
            ForEach(actions) { action in
                if action.isPrimary {
                    GoldPrimaryButton(title: action.title, systemImage: action.systemImage, action: action.handler)
                        .frame(maxWidth: 280)
                } else {
                    SecondaryButton(title: action.title, systemImage: action.systemImage, action: action.handler)
                }
            }
        }
        .padding(FivoSpacing.xl)
        .frame(maxWidth: .infinity)
    }
}

struct EmptyStateAction: Identifiable {
    let id = UUID()
    var title: String
    var systemImage: String?
    var isPrimary: Bool = false
    var handler: () -> Void
}

struct ErrorStateView: View {
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: FivoSpacing.sm) {
            Label("加载失败", systemImage: "exclamationmark.triangle")
                .font(FivoFont.cardTitle)
                .foregroundStyle(FivoColor.danger)
            Text(message)
                .font(FivoFont.callout)
                .foregroundStyle(FivoColor.textSecondary)
                .multilineTextAlignment(.center)
            if let retry {
                SecondaryButton(title: "重试", systemImage: "arrow.clockwise", action: retry)
            }
        }
        .padding(FivoSpacing.lg)
        .frame(maxWidth: .infinity)
        .softCard()
    }
}

// MARK: - Rows / headers

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var trailingTitle: String?
    var trailingAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FivoFont.sectionTitle)
                    .foregroundStyle(FivoColor.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(FivoFont.caption)
                        .foregroundStyle(FivoColor.textSecondary)
                }
            }
            Spacer()
            if let trailingTitle, let trailingAction {
                Button(trailingTitle, action: trailingAction)
                    .font(FivoFont.captionStrong)
                    .foregroundStyle(FivoColor.textPrimary)
            }
        }
    }
}

struct FieldRow: View {
    let label: String
    let value: String
    var valueColor: Color = FivoColor.textPrimary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: FivoSpacing.sm) {
            Text(label)
                .font(FivoFont.callout)
                .foregroundStyle(FivoColor.textSecondary)
                .frame(width: 82, alignment: .leading)
            Text(value)
                .font(FivoFont.callout)
                .foregroundStyle(valueColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .padding(.vertical, 3)
    }
}

struct DividerSoft: View {
    var body: some View {
        Rectangle()
            .fill(FivoColor.separator.opacity(0.5))
            .frame(height: 1)
    }
}

// MARK: - Toast

struct ToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(FivoFont.callout.weight(.semibold))
            .foregroundStyle(FivoColor.surfaceBase)
            .padding(.horizontal, FivoSpacing.lg)
            .padding(.vertical, FivoSpacing.sm)
            .background(FivoColor.textPrimary.opacity(0.92), in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
    }
}

// MARK: - Keyboard dismissal

extension View {
    func dismissKeyboardOnTap() -> some View {
        simultaneousGesture(TapGesture().onEnded {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        })
    }
}
