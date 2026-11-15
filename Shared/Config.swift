import Foundation
import WidgetKit

/// 앱과 위젯이 공유하는 칸 설정. App Group 으로 주고받는다.
struct LauncherConfig: Codable, Equatable {
    var grid: Int = 2                       // 2 또는 3
    var urls: [String] = ["maps://", "music://", "sms://", "message://", "", "", "", "", ""]

    static let groupID = "group.com.MACHU.Launcher"
    private static let key = "config.v1"

    /// 재서명 도구가 앱 그룹 이름을 바꿔도 찾을 수 있도록 후보를 모두 시도한다.
    private static func defaultsStore() -> UserDefaults? {
        var ids: [String] = []
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { ids += alt }
        ids.append(groupID)
        for id in ids {
            if FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil,
               let d = UserDefaults(suiteName: id) { return d }
        }
        return nil
    }

    static var isSharingAvailable: Bool { defaultsStore() != nil }

    static func load() -> LauncherConfig {
        guard let d = defaultsStore(), let data = d.data(forKey: key),
              var c = try? JSONDecoder().decode(LauncherConfig.self, from: data) else { return LauncherConfig() }
        c.grid = (c.grid == 3) ? 3 : 2
        while c.urls.count < 9 { c.urls.append("") }
        return c
    }

    @discardableResult
    func save() -> Bool {
        guard let d = Self.defaultsStore(), let data = try? JSONEncoder().encode(self) else { return false }
        d.set(data, forKey: Self.key)
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }
}
