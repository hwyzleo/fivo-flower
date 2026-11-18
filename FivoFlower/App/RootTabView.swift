import SwiftUI
import Combine
import UIKit

struct RootTabView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.scenePhase) private var scenePhase
    @State private var showAddSheet = false
    @State private var isKeyboardVisible = false

    var body: some View {
        @Bindable var env = env
        ZStack(alignment: .bottom) {
            FivoColor.surfaceBase.ignoresSafeArea()

            TabView(selection: $env.selectedTab) {
                GardenHomeView()
                    .tag(RootTab.garden)
                JournalHomeView()
                    .tag(RootTab.journal)
                LedgerHomeView()
                    .tag(RootTab.ledger)
                CareCalendarView()
                    .tag(RootTab.calendar)
            }
            .toolbar(.hidden, for: .tabBar)

            if !isKeyboardVisible {
                FivoTabBar(selected: $env.selectedTab) {
                    showAddSheet = true
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddActionSheet()
                .presentationDragIndicator(.visible)
        }
        .overlay(alignment: .top) {
            if let toast = env.toast {
                ToastView(message: toast)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityIdentifier("toast")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: env.toast)
        .task {
            await env.reconcileNotifications()
        }
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active {
                Task { await env.reconcileNotifications() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = true }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) { isKeyboardVisible = false }
        }
    }
}

// MARK: - Custom tab bar

struct FivoTabBar: View {
    @Binding var selected: RootTab
    var onAdd: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.garden)
            tabButton(.journal)
            addButton
            tabButton(.ledger)
            tabButton(.calendar)
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(FivoColor.surfaceElevated)
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.5), lineWidth: 0.8)
                }
                .shadow(color: FivoColor.cardHighlight, radius: 8, x: -4, y: -4)
                .shadow(color: FivoColor.cardShadow, radius: 12, x: 0, y: 4)
                .ignoresSafeArea(edges: .bottom)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private func tabButton(_ tab: RootTab) -> some View {
        Button {
            selected = tab
        } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 19, weight: selected == tab ? .semibold : .regular))
                    .frame(height: 24)
                Text(tab.title)
                    .font(.system(size: 10, weight: selected == tab ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(selected == tab ? FivoColor.textPrimary : FivoColor.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected == tab ? .isSelected : [])
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(FivoColor.textPrimary)
                .frame(width: 58, height: 58)
                .background {
                    Circle()
                        .fill(LinearGradient(
                            colors: [FivoColor.accentStart, FivoColor.accentEnd],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .shadow(color: FivoColor.accentEnd.opacity(0.45), radius: 10, x: 0, y: 5)
                }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .offset(y: -14)
        .accessibilityLabel("新增")
        .accessibilityIdentifier("tab.add")
    }
}

// MARK: - Add action sheet

enum AddRoute: String, CaseIterable, Identifiable, Hashable {
    case plant
    case importOrder
    case care
    case tool
    case ledger

    var id: String { rawValue }

    var title: String {
        switch self {
        case .plant: return "手动添加植物"
        case .importOrder: return "订单截图导入"
        case .care: return "记养护"
        case .tool: return "添加工具资材"
        case .ledger: return "记一笔"
        }
    }

    var subtitle: String {
        switch self {
        case .plant: return "填写品种、购买信息与封面"
        case .importOrder: return "识别订单截图并生成档案"
        case .care: return "为单株或多株植物记录养护"
        case .tool: return "登记工具、消耗品库存和设备状态"
        case .ledger: return "记录支出、收入或退款"
        }
    }

    var systemImage: String {
        switch self {
        case .plant: return "leaf"
        case .importOrder: return "doc.text.viewfinder"
        case .care: return "drop"
        case .tool: return "shippingbox"
        case .ledger: return "yensign.circle"
        }
    }
}

struct AddActionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var path: [AddRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: FivoSpacing.sm) {
                    ForEach(AddRoute.allCases) { route in
                        Button {
                            path.append(route)
                        } label: {
                            HStack(spacing: FivoSpacing.md) {
                                Image(systemName: route.systemImage)
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(FivoColor.textPrimary)
                                    .frame(width: 46, height: 46)
                                    .background {
                                        Circle()
                                            .fill(LinearGradient(
                                                colors: [FivoColor.accentStart.opacity(0.7), FivoColor.accentEnd.opacity(0.4)],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                    }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.title)
                                        .font(FivoFont.cardTitle)
                                        .foregroundStyle(FivoColor.textPrimary)
                                    Text(route.subtitle)
                                        .font(FivoFont.caption)
                                        .foregroundStyle(FivoColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(FivoColor.textSecondary)
                            }
                            .softCard(padding: FivoSpacing.sm)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("add.\(route.rawValue)")
                    }
                }
                .padding(FivoSpacing.page)
            }
            .background(FivoColor.surfaceBase)
            .navigationTitle("新增")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .navigationDestination(for: AddRoute.self) { route in
                destination(for: route)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: AddRoute) -> some View {
        switch route {
        case .plant:
            PlantEditView(mode: .create, onFinish: { dismiss() })
        case .importOrder:
            OrderImportView(onFinish: { dismiss() })
        case .care:
            CareRecordView(preselectedPlantID: nil, onFinish: { dismiss() })
        case .tool:
            ToolEditView(toolID: nil, onFinish: { dismiss() })
        case .ledger:
            LedgerEntryEditor(entryID: nil, preselectPlantID: nil, preselectToolID: nil, onFinish: { dismiss() })
        }
    }
}
