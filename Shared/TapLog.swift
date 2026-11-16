import Darwin
import Foundation

/// 칸 입력 기록. 위젯의 칸 버튼이 눌리면 이 파일 끝에 16바이트를 덧붙이는 것이 입력 처리의 전부다.
/// (읽기 → 판정 → 저장을 하지 않으므로 잠금도 필요 없고, 빠르게 겹쳐 눌러도 서로 덮어쓰지 않는다)
/// 조합 판정은 위젯이 다시 그려질 때 기록을 처음부터 되감아 계산한다.
enum TapLog {
    /// 기록 한 줄: 누른 시각, 칸 번호
    struct Rec {
        var at: Double      // timeIntervalSinceReferenceDate
        var cell: Int32
        var pad: Int32 = 0
    }
    static let recSize = MemoryLayout<Rec>.size   // 16

    /// 되감을 때 보는 최근 기록 수 (조합 길이보다 훨씬 크면 된다)
    static let window = 32

    /// 검증용: 지정하면 공유 폴더 대신 이 폴더를 쓴다.
    static var directoryOverride: URL?
    private static func dir() -> URL? { directoryOverride ?? LauncherConfig.sharedContainerURL() }
    private static func logURL() -> URL? { dir()?.appendingPathComponent("taplog.bin") }
    private static func resetURL() -> URL? { dir()?.appendingPathComponent("tapreset.bin") }

    /// 입력 하나를 기록한다. 공유 폴더를 못 쓰면 false.
    @discardableResult
    static func append(cell: Int, at: Date = .now) -> Bool {
        guard let url = logURL() else { return false }
        var rec = Rec(at: at.timeIntervalSinceReferenceDate, cell: Int32(cell))
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return withUnsafeBytes(of: &rec) { write(fd, $0.baseAddress, recSize) } == recSize
    }

    /// 지금까지의 입력을 비운다. (이 시각 이전의 기록은 없는 것으로 본다)
    static func markReset(at: Date = .now) {
        guard let url = resetURL() else { return }
        var t = at.timeIntervalSinceReferenceDate
        let data = Data(bytes: &t, count: MemoryLayout<Double>.size)
        try? data.write(to: url, options: [.atomic])
    }

    private static func readReset() -> Double {
        guard let url = resetURL(), let d = try? Data(contentsOf: url), d.count == MemoryLayout<Double>.size else {
            return -.infinity
        }
        return d.withUnsafeBytes { $0.loadUnaligned(as: Double.self) }
    }

    /// 기록의 마지막 n줄과 전체 줄 수
    private static func tail(_ n: Int) -> (recs: [Rec], total: Int) {
        guard let url = logURL() else { return ([], 0) }
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return ([], 0) }
        defer { close(fd) }
        var st = stat()
        guard fstat(fd, &st) == 0 else { return ([], 0) }
        let total = Int(st.st_size) / recSize
        let k = min(n, total)
        guard k > 0 else { return ([], total) }
        var recs = [Rec](repeating: Rec(at: 0, cell: 0), count: k)
        let want = k * recSize
        let got = recs.withUnsafeMutableBytes { pread(fd, $0.baseAddress, want, off_t((total - k) * recSize)) }
        guard got == want else { return ([], total) }
        return (recs, total)
    }

    /// 기록이 너무 커졌으면 최근 것만 남긴다. (앱이 켜질 때만 호출)
    static func trimIfNeeded(limitBytes: Int = 1_000_000) {
        guard let url = logURL(),
              let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int,
              size > limitBytes else { return }
        let (recs, _) = tail(window)
        let data = recs.withUnsafeBytes { Data($0) }
        try? data.write(to: url, options: [.atomic])
    }

    /// 기록을 되감아 지금의 입력 상태를 만든다.
    static func state(config: LauncherConfig, now: Date = .now) -> TapState {
        let (recs, total) = tail(window)
        return replay(recs, total: total, resetAt: readReset(), config: config, now: now)
    }

    /// 순수 계산부 (기기 밖에서도 검증할 수 있게 분리)
    static func replay(_ recs: [Rec], total: Int, resetAt: Double, config: LauncherConfig, now: Date) -> TapState {
        var s = TapState()
        s.count = total
        var seq: [Int] = []
        var lastAt = -Double.infinity
        var ready: String? = nil
        var last: Int? = nil
        for r in recs where r.at > resetAt && r.cell > 0 {
            // 마지막 입력 뒤 제한시간이 지났으면 처음부터
            if r.at - lastAt > config.timeout { seq = [] }
            let res = ComboLogic.resolve(seq: seq, tap: Int(r.cell), combos: config.combos)
            seq = res.new
            ready = res.url
            last = Int(r.cell)
            lastAt = r.at
        }
        guard let last else { return s }
        s.lastCell = last
        s.at = Date(timeIntervalSinceReferenceDate: lastAt)
        // 지금 시각 기준으로도 제한시간이 지났으면 입력 중이던 상태는 비운다
        if now.timeIntervalSinceReferenceDate - lastAt <= config.timeout {
            s.seq = seq
            s.readyURL = ready
        }
        return s
    }
}
