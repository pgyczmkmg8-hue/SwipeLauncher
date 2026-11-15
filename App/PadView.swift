import SwiftUI
import UIKit

struct PadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var slots = Config.load()
    @State private var active: Direction?
    @State private var message = "스와이프해서 앱 실행"

    private let threshold: CGFloat = 40

    var body: some View {
        ZStack {
            Rectangle().fill(.black.opacity(0.88)).ignoresSafeArea()

            VStack {
                hint(.up)
                Spacer()
                HStack { hint(.left); Spacer(); hint(.right) }
                Spacer()
                hint(.down)
            }
            .padding(32)

            Text(message)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.7))

            VStack {
                HStack {
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
            }
            .padding()
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: threshold)
                .onChanged { active = direction(for: $0.translation) }
                .onEnded { value in
                    active = nil
                    if let d = direction(for: value.translation) { launch(d) }
                }
        )
        .onAppear { slots = Config.load() }
    }

    private func hint(_ d: Direction) -> some View {
        VStack(spacing: 6) {
            Image(systemName: d.symbol).font(.title2)
            Text(slots[d]?.name ?? "-").font(.footnote)
        }
        .foregroundStyle(active == d ? Color.accentColor : .white.opacity(0.6))
        .scaleEffect(active == d ? 1.3 : 1)
        .animation(.spring(duration: 0.2), value: active)
    }

    private func direction(for t: CGSize) -> Direction? {
        guard max(abs(t.width), abs(t.height)) >= threshold else { return nil }
        if abs(t.width) > abs(t.height) { return t.width > 0 ? .right : .left }
        return t.height > 0 ? .down : .up
    }

    private func launch(_ d: Direction) {
        guard let slot = slots[d], let url = URL(string: slot.url) else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        UIApplication.shared.open(url) { ok in
            if !ok { message = "\(slot.name) 실행 실패 (URL 스킴 확인)" }
        }
    }
}
