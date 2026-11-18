import SwiftUI

@main
struct FivoFlowerApp: App {
    @State private var environment: AppEnvironment

    init() {
        _environment = State(initialValue: AppEnvironment.bootstrap())
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(environment)
                .tint(FivoColor.textPrimary)
        }
    }
}
