import Foundation

enum ComboLogic {
    /// 칸에 쓰는 글자. 순서대로 칸 번호 1~12 (키패드: 1~9, *, 0, #)
    static let symbols: [Character] = ["1","2","3","4","5","6","7","8","9","*","0","#"]

    static func symbol(_ cell: Int) -> String {
        (1...symbols.count).contains(cell) ? String(symbols[cell - 1]) : "?"
    }

    /// "11*0" → [1,1,10,11]. 칸에 없는 글자는 무시한다.
    static func digits(_ s: String) -> [Int] {
        s.compactMap { ch in symbols.firstIndex(of: ch).map { $0 + 1 } }
    }

    /// 지금까지 누른 seq 에 tap 을 더했을 때의 결과.
    /// - new: 저장할 새 상태(조합이 완성되면 빈 배열)
    /// - url: 조합이 완성되면 열 주소
    /// 완성된 조합이 있으면 그 즉시 실행한다. (더 긴 조합의 앞부분과 겹치면 짧은 쪽이 먼저 실행됨)
    static func resolve(seq: [Int], tap: Int, combos: [Combo]) -> (new: [Int], url: String?) {
        func match(_ c: [Int]) -> String? {
            combos.first { digits($0.seq) == c && !$0.url.trimmingCharacters(in: .whitespaces).isEmpty }?.url
        }
        func hasLonger(_ c: [Int]) -> Bool {
            combos.contains { let q = digits($0.seq); return q.count > c.count && Array(q.prefix(c.count)) == c }
        }
        let cand = seq + [tap]
        if let u = match(cand) { return ([], u) }
        if hasLonger(cand) { return (cand, nil) }
        // 이어지지 않으면 이번 탭부터 다시 시작
        let one = [tap]
        if let u = match(one) { return ([], u) }
        if hasLonger(one) { return (one, nil) }
        return ([], nil)
    }
}
