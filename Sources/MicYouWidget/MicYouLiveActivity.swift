import SwiftUI
import WidgetKit

#if os(iOS)
import ActivityKit

struct MicYouLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MicYouActivityAttributes.self) { context in
            HStack(spacing: 14) {
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
                    .font(.title2)
                    .foregroundStyle(context.state.isMuted ? .orange : .green)
                    .frame(width: 42, height: 42)
                    .background(.quaternary, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(ProductBrand.name).font(.headline)
                    Text(context.attributes.serverName).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Link(destination: URL(string: "\(ProductBrand.urlScheme)://\(context.state.isMuted ? "unmute" : "mute")")!) {
                    Image(systemName: context.state.isMuted ? "mic.fill" : "mic.slash.fill")
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .background(.quaternary, in: Circle())
                }
                .accessibilityLabel(context.state.isMuted ? "Unmute microphone" : "Mute microphone")
            }
            .padding(16)
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.state.isMuted ? "Muted" : "Live", systemImage: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.headline)
                        .foregroundStyle(context.state.isMuted ? .orange : .green)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.serverName).font(.caption).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text("Microphone stream").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Link(destination: URL(string: "\(ProductBrand.urlScheme)://\(context.state.isMuted ? "unmute" : "mute")")!) {
                            Label(context.state.isMuted ? "Unmute" : "Mute", systemImage: context.state.isMuted ? "mic.fill" : "mic.slash.fill")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(context.state.isMuted ? .orange : .green)
            } compactTrailing: {
                Image(systemName: "waveform")
                    .foregroundStyle(.secondary)
            } minimal: {
                Image(systemName: context.state.isMuted ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(context.state.isMuted ? .orange : .green)
            }
            .widgetURL(URL(string: "\(ProductBrand.urlScheme)://open"))
            .keylineTint(.green)
        }
    }
}
#endif

@main
struct MicYouWidgetBundle: WidgetBundle {
    var body: some Widget {
        #if os(iOS)
        MicYouLiveActivity()
        #endif
        MicWispStatusWidget()
    }
}
