import AppIntents
import SwiftUI
import UniformTypeIdentifiers
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

    @Parameter(title: "투명 배경 이미지", supportedContentTypes: [.image])
    var background: IntentFile?

    @Parameter(title: "위치 보정용 표식 색 표시", default: false)
    var calibration: Bool

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
        .containerBackground(for: .widget) { backgroundView }
    }

    /// IntentFile 의 data 가 비어 있으면 파일 URL 로 직접 읽는다.
    private func loadBackgroundImage() -> UIImage? {
        guard let f = config.background else { return nil }
        if !f.data.isEmpty, let img = UIImage(data: f.data) { return img }
        if let url = f.fileURL {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let d = try? Data(contentsOf: url), let img = UIImage(data: d) { return img }
        }
        return nil
    }

    /// 표식 색 → 선택한 이미지 → (없으면) 투명 시도 순서
    @ViewBuilder
    private var backgroundView: some View {
        if config.calibration {
            Color(red: 1, green: 0, blue: 1)
        } else if let image = loadBackgroundImage() {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private func cell(_ index: Int) -> some View {
        let raw = config.urls[index].trimmingCharacters(in: .whitespaces)
        let area = Color.black.opacity(0.001)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        if let url = URL(string: raw), !raw.isEmpty {
            Link(destination: url) { area }
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
        .description("배경 이미지를 월페이퍼에 맞춰 투명처럼 보이게 하고, 칸을 터치하면 지정한 앱이 열립니다. 위젯을 길게 눌러 '위젯 편집'에서 설정하세요.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
