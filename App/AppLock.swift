import LocalAuthentication
import SwiftUI

/// 앱 화면 보호: 지문/얼굴 잠금과 블러 처리. 둘 다 기본으로 켜져 있다.
/// (앱 화면만 지킨다. 위젯 칸 입력과 대상 앱 열기는 잠금과 무관하게 바로 동작한다)
final class AppLock: ObservableObject {
    static let shared = AppLock()

    private static let lockKey = "security.lock.v1"
    private static let blurKey = "security.blur.v1"

    /// 생체 인증(없으면 기기 암호)으로 앱을 잠근다.
    @Published var lockEnabled: Bool {
        didSet { UserDefaults.standard.set(lockEnabled, forKey: Self.lockKey) }
    }
    /// 앱이 활성 상태가 아닐 때(앱 전환 화면 등) 화면을 흐리게 가린다.
    @Published var blurEnabled: Bool {
        didSet { UserDefaults.standard.set(blurEnabled, forKey: Self.blurKey) }
    }
    @Published private(set) var locked: Bool
    @Published private(set) var shielded = false
    @Published private(set) var message = ""

    private var authenticating = false
    private var phase: ScenePhase = .inactive
    private var lastRelay = Date.distantPast

    private init() {
        let d = UserDefaults.standard
        let lock = (d.object(forKey: Self.lockKey) as? Bool) ?? true
        lockEnabled = lock
        blurEnabled = (d.object(forKey: Self.blurKey) as? Bool) ?? true
        locked = lock       // 앱이 켜질 때는 잠긴 상태로 시작
    }

    /// 위젯에서 대상 앱을 열려고 우리 앱이 잠깐 켜진 경우: 그때는 인증창을 띄우지 않는다.
    func noteRelay() { lastRelay = Date() }

    func scenePhaseChanged(_ new: ScenePhase) {
        phase = new
        switch new {
        case .active:
            shielded = false
            if locked { autoAuthenticateSoon() }
        case .inactive:
            // 인증창이 뜰 때도 잠깐 inactive 가 되므로 잠그지는 않고 가리기만 한다
            shielded = blurEnabled
        case .background:
            shielded = blurEnabled
            if lockEnabled { locked = true }
        @unknown default:
            break
        }
    }

    private func autoAuthenticateSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.locked, self.phase == .active,
                  Date().timeIntervalSince(self.lastRelay) > 3 else { return }
            self.authenticate()
        }
    }

    func setLockEnabled(_ on: Bool) {
        lockEnabled = on
        if !on { locked = false }
    }

    func authenticate() {
        guard locked, !authenticating else { return }
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else {
            // 기기 암호도 없으면 잠글 방법이 없으므로 잠금을 풀어 둔다
            message = "이 기기에는 암호나 생체 인증이 설정되어 있지 않아 잠글 수 없습니다."
            locked = false
            return
        }
        authenticating = true
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "SwipeLauncher 설정을 열려면 인증하세요.") { ok, error in
            DispatchQueue.main.async {
                self.authenticating = false
                if ok {
                    self.message = ""
                    self.locked = false
                } else {
                    self.message = (error as? LAError)?.code == .userCancel ? "" : "인증하지 못했습니다."
                }
            }
        }
    }
}

/// 앱 전체를 감싸서 잠금 화면과 블러를 입힌다.
struct RootView: View {
    @ObservedObject private var lock = AppLock.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let hidden = lock.locked || lock.shielded
        ZStack {
            ContentView()
                .environmentObject(lock)
                .blur(radius: hidden ? 30 : 0)
                .allowsHitTesting(!lock.locked)
                .accessibilityHidden(lock.locked)

            if hidden {
                Rectangle().fill(.regularMaterial).ignoresSafeArea()
            }
            if lock.locked {
                VStack(spacing: 16) {
                    Image(systemName: "lock.fill").font(.system(size: 44))
                    Text("잠겨 있습니다").font(.headline)
                    if !lock.message.isEmpty {
                        Text(lock.message).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    Button("잠금 해제") { lock.authenticate() }
                        .buttonStyle(.borderedProminent)
                }
                .padding(32)
            }
        }
        .onChange(of: scenePhase) { _, phase in lock.scenePhaseChanged(phase) }
        .onAppear { lock.scenePhaseChanged(scenePhase) }
    }
}
