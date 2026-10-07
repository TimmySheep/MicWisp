import AppKit
import SwiftUI

struct AboutView: View {
    @EnvironmentObject private var backend: BackendController
    @AppStorage("language") private var language = "system"

    var body: some View {
        Form {
            Section(L10n.string("about.title")) {
                Text(ProductIdentity.name).font(.largeTitle.bold())
                Text("\(L10n.string("about.version")): \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0")")
                    .foregroundStyle(.secondary)
                Text("Copyright (C) 2026 TimmySheep")
                Text(L10n.string("about.upstreamCopyright"))
                Text(L10n.string("about.independent")).textSelection(.enabled)
                Text(L10n.string("about.license")).textSelection(.enabled)
                Button {
                    openLicense("GPL-3.0.txt")
                } label: { Label(L10n.string("about.openLicense"), systemImage: "doc.text") }
                Button {
                    openLicense("UPSTREAM-LICENSE.txt")
                } label: { Label(L10n.string("about.upstreamLicense"), systemImage: "doc.text") }
            }

            Section(L10n.string("settings.title")) {
                Picker(L10n.string("settings.language"), selection: $language) {
                    Text(L10n.string("settings.system")).tag("system")
                    Text(L10n.string("settings.english")).tag("en")
                    Text(L10n.string("settings.chinese")).tag("zh-Hans")
                }
                Toggle(L10n.string("settings.launchAtLogin"), isOn: Binding(
                    get: { backend.isLaunchAtLoginEnabled },
                    set: { backend.setLaunchAtLogin($0) }
                ))
                Text(L10n.string("settings.explicitStart"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .navigationTitle(L10n.string("nav.about"))
    }

    private func openLicense(_ name: String) {
        guard let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Licenses") else {
            backend.errorMessage = L10n.string("about.licenseMissing")
            return
        }
        if !NSWorkspace.shared.open(url) {
            backend.errorMessage = L10n.string("about.licenseMissing")
        }
    }
}
