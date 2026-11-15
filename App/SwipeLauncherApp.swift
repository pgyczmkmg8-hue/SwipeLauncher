import SwiftUI
import UIKit
import WidgetKit

@main
struct SwipeLauncherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { WidgetCenter.shared.reloadAllTimelines() }
        }
    }
}

enum UpdateChecker {
    static let apiURL = URL(string: "https://gitlab.com/api/v4/projects/Yami_Q_Ray%2Flauncher/releases?per_page=1")!
    static let releasesPage = "https://gitlab.com/Yami_Q_Ray/launcher/-/releases"

    struct Release: Decodable {
        let tag_name: String
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 최신 릴리즈 태그 (예: "v1.2.0")
    static func latestTag() async throws -> String {
        let (data, _) = try await URLSession.shared.data(from: apiURL)
        let releases = try JSONDecoder().decode([Release].self, from: data)
        guard let tag = releases.first?.tag_name else { throw URLError(.cannotParseResponse) }
        return tag
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
}

struct ContentView: View {
    @State private var test = ""
    @State private var result = ""
    @State private var updateStatus = ""
    @State private var latestTag: String?
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                Section("사용법") {
                    Text("1. 앱을 설치한 뒤 아이폰을 한 번 재시작합니다. (투명 설정을 시스템이 처음 읽도록)\n2. 홈 화면을 길게 눌러 위젯 추가 → '투명 런처'\n3. 위젯을 길게 눌러 '위젯 편집'에서 칸 개수(2×2 / 3×3)와 칸별 URL 스킴 입력\n4. 투명한 칸을 터치하면 앱이 열립니다")
                        .font(.callout)
                }
                Section {
                    TextField("URL 스킴 (예: maps://)", text: $test)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    Button("열어서 테스트") {
                        guard let url = URL(string: test.trimmingCharacters(in: .whitespaces)) else {
                            result = "올바르지 않은 URL"
                            return
                        }
                        UIApplication.shared.open(url) { ok in
                            result = ok ? "열림" : "열 수 없음 (스킴 확인)"
                        }
                    }
                    if !result.isEmpty { Text(result).foregroundStyle(.secondary) }
                } header: {
                    Text("스킴 테스트")
                }
                Section {
                    LabeledContent("현재 버전", value: UpdateChecker.currentVersion)
                    Button(checking ? "확인 중…" : "업데이트 확인") { Task { await check() } }
                        .disabled(checking)
                    if !updateStatus.isEmpty { Text(updateStatus).foregroundStyle(.secondary) }
                    if let tag = latestTag, UpdateChecker.isNewer(tag, than: UpdateChecker.currentVersion),
                       let url = URL(string: "\(UpdateChecker.releasesPage)/\(tag)") {
                        Link("\(tag) 다운로드 페이지 열기", destination: url)
                    }
                } header: {
                    Text("업데이트")
                }
            }
            .navigationTitle("투명 런처")
            .task { await check() }
        }
    }

    private func check() async {
        checking = true
        defer { checking = false }
        do {
            let tag = try await UpdateChecker.latestTag()
            latestTag = tag
            updateStatus = UpdateChecker.isNewer(tag, than: UpdateChecker.currentVersion)
                ? "새 버전 \(tag) 이(가) 있습니다"
                : "최신 버전입니다"
        } catch {
            updateStatus = "확인 실패 (네트워크를 확인하세요)"
        }
    }
}
