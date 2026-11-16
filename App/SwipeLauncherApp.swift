import SwiftUI
import UIKit
import WidgetKit

@main
struct SwipeLauncherApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .task {
                    TapLog.trimIfNeeded()
                    WidgetCenter.shared.reloadAllTimelines()
                }
                .onOpenURL { url in
                    // 위젯 칸 탭(조합 완성): swipelauncher://open?u=<대상 주소> → 대상 앱 실행
                    guard url.scheme == "swipelauncher", url.host == "open",
                          let u = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                            .queryItems?.first(where: { $0.name == "u" })?.value,
                          let target = URL(string: u) else { return }
                    AppLock.shared.noteRelay()
                    RelayOpener.shared.open(target)
                    TapState.reset()    // 입력 상태 정리는 열기 요청 뒤에
                }
                .onChange(of: scenePhase) { _, phase in
                    // 앱이 막 켜지는 중이라 열기가 무시됐다면, 활성화된 뒤 다시 시도한다
                    if phase == .active { RelayOpener.shared.retryPending() }
                }
        }
    }
}

/// 위젯에서 넘어온 대상 주소를 연다. 앱이 켜지는 도중에는 열기가 무시될 수 있어서, 실패하면 짧게 재시도하고 결과를 남긴다.
final class RelayOpener {
    static let shared = RelayOpener()
    private var pending: URL?
    private static let logKey = "relay.log.v1"

    static var lastLog: String {
        UserDefaults.standard.string(forKey: logKey) ?? "기록 없음"
    }

    private func record(_ text: String) {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        UserDefaults.standard.set("\(f.string(from: Date())) \(text)", forKey: Self.logKey)
    }

    func open(_ url: URL) {
        pending = url
        attempt(url, n: 0)
    }

    func retryPending() {
        if let url = pending { attempt(url, n: 0) }
    }

