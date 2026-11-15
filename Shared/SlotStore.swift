import CoreGraphics
import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

/// 앱과 위젯이 공유하는 "투명 배경 조각(슬롯)" 저장소.
/// 앱 그룹을 쓸 수 없는 환경이면 containerURL 이 nil 이고, 위젯은 파일 선택 방식으로 대신한다.
enum SlotStore {
    static let primaryGroup = "group.com.MACHU.Launcher"

    /// 재서명 도구가 앱 그룹 이름을 바꿔도 찾을 수 있도록 후보를 모두 시도한다.
    static func containerURL() -> URL? {
        var ids: [String] = []
        if let alt = Bundle.main.object(forInfoDictionaryKey: "ALTAppGroups") as? [String] { ids += alt }
        ids.append(primaryGroup)
        for id in ids {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return url }
        }
        return nil
    }

    static var isAvailable: Bool { containerURL() != nil }

    private static func dir() -> URL? {
        guard let base = containerURL() else { return nil }
        let d = base.appendingPathComponent("slots", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func slotURL(_ number: Int) -> URL? {
        dir()?.appendingPathComponent("slot_\(number).png")
    }

    /// 1번부터 번호를 매겨 저장한다. 이전 조각은 모두 지운다.
    @discardableResult
    static func save(slots: [CGImage]) -> Bool {
        guard let d = dir() else { return false }
        if let old = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) {
            for f in old { try? FileManager.default.removeItem(at: f) }
        }
        for (i, img) in slots.enumerated() {
            guard let url = slotURL(i + 1),
                  let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
            else { return false }
            CGImageDestinationAddImage(dest, img, nil)
            if !CGImageDestinationFinalize(dest) { return false }
        }
        return true
    }

    static func loadSlot(_ number: Int) -> UIImage? {
        guard number > 0, let url = slotURL(number), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    static func count() -> Int {
        guard let d = dir(), let files = try? FileManager.default.contentsOfDirectory(at: d, includingPropertiesForKeys: nil) else { return 0 }
        return files.filter { $0.lastPathComponent.hasPrefix("slot_") }.count
    }
}
