import Combine
import Foundation
import SwiftUI

@MainActor
final class MicYouSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var host: String { didSet { defaults.set(host, forKey: Key.host) } }
    @Published var port: Int { didSet { defaults.set(port, forKey: Key.port) } }
    @Published var sampleRate: Int { didSet { defaults.set(sampleRate, forKey: Key.sampleRate) } }
    @Published var channelCount: Int { didSet { defaults.set(channelCount, forKey: Key.channelCount) } }
    @Published var visualizerStyle: Int { didSet { defaults.set(visualizerStyle, forKey: Key.visualizerStyle) } }
    @Published var noiseSuppression: NoiseMode { didSet { defaults.set(noiseSuppression.rawValue, forKey: Key.noiseSuppression) } }
    @Published var noiseIntensity: Double { didSet { defaults.set(noiseIntensity, forKey: Key.noiseIntensity) } }
    @Published var keepScreenAwake: Bool { didSet { defaults.set(keepScreenAwake, forKey: Key.keepScreenAwake) } }
    @Published var streamingNotification: Bool { didSet { defaults.set(streamingNotification, forKey: Key.streamingNotification) } }
    @Published var autoCheckUpdates: Bool { didSet { defaults.set(autoCheckUpdates, forKey: Key.autoCheckUpdates) } }
    @Published var oledBlack: Bool { didSet { defaults.set(oledBlack, forKey: Key.oledBlack) } }
    @Published var accentIndex: Int { didSet { defaults.set(accentIndex, forKey: Key.accentIndex) } }
    @Published var appearance: Appearance { didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) } }
    @Published var language: Language { didSet { defaults.set(language.rawValue, forKey: Key.language) } }
    @Published private(set) var backgroundImagePath: String?
    @Published private(set) var recentHosts: [String]

    enum NoiseMode: String, CaseIterable, Identifiable {
        case off
        case system
        case rnnoise
        var id: String { rawValue }
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system
        case light
        case dark
        var id: String { rawValue }
    }

    enum Language: String, CaseIterable, Identifiable {
        case system
        case simplifiedChinese
        case traditionalChinese
        case english
        var id: String { rawValue }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        host = defaults.string(forKey: Key.host) ?? ""
        port = defaults.object(forKey: Key.port) as? Int ?? 8554
        sampleRate = defaults.object(forKey: Key.sampleRate) as? Int ?? 48_000
        channelCount = defaults.object(forKey: Key.channelCount) as? Int ?? 1
        visualizerStyle = defaults.object(forKey: Key.visualizerStyle) as? Int ?? 0
        noiseSuppression = NoiseMode(rawValue: defaults.string(forKey: Key.noiseSuppression) ?? "system") ?? .system
        noiseIntensity = defaults.object(forKey: Key.noiseIntensity) as? Double ?? 70
        keepScreenAwake = defaults.bool(forKey: Key.keepScreenAwake)
        streamingNotification = defaults.object(forKey: Key.streamingNotification) as? Bool ?? true
        autoCheckUpdates = defaults.object(forKey: Key.autoCheckUpdates) as? Bool ?? true
        oledBlack = defaults.bool(forKey: Key.oledBlack)
        accentIndex = defaults.object(forKey: Key.accentIndex) as? Int ?? 0
        appearance = Appearance(rawValue: defaults.string(forKey: Key.appearance) ?? "system") ?? .system
        language = Language(rawValue: defaults.string(forKey: Key.language) ?? "system") ?? .system
        backgroundImagePath = defaults.string(forKey: Key.backgroundImagePath)
        recentHosts = defaults.stringArray(forKey: Key.recentHosts) ?? []
    }

    var locale: Locale {
        switch language {
        case .system: .autoupdatingCurrent
        case .simplifiedChinese: Locale(identifier: "zh-Hans")
        case .traditionalChinese: Locale(identifier: "zh-Hant")
        case .english: Locale(identifier: "en")
        }
    }

    var accentColor: Color {
        let palette: [Color] = [.accentColor, .indigo, .teal, .orange, .pink, .purple]
        return palette.indices.contains(accentIndex) ? palette[accentIndex] : .accentColor
    }

    func saveBackgroundImage(_ data: Data) {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MicYou", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("background-image")
            try data.write(to: url, options: .atomic)
            backgroundImagePath = url.path
            defaults.set(url.path, forKey: Key.backgroundImagePath)
        } catch {
            MicYouLogger.shared.write("Could not save background image: \(error.localizedDescription)")
        }
    }

    func clearBackgroundImage() {
        if let backgroundImagePath { try? FileManager.default.removeItem(atPath: backgroundImagePath) }
        backgroundImagePath = nil
        defaults.removeObject(forKey: Key.backgroundImagePath)
    }

    func rememberRecentHost(_ host: String) {
        recentHosts.removeAll { $0.caseInsensitiveCompare(host) == .orderedSame }
        recentHosts.insert(host, at: 0)
        recentHosts = Array(recentHosts.prefix(8))
        defaults.set(recentHosts, forKey: Key.recentHosts)
    }

    private enum Key {
        static let host = "micyou_host"
        static let port = "micyou_port"
        static let sampleRate = "micyou_sample_rate"
        static let channelCount = "micyou_channel_count"
        static let visualizerStyle = "micyou_visualizer_style"
        static let noiseSuppression = "micyou_noise_suppression"
        static let noiseIntensity = "micyou_noise_intensity"
        static let keepScreenAwake = "micyou_keep_screen_on"
        static let streamingNotification = "micyou_streaming_notification"
        static let autoCheckUpdates = "micyou_auto_check_update"
        static let oledBlack = "micyou_oled_black"
        static let accentIndex = "micyou_accent_index"
        static let appearance = "micyou_appearance"
        static let language = "micyou_language"
        static let recentHosts = "micyou_recent_hosts"
        static let backgroundImagePath = "micyou_background_image_path"
    }
}
