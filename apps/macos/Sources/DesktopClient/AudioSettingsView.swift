import SwiftUI

struct AudioSettingsView: View {
    @EnvironmentObject private var backend: BackendController
    private let frequencies = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

    var body: some View {
        Form {
            Section(L10n.string("audio.title")) {
                slider(L10n.string("audio.gain"), keyPath: \.gain, range: -50...50)
                Toggle(L10n.string("audio.noise"), isOn: boolBinding(\.nsEnabled))
                Picker(L10n.string("audio.noiseType"), selection: stringBinding(\.nsType)) {
                    Text("PureVox").tag("PureVox")
                    Text("RNNoise").tag("RNNoise")
                    Text("Speexdsp").tag("Speexdsp")
                }
                .disabled(!backend.dspSettings.nsEnabled)
                slider(L10n.string("audio.intensity"), keyPath: \.nsIntensity, range: 0...100)
                    .disabled(!backend.dspSettings.nsEnabled)

                Toggle(L10n.string("audio.aec"), isOn: boolBinding(\.aecEnabled))
                Toggle(L10n.string("audio.dereverb"), isOn: boolBinding(\.dereverbEnabled))
                slider(L10n.string("audio.dereverbLevel"), keyPath: \.dereverbLevel, range: 0...100)
                    .disabled(!backend.dspSettings.dereverbEnabled)

                Toggle(L10n.string("audio.agc"), isOn: boolBinding(\.agcEnabled))
                slider(L10n.string("audio.agcTarget"), keyPath: \.agcTarget, range: 0...32_767)
                    .disabled(!backend.dspSettings.agcEnabled)
                slider(L10n.string("audio.agcAttack"), keyPath: \.agcAttack, range: 1...100)
                    .disabled(!backend.dspSettings.agcEnabled)
                slider(L10n.string("audio.agcDecay"), keyPath: \.agcDecay, range: 1...100)
                    .disabled(!backend.dspSettings.agcEnabled)

                Toggle(L10n.string("audio.vad"), isOn: boolBinding(\.vadEnabled))
                slider(L10n.string("audio.vadThreshold"), keyPath: \.vadThreshold, range: -100...0)
                    .disabled(!backend.dspSettings.vadEnabled)
                slider(L10n.string("audio.buffer"), range: 100...1_200, value: Binding(
                    get: { Double(backend.dspSettings.outputBufferMs) },
                    set: { value in
                        var settings = backend.dspSettings
                        settings.outputBufferMs = UInt32(value.rounded())
                        backend.updateDSPSettings(settings)
                    }
                ))
                Text(L10n.string("audio.settingsSaved")).font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.string("audio.equalizer")) {
                Toggle(L10n.string("audio.equalizer"), isOn: Binding(
                    get: { backend.dspSettings.equalizer.enabled },
                    set: { value in
                        var settings = backend.dspSettings
                        settings.equalizer.enabled = value
                        backend.updateDSPSettings(settings)
                    }
                ))
                slider(L10n.string("audio.preamp"), range: -12...12, value: Binding(
                    get: { Double(backend.dspSettings.equalizer.preAmp) },
                    set: { value in
                        var settings = backend.dspSettings
                        settings.equalizer.preAmp = Float(value)
                        backend.updateDSPSettings(settings)
                    }
                ))
                .disabled(!backend.dspSettings.equalizer.enabled)
                ForEach(frequencies.indices, id: \.self) { index in
                    slider(L10n.string("audio.band.\(frequencies[index])"), range: -12...12, value: Binding(
                        get: { Double(backend.dspSettings.equalizer.gains.indices.contains(index) ? backend.dspSettings.equalizer.gains[index] : 0) },
                        set: { value in
                            var settings = backend.dspSettings
                            if settings.equalizer.gains.indices.contains(index) {
                                settings.equalizer.gains[index] = Float(value)
                                backend.updateDSPSettings(settings)
                            }
                        }
                    ))
                    .disabled(!backend.dspSettings.equalizer.enabled)
                }
            }

            Section(L10n.string("audio.chain")) {
                ForEach(Array(backend.dspSettings.processingChain.enumerated()), id: \.offset) { item in
                    let index = item.offset
                    let node = item.element
                    HStack {
                        Text(L10n.string("audio.node.\(node)"))
                        Spacer()
                        Button {
                            moveNode(from: index, by: -1)
                        } label: { Label(L10n.string("audio.moveUp"), systemImage: "arrow.up") }
                        .disabled(index == 0)
                        Button {
                            moveNode(from: index, by: 1)
                        } label: { Label(L10n.string("audio.moveDown"), systemImage: "arrow.down") }
                        .disabled(index == backend.dspSettings.processingChain.count - 1)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(24)
        .navigationTitle(L10n.string("nav.audio"))
        .task {
            await backend.refreshBackendState()
            await backend.setSpectrumStreaming(true)
        }
        .onDisappear { Task { await backend.setSpectrumStreaming(false) } }
    }

    private func slider(_ title: String, keyPath: WritableKeyPath<DSPSettings, Float>, range: ClosedRange<Double>) -> some View {
        slider(title, range: range, value: Binding(
            get: { Double(backend.dspSettings[keyPath: keyPath]) },
            set: { value in
                var settings = backend.dspSettings
                settings[keyPath: keyPath] = Float(value)
                backend.updateDSPSettings(settings)
            }
        ))
    }

    private func slider(_ title: String, range: ClosedRange<Double>, value: Binding<Double>) -> some View {
        HStack {
            Text(title).frame(minWidth: 190, alignment: .leading)
            Slider(value: value, in: range)
            Text(value.wrappedValue.formatted(.number.precision(.fractionLength(0...1))))
                .monospacedDigit().frame(minWidth: 52, alignment: .trailing)
        }
    }

    private func boolBinding(_ keyPath: WritableKeyPath<DSPSettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { backend.dspSettings[keyPath: keyPath] },
            set: { value in
                var settings = backend.dspSettings
                settings[keyPath: keyPath] = value
                backend.updateDSPSettings(settings)
            }
        )
    }

    private func stringBinding(_ keyPath: WritableKeyPath<DSPSettings, String>) -> Binding<String> {
        Binding(
            get: { backend.dspSettings[keyPath: keyPath] },
            set: { value in
                var settings = backend.dspSettings
                settings[keyPath: keyPath] = value
                backend.updateDSPSettings(settings)
            }
        )
    }

    private func moveNode(from index: Int, by offset: Int) {
        let target = index + offset
        var settings = backend.dspSettings
        guard settings.processingChain.indices.contains(target) else { return }
        settings.processingChain.swapAt(index, target)
        backend.updateDSPSettings(settings)
    }
}
