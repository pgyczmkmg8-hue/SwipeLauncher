import AppIntents
import Foundation
import WidgetKit

/// 조합이 완성되는 칸에서 쓰는 버튼: 상태를 비우고 지정한 주소를 바로 연다. (우리 앱을 거치지 않음)
/// 시스템이 인텐트 메타데이터를 앱 본체에서도 찾기 때문에 앱과 위젯 양쪽에 같이 들어간다.
struct OpenLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "앱 열기"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "주소") var url: String

    init() { self.url = "" }
    init(url: String) { self.url = url }

    func perform() async throws -> some IntentResult & OpensIntent {
        TapState(seq: [], at: .now).save()
        WidgetCenter.shared.reloadAllTimelines()
        let target = URL(string: url) ?? URL(string: "about:blank")!
        return .result(opensIntent: OpenURLIntent(target))
    }
}

/// 조합이 아직 끝나지 않은 칸에서 쓰는 버튼: 누른 번호만 기록한다.
struct TapIntent: AppIntent {
    static var title: LocalizedStringResource = "칸 입력"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "칸 번호") var cell: Int

    init() { self.cell = 0 }
    init(cell: Int) { self.cell = cell }

    func perform() async throws -> some IntentResult {
        let cfg = LauncherConfig.load()
        let state = TapState.current(timeout: cfg.timeout)
        let r = ComboLogic.resolve(seq: state.seq, tap: cell, combos: cfg.combos)
        TapState(seq: r.new, at: .now).save()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
