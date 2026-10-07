import SwiftUI

struct ContentView: View {
    @ObservedObject var model: MicYouAppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @FocusState private var hostFocused: Bool

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    List {
                        Label("Microphone", systemImage: "mic.fill")
                        NavigationLink {
                            MicYouSettingsView(settings: model.settings)
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                    }
                    .listStyle(.sidebar)
                    .navigationTitle(ProductBrand.name)
                } detail: {
                    NavigationStack { dashboard }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack { dashboard }
            }
        }
        .tint(model.settings.accentColor)
        .preferredColorScheme(preferredColorScheme)
        .environment(\.locale, model.settings.locale)
        .task { model.startDiscovery() }
    }

    private var dashboard: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340, maximum: 610), spacing: 18)], spacing: 18) {
                connectionCard
                microphoneCard
                serverCard
                footer
            }
            .frame(maxWidth: 1_260)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .frame(maxWidth: .infinity)
        }
        .background(background)
        .navigationTitle(ProductBrand.name)
        .toolbar {
            if horizontalSizeClass != .regular {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MicYouSettingsView(settings: model.settings)
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 17, weight: .semibold))
                    }
                    .accessibilityLabel("Settings")
                }
            }
        }
        .onChange(of: model.settings.keepScreenAwake) { _ in model.scenePhaseChanged(.active) }
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Connect to your computer")
                        .font(.headline)
                    Text("Choose a discovered server or enter its address")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button {
                    model.refreshDiscovery()
                } label: {
                    Image(systemName: model.isScanning ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(.thinMaterial, in: Circle())
                }
                .accessibilityLabel("Refresh server discovery")
            }

            HStack(spacing: 10) {
                TextField("Host name or IP", text: hostBinding)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.next)
                    .focused($hostFocused)
                    .padding(.horizontal, 13)
                    .frame(height: 48)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))

                TextField("8554", value: portBinding, format: .number)
                    .keyboardType(.numberPad)
                    .frame(width: 76, height: 48)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 7)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel("Port")
            }

            Button {
                hostFocused = false
                model.connectManually()
            } label: {
                Label("Connect", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(.white)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 16))
            }
            .disabled(model.state == .connecting || model.state == .streaming)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var microphoneCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(model.state.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("connection-status")
                Spacer()
                if model.state == .streaming, let name = model.selectedServerName {
                    Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            AudioVisualizerView(level: model.audioLevel, style: model.settings.visualizerStyle)
                .frame(height: 210)
                .accessibilityLabel("Microphone level \(Int(model.audioLevel * 100)) percent")

            HStack(spacing: 12) {
                Button {
                    model.toggleMute()
                } label: {
                    Label(model.isMuted ? "Unmute" : "Mute", systemImage: model.isMuted ? "mic.slash.fill" : "mic.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .font(.subheadline.weight(.semibold))
                        .background(model.isMuted ? Color.red.opacity(0.16) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
                }
                .disabled(model.state != .streaming)
                .accessibilityIdentifier("mute-button")

                Button {
                    if model.state == .streaming || model.state == .connecting {
                        model.disconnect()
                    } else {
                        model.connectManually()
                    }
                } label: {
                    Label(model.state == .streaming || model.state == .connecting ? "Disconnect" : "Start microphone", systemImage: model.state == .streaming ? "stop.fill" : "mic.circle.fill")
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .background(model.state == .streaming ? Color.red.gradient : Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 15))
                }
                .accessibilityIdentifier("stream-button")
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var serverCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Nearby servers").font(.headline)
                Spacer()
                Text(model.isScanning ? "Searching" : "Local network")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if model.discoveredServers.isEmpty {
                Label("No MicYou server found", systemImage: "dot.radiowaves.left.and.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(model.discoveredServers) { server in
                    Button {
                        model.connect(to: server)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "desktopcomputer")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 40, height: 40)
                                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                Text("MicYou · TCP").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("server-\(server.id)")
                }
            }
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield")
            Text("Audio is sent directly to your selected computer over your local network.")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private var statusColor: Color {
        switch model.state {
        case .idle: .secondary
        case .connecting: .orange
        case .streaming: model.isMuted ? .orange : .green
        case .failed: .red
        }
    }

    private var preferredColorScheme: ColorScheme? {
        switch model.settings.appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    private var hostBinding: Binding<String> {
        Binding(get: { model.settings.host }, set: { model.settings.host = $0 })
    }

    private var portBinding: Binding<Int> {
        Binding(get: { model.settings.port }, set: { model.settings.port = $0 })
    }

    @ViewBuilder
    private var background: some View {
        if let path = model.settings.backgroundImagePath, let image = UIImage(contentsOfFile: path) {
            Image(uiImage: image).resizable().scaledToFill().overlay(.black.opacity(colorScheme == .dark ? 0.5 : 0.2)).ignoresSafeArea()
        } else if model.settings.oledBlack && colorScheme == .dark {
            Color.black.ignoresSafeArea()
        } else {
            Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
        }
    }
}

private struct AudioVisualizerView: View {
    let level: Double
    let style: Int
    private let accent = Color.accentColor

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, geometry.size.height)
            ZStack {
                switch style {
                case 1: ripple(size: size)
                case 2: bars(size: size)
                case 3: waveform(size: size)
                case 4: glow(size: size)
                case 5: particles(size: size)
                default: ring(size: size)
                }
                Image(systemName: "mic.fill")
                    .font(.system(size: size * 0.16, weight: .medium))
                    .foregroundStyle(level > 0.03 ? accent : Color.secondary)
                    .shadow(color: accent.opacity(level * 0.5), radius: 12 + level * 14)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeOut(duration: 0.12), value: level)
        }
    }

    private func ring(size: CGFloat) -> some View {
        ZStack {
            Circle().stroke(accent.opacity(0.12), lineWidth: 9).frame(width: size * 0.78, height: size * 0.78)
            Circle().trim(from: 0, to: max(0.02, level)).stroke(accent.gradient, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .frame(width: size * 0.78, height: size * 0.78).rotationEffect(.degrees(-90))
            Circle().stroke(accent.opacity(0.22), lineWidth: 1).frame(width: size * 0.56, height: size * 0.56)
        }
    }

    private func ripple(size: CGFloat) -> some View {
        ZStack {
            ForEach(0..<4) { index in
                let diameter = size * (CGFloat(0.32) + CGFloat(index) * 0.18 + CGFloat(level) * 0.09)
                Circle().stroke(accent.opacity(0.4 - Double(index) * 0.08), lineWidth: 2)
                    .frame(width: diameter, height: diameter)
            }
        }
    }

    private func bars(size: CGFloat) -> some View {
        HStack(alignment: .center, spacing: 5) {
            ForEach(0..<15) { index in
                let envelope = CGFloat(0.12 + abs(sin(Double(index) * 0.62)) * 0.55)
                Capsule().fill(accent.opacity(0.55 + envelope * 0.45))
                    .frame(width: max(3, size * 0.018), height: max(7, size * envelope * (0.2 + CGFloat(level) * 1.1)))
            }
        }
    }

    private func waveform(size: CGFloat) -> some View {
        Canvas { context, canvasSize in
            var path = Path()
            let mid = canvasSize.height / 2
            let amplitude = canvasSize.height * (0.04 + level * 0.39)
            for x in stride(from: 0.0, through: Double(canvasSize.width), by: 2) {
                let progress = x / Double(canvasSize.width)
                let y = Double(mid) + sin(progress * .pi * 8) * Double(amplitude) * (0.4 + abs(cos(progress * .pi * 2)) * 0.6)
                if x == 0 { path.move(to: CGPoint(x: CGFloat(x), y: CGFloat(y))) } else { path.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y))) }
            }
            context.stroke(path, with: .color(accent.opacity(0.85)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        }
        .frame(width: size * 0.86, height: size * 0.45)
    }

    private func glow(size: CGFloat) -> some View {
        Circle().fill(accent.opacity(0.18 + level * 0.35)).frame(width: size * (0.48 + CGFloat(level) * 0.2), height: size * (0.48 + CGFloat(level) * 0.2)).blur(radius: 20 + CGFloat(level) * 22)
    }

    private func particles(size: CGFloat) -> some View {
        ZStack {
            ForEach(0..<18) { index in
                let angle = Double(index) * .pi * 2 / 18
                let radius = size * CGFloat(0.2 + 0.14 * (0.5 + 0.5 * sin(Double(index) * 1.8 + level * 5)))
                Circle().fill(accent.opacity(0.35 + level * 0.5))
                    .frame(width: 3 + CGFloat(level) * 6, height: 3 + CGFloat(level) * 6)
                    .offset(x: cos(angle) * radius, y: sin(angle) * radius)
            }
        }
    }
}
