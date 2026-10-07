import AppKit
import SwiftUI

enum ProductIdentity {
    static var name: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? ProcessInfo.processInfo.processName
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? ""
    }
}

@MainActor
@main
struct DesktopApp: App {
    @NSApplicationDelegateAdaptor(DesktopAppDelegate.self) private var appDelegate
    @StateObject private var backend = BackendController()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainView()
                .environmentObject(backend)
        }
        .windowResizability(.contentSize)

        MenuBarExtra(ProductIdentity.name, systemImage: "mic.fill") {
            MenuBarContent()
                .environmentObject(backend)
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class DesktopAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !ProductIdentity.bundleIdentifier.isEmpty else { return }
        let currentPID = NSRunningApplication.current.processIdentifier
        let otherInstance = NSRunningApplication.runningApplications(withBundleIdentifier: ProductIdentity.bundleIdentifier)
            .first { $0.processIdentifier != currentPID }
        if let otherInstance {
            otherInstance.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            NSApplication.shared.terminate(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct MenuBarContent: View {
    @EnvironmentObject private var backend: BackendController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(backend.phaseLabel)
        Button(L10n.string("menu.open")) { openWindow(id: "main") }
        if backend.canStop {
            Button(L10n.string("action.stop")) { Task { await backend.stop() } }
        } else {
            Button(L10n.string("action.start")) { Task { await backend.start() } }
        }
        Divider()
        Button(L10n.string("menu.quit")) { NSApplication.shared.terminate(nil) }
    }
}
