import AppIntents
import Foundation

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
        TapState.reset()
        let target = URL(string: url) ?? URL(string: "about:blank")!
        return .result(opensIntent: OpenURLIntent(target))
    }
}

/// 조합이 아직 끝나지 않은 칸에서 쓰는 버튼: 누른 번호만 기록한다.
/// 화면이 늦게 갱신돼 마지막 칸이 아직 일반 입력 버튼일 때 조합이 완성되면, 입력을 버리지 않고
/// '완성 대기'로 기록한다. 위젯이 다시 그려지면 그 칸이 앱 열기 버튼이 되어 한 번 더 누르면 열린다.
struct TapIntent: AppIntent {
    static var title: LocalizedStringResource = "칸 입력"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "칸 번호") var cell: Int
    /// App Group 을 못 쓰는 설치본에서 위젯이 직접 넘겨주는 조합(문자열)과 제한시간
    @Parameter(title: "조합") var combosText: String
    @Parameter(title: "제한시간") var timeout: Int

    init() { self.cell = 0; self.combosText = ""; self.timeout = 4 }
    init(cell: Int, combosText: String = "", timeout: Int = 4) {
        self.cell = cell; self.combosText = combosText; self.timeout = timeout
    }

    func perform() async throws -> some IntentResult {
        // 평소에는 누른 칸 번호를 기록 파일 끝에 덧붙이기만 한다. (판정은 위젯이 다시 그려질 때 한다)
        if TapLog.append(cell: cell) { return .result() }

        // 공유 폴더를 못 쓰는 설치본: 예전 방식(위젯이 넘겨준 조합으로 직접 판정)
        var cfg = LauncherConfig()
        cfg.combos = LauncherConfig.parseCombos(combosText)
        cfg.timeout = Double(min(max(timeout, 1), 15))
        let tapped = cell
        TapState.exclusive {
            let state = TapState.legacyCurrent(timeout: cfg.timeout)
            let r = ComboLogic.resolve(seq: state.seq, tap: tapped, combos: cfg.combos)
            let prev = TapState.legacyLoad()
            TapState(seq: r.new, at: .now, lastCell: tapped, count: prev.count + 1, readyURL: r.url).save()
        }
        return .result()
    }
}
