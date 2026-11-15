import SwiftUI
import UIKit
import WidgetKit

@main
struct SwipeLauncherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { WidgetCenter.shared.reloadAllTimelines() }
                .onOpenURL { url in
                    // 위젯 칸 탭: swipelauncher://open?u=<대상 주소> → 대상 앱 실행
                    guard url.scheme == "swipelauncher", url.host == "open",
                          let u = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "u" })?.value,
                          let target = URL(string: u) else { return }
                    UIApplication.shared.open(target)
                }
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
    @State private var config = LauncherConfig.load()
    @State private var sharing = LauncherConfig.isSharingAvailable
    @State private var testResult = ""
    @State private var updateStatus = ""
    @State private var latestTag: String?
    @State private var checking = false

    var body: some View {
        NavigationStack {
            Form {
                if !sharing {
                    Section {
                        Text("이 설치본은 앱과 위젯 사이 저장소(App Group)를 쓸 수 없어서, 여기서 정한 설정이 위젯에 전달되지 않습니다. 재서명 도구에서 App Group 권한을 유지하도록 설치해 보세요.")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Picker("칸 구성", selection: $config.grid) {
                        Text("2 × 2").tag(2)
                        Text("3 × 3").tag(3)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("칸 개수")
                } footer: {
                    Text("위젯을 길게 눌러 편집할 필요 없이 여기서 정하면 위젯에 바로 반영됩니다.")
                }

                Section {
                    ForEach(0..<(config.grid * config.grid), id: \.self) { i in
                        HStack {
                            Text("\(i + 1)")
                                .font(.headline)
                                .frame(width: 24)
                            TextField("URL 스킴 (예: maps://)", text: urlBinding(i))
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                            Button("테스트") { open(config.urls[i]) }
                                .buttonStyle(.borderless)
                        }
                    }
                    if !testResult.isEmpty { Text(testResult).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("칸별 앱 (왼쪽 위가 1번, 가로로 이어서)")
                } footer: {
                    Text("비워 두면 그 칸은 눌러도 아무 일도 없습니다.")
                }

                Section("사용법") {
                    Text("1. 앱을 설치한 뒤 아이폰을 한 번 재시작합니다. (투명 설정을 시스템이 처음 읽도록)\n2. 홈 화면을 길게 눌러 위젯 추가 → '투명 런처'\n3. 이 화면에서 칸 개수와 칸별 앱을 정합니다.\n4. 투명한 칸을 터치하면 해당 앱이 열립니다.")
                        .font(.callout)
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
            .onChange(of: config) { _, new in
                sharing = LauncherConfig.isSharingAvailable
                new.save()
            }
        }
    }

    private func urlBinding(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < config.urls.count ? config.urls[i] : "" },
            set: { v in
                while config.urls.count < 9 { config.urls.append("") }
                config.urls[i] = v
            }
        )
    }

    private func open(_ raw: String) {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespaces)), !raw.isEmpty else {
            testResult = "비어 있거나 올바르지 않은 URL"
            return
        }
        UIApplication.shared.open(url) { ok in
            testResult = ok ? "열림" : "열 수 없음 (스킴 확인)"
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
