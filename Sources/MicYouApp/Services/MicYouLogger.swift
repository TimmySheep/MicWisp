import Foundation

final class MicYouLogger {
    static let shared = MicYouLogger()
    private let queue = DispatchQueue(label: "com.timmy.micyou.log", qos: .utility)
    private let fileURL: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MicYou/Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("micyou.log")
    }

    func write(_ message: String) {
        queue.async {
            let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
            guard let data = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: self.fileURL.path),
               let handle = try? FileHandle(forWritingTo: self.fileURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: self.fileURL, options: .atomic)
            }
        }
    }

    var exportURL: URL { fileURL }
}
