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
    var grid: Int = 2            // 2(2×2), 3(3×3), 4(3열×4줄 키패드)
    var timeout: Double = 4      // 입력 제한시간(초): 마지막 탭 뒤 이 시간이 지나면 처음부터
    var combos: [Combo] = [
        Combo(seq: "11", url: "maps://"),
        Combo(seq: "12", url: "music://"),
        Combo(seq: "21", url: "sms://"),
        Combo(seq: "22", url: "message://"),
    ]

    static let groupID = "group.com.MACHU.Launcher"

    var cols: Int { grid == 2 ? 2 : 3 }
    var rows: Int { grid == 2 ? 2 : (grid == 3 ? 3 : 4) }
    var cellCount: Int { rows * cols }

    /// "11 maps://; 12 music://" 형태의 문자열로 바꾼다. (위젯 편집 화면에 붙여넣는 용도)
    func combosText() -> String {
        combos.filter { !ComboLogic.digits($0.seq).isEmpty && !$0.url.isEmpty }
            .map { "\($0.seq) \($0.url)" }.joined(separator: "; ")
    }

    static func parseCombos(_ text: String) -> [Combo] {
        text.split(whereSeparator: { $0 == ";" || $0 == "\n" }).compactMap { item in
            let t = item.trimmingCharacters(in: .whitespaces)
            guard let sp = t.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
            let seq = String(t[..<sp])
            let url = t[sp...].trimmingCharacters(in: .whitespaces)
            return (ComboLogic.digits(seq).isEmpty || url.isEmpty) ? nil : Combo(seq: seq, url: url)
        }
    }
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
        let signed = signedGroups() ?? []
        ids += signed.filter { !$0.contains("*") }.sorted()
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

    /// 앱 실행파일의 코드 서명에 들어 있는 권한(entitlements) 중 App Group 목록.
    /// 재서명 도구가 실제로 넣어 준 값이라 가장 정확하다. 읽지 못하면 nil.
    static func signedGroups() -> [String]? {
        guard let path = Bundle.main.executablePath,
              let d = try? Data(contentsOf: URL(fileURLWithPath: path), options: .mappedIfSafe) else { return nil }
        let magic = Data([0xFA, 0xDE, 0x71, 0x71])      // 코드 서명의 entitlements(XML) 블롭
        var from = d.startIndex
        while let r = d.range(of: magic, in: from..<d.endIndex) {
            from = r.upperBound
            guard r.lowerBound + 8 <= d.endIndex else { break }
            let len = d[(r.lowerBound + 4)..<(r.lowerBound + 8)].reduce(0) { ($0 << 8) | Int($1) }
            let end = r.lowerBound + len
            guard len > 8, end <= d.endIndex else { continue }
            let body = d.subdata(in: (r.lowerBound + 8)..<end)
            guard let plist = try? PropertyListSerialization.propertyList(from: body, options: [], format: nil) as? [String: Any]
            else { continue }
            return (plist["com.apple.security.application-groups"] as? [String]) ?? []
        }
        return nil
    }

    /// 경고창에 보여줄 진단 문구
    static func diagnostics() -> String {
        var lines: [String] = []
        if let g = signedGroups() {
            lines.append(g.isEmpty ? "서명 권한: App Group 없음" : "서명 권한의 App Group: " + g.joined(separator: ", "))
        } else {
            lines.append("서명 권한: 읽지 못함")
        }
        if let g = profileGroups() {
            lines.append(g.isEmpty ? "프로필: App Group 없음" : "프로필의 App Group: " + g.joined(separator: ", "))
        } else {
            lines.append("프로필: 읽지 못함")
        }
        let tried = candidateGroups().map { id -> String in
            let ok = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) != nil
            return (ok ? "연결됨 " : "실패 ") + id
        }
        lines.append("시도한 이름:\n" + tried.joined(separator: "\n"))
        return lines.joined(separator: "\n")
    }

    static var isSharingAvailable: Bool { sharedDefaults() != nil }

    static func load() -> LauncherConfig {
        guard let d = sharedDefaults(), let data = d.data(forKey: key),
              var c = try? JSONDecoder().decode(LauncherConfig.self, from: data) else { return LauncherConfig() }
        c.grid = [2, 3, 4].contains(c.grid) ? c.grid : 2
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
        let d = LauncherConfig.sharedDefaults() ?? UserDefaults.standard
        guard let data = d.data(forKey: key),
              let s = try? JSONDecoder().decode(TapState.self, from: data) else { return TapState() }
        return s
    }

    /// 제한시간이 지났으면 빈 상태로 본다.
    static func current(timeout: Double, now: Date = .now) -> TapState {
        let s = load()
        return now.timeIntervalSince(s.at) <= timeout ? s : TapState()
    }

    func save() {
        let d = LauncherConfig.sharedDefaults() ?? UserDefaults.standard
        guard let data = try? JSONEncoder().encode(self) else { return }
        d.set(data, forKey: Self.key)
    }
}
