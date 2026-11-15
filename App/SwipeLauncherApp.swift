import SwiftUI

@main
struct SwipeLauncherApp: App {
    @State private var showPad = false

    var body: some Scene {
        WindowGroup {
            SettingsView(showPad: $showPad)
                .fullScreenCover(isPresented: $showPad) { PadView() }
                .onOpenURL { url in
                    if url.host == "pad" { showPad = true }
                }
        }
    }
}
