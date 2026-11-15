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

    /// 재서명 도구가 앱 그룹 이름을 바꿔도 찾을 수 있도록 후보를 모두 시도한다.
    static func sharedDefaults() -> UserDefaults? {
        var ids: [String] = []
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { ids += alt }
        ids.append(groupID)
        for id in ids {
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil,
               let d = UserDefaults(suiteName: id) { return d }
        }
        return nil
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
