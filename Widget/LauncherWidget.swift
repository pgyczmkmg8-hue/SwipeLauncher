import AppIntents
import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    let date: Date
    let config: LauncherConfig
    let seq: [Int]          // 이 시점까지 누른 칸 번호
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, config: LauncherConfig(), seq: []) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let c = LauncherConfig.load()
        completion(Entry(date: .now, config: c, seq: TapState.current(timeout: c.timeout).seq))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let c = LauncherConfig.load()
        let st = TapState.current(timeout: c.timeout)
        var entries = [Entry(date: .now, config: c, seq: st.seq)]
        // 제한시간이 지나면 입력 상태를 비운 화면으로 바꾼다.
        if !st.seq.isEmpty {
            entries.append(Entry(date: st.at.addingTimeInterval(c.timeout + 0.2), config: c, seq: []))
        }
        completion(Timeline(entries: entries, policy: .never))
    }
}

struct GridView: View {
    let entry: Entry

    var body: some View {
        let n = entry.config.grid
        VStack(spacing: 0) {
            ForEach(0..<n, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<n, id: \.self) { col in
                        cell(row * n + col + 1)
                    }
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private func cell(_ number: Int) -> some View {
        // 눈에 보이지 않을 만큼만 칠해서(알파 1/255 수준) 터치 영역으로 인식되게 한다.
        let area = Color.black.opacity(0.004)
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        let r = ComboLogic.resolve(seq: entry.seq, tap: number, combos: entry.config.combos)
        if let url = r.url {
            // 이 칸을 누르면 조합이 완성된다 → 바로 앱 열기
            Button(intent: OpenLinkIntent(url: url)) { area }.buttonStyle(.plain)
        } else if !r.new.isEmpty || !entry.seq.isEmpty {
            // 조합 진행 중 → 번호만 기록
            Button(intent: TapIntent(cell: number)) { area }.buttonStyle(.plain)
        } else {
            area
        }
    }
}

@main
struct LauncherWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LauncherWidget", provider: Provider()) { entry in
            GridView(entry: entry)
        }
        .configurationDisplayName("투명 런처")
        .description("투명한 칸을 정해진 순서로 누르면 앱이 열립니다. 조합은 앱에서 정합니다.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
