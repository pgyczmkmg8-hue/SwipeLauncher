import Foundation
import WidgetKit

enum Direction: String, CaseIterable, Codable, Identifiable {
    case up, down, left, right
    var id: String { rawValue }
    var title: String {
        switch self {
        case .up: "위로"
        case .down: "아래로"
        case .left: "왼쪽으로"
        case .right: "오른쪽으로"
        }
    }
    var symbol: String {
        switch self {
        case .up: "arrow.up"
        case .down: "arrow.down"
        case .left: "arrow.left"
        case .right: "arrow.right"
        }
    }
}

struct AppSlot: Codable, Equatable {
    var name: String
    var url: String
}

enum Config {
    static let groupID = "group.com.MACHU.Launcher"
    static let padURL = URL(string: "swipelauncher://pad")!
    private static let key = "slots.v1"

    static let defaults: [Direction: AppSlot] = [
        .up: AppSlot(name: "지도", url: "maps://"),
        .down: AppSlot(name: "음악", url: "music://"),
        .left: AppSlot(name: "메시지", url: "sms://"),
        .right: AppSlot(name: "메일", url: "message://"),
    ]

    private static var store: UserDefaults {
        UserDefaults(suiteName: groupID) ?? .standard
    }

    static func load() -> [Direction: AppSlot] {
        guard let data = store.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: AppSlot].self, from: data)
        else { return defaults }
        var result = defaults
        for (k, v) in decoded {
            if let d = Direction(rawValue: k) { result[d] = v }
        }
        return result
    }

    static func save(_ slots: [Direction: AppSlot]) {
        let raw = Dictionary(uniqueKeysWithValues: slots.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) { store.set(data, forKey: key) }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
