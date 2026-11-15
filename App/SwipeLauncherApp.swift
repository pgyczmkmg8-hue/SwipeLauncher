import SwiftUI
import UIKit

@main
struct SwipeLauncherApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}

struct ContentView: View {
    @State private var test = ""
    @State private var result = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("사용법") {
                    Text("1. 홈 화면을 길게 눌러 위젯 추가 → '투명 런처'\n2. 위젯을 길게 눌러 '위젯 편집'\n3. 칸 개수(2×2 / 3×3)와 칸별 URL 스킴 입력\n4. 투명한 칸을 터치하면 앱이 열립니다")
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
            }
            .navigationTitle("투명 런처")
        }
    }
}
