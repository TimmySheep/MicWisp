import SwiftUI

@main
struct MicYouApp: App {
    @StateObject private var model = MicYouAppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onOpenURL(perform: model.handleDeepLink)
                .onChange(of: scenePhase) { phase in
                    model.scenePhaseChanged(phase)
                }
        }
    }
}
