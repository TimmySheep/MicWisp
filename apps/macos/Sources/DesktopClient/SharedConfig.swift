import Foundation
import Darwin

enum SharedConfig {
    static var directory: URL {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return URL(fileURLWithPath: xdg, isDirectory: true).appendingPathComponent("micyou", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("micyou", isDirectory: true)
    }

    static func load<T: Decodable>(_ type: T.Type, file: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(file)) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func save<T: Encodable>(_ value: T, file: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: directory.appendingPathComponent(file), options: .atomic)
    }
}

enum SidecarLocator {
    static func locate() -> URL? {
        let bundled = [
            Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/micyou-cli"),
            Bundle.main.resourceURL?.appendingPathComponent("Helpers/micyou-cli"),
        ].compactMap { $0 }
        let fromPath = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("micyou-cli") }
        return (bundled + fromPath).first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

enum LocalNetworkAddresses {
    static func ipv4() -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }

        var result = Set<String>()
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let item = current {
            let interface = item.pointee
            if let address = interface.ifa_addr,
               address.pointee.sa_family == UInt8(AF_INET),
               (interface.ifa_flags & UInt32(IFF_UP)) != 0,
               (interface.ifa_flags & UInt32(IFF_LOOPBACK)) == 0 {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let status = getnameinfo(
                    address,
                    socklen_t(address.pointee.sa_len),
                    &host,
                    socklen_t(host.count),
                    nil,
                    0,
                    NI_NUMERICHOST
                )
                if status == 0 {
                    let length = host.firstIndex(of: 0) ?? host.endIndex
                    result.insert(String(decoding: host[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self))
                }
            }
            current = interface.ifa_next
        }
        return result.sorted()
    }
}
