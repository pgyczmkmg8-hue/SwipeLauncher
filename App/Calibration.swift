import CoreGraphics
import Foundation

/// 스크린샷에서 위젯 위치(표식 색 영역)를 찾고, 다른 스크린샷에서 그 부분을 잘라내는 도구.
enum Calibration {
    /// 표식 색(마젠타) 픽셀 판정. 압축·색 보정에 약간 견디도록 여유를 둔다.
    @inline(__always)
    private static func isMarker(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Bool {
        r > 200 && b > 200 && g < 70
    }

    /// 표식 색 영역의 외접 사각형(픽셀 좌표). 충분히 큰 영역이 없으면 nil.
    static func detectMarker(in image: CGImage) -> CGRect? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }

        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4, space: space, bitmapInfo: info) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var rowCount = [Int](repeating: 0, count: h)
        var colCount = [Int](repeating: 0, count: w)
        var total = 0
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                if isMarker(data[i], data[i + 1], data[i + 2]) {
                    rowCount[y] += 1
                    colCount[x] += 1
                    total += 1
                }
            }
        }
        // 노이즈 방지: 화면의 0.5% 이상은 표식이어야 한다
        guard total > (w * h) / 200 else { return nil }

        // 행/열 별로 "충분히 많이 칠해진" 구간만 채택 (가장자리 안티앨리어싱 제외)
        let rowMax = rowCount.max() ?? 0
        let colMax = colCount.max() ?? 0
        let rowThreshold = max(8, rowMax / 2)
        let colThreshold = max(8, colMax / 2)
        guard let minY = rowCount.firstIndex(where: { $0 >= rowThreshold }),
              let maxY = rowCount.lastIndex(where: { $0 >= rowThreshold }),
              let minX = colCount.firstIndex(where: { $0 >= colThreshold }),
              let maxX = colCount.lastIndex(where: { $0 >= colThreshold }),
              maxX > minX, maxY > minY else { return nil }

        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// 픽셀 좌표 사각형으로 자르기
    static func crop(_ image: CGImage, to rect: CGRect) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let r = rect.integral.intersection(bounds)
        guard r.width > 1, r.height > 1 else { return nil }
        return image.cropping(to: r)
    }
}
