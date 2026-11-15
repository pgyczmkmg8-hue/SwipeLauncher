import Foundation
import WidgetKit

/// 조합 하나: 칸 번호를 이 순서로 누르면 url 을 연다. (예: seq "1123" → music://)
struct Combo: Codable, Equatable, Identifiable {
    var id = UUID()
    var seq: String
    var url: String
}

/// 앱과 위젯이 공유하는 설정. App Group 으로 주고받는다.
struct LauncherConfig: Codable, Equatable {
    var grid: Int = 2            // 2 또는 3
    var timeout: Double = 4      // 입력 제한시간(초): 마지막 탭 뒤 이 시간이 지나면 처음부터
    var combos: [Combo] = [
        Combo(seq: "11", url: "maps://"),
        Combo(seq: "12", url: "music://"),
        Combo(seq: "21", url: "sms://"),
        Combo(seq: "22", url: "message://"),
    ]

    static let groupID = "group.com.MACHU.Launcher"
    private static let key = "config.v2"

    /// 서명 프로필(embedded.mobileprovision)에 적힌 App Group 목록. 프로필이 없으면 nil.
    static func profileGroups() -> [String]? {
        guard let path = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision"),
              let data = FileManager.default.contents(atPath: path),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)),
              start.lowerBound < end.upperBound,
              let plist = try? PropertyListSerialization.propertyList(
                from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil) as? [String: Any],
              let ent = plist["Entitlements"] as? [String: Any]
        else { return nil }
        return (ent["com.apple.security.application-groups"] as? [String]) ?? []
    }

    /// 재서명 도구가 그룹 이름을 바꿔도 찾을 수 있도록, 앱이 서명된 프로필의 그룹과 기본 이름을 모두 시도한다.
    /// 앱과 위젯이 같은 후보 순서를 쓰도록 정렬해 둔다.
    private static func candidateGroups() -> [String] {
        var ids: [String] = []
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { ids += alt }
        if let groups = profileGroups() {
            let usable = groups.filter { !$0.contains("*") }
            // 우리 이름과 가까운 것을 먼저, 나머지는 이름순
            ids += usable.filter { $0.localizedCaseInsensitiveContains("MACHU") || $0.localizedCaseInsensitiveContains("Launcher") }.sorted()
            ids += usable.sorted()
        }
        ids.append(groupID)
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    static func sharedDefaults() -> UserDefaults? {
        for id in candidateGroups() {
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil,
               let d = UserDefaults(suiteName: id) { return d }
        }
        return nil
    }

    /// 경고창에 보여줄 진단 문구
    static func diagnostics() -> String {
        guard let groups = profileGroups() else {
            return "서명 프로필 정보를 읽지 못했습니다. (시뮬레이터이거나 프로필이 없는 설치본)"
        }
        if groups.isEmpty {
            return "서명 프로필에 App Group 권한이 없습니다. 이 프로필로는 앱과 위젯이 설정을 나눠 쓸 수 없습니다."
        }
        return "서명 프로필의 App Group: " + groups.joined(separator: ", ") + "\n연결에 실패했다면 이 이름으로 앱·위젯이 같은 그룹을 쓰도록 서명되지 않은 것입니다."
    }

    static var isSharingAvailable: Bool { sharedDefaults() != nil }

    static func load() -> LauncherConfig {
        guard let d = sharedDefaults(), let data = d.data(forKey: key),
              var c = try? JSONDecoder().decode(LauncherConfig.self, from: data) else { return LauncherConfig() }
        c.grid = (c.grid == 3) ? 3 : 2
        c.timeout = min(max(c.timeout, 1), 15)
        return c
    }

    @discardableResult
    func save() -> Bool {
        guard let d = Self.sharedDefaults(), let data = try? JSONEncoder().encode(self) else { return false }
        d.set(data, forKey: Self.key)
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }
}

/// 지금까지 누른 칸 번호(1부터)와 마지막으로 누른 시각.
struct TapState: Codable {
    var seq: [Int] = []
    var at: Date = .distantPast

    private static let key = "tapstate.v1"

    static func load() -> TapState {
        guard let d = LauncherConfig.sharedDefaults(), let data = d.data(forKey: key),
              let s = try? JSONDecoder().decode(TapState.self, from: data) else { return TapState() }
        return s
    }

    /// 제한시간이 지났으면 빈 상태로 본다.
    static func current(timeout: Double, now: Date = .now) -> TapState {
        let s = load()
        return now.timeIntervalSince(s.at) <= timeout ? s : TapState()
    }

    func save() {
        guard let d = LauncherConfig.sharedDefaults(), let data = try? JSONEncoder().encode(self) else { return }
        d.set(data, forKey: Self.key)
    }
}
