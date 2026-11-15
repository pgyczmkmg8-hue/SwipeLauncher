import PhotosUI
import SwiftUI

struct SavedBackground: Identifiable {
    let id = UUID()
    let url: URL
}

struct TransparentSetupView: View {
    @State private var markerItem: PhotosPickerItem?
    @State private var blankItem: PhotosPickerItem?
    @State private var markerImage: UIImage?
    @State private var blankImage: UIImage?
    @State private var markerRect: CGRect?
    @State private var result: UIImage?
    @State private var message = ""
    @State private var savedURL: URL?

    var body: some View {
        Form {
            Section("1단계 · 위치 찾기용 스크린샷") {
                Text("① 홈 화면에 '투명 런처' 위젯을 올리고, 위젯 편집에서 '위치 보정용 표식 색 표시'를 켭니다. 위젯이 자홍색(마젠타)으로 변합니다.\n② 그 화면을 스크린샷으로 찍습니다.")
                    .font(.callout)
                PhotosPicker(selection: $markerItem, matching: .images) {
                    Label(markerImage == nil ? "표식 스크린샷 고르기" : "다시 고르기", systemImage: "photo")
                }
                if markerImage != nil {
                    if let r = markerRect {
                        Text("위젯 위치 찾음: \(Int(r.width))×\(Int(r.height))px  (x \(Int(r.minX)), y \(Int(r.minY)))")
                            .font(.footnote).foregroundStyle(.green)
                    } else {
                        Text("자홍색 위젯을 찾지 못했습니다. 위젯 표식 색이 켜진 화면인지 확인하세요.")
                            .font(.footnote).foregroundStyle(.red)
                    }
                }
            }

            Section("2단계 · 빈 화면 스크린샷") {
                Text("③ 위젯을 올린 페이지와 같은 자리에, 아이콘과 위젯이 모두 없는 빈 페이지를 만듭니다. (아이콘이 없는 페이지로 넘기거나, 위젯과 아이콘을 잠시 치웁니다)\n④ 같은 위치에서 스크린샷을 찍습니다.")
                    .font(.callout)
                PhotosPicker(selection: $blankItem, matching: .images) {
                    Label(blankImage == nil ? "빈 화면 스크린샷 고르기" : "다시 고르기", systemImage: "photo")
                }
            }

            if let result {
                Section("결과 미리보기") {
                    Image(uiImage: result)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 220)
                        .border(.secondary)
                    Button("파일로 저장") { save(result) }
                    if let savedURL {
                        Text("저장됨: 파일 앱 → 내 iPhone → SwipeLauncher → \(savedURL.lastPathComponent)")
                            .font(.footnote)
                        ShareLink(item: savedURL) { Label("공유 / 다른 곳에 저장", systemImage: "square.and.arrow.up") }
                    }
                    Text("저장 후 위젯을 길게 눌러 '위젯 편집' → '투명 배경 이미지' → 선택 → 둘러보기 → 나의 iPhone → SwipeLauncher 폴더에서 이 파일을 고르세요. (폴더가 안 열리면 파일 앱 검색창에 transparent 를 입력해 찾으세요.) 표식 색 표시는 꺼 둡니다.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !message.isEmpty {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }

            Section("알아두기") {
                Text("• 월페이퍼, 디스플레이 확대(확대 보기), 큰 아이콘 설정을 바꾸면 다시 만들어야 합니다.\n• 가로·세로는 위치가 달라서 각각 따로 만들어야 합니다.\n• 위젯 크기(소/중/대)와 위치마다 위젯과 이미지를 따로 만듭니다.")
                    .font(.footnote)
            }
        }
        .navigationTitle("투명 배경 만들기")
        .onChange(of: markerItem) { _, item in load(item) { img in
            markerImage = img
            markerRect = img.flatMap { Calibration.detectMarker(in: $0.normalizedCGImage()) }
            process()
        } }
        .onChange(of: blankItem) { _, item in load(item) { img in
            blankImage = img
            process()
        } }
    }

    private func load(_ item: PhotosPickerItem?, done: @escaping (UIImage?) -> Void) {
        guard let item else { return }
        Task {
            let data = try? await item.loadTransferable(type: Data.self)
            let image = data.flatMap { UIImage(data: $0) }
            await MainActor.run { done(image) }
        }
    }

    private func process() {
        result = nil
        savedURL = nil
        message = ""
        guard let markerImage, let blankImage, let rect = markerRect else { return }
        let blank = blankImage.normalizedCGImage()
        let marker = markerImage.normalizedCGImage()
        guard marker.width == blank.width, marker.height == blank.height else {
            message = "두 스크린샷의 크기가 다릅니다. (\(marker.width)×\(marker.height) / \(blank.width)×\(blank.height)) 같은 기기, 같은 방향에서 찍은 스크린샷을 쓰세요."
            return
        }
        if let cropped = Calibration.crop(blank, to: rect) {
            result = UIImage(cgImage: cropped)
        } else {
            message = "이미지를 자르지 못했습니다."
        }
    }

    private func save(_ image: UIImage) {
        guard let data = image.pngData() else { message = "PNG 변환 실패"; return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        let url = docs.appendingPathComponent("transparent_\(f.string(from: Date())).png")
        do {
            try data.write(to: url)
            savedURL = url
            message = "저장했습니다."
        } catch {
            message = "저장 실패: \(error.localizedDescription)"
        }
    }
}

extension UIImage {
    /// 방향 정보를 제거한 CGImage (스크린샷은 대부분 .up 이지만 안전하게)
    func normalizedCGImage() -> CGImage {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size.width * scale, height: size.height * scale), format: format)
        let img = renderer.image { _ in draw(in: CGRect(origin: .zero, size: CGSize(width: size.width * scale, height: size.height * scale))) }
        return img.cgImage ?? cgImage!
    }
}
