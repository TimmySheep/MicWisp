import PhotosUI
import SwiftUI
import UserNotifications

struct MicYouSettingsView: View {
    @ObservedObject var settings: MicYouSettings
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var notificationDenied = false
    @State private var updateMessage: String?

    var body: some View {
        Form {
            Section("Network") {
                TextField("Default host", text: $settings.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("TCP port (default 8554)", value: $settings.port, format: .number)
                    .keyboardType(.numberPad)
                if !settings.recentHosts.isEmpty {
                    ForEach(settings.recentHosts, id: \.self) { host in
                        Button(host) { settings.host = host }
                    }
                }
            }

            Section("Audio") {
                Picker("Sample rate", selection: $settings.sampleRate) {
                    Text("16 kHz").tag(16_000)
                    Text("44.1 kHz").tag(44_100)
                    Text("48 kHz").tag(48_000)
                    Text("96 kHz").tag(96_000)
                }
                Picker("Channels", selection: $settings.channelCount) {
                    Text("Mono").tag(1)
                    Text("Stereo").tag(2)
                }
                Picker("Noise reduction", selection: $settings.noiseSuppression) {
                    Text("Off").tag(MicYouSettings.NoiseMode.off)
                    Text("System voice processing").tag(MicYouSettings.NoiseMode.system)
                    Text("RNNoise (not available yet)").tag(MicYouSettings.NoiseMode.rnnoise).disabled(true)
                }
                Text("RNNoise is not bundled in this build. System voice processing uses the iOS audio session when supported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading) {
                    HStack { Text("RNNoise strength"); Spacer(); Text("\(Int(settings.noiseIntensity))%").foregroundStyle(.secondary) }
                    Slider(value: $settings.noiseIntensity, in: 0...100, step: 1)
                }
                .disabled(settings.noiseSuppression != .rnnoise)
                Text("System voice processing is controlled by iOS and may depend on the selected input route.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Theme", selection: $settings.appearance) {
                    Text("System").tag(MicYouSettings.Appearance.system)
                    Text("Light").tag(MicYouSettings.Appearance.light)
                    Text("Dark").tag(MicYouSettings.Appearance.dark)
                }
                Picker("Accent color", selection: $settings.accentIndex) {
                    Text("System").tag(0)
                    Text("Indigo").tag(1)
                    Text("Teal").tag(2)
                    Text("Orange").tag(3)
                    Text("Pink").tag(4)
                    Text("Purple").tag(5)
                }
                Toggle("OLED black in dark mode", isOn: $settings.oledBlack)
                Picker("Visualizer", selection: $settings.visualizerStyle) {
                    Text("Volume ring").tag(0)
                    Text("Ripple").tag(1)
                    Text("Bars").tag(2)
                    Text("Waveform").tag(3)
                    Text("Glow").tag(4)
                    Text("Particles").tag(5)
                }
                let hasBackgroundImage = settings.backgroundImagePath != nil
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label(hasBackgroundImage ? "Replace background image" : "Choose background image", systemImage: "photo")
                }
                .onChange(of: selectedPhoto) { item in
                    Task {
                        guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                        settings.saveBackgroundImage(data)
                    }
                }
                if settings.backgroundImagePath != nil {
                    Button("Clear background image", role: .destructive) { settings.clearBackgroundImage() }
                }
            }

            Section("General") {
                Picker("Language", selection: $settings.language) {
                    Text("Follow system").tag(MicYouSettings.Language.system)
                    Text("简体中文").tag(MicYouSettings.Language.simplifiedChinese)
                    Text("繁體中文").tag(MicYouSettings.Language.traditionalChinese)
                    Text("English").tag(MicYouSettings.Language.english)
                }
                Toggle("Keep screen awake while streaming", isOn: $settings.keepScreenAwake)
                Toggle("Streaming notification", isOn: $settings.streamingNotification)
                    .onChange(of: settings.streamingNotification) { enabled in
                        guard enabled else { return }
                        MicYouNotificationService.shared.requestPermission { granted in
                            if !granted {
                                settings.streamingNotification = false
                                notificationDenied = true
                            }
                        }
                    }
                Toggle("Check for updates on launch", isOn: $settings.autoCheckUpdates)
                    .disabled(true)
                Text("Update checking will be enabled after this independent client has a published release feed.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                LabeledContent("Protocol", value: "MicYou TCP / Protobuf")
                ShareLink(item: MicYouLogger.shared.exportURL) {
                    Label("Export diagnostic log", systemImage: "square.and.arrow.up")
                }
                Button("Check for updates") { updateMessage = "No public release feed is configured yet." }
                Text("Source repository URL will be published with the first release.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Link("Open-source licenses", destination: URL(string: "https://www.gnu.org/licenses/gpl-3.0.html")!)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Notifications are disabled", isPresented: $notificationDenied) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Enable notifications in iOS Settings to show streaming status.")
        }
        .alert("Updates", isPresented: Binding(get: { updateMessage != nil }, set: { if !$0 { updateMessage = nil } })) {
            Button("OK", role: .cancel) { updateMessage = nil }
        } message: {
            Text(updateMessage ?? "")
        }
    }
}
