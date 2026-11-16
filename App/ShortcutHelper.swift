import SwiftUI
import UIKit

/// URL 스킴이 없는 앱도 열 수 있게, 단축어 실행 주소를 만들어 주는 도우미.
/// 단축어 앱에서 '앱 열기' 동작 하나짜리 단축어를 만들어 두고, 그 이름으로 주소를 만든다.
struct ShortcutHelperView: View {
    /// 만든 주소를 새 조합으로 추가한다.
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var result = ""

    /// shortcuts://run-shortcut?name=<이름>  (이름은 전부 퍼센트 인코딩)
    private var url: String {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, let enc = n.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return "" }
        return "shortcuts://run-shortcut?name=" + enc
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("1. 단축어 앱에서 새 단축어를 만들고 '앱 열기' 동작을 넣어 열 앱을 고릅니다.\n2. 그 단축어의 이름을 아래에 똑같이 적습니다.\n3. 만들어진 주소를 조합에 추가합니다.")
                        .font(.callout)
                    Button("단축어 앱 열기") { open("shortcuts://") }
                } header: {
                    Text("만드는 방법")
                }

                Section {
                    TextField("단축어 이름", text: $name)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !url.isEmpty {
                        Text(url).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                        Button("조합으로 추가") {
                            onAdd(url)
                            dismiss()
                        }
                        Button("주소 복사") {
                            UIPasteboard.general.string = url
                            result = "복사했습니다."
                        }
                        Button("테스트") { open(url) }
                    }
                    if !result.isEmpty { Text(result).font(.footnote).foregroundStyle(.secondary) }
                } header: {
                    Text("단축어 이름")
                } footer: {
                    Text("단축어가 실행되면서 앱이 열립니다. 단축어 앱이 잠깐 거쳐 가므로 URL 스킴으로 여는 것보다 조금 느릴 수 있습니다.")
                }
            }
            .navigationTitle("단축어로 앱 열기")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
            }
        }
    }

    private func open(_ raw: String) {
        guard let u = URL(string: raw) else { result = "올바르지 않은 주소"; return }
        UIApplication.shared.open(u) { ok in
            DispatchQueue.main.async { result = ok ? "열림" : "열 수 없음 (단축어 이름 확인)" }
        }
    }
}
