import AppIntents
import SwiftUI
import WidgetKit

enum GridSize: String, AppEnum {
    case two, three
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "칸 개수"
    static var caseDisplayRepresentations: [GridSize: DisplayRepresentation] = [
        .two: "2 × 2",
        .three: "3 × 3",
    ]
    var count: Int { self == .two ? 2 : 3 }
}

struct LauncherIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "칸 설정"
    static var description = IntentDescription("칸마다 실행할 앱의 URL 스킴을 입력하세요. (예: maps://)")

    @Parameter(title: "칸 개수", default: .two) var grid: GridSize
    @Parameter(title: "1번 (왼쪽 위)", default: "maps://") var u1: String
    @Parameter(title: "2번", default: "music://") var u2: String
    @Parameter(title: "3번", default: "sms://") var u3: String
    @Parameter(title: "4번", default: "message://") var u4: String
    @Parameter(title: "5번 (3×3만)", default: "") var u5: String
    @Parameter(title: "6번 (3×3만)", default: "") var u6: String
    @Parameter(title: "7번 (3×3만)", default: "") var u7: String
    @Parameter(title: "8번 (3×3만)", default: "") var u8: String
    @Parameter(title: "9번 (3×3만)", default: "") var u9: String

    var urls: [String] { [u1, u2, u3, u4, u5, u6, u7, u8, u9] }
}

/// 칸을 탭했을 때 지정한 주소를 연다. (시스템 OpenURLIntent 를 직접 버튼에 쓰면 메타데이터 오류가 난다)
struct OpenLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "앱 열기"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "주소") var url: String

    init() { self.url = "" }
    init(url: String) { self.url = url }

    func perform() async throws -> some IntentResult & OpensIntent {
        let target = URL(string: url) ?? URL(string: "swipelauncher://invalid")!
        return .result(opensIntent: OpenURLIntent(target))
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let config: LauncherIntent
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, config: LauncherIntent()) }
    func snapshot(for configuration: LauncherIntent, in context: Context) async -> Entry {
        Entry(date: .now, config: configuration)
    }
    func timeline(for configuration: LauncherIntent, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: [Entry(date: .now, config: configuration)], policy: .never)
    }
}

struct GridView: View {
    let config: LauncherIntent

    var body: some View {
        let n = config.grid.count
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

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        let raw = config.urls[index].trimmingCharacters(in: .whitespaces)
        let area = Color.black.opacity(0.03)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        if URL(string: raw) != nil, !raw.isEmpty {
            Button(intent: OpenLinkIntent(url: raw)) { area }
                .buttonStyle(.plain)
        } else {
            area
        }
    }
}

@main
struct LauncherWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LauncherWidget", intent: LauncherIntent.self, provider: Provider()) { entry in
            GridView(config: entry.config)
        }
        .configurationDisplayName("투명 런처")
        .description("투명한 칸을 터치하면 지정한 앱이 열립니다. 위젯을 길게 눌러 '위젯 편집'에서 설정하세요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
