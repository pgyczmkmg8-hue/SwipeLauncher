import Darwin
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
    var openDirect: Bool = false // true: 인텐트로 바로 열기(실험), false: 앱을 거쳐 열기(폰에서 확인된 방식)
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

    private static let lock = NSLock()
    private static var cachedDefaults: UserDefaults?
    private static var cachedContainer: URL?
    private static var cachedID: String?
    private static let savedKey = "resolvedGroup.v1"

    /// 앱 그룹 공유 폴더. 입력 기록과 설정처럼 즉시 서로 보여야 하는 값은 UserDefaults 가 아니라 이 폴더의 파일에 둔다.
    /// 한 번 찾은 그룹은 프로세스 안에서 기억하고, 다음 실행에서도 바로 쓰도록 이름을 저장해 둔다.
    /// (서명 권한 탐색과 컨테이너 확인은 비싸서 탭마다 반복하면 위젯 입력이 느려진다)
    static func sharedContainerURL() -> URL? {
        lock.lock(); defer { lock.unlock() }
        if let u = cachedContainer { return u }

        func probe(_ id: String) -> Bool {
            guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) else { return false }
            cachedContainer = url
            cachedID = id
            return true
        }
        // 1) 지난번에 성공한 이름
        if let saved = UserDefaults.standard.string(forKey: savedKey), probe(saved) { return cachedContainer }
        // 2) 후보 전체 탐색 (처음 한 번만)
        for id in candidateGroups() where probe(id) {
            UserDefaults.standard.set(id, forKey: savedKey)
            return cachedContainer
        }
        return nil
    }

    /// 예전 버전이 저장한 설정을 읽어 오는 용도로만 쓴다.
    static func sharedDefaults() -> UserDefaults? {
        guard sharedContainerURL() != nil else { return nil }
        lock.lock(); defer { lock.unlock() }
        if let d = cachedDefaults { return d }
        guard let id = cachedID, let d = UserDefaults(suiteName: id) else { return nil }
        cachedDefaults = d
        return d
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

    static var isSharingAvailable: Bool { sharedContainerURL() != nil }

    private static func configFileURL() -> URL? {
        sharedContainerURL()?.appendingPathComponent("config.json")
    }

    /// 설정은 공유 폴더의 작은 파일에서 읽는다. (UserDefaults 는 새 프로세스에서 처음 읽을 때 시스템 호출이 오가서 느리다)
    /// 파일이 없으면 예전 버전이 UserDefaults 에 저장한 값을 읽는다.
    static func load() -> LauncherConfig {
        var data: Data?
        if let url = configFileURL() { data = try? Data(contentsOf: url) }
        if data == nil { data = sharedDefaults()?.data(forKey: key) }
        guard let data, var c = try? JSONDecoder().decode(LauncherConfig.self, from: data) else { return LauncherConfig() }
        c.grid = [2, 3, 4].contains(c.grid) ? c.grid : 2
        c.timeout = min(max(c.timeout, 1), 15)
        return c
    }

    @discardableResult
    func save() -> Bool {
        guard let data = try? JSONEncoder().encode(self), Self.isSharingAvailable else { return false }
        if let url = Self.configFileURL() { try? data.write(to: url, options: [.atomic]) }
        Self.sharedDefaults()?.set(data, forKey: Self.key)   // 예전 버전과의 호환
        WidgetCenter.shared.reloadAllTimelines()
        return true
    }
}

/// 지금까지 누른 칸 번호(1부터)와 마지막으로 누른 시각.
/// 앱 그룹 공유 폴더의 파일에 저장해서, 입력 처리와 위젯 다시 그리기가 서로 즉시 보이게 한다.
/// (UserDefaults 는 다른 프로세스에 전달되기까지 지연될 수 있어 한 박자 늦은 화면이 생긴다)
struct TapState: Codable {
    var seq: [Int] = []
    var at: Date = .distantPast
    var lastCell: Int? = nil      // 마지막으로 누른 칸(누름 표시용)
    var count: Int = 0            // 인텐트가 실행된 총 횟수(진단용)
    var readyURL: String? = nil   // 화면이 늦어 놓친 마지막 입력으로 이미 완성된 조합의 주소 (그 칸을 한 번 더 누르면 연다)

    private static let fileName = "tapstate.json"
    private static let fallbackKey = "tapstate.v1"

    private static func fileURL() -> URL? {
        LauncherConfig.sharedContainerURL()?.appendingPathComponent(fileName)
    }

    /// 입력 처리를 한 번에 하나씩만 하도록 파일 잠금을 건다.
    /// 빠르게 연속으로 누르면 입력 처리가 겹쳐서, 서로의 결과를 못 보고 덮어쓰기 때문이다.
    static func exclusive<T>(_ body: () -> T) -> T {
        guard let dir = LauncherConfig.sharedContainerURL() else { return body() }
        let fd = open(dir.appendingPathComponent("tapstate.lock").path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return body() }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN); close(fd) }
        return body()
    }

    // MARK: 입력 상태 (공유 폴더를 쓸 수 있으면 입력 기록(TapLog)을 되감아 계산하고, 못 쓰면 예전 방식)

    /// 지금의 입력 상태. 설정(조합, 제한시간)은 한 번 읽은 것을 넘겨 받아 중복 읽기를 피한다.
    static func current(config: LauncherConfig, now: Date = .now) -> TapState {
        if LauncherConfig.sharedContainerURL() != nil { return TapLog.state(config: config, now: now) }
        return legacyCurrent(timeout: config.timeout, now: now)
    }

    static func load() -> TapState {
        current(config: LauncherConfig.load())
    }

    /// 입력을 비운다. (조합이 완성되어 앱을 열 때)
    static func reset() {
        if LauncherConfig.sharedContainerURL() != nil { TapLog.markReset() } else { TapState().save() }
    }

    // MARK: 예전 방식 (App Group 을 못 쓰는 설치본)

    static func legacyLoad() -> TapState {
        if let url = fileURL() {
            guard let data = try? Data(contentsOf: url),
                  let s = try? JSONDecoder().decode(TapState.self, from: data) else { return TapState() }
            return s
        }
        guard let data = UserDefaults.standard.data(forKey: fallbackKey),
              let s = try? JSONDecoder().decode(TapState.self, from: data) else { return TapState() }
        return s
    }

    /// 제한시간이 지났으면 빈 상태로 본다.
    static func legacyCurrent(timeout: Double, now: Date = .now) -> TapState {
        let s = legacyLoad()
        return now.timeIntervalSince(s.at) <= timeout ? s : TapState()
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        if let url = Self.fileURL() {
            try? data.write(to: url, options: [.atomic])
        } else {
            UserDefaults.standard.set(data, forKey: Self.fallbackKey)
        }
    }
}
