import SwiftUI
import WidgetKit

struct MicWispStatusEntry: TimelineEntry {
    let date: Date
    let isStreaming: Bool
    let server: String
    let isMuted: Bool
}

struct MicWispStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> MicWispStatusEntry {
        MicWispStatusEntry(date: Date(), isStreaming: true, server: "My computer", isMuted: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (MicWispStatusEntry) -> Void) {
        completion(readStatus())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MicWispStatusEntry>) -> Void) {
        completion(Timeline(entries: [readStatus()], policy: .after(Date().addingTimeInterval(15 * 60))))
    }

    private func readStatus() -> MicWispStatusEntry {
        let group = Bundle.main.object(forInfoDictionaryKey: "MICWISP_APP_GROUP") as? String ?? ""
        let defaults = group.isEmpty ? nil : UserDefaults(suiteName: group)
        return MicWispStatusEntry(
            date: Date(),
            isStreaming: defaults?.bool(forKey: "streaming") ?? false,
            server: defaults?.string(forKey: "server") ?? "",
            isMuted: defaults?.bool(forKey: "muted") ?? false
        )
    }
}

struct MicWispStatusWidget: Widget {
    static let kind = ProductBrand.statusWidgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: MicWispStatusProvider()) { entry in
            MicWispStatusWidgetView(entry: entry)
                .background(Color(uiColor: .secondarySystemBackground))
        }
        .configurationDisplayName(ProductBrand.name)
        .description("View the current microphone connection.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct MicWispStatusWidgetView: View {
    let entry: MicWispStatusEntry

    var body: some View {
        Link(destination: URL(string: "\(ProductBrand.urlScheme)://open")!) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: entry.isMuted ? "mic.slash.fill" : "mic.fill")
                        .foregroundStyle(entry.isStreaming ? (entry.isMuted ? .orange : .green) : .secondary)
                    Spacer()
                    Text(ProductBrand.name).font(.headline)
                }
                Spacer(minLength: 0)
                Text(entry.isStreaming ? "Streaming" : "Not connected")
                    .font(.title3.weight(.semibold))
                if !entry.server.isEmpty { Text(entry.server).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                if entry.isStreaming { Text(entry.isMuted ? "Microphone muted" : "Microphone live").font(.caption2).foregroundStyle(.secondary) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