    private func attempt(_ url: URL, n: Int) {
        UIApplication.shared.open(url, options: [:]) { [weak self] ok in
            DispatchQueue.main.async {
                guard let self else { return }
                if ok {
                    self.pending = nil
                    self.record("열림 · \(url.absoluteString) · 시도 \(n + 1)회")
                } else if n < 6 {
                    self.record("실패(재시도 \(n + 1)) · \(url.absoluteString)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.attempt(url, n: n + 1) }
                } else {
                    self.record("끝내 실패 · \(url.absoluteString) (스킴 확인)")
                }
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
    @EnvironmentObject private var lock: AppLock
    @State private var config = LauncherConfig.load()
    @State private var sharing = LauncherConfig.isSharingAvailable
    @State private var testResult = ""
    @State private var updateStatus = ""
    @State private var latestTag: String?
    @State private var checking = false
    @State private var haptic = LauncherConfig.hapticEnabled

    var body: some View {
        NavigationStack {
            Form {
                if !sharing {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("앱과 위젯 사이 저장소(App Group)를 쓸 수 없어서, 여기서 정한 설정이 위젯에 자동으로 전달되지 않습니다. 대신 아래 '위젯 편집용 문자열 복사'로 복사해서, 위젯을 길게 눌러 '위젯 편집'의 '조합' 칸에 붙여넣으세요.")
                                .font(.callout)
                                .foregroundStyle(.red)
                            Button("위젯 편집용 문자열 복사") {
                                UIPasteboard.general.string = config.combosText()
                                testResult = "복사했습니다: " + config.combosText()
                            }
                            Text(LauncherConfig.diagnostics())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                }

                Section {
                    Picker("칸 구성", selection: $config.grid) {
                        Text("2×2").tag(2)
                        Text("3×3").tag(3)
                        Text("3×4 키패드").tag(4)
                    }
                    .pickerStyle(.segmented)
                    numberGrid
                } header: {
                    Text("칸 번호")
                } footer: {
                    Text("위젯의 칸은 왼쪽 위부터 가로로 이어서 위 그림과 같은 순서입니다. 위젯은 투명해서 글자가 보이지 않으니 위 그림을 기준으로 누르세요. 키패드는 조합에 1~9, 0, *, # 를 쓸 수 있습니다.")
                }

                Section {
                    ForEach($config.combos) { $combo in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("순서").font(.footnote).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
                                TextField("예: 1123", text: $combo.seq)
                                    .keyboardType(.numbersAndPunctuation)
                                    .autocorrectionDisabled()
                                    .font(.title3.monospacedDigit())
                                    .onChange(of: combo.seq) { _, v in
                                        let f = String(v.filter { "1234567890*#".contains($0) })
                                        if f != v { combo.seq = f }
                                    }
                            }
                            HStack {
                                Text("앱").font(.footnote).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
                                TextField("URL 스킴 (예: music://)", text: $combo.url)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                Button("테스트") { open(combo.url) }
                                    .buttonStyle(.borderless)
                            }
                            if let w = warning(for: combo) {
                                Text(w).font(.caption).foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .onDelete { config.combos.remove(atOffsets: $0) }

                    Button {
                        config.combos.append(Combo(seq: "", url: ""))
                    } label: {
                        Label("조합 추가", systemImage: "plus.circle")
                    }
                    if !testResult.isEmpty { Text(testResult).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("조합 → 앱")
                } footer: {
                    Text("칸 번호를 이 순서대로 누르면 앱이 열립니다. 한 자리(예: 3)로 정하면 그 칸만 눌러도 열립니다. 다른 조합의 앞부분과 같으면 짧은 조합이 먼저 실행됩니다. 목록을 왼쪽으로 밀면 삭제됩니다.")
                }

                Section {
                    Toggle("인텐트로 바로 열기 (실험)", isOn: $config.openDirect)
                } footer: {
                    Text("끄면(기본) 조합이 완성될 때 우리 앱이 잠깐 열렸다가 대상 앱으로 넘어갑니다. 이 방식이 폰에서 확인된 방식입니다. 켜면 앱을 거치지 않지만 환경에 따라 동작하지 않을 수 있습니다.")
                }

                Section {
                    Stepper(value: $config.timeout, in: 1...15, step: 1) {
                        Text("입력 제한시간  \(Int(config.timeout))초")
                    }
                } footer: {
                    Text("마지막으로 누른 뒤 이 시간이 지나면 입력이 처음부터 다시 시작됩니다. 중간에 조합과 맞지 않는 칸을 눌러도 그 칸부터 다시 시작합니다.")
                }

                Section {
                    Toggle("탭할 때 진동", isOn: $haptic)
                        .onChange(of: haptic) { _, on in LauncherConfig.hapticEnabled = on }
                } header: {
                    Text("반응")
                } footer: {
                    Text("칸을 누르는 순간 진동으로 먼저 알려 줍니다. 화면 표시는 시스템이 위젯을 다시 그린 뒤에 나타나서 조금 늦을 수 있습니다. 기기의 '시스템 햅틱' 설정이 꺼져 있으면 진동하지 않습니다.")
                }

                Section {
                    Toggle("지문·얼굴 잠금", isOn: Binding(get: { lock.lockEnabled }, set: { lock.setLockEnabled($0) }))
                    Toggle("블러 처리", isOn: $lock.blurEnabled)
                } header: {
                    Text("보안")
                } footer: {
                    Text("잠금: 앱을 열 때마다 인증합니다. (생체 인증이 안 되면 기기 암호) 블러: 앱 전환 화면 등에서 앱 내용을 흐리게 가립니다. 앱 화면만 보호하며, 위젯 칸 입력과 앱 열기는 잠금과 무관하게 바로 동작합니다.")
                }

                Section("사용법") {
                    Text("1. 앱을 설치한 뒤 아이폰을 한 번 재시작합니다. (투명 설정을 시스템이 처음 읽도록)\n2. 홈 화면을 길게 눌러 위젯 추가 → '투명 런처'\n3. 이 화면에서 칸 개수와 '조합 → 앱'을 정합니다.\n4. 투명한 칸을 정해 둔 순서대로 누르면 해당 앱이 열립니다.")
                        .font(.callout)
                }

                Section {
                    let st = TapState.load()
                    LabeledContent("App Group 연결", value: sharing ? "연결됨" : "안 됨")
                    LabeledContent("위젯 입력 횟수", value: sharing ? "\(st.count)회" : "확인 불가")
                    if sharing, let c = st.lastCell {
                        LabeledContent("마지막 입력", value: "\(ComboLogic.symbol(c))번 칸, \(Int(Date().timeIntervalSince(st.at)))초 전")
                    }
                    LabeledContent("마지막 열기", value: RelayOpener.lastLog)
                    Button("새로고침") { sharing = LauncherConfig.isSharingAvailable; config = LauncherConfig.load() }
                } header: {
                    Text("진단")
                } footer: {
                    Text("위젯 칸을 누른 뒤 '새로고침'을 누르세요. 입력 횟수가 늘면 위젯의 칸 입력은 정상입니다. 늘지 않으면 칸 입력이 위젯에서 실행되지 않는 것입니다.")
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

    private var numberGrid: some View {
        let rows = config.rows, cols = config.cols
        return VStack(spacing: 6) {
            ForEach(0..<rows, id: \.self) { r in
                HStack(spacing: 6) {
                    ForEach(0..<cols, id: \.self) { c in
                        Text(ComboLogic.symbol(r * cols + c + 1))
                            .font(.title2.weight(.semibold).monospacedDigit())
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .frame(maxWidth: 220)
        .frame(maxWidth: .infinity)
    }

    private func warning(for combo: Combo) -> String? {
        let d = ComboLogic.digits(combo.seq)
        if d.isEmpty { return combo.seq.isEmpty ? nil : "1~9, 0, *, # 만 쓸 수 있습니다." }
        if d.contains(where: { $0 > config.cellCount }) { return "현재 칸 구성에 없는 칸이 있습니다." }
        let others = config.combos.filter { $0.id != combo.id }.map { ComboLogic.digits($0.seq) }
        if others.contains(d) { return "같은 순서의 조합이 이미 있습니다." }
        if others.contains(where: { $0.count < d.count && Array(d.prefix($0.count)) == $0 }) {
            return "더 짧은 조합과 앞부분이 같아서 이 조합은 실행되지 않습니다."
        }
        return nil
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
