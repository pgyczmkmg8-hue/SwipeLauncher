import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let config: LauncherConfig
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, config: LauncherConfig()) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: .now, config: LauncherConfig.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now, config: LauncherConfig.load())], policy: .never))
    }
}

struct GridView: View {
    let config: LauncherConfig

    var body: some View {
        let n = config.grid
        VStack(spacing: 0) {
            ForEach(0..<n, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<n, id: \.self) { col in
                        cell(row * n + col)
                    }
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    /// 우리 앱 주소(swipelauncher://open?u=...)로 보내면 앱이 즉시 대상 앱을 연다.
    private static func relayURL(for raw: String) -> URL? {
        guard !raw.isEmpty, URL(string: raw) != nil else { return nil }
        var c = URLComponents()
        c.scheme = "swipelauncher"
        c.host = "open"
        c.queryItems = [URLQueryItem(name: "u", value: raw)]
        return c.url
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        let raw = index < config.urls.count ? config.urls[index].trimmingCharacters(in: .whitespaces) : ""
        // 눈에 보이지 않을 만큼만 칠해서(알파 1/255 수준) 터치 영역으로 인식되게 한다.
        let area = Color.black.opacity(0.004)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        if let target = Self.relayURL(for: raw) {
            Link(destination: target) { area }
        } else {
            area
        }
    }
}

@main
struct LauncherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LauncherWidget", provider: Provider()) { entry in
            GridView(config: entry.config)
        }
        .configurationDisplayName("투명 런처")
        .description("투명한 칸을 터치하면 앱에서 지정한 앱이 열립니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
