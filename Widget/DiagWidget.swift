import AppIntents
import SwiftUI
import WidgetKit

/// 폰에서 칸 입력이 어디서 막히는지 가려내는 진단용 위젯.
/// 같은 인텐트를 서로 다른 눌림 영역(불투명 / 거의 투명 / 약간 투명)에 붙여 놓고, 입력 횟수를 화면에 보여 준다.
struct DiagEntry: TimelineEntry {
    let date: Date
    let count: Int
    let lastCell: Int?
    let groupOK: Bool
}

struct DiagProvider: TimelineProvider {
    private func make() -> DiagEntry {
        let st = TapState.load()
        return DiagEntry(date: .now, count: st.count, lastCell: st.lastCell, groupOK: LauncherConfig.isSharingAvailable)
    }
    func placeholder(in context: Context) -> DiagEntry { make() }
    func getSnapshot(in context: Context, completion: @escaping (DiagEntry) -> Void) { completion(make()) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DiagEntry>) -> Void) {
        completion(Timeline(entries: [make()], policy: .never))
    }
}

struct DiagView: View {
    let entry: DiagEntry

    var body: some View {
        VStack(spacing: 6) {
            Text("진단 · 입력 \(entry.count)회 · 마지막 \(entry.lastCell.map(String.init) ?? "-")번 · 그룹 \(entry.groupOK ? "OK" : "X")")
                .font(.system(size: 11, weight: .semibold))
                .multilineTextAlignment(.center)
            button("A 진하게", cell: 1, fill: Color.blue.opacity(1))
            button("B 거의 투명", cell: 2, fill: Color.blue.opacity(0.004))
            button("C 옅게", cell: 3, fill: Color.blue.opacity(0.08))
        }
        .padding(6)
        .containerBackground(for: .widget) { Color.white }
    }

    private func button(_ title: String, cell: Int, fill: Color) -> some View {
        Button(intent: TapIntent(cell: cell)) {
            ZStack {
                fill
                Text(title).font(.system(size: 11)).foregroundStyle(.black)
            }
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.gray, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct DiagWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DiagWidget", provider: DiagProvider()) { entry in
            DiagView(entry: entry)
        }
        .configurationDisplayName("투명 런처 진단")
        .description("칸 입력이 실행되는지 확인하는 진단용 위젯입니다. 버튼을 눌러 입력 횟수가 늘어나는지 보세요.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct LauncherBundle: WidgetBundle {
    var body: some Widget {
        LauncherWidget()
        DiagWidget()
    }
}
