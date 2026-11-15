import CoreGraphics
import Foundation

/// 스크린샷에서 위젯 위치(표식 색 영역)를 찾고, 다른 스크린샷에서 그 부분을 잘라내는 도구.
enum Calibration {
    /// 표식 색(마젠타) 픽셀 판정. 압축·색 보정에 약간 견디도록 여유를 둔다.
    @inline(__always)
    private static func isMarker(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool {
        r > 200 && b > 200 && g < 70
    }

    private static func rgba(_ image: CGImage) -> [UInt8]? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// 표식 색 영역을 모두 찾는다(위젯 여러 개 동시 가능). 읽는 순서(위→아래, 왼쪽→오른쪽)로 정렬해 반환.
    static func detectMarkers(in image: CGImage) -> [CGRect] {
        let w = image.width, h = image.height
        guard let data = rgba(image) else { return [] }

        var mask = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) {
            let p = i * 4
            mask[i] = isMarker(data[p], data[p + 1], data[p + 2])
        }

        var visited = [Bool](repeating: false, count: w * h)
        var rects: [CGRect] = []
        let minArea = max(2000, (w * h) / 400)   // 화면의 0.25% 미만은 노이즈
        var stack: [Int] = []

        for start in 0..<(w * h) where mask[start] && !visited[start] {
            var minX = w, minY = h, maxX = 0, maxY = 0, area = 0
            stack.removeAll(keepingCapacity: true)
            stack.append(start)
            visited[start] = true
            while let cur = stack.popLast() {
                let x = cur % w, y = cur / w
                area += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
                // 4방향 이웃
                if x > 0, mask[cur - 1], !visited[cur - 1] { visited[cur - 1] = true; stack.append(cur - 1) }
                if x < w - 1, mask[cur + 1], !visited[cur + 1] { visited[cur + 1] = true; stack.append(cur + 1) }
                if y > 0, mask[cur - w], !visited[cur - w] { visited[cur - w] = true; stack.append(cur - w) }
                if y < h - 1, mask[cur + w], !visited[cur + w] { visited[cur + w] = true; stack.append(cur + w) }
            }
            if area >= minArea, maxX > minX, maxY > minY {
                rects.append(CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
            }
        }
        return sortReadingOrder(rects)
    }

    /// 같은 줄(세로 위치가 비슷한 것)끼리 묶어서 왼쪽→오른쪽으로 정렬
    static func sortReadingOrder(_ rects: [CGRect]) -> [CGRect] {
        guard !rects.isEmpty else { return [] }
        let heights = rects.map { $0.height }.sorted()
        let tolerance = max(20, heights[heights.count / 2] * 0.35)
        let byY = rects.sorted { $0.minY < $1.minY }
        var rows: [[CGRect]] = []
        for r in byY {
            if let last = rows.last, abs(last[0].minY - r.minY) <= tolerance {
                rows[rows.count - 1].append(r)
            } else {
                rows.append([r])
            }
        }
        return rows.flatMap { $0.sorted { $0.minX < $1.minX } }
    }

    /// 픽셀 좌표 사각형으로 자르기
    static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = rect.integral.intersection(bounds)
        guard r.width > 1, r.height > 1 else { return nil }
        return image.cropping(to: r)
    }
}
