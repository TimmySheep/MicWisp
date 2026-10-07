import SwiftUI

private enum DesktopSection: String, CaseIterable, Identifiable {
    case dashboard
    case connection
    case audio
    case about

    var id: String { rawValue }
    var title: String { L10n.string("nav.\(rawValue)") }
    var symbol: String {
        switch self {
        case .dashboard: "waveform.path"
        case .connection: "network"
        case .audio: "slider.horizontal.3"
        case .about: "info.circle"
        }
    }
}

struct MainView: View {
    @EnvironmentObject private var backend: BackendController
    @AppStorage("language") private var language = "system"
    @State private var selection: DesktopSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(DesktopSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.symbol)
                    .tag(section as DesktopSection?)
            }
            .navigationTitle(ProductIdentity.name)
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard: DashboardView()
                case .connection: ConnectionSettingsView()
                case .audio: AudioSettingsView()
                case .about: AboutView()
                }
            }
            .frame(minWidth: 600, minHeight: 500)
        }
        .frame(minWidth: 900, minHeight: 620)
        .id(language)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Label(backend.phaseLabel, systemImage: backend.phase.isRunning ? "checkmark.circle.fill" : "mic")
                    .foregroundStyle(backend.phase.isRunning ? .green : .secondary)
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        if backend.canStop { await backend.stop() }
                        else { await backend.start() }
                    }
                } label: {
                    Label(
                        L10n.string(backend.canStop ? "action.stop" : "action.start"),
                        systemImage: backend.canStop ? "stop.fill" : "mic.fill"
                    )
                }
                .disabled(backend.phase == .starting)
            }
        }
        .alert(L10n.string("settings.error"), isPresented: Binding(
            get: { backend.errorMessage != nil },
            set: { if !$0 { backend.errorMessage = nil } }
        )) {
            Button(L10n.string("action.ok"), role: .cancel) { backend.errorMessage = nil }
        } message: {
            Text(backend.errorMessage ?? "")
        }
        .onChange(of: selection) { newValue in
            Task { await backend.setSpectrumStreaming(newValue == .audio) }
        }
        .onDisappear {
            Task { await backend.setSpectrumStreaming(false) }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject private var backend: BackendController

    private var normalizedLevel: Double {
        Double(backend.audioLevel) / Double(max(backend.audioPeak, 1))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.string("dashboard.title")).font(.largeTitle.bold())
                        Text(backend.phaseLabel).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if backend.canStop {
                        Button {
                            Task { await backend.stop() }
                        } label: { Label(L10n.string("action.stop"), systemImage: "stop.fill") }
                        .buttonStyle(.bordered)
                    } else {
                        Button {
                            Task { await backend.start() }
                        } label: { Label(L10n.string("action.start"), systemImage: "mic.fill") }
                        .buttonStyle(.borderedProminent)
                        .disabled(backend.phase == .starting)
                    }
                }

                GroupBox {
                    HStack(spacing: 16) {
                        Image(systemName: backend.connectedDevice == nil ? "iphone.slash" : "iphone.gen3")
                            .font(.system(size: 28))
                            .foregroundColor(backend.connectedDevice == nil ? Color.secondary : Color.green)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.string("dashboard.device")).font(.headline)
                            if let device = backend.connectedDevice {
                                Text("\(device.name) · \(device.ip)")
                                Text("\(L10n.string("dashboard.phoneLatency")): \(device.latency) ms")
                                    .font(.caption).foregroundStyle(.secondary)
                            } else {
                                Text(L10n.string("dashboard.noDevice")).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if backend.connection.mode == "web" {
                            Label("\(backend.webClientCount) · \(L10n.string("dashboard.clients"))", systemImage: "globe")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }

                if !backend.phase.isRunning {
                    Label(L10n.string("dashboard.empty"), systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                }

                GroupBox(L10n.string("dashboard.level")) {
                    HStack {
                        ProgressView(value: normalizedLevel)
                        Text("\(backend.audioLevel)").monospacedDigit().frame(minWidth: 60, alignment: .trailing)
                    }
                    .padding(.vertical, 4)
                }

                if let metrics = backend.metrics {
                    GroupBox(L10n.string("dashboard.metrics")) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), alignment: .leading)], alignment: .leading, spacing: 14) {
                            MetricCard(title: L10n.string("dashboard.latency"), value: "\(metrics.latencyMs) ms")
                            MetricCard(title: L10n.string("dashboard.networkLatency"), value: "\(metrics.networkLatencyMs) ms")
                            MetricCard(title: L10n.string("dashboard.jitter"), value: String(format: "%.1f ms", metrics.jitterMs))
                            MetricCard(title: L10n.string("dashboard.loss"), value: String(format: "%.2f%%", metrics.packetLossRate * 100))
                            MetricCard(title: L10n.string("dashboard.buffer"), value: "\(metrics.bufferDurationMs) ms")
                            MetricCard(title: L10n.string("dashboard.bitrate"), value: "\(metrics.bitrate)")
                            MetricCard(title: L10n.string("dashboard.sampleRate"), value: "\(metrics.sampleRate) Hz")
                        }
                        .padding(.vertical, 5)
                    }
                }

                if !backend.spectrum.isEmpty {
                    GroupBox(L10n.string("dashboard.spectrum")) {
                        SpectrumChart(values: backend.spectrum).frame(height: 100).padding(.vertical, 5)
                    }
                }

                HStack {
                    Toggle(L10n.string("dashboard.muted"), isOn: Binding(
                        get: { backend.isMuted },
                        set: { value in Task { await backend.setMuted(value) } }
                    ))
                    .disabled(!backend.isBackendReady)
                    Toggle(L10n.string("dashboard.monitoring"), isOn: Binding(
                        get: { backend.isMonitoring },
                        set: { value in Task { await backend.setMonitoring(value) } }
                    ))
                    .disabled(!backend.isBackendReady)
                }
                .toggleStyle(.switch)

                if let warning = backend.warningMessage {
                    Label(warning, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                if let aec = backend.aecMessage {
                    Label("AEC: \(aec)", systemImage: "info.circle").foregroundStyle(.secondary)
                }
                if let diagnostic = backend.diagnosticMessage {
                    Text(diagnostic).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            }
            .padding(24)
        }
    }
}

private struct MetricCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.monospacedDigit().weight(.medium))
        }
    }
}

private struct SpectrumChart: View {
    let values: [Double]

    var body: some View {
        Canvas { context, size in
            guard values.count > 1 else { return }
            let peak = max(values.map(abs).max() ?? 1, 0.0001)
            var path = Path()
            for (index, value) in values.enumerated() {
                let x = size.width * CGFloat(index) / CGFloat(values.count - 1)
                let normalized = min(max(value / peak, -1), 1)
                let y = size.height * (1 - CGFloat(normalized + 1) / 2)
                if index == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            context.stroke(path, with: .color(.accentColor), lineWidth: 1.5)
        }
        .accessibilityLabel(L10n.string("dashboard.spectrum"))
    }
}
