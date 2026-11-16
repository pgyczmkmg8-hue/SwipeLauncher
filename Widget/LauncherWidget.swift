import AppIntents
import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let config: LauncherConfig
    let seq: [Int]          // 이 시점까지 누른 칸 번호
    var readyURL: String? = nil   // 놓친 마지막 입력으로 이미 완성된 조합(마지막으로 누른 칸을 다시 누르면 연다)
    var readyCell: Int? = nil
    let direct: Bool = false
    let combosText: String = ""
    var flash: Int? = nil   // 방금 누른 칸 (잠깐 살짝 불투명하게 표시)
}

struct Provider: TimelineProvider {
    /// 누른 칸이 불투명하게 보이는 시간(초)
    static let flashDuration: TimeInterval = 0.1
    /// 마지막 입력이 이 시간 안이면 표시 대상으로 본다. (폰에서는 입력 처리 뒤 화면이 늦게 그려질 수 있다)
    static let flashWindow: TimeInterval = 3.0

    /// 설정과 입력 상태는 한 번씩만 읽는다.
    private func make(at now: Date = .now) -> (Entry, LauncherConfig, TapState) {
        let cfg = LauncherConfig.load()
        let st = TapState.current(config: cfg, now: now)
        let fresh = now.timeIntervalSince(st.at) < Self.flashWindow
        return (Entry(date: now, config: cfg, seq: st.seq, readyURL: st.readyURL, readyCell: st.lastCell,
                      flash: fresh ? st.lastCell : nil), cfg, st)
    }

    func placeholder(in context: Context) -> Entry { make().0 }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(make().0)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let (e, cfg, st) = make(at: now)
        var entries = [e]
        // 표시는 이 화면이 그려진 시점부터 잠깐만 보여 주고 거둔다.
        if e.flash != nil {
            entries.append(Entry(date: now.addingTimeInterval(Self.flashDuration), config: cfg, seq: st.seq,
                                 readyURL: st.readyURL, readyCell: st.lastCell, flash: nil))
        }
        // 제한시간이 지나면 입력 상태를 비운 화면으로 바꾼다.
        if !st.seq.isEmpty || st.readyURL != nil {
            entries.append(Entry(date: st.at.addingTimeInterval(cfg.timeout + 0.2), config: cfg, seq: [], flash: nil))
        }
        completion(Timeline(entries: entries, policy: .never))
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

    /// 칸을 눌렀을 때의 결과. 놓친 마지막 입력으로 이미 완성된 조합이면 그 칸을 다시 눌러 연다.
    private func resolved(_ number: Int) -> (new: [Int], url: String?) {
        let r = ComboLogic.resolve(seq: entry.seq, tap: number, combos: entry.config.combos)
        if r.url == nil, let ready = entry.readyURL, entry.readyCell == number { return (new: [], url: ready) }
        return r
    }

    private static func relayURL(_ raw: String) -> URL? {
        guard !raw.isEmpty, URL(string: raw) != nil,
              let enc = raw.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "swipelauncher://open?u=" + enc)
    }

    @ViewBuilder
    private func cell(_ number: Int) -> some View {
        // 눈에 보이지 않을 만큼만 칠해서(알파 1/255 수준) 터치 영역으로 인식되게 한다.
        // 방금 누른 칸은 잠깐 살짝 불투명하게 보여 준다.
        let area = (entry.flash == number ? Color.white.opacity(0.28) : Color.black.opacity(0.004))
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let r = resolved(number)
        if let url = r.url, entry.config.openDirect, !entry.direct {
            // (실험) 인텐트로 바로 열기
            Button(intent: OpenLinkIntent(url: url)) { area }.buttonStyle(.plain)
        } else if let url = r.url, let relay = Self.relayURL(url) {
            // 조합 완성 → 우리 앱 주소로 보내면 앱이 즉시 대상 앱을 연다 (폰에서 확인된 방식)
            Link(destination: relay) { area }
        } else {
            // 진행 중이거나 조합과 무관한 칸도 반드시 버튼으로 받는다.
            // (일반 영역으로 두면 시스템 기본 동작인 '위젯 앱 열기'가 실행된다)
            Button(intent: TapIntent(cell: number, combosText: entry.direct ? entry.combosText : "",
                                     timeout: Int(entry.config.timeout))) { area }.buttonStyle(.plain)
        }
    }
}

struct LauncherWidget: Widget {
    /// 지원하는 크기. 가장 큰 크기(페이지를 채우는 위젯)는 이를 지원하는 기기에서만 목록에 나타난다.
    static var families: [WidgetFamily] {
        var f: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge]
        if #available(iOS 27.0, *) { f.append(.systemExtraLargePortrait) }
        return f
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LauncherWidget", provider: Provider()) { entry in
            GridView(entry: entry)
        }
        .configurationDisplayName("투명 런처")
        .description("투명한 칸을 정해진 순서로 누르면 앱이 열립니다. 조합은 앱에서 정합니다.")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }
}
