import SwiftUI

struct SettingsView: View {
    @Binding var showPad: Bool
    @State private var slots = Config.load()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("제스처 패드 열기") { showPad = true }
                } footer: {
                    Text("홈 화면 위젯을 탭해도 이 패드가 열립니다.")
                }

                ForEach(Direction.allCases) { d in
                    Section(header: Label(d.title, systemImage: d.symbol)) {
                        TextField("이름", text: binding(d, \.name))
                        TextField("URL 스킴 (예: maps://)", text: binding(d, \.url))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)
                    }
                }
            }
            .navigationTitle("SwipeLauncher")
        }
    }

    private func binding(_ d: Direction, _ kp: WritableKeyPath<AppSlot, String>) -> Binding<String> {
        Binding(
            get: { slots[d]?[keyPath: kp] ?? "" },
            set: {
                slots[d]?[keyPath: kp] = $0
                Config.save(slots)
            }
        )
    }
}
