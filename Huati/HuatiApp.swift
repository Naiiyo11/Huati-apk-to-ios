import SwiftUI

@main @MainActor struct HuatiApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model).preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.activate() }
                    else if phase == .background { BackgroundCoordinator.shared.enterBackground(model) }
                }
        }
    }
}
