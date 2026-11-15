import AppIntents
import SwiftUI
import WidgetKit

enum GridChoice: String, AppEnum {
    case two, three, keypad
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "칸 구성"
    static var caseDisplayRepresentations: [GridChoice: DisplayRepresentation] = [
        .two: "2 × 2", .three: "3 × 3", .keypad: "3 × 4 (키패드)",
    ]
    var value: Int { self == .two ? 2 : (self == .three ? 3 : 4) }
}

/// 앱과 위젯이 App Group 으로 설정을 나눠 쓸 수 있으면 이 값들은 쓰이지 않는다.
/// (나눠 쓸 수 없는 설치본에서만, 위젯 편집 화면에서 직접 정하는 보조 방식)
struct LauncherIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "조합 설정"
    static var description = IntentDescription("앱에서 설정이 전달되지 않을 때만 사용합니다. 형식: 순서 주소; 순서 주소")

    @Parameter(title: "칸 구성", default: .two) var grid: GridChoice
    @Parameter(title: "조합 (예: 11 maps://; 12 music://)", default: "11 maps://; 12 music://; 21 sms://; 22 message://")
    var combos: String
    @Parameter(title: "입력 제한시간(초)", default: 4) var timeout: Int
}

struct Entry: TimelineEntry {
    let date: Date
    let config: LauncherConfig
    let seq: [Int]          // 이 시점까지 누른 칸 번호
    let direct: Bool        // 위젯 편집값을 직접 쓰는 모드(App Group 없음)
    let combosText: String
    var flash: Int? = nil   // 방금 누른 칸 (잠깐 살짝 불투명하게 표시)
}

struct Provider: AppIntentTimelineProvider {
    private func make(_ c: LauncherIntent?, at now: Date = .now) -> (Entry, LauncherConfig) {
        var cfg = LauncherConfig.load()
        let direct = !LauncherConfig.isSharingAvailable
        var text = ""
        if direct, let c {
            cfg.grid = c.grid.value
            cfg.timeout = Double(min(max(c.timeout, 1), 15))
            cfg.combos = LauncherConfig.parseCombos(c.combos)
            text = c.combos
        }
        let st = TapState.current(timeout: cfg.timeout)
        let flashing = now.timeIntervalSince(st.at) < Self.flashDuration
        return (Entry(date: now, config: cfg, seq: st.seq, direct: direct, combosText: text,
                      flash: flashing ? st.lastCell : nil), cfg)
    }

    /// 누른 칸이 불투명하게 보이는 시간(초)
    static let flashDuration: TimeInterval = 0.7

    func placeholder(in context: Context) -> Entry { make(nil).0 }

    func snapshot(for configuration: LauncherIntent, in context: Context) async -> Entry {
        make(configuration).0
    }

    func timeline(for configuration: LauncherIntent, in context: Context) async -> Timeline<Entry> {
        let (e, cfg) = make(configuration)
        let st = TapState.current(timeout: cfg.timeout)
        var entries = [e]
        // 누름 표시를 거둔 화면
        if e.flash != nil {
            entries.append(Entry(date: st.at.addingTimeInterval(Self.flashDuration + 0.05), config: cfg, seq: st.seq,
                                 direct: e.direct, combosText: e.combosText, flash: nil))
        }
        // 제한시간이 지나면 입력 상태를 비운 화면으로 바꾼다.
        if !st.seq.isEmpty {
            entries.append(Entry(date: st.at.addingTimeInterval(cfg.timeout + 0.2), config: cfg, seq: [],
                                 direct: e.direct, combosText: e.combosText, flash: nil))
        }
        return Timeline(entries: entries, policy: .never)
    }
}

struct GridView: View {
    let entry: Entry

    var body: some View {
        let rows = entry.config.rows, cols = entry.config.cols
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { col in
                        cell(row * cols + col + 1)
                    }
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func cell(_ number: Int) -> some View {
        // 눈에 보이지 않을 만큼만 칠해서(알파 1/255 수준) 터치 영역으로 인식되게 한다.
        // 방금 누른 칸은 잠깐 살짝 불투명하게 보여 준다.
        let area = (entry.flash == number ? Color.white.opacity(0.28) : Color.black.opacity(0.004))
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let r = ComboLogic.resolve(seq: entry.seq, tap: number, combos: entry.config.combos)
        if let url = r.url {
            // 이 칸을 누르면 조합이 완성된다 → 바로 앱 열기
            Button(intent: OpenLinkIntent(url: url)) { area }.buttonStyle(.plain)
        } else {
            // 진행 중이거나 조합과 무관한 칸도 반드시 버튼으로 받는다.
            // (일반 영역으로 두면 시스템 기본 동작인 '위젯 앱 열기'가 실행된다)
            Button(intent: TapIntent(cell: number, combosText: entry.direct ? entry.combosText : "",
                                     timeout: Int(entry.config.timeout))) { area }.buttonStyle(.plain)
        }
    }
}

@main
struct LauncherWidget: Widget {
    /// 지원하는 크기. 가장 큰 크기(페이지를 채우는 위젯)는 이를 지원하는 기기에서만 목록에 나타난다.
    static var families: [WidgetFamily] {
        var f: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        if #available(iOS 27.0, *) { f.append(.systemExtraLargePortrait) }
        return f
    }

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "LauncherWidget", intent: LauncherIntent.self, provider: Provider()) { entry in
            GridView(entry: entry)
        }
        .configurationDisplayName("투명 런처")
        .description("투명한 칸을 정해진 순서로 누르면 앱이 열립니다. 조합은 앱에서 정합니다.")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }
}
