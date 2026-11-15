import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let slots: [Direction: AppSlot]
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, slots: Config.defaults) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, slots: Config.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now, slots: Config.load())], policy: .never))
    }
}

struct LauncherWidgetView: View {
    let entry: Entry

    var body: some View {
        VStack {
            label(.up)
            Spacer()
            HStack {
                label(.left)
                Spacer()
                Image(systemName: "hand.draw")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Spacer()
                label(.right)
            }
            Spacer()
            label(.down)
        }
        .widgetURL(Config.padURL)
        .containerBackground(for: .widget) {
            Rectangle().fill(.ultraThinMaterial)
        }
    }

    private func label(_ d: Direction) -> some View {
        VStack(spacing: 2) {
            Image(systemName: d.symbol).font(.caption.bold())
            Text(entry.slots[d]?.name ?? "-").font(.caption2)
        }
        .foregroundStyle(.primary)
    }
}

@main
struct LauncherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LauncherWidget", provider: Provider()) { entry in
            LauncherWidgetView(entry: entry)
        }
        .configurationDisplayName("SwipeLauncher")
        .description("탭하면 제스처 패드가 열려요. 스와이프로 앱을 실행하세요.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
