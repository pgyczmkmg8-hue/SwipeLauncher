import Foundation

/// GitHub와 GitLab 릴리즈를 모두 조회해 가장 새 버전을 고른다. Foundation만 사용(테스트용 단독 컴파일 가능).
enum UpdateChecker {
    // MARK: 소스 설정 (한 곳에 모음)
    static let githubRepo = "pgyczmkmg8-hue/SwipeLauncher"
    static let gitlabProject = "Yami_Q_Ray/launcher"

    enum Source: String, CaseIterable {
        case github, gitlab

        var displayName: String { self == .github ? "GitHub" : "GitLab" }

        var apiURL: URL {
            switch self {
            case .github:
                return URL(string: "https://api.github.com/repos/\(UpdateChecker.githubRepo)/releases?per_page=20")!
            case .gitlab:
                let enc = UpdateChecker.gitlabProject.replacingOccurrences(of: "/", with: "%2F")
                return URL(string: "https://gitlab.com/api/v4/projects/\(enc)/releases?per_page=20")!
            }
        }

        func releasePage(for tag: String) -> URL {
            switch self {
            case .github: return URL(string: "https://github.com/\(UpdateChecker.githubRepo)/releases/tag/\(tag)")!
            case .gitlab: return URL(string: "https://gitlab.com/\(UpdateChecker.gitlabProject)/-/releases/\(tag)")!
            }
        }
    }

    struct Release: Equatable {
        let tag: String
        let pageURL: URL
        let ipaURL: URL?
        /// 받기 링크: 직접 IPA 링크가 있으면 그것, 없으면 릴리즈 페이지
        var downloadURL: URL { ipaURL ?? pageURL }
    }

    enum SourceResult: Equatable {
        case release(Release)
        case noRelease
        case failed(String)
    }

    struct Outcome {
        let results: [Source: SourceResult]
        /// 전체에서 가장 높은 버전
        let newest: Release?
        /// newest 태그를 가진 소스들 (해당 소스의 릴리즈)
        let carriers: [(source: Source, release: Release)]
        /// 한 곳이라도 응답했는가 (릴리즈가 없어도 응답으로 본다)
        let anyResponded: Bool

        /// 소스별 결과 한 줄 요약
        var summary: String {
            Source.allCases.map { s in
                switch results[s] {
                case .release(let r)?: return "\(s.displayName) \(r.tag)"
                case .noRelease?: return "\(s.displayName) 릴리즈 없음"
                case .failed(let why)?: return "\(s.displayName) 확인 실패 (\(why))"
                case nil: return "\(s.displayName) 확인 실패"
                }
            }.joined(separator: " · ")
        }
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static func isNewer(_ tag: String, than current: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 }
        }
        let a = parts(tag), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    // MARK: 파서
    /// `v?1.2.3` 형태(숫자와 점만)인지
    static func isVersionTag(_ tag: String) -> Bool {
        var s = Substring(tag)
        if s.first == "v" || s.first == "V" { s = s.dropFirst() }
        guard !s.isEmpty, s.first != ".", s.last != "." else { return false }
        return s.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") } && !s.contains("..")
    }

    private struct GHRelease: Decodable {
        struct Asset: Decodable { let name: String?; let browser_download_url: String? }
        let tag_name: String?
        let draft: Bool?
        let prerelease: Bool?
        let html_url: String?
        let assets: [Asset]?
    }

    static func parseGitHub(_ data: Data) throws -> [Release] {
        let items = try JSONDecoder().decode([GHRelease].self, from: data)
        return items.compactMap { r in
            guard let tag = r.tag_name, isVersionTag(tag), r.draft != true, r.prerelease != true else { return nil }
            let page = r.html_url.flatMap(URL.init(string:)) ?? Source.github.releasePage(for: tag)
            let ipa = (r.assets ?? [])
                .first { ($0.name ?? "").lowercased().hasSuffix(".ipa") }
                .flatMap { $0.browser_download_url }
                .flatMap(URL.init(string:))
            return Release(tag: tag, pageURL: page, ipaURL: ipa)
        }
    }

    private struct GLRelease: Decodable {
        struct Link: Decodable { let name: String?; let url: String?; let direct_asset_url: String? }
        struct Assets: Decodable { let links: [Link]? }
        let tag_name: String?
        let upcoming_release: Bool?
        let assets: Assets?
    }

    static func parseGitLab(_ data: Data) throws -> [Release] {
        let items = try JSONDecoder().decode([GLRelease].self, from: data)
        return items.compactMap { r in
            guard let tag = r.tag_name, isVersionTag(tag), r.upcoming_release != true else { return nil }
            let ipa = (r.assets?.links ?? [])
                .first { ($0.name ?? "").lowercased().hasSuffix(".ipa") }
                .flatMap { ($0.direct_asset_url?.isEmpty == false ? $0.direct_asset_url : $0.url) }
                .flatMap(URL.init(string:))
            return Release(tag: tag, pageURL: Source.gitlab.releasePage(for: tag), ipaURL: ipa)
        }
    }

    /// 목록에서 가장 높은 버전 (API 순서에 의존하지 않음)
    static func newest(_ releases: [Release]) -> Release? {
        releases.reduce(nil) { best, r in
            guard let b = best else { return r }
            return isNewer(r.tag, than: b.tag) ? r : b
        }
    }

    // MARK: 조회
    typealias Fetch = (URLRequest) async throws -> (Data, URLResponse)

    static let defaultFetch: Fetch = { try await URLSession.shared.data(for: $0) }

    static func request(for source: Source) -> URLRequest {
        var req = URLRequest(url: source.apiURL)
        req.timeoutInterval = 10
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.setValue("SwipeLauncher/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        if source == .github { req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept") }
        return req
    }

    private static func reason(_ error: Error) -> String {
        if let e = error as? URLError {
            switch e.code {
            case .timedOut: return "시간 초과"
            case .notConnectedToInternet, .networkConnectionLost: return "오프라인"
            default: return "네트워크 오류"
            }
        }
        if error is DecodingError { return "응답 형식 오류" }
        return "오류"
    }

    private static func query(_ source: Source, fetch: Fetch) async -> SourceResult {
        do {
            let (data, resp) = try await fetch(request(for: source))
            guard let http = resp as? HTTPURLResponse else { return .failed("응답 없음") }
            guard http.statusCode == 200 else { return .failed("HTTP \(http.statusCode)") }
            let list = try (source == .github ? parseGitHub(data) : parseGitLab(data))
            if let best = newest(list) { return .release(best) }
            return .noRelease
        } catch {
            return .failed(reason(error))
        }
    }

    /// 두 소스를 동시에 조회한다. 절대 throw 하지 않는다.
    static func check(fetch: @escaping Fetch = defaultFetch) async -> Outcome {
        async let gh = query(.github, fetch: fetch)
        async let gl = query(.gitlab, fetch: fetch)
        let results: [Source: SourceResult] = [.github: await gh, .gitlab: await gl]
        return makeOutcome(results)
    }

    static func makeOutcome(_ results: [Source: SourceResult]) -> Outcome {
        var found: [(Source, Release)] = []
        var responded = false
        for s in Source.allCases {
            switch results[s] {
            case .release(let r)?: found.append((s, r)); responded = true
            case .noRelease?: responded = true
            default: break
            }
        }
        let best = newest(found.map { $0.1 })
        let carriers = found
            .filter { best != nil && !isNewer(best!.tag, than: $0.1.tag) && !isNewer($0.1.tag, than: best!.tag) }
            .map { (source: $0.0, release: $0.1) }
        return Outcome(results: results, newest: best, carriers: carriers, anyResponded: responded)
    }
}
