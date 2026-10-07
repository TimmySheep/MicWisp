import SwiftUI

struct ConnectionSettingsView: View {
    @EnvironmentObject private var backend: BackendController
    @State private var isApplying = false

    private var isValid: Bool {
        if backend.connection.mode == "web" { return backend.connection.webPort > 0 }
        return backend.connection.port > 0 && backend.connection.port < UInt16.max
    }

    var body: some View {
        Form {
            Section(L10n.string("connection.title")) {
                Picker(L10n.string("connection.mode"), selection: $backend.connection.mode) {
                    Text(L10n.string("connection.wifi")).tag("wifi")
                    Text(L10n.string("connection.usb")).tag("usb")
                    Text(L10n.string("connection.web")).tag("web")
                }

                if backend.connection.mode == "web" {
                    TextField(L10n.string("connection.webPort"), value: $backend.connection.webPort, format: .number.grouping(.never))
                        .frame(maxWidth: 240)
                } else {
                    TextField(L10n.string("connection.port"), value: $backend.connection.port, format: .number.grouping(.never))
                        .frame(maxWidth: 320)
                    TextField(L10n.string("connection.bind"), text: $backend.connection.bindAddress)
                        .disabled(backend.connection.autoBind || backend.connection.mode == "usb")
                        .frame(maxWidth: 320)
                    Toggle(L10n.string("connection.autoBind"), isOn: $backend.connection.autoBind)
                        .disabled(backend.connection.mode == "usb")
                }

                Picker(L10n.string("connection.output"), selection: $backend.connection.outputDevice) {
                    Text(L10n.string("connection.defaultOutput")).tag("")
                    ForEach(backend.audioDevices, id: \.self) { device in
                        Text(device).tag(device)
                    }
                }
                Text(L10n.string("connection.outputHint")).font(.caption).foregroundStyle(.secondary)
                Toggle(L10n.string("connection.muteSync"), isOn: $backend.connection.muteSync)

                if backend.connection.mode == "usb" {
                    Text(L10n.string("connection.usbHint")).font(.callout).foregroundStyle(.secondary)
                    if backend.adbDevices.isEmpty {
                        Text(L10n.string("connection.noADB")).font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(backend.adbDevices, id: \.self) { device in
                            Label(device, systemImage: "cable.connector")
                        }
                    }
                } else if backend.connection.mode == "web" {
                    Text(L10n.string("connection.webHint")).font(.callout).foregroundStyle(.secondary)
                }

                Text(L10n.string("connection.restart")).font(.caption).foregroundStyle(.secondary)
                if !isValid {
                    Label(L10n.string("connection.invalidPort"), systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                Button {
                    isApplying = true
                    Task {
                        await backend.applyConnectionSettings()
                        isApplying = false
                    }
                } label: {
                    if isApplying { ProgressView() }
                    else { Text(L10n.string("action.apply")) }
                }
                .disabled(!isValid || isApplying)
            }

            Section(L10n.string("connection.discovery")) {
                Text(L10n.string("connection.discoveryHint")).font(.caption).foregroundStyle(.secondary)
                if backend.discoveredServices.isEmpty {
                    Text(L10n.string("connection.noneFound")).foregroundStyle(.secondary)
                } else {
                    ForEach(backend.discoveredServices, id: \.self) { service in
                        Label(service, systemImage: "dot.radiowaves.left.and.right")
                            .textSelection(.enabled)
                    }
                }
            }

            if backend.connection.mode == "wifi" {
                Section(L10n.string("connection.localAddresses")) {
                    Text(L10n.string("connection.localAddressesHint"))
                        .font(.caption).foregroundStyle(.secondary)
                    if backend.localAddresses.isEmpty {
                        Text(L10n.string("connection.noLocalAddresses"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(backend.localAddresses, id: \.self) { address in
                            Label("\(address):\(backend.connection.port)", systemImage: "network")
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            Section(L10n.string("connection.virtualStatus")) {
                let installed = backend.virtualAudioStatus["installed"] as? Bool
                Label(
                    L10n.string(installed == true ? "connection.installed" : "connection.notInstalled"),
                    systemImage: installed == true ? "checkmark.circle.fill" : "exclamationmark.circle"
                )
                if let urlString = backend.virtualAudioStatus["manualSetupUrl"] as? String,
                   let url = URL(string: urlString) {
                    Link(L10n.string("connection.openSetup"), destination: url)
                }
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .navigationTitle(L10n.string("nav.connection"))
        .task { await backend.refreshBackendState() }
    }
}
