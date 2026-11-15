import AppIntents
import Foundation

/// 위젯 칸을 탭하면 지정한 주소(URL 스킴)를 바로 연다. 우리 앱을 거치지 않는다.
/// 시스템이 인텐트 메타데이터를 앱 본체에서도 찾기 때문에 앱과 위젯 양쪽에 같이 들어간다.
struct OpenLinkIntent: AppIntent {
    static var title: LocalizedStringResource = "앱 열기"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "주소") var url: String

    init() { self.url = "" }
    init(url: String) { self.url = url }

    func perform() async throws -> some IntentResult & OpensIntent {
        let target = URL(string: url) ?? URL(string: "about:blank")!
        return .result(opensIntent: OpenURLIntent(target))
    }
}
