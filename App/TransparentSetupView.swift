import PhotosUI
import SwiftUI
import WidgetKit

struct TransparentSetupView: View {
    @State private var markerItem: PhotosPickerItem?
    @State private var blankItem: PhotosPickerItem?
    @State private var markerImage: UIImage?
    @State private var blankImage: UIImage?
    @State private var rects: [CGRect] = []
    @State private var message = ""
    @State private var applied = false
    @State private var savedFiles: [URL] = []

    var body: some View {
        Form {
            Section("1단계 · 위젯 위치 알려주기") {
                Text("① 홈 화면에 '투명 런처' 위젯을 원하는 자리에 올립니다. (여러 개 가능, 소·중·대 섞어도 됩니다)\n② 각 위젯을 길게 눌러 '위젯 편집'에서 '위치 보정용 표식 색 표시'를 켭니다. 위젯이 자홍색으로 변합니다.\n③ 그 홈 화면을 스크린샷으로 찍습니다.")
                    .font(.callout)
                PhotosPicker(selection: $markerItem, matching: .images) {
                    Label(markerImage == nil ? "표식 스크린샷 고르기" : "다시 고르기", systemImage: "photo")
                }
                if markerImage != nil {
                    if rects.isEmpty {
                        Text("자홍색 위젯을 찾지 못했습니다. 표식 색 표시가 켜진 화면인지 확인하세요.")
                            .font(.footnote).foregroundStyle(.red)
                    } else {
                        Text("위젯 \(rects.count)개를 찾았습니다. 번호는 위→아래, 왼쪽→오른쪽 순서입니다.")
                            .font(.footnote).foregroundStyle(.green)
                    }
                }
                if let markerImage, !rects.isEmpty {
                    MarkedPreview(image: markerImage, rects: rects)
                }
            }

            Section("2단계 · 빈 화면 스크린샷") {
                Text("④ 같은 위치(같은 페이지 자리)에서 아이콘과 위젯이 모두 없는 빈 페이지를 만들어 스크린샷을 찍습니다.")
                    .font(.callout)
                PhotosPicker(selection: $blankItem, matching: .images) {
                    Label(blankImage == nil ? "빈 화면 스크린샷 고르기" : "다시 고르기", systemImage: "photo")
                }
            }

            Section("3단계 · 적용") {
                Button("저장하고 위젯에 적용") { apply() }
                    .disabled(markerImage == nil || blankImage == nil || rects.isEmpty)
                if applied {
                    if SlotStore.isAvailable {
                        Text("적용했습니다. 위젯 편집에서 '투명 위치' 번호를 위 미리보기의 번호로 입력하고, '위치 보정용 표식 색 표시'는 끄세요. 효과는 '배경 효과'에서 고릅니다.")
                            .font(.footnote)
                    } else {
                        Text("이 기기에서는 앱 그룹을 쓸 수 없어 파일 방식으로 저장했습니다. 위젯 편집 → '투명 배경 이미지' → 선택 → 나의 iPhone → SwipeLauncher 폴더에서 해당 번호 파일을 고르세요. (안 열리면 검색창에 transparent 입력)")
                            .font(.footnote)
                    }
                    ForEach(savedFiles, id: \.self) { url in
                        Text(url.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if !message.isEmpty {
                Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }

            Section("알아두기") {
                Text("• 월페이퍼, 디스플레이 확대, 큰 아이콘 설정을 바꾸면 이 과정을 다시 해야 합니다.\n• 가로·세로는 위치가 달라서 각각 따로 해야 합니다.\n• 위젯 위치를 바꾸면 해당 자리의 번호로 다시 지정하세요.")
                    .font(.footnote)
            }
        }
        .navigationTitle("투명 배경 만들기")
        .onChange(of: markerItem) { _, item in load(item) { img in
            markerImage = img
            rects = img.map { Calibration.detectMarkers(in: $0.normalizedCGImage()) } ?? []
            applied = false
        } }
        .onChange(of: blankItem) { _, item in load(item) { img in
            blankImage = img
            applied = false
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

    private func apply() {
        applied = false
        message = ""
        savedFiles = []
        guard let markerImage, let blankImage else { return }
        let marker = markerImage.normalizedCGImage()
        let blank = blankImage.normalizedCGImage()
        guard marker.width == blank.width, marker.height == blank.height else {
            message = "두 스크린샷의 크기가 다릅니다. (\(marker.width)×\(marker.height) / \(blank.width)×\(blank.height)) 같은 기기, 같은 방향에서 찍은 스크린샷을 쓰세요."
            return
        }
        let crops = rects.compactMap { Calibration.crop(blank, to: $0) }
        guard crops.count == rects.count else { message = "일부 위젯을 자르지 못했습니다."; return }

        // 파일 방식 대비: 앱 문서 폴더에도 저장
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let old = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil) {
            for f in old where f.lastPathComponent.hasPrefix("transparent_slot_") { try? FileManager.default.removeItem(at: f) }
        }
        for (i, c) in crops.enumerated() {
            let url = docs.appendingPathComponent("transparent_slot_\(i + 1).png")
            if let data = UIImage(cgImage: c).pngData(), (try? data.write(to: url)) != nil {
                savedFiles.append(url)
            }
        }

        // 공유 저장소(앱 그룹)에 저장 → 위젯은 번호만 고르면 된다
        _ = SlotStore.save(slots: crops)
        WidgetCenter.shared.reloadAllTimelines()
        applied = true
    }
}

/// 표식 스크린샷 위에 찾은 위젯 위치와 번호를 그려서 보여준다.
struct MarkedPreview: View {
    let image: UIImage
    let rects: [CGRect]

    var body: some View {
        let cg = image.normalizedCGImage()
        let w = CGFloat(cg.width), h = CGFloat(cg.height)
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .overlay {
                GeometryReader { geo in
                    let s = geo.size.width / w
                    ForEach(Array(rects.enumerated()), id: \.offset) { i, r in
                        ZStack {
                            Rectangle().stroke(Color.yellow, lineWidth: 3)
                            Text("\(i + 1)")
                                .font(.system(size: max(18, r.height * s * 0.4), weight: .heavy))
                                .foregroundStyle(.yellow)
                                .shadow(color: .black, radius: 2)
                        }
                        .frame(width: r.width * s, height: r.height * s)
                        .position(x: (r.minX + r.width / 2) * s, y: (r.minY + r.height / 2) * s)
                    }
                }
            }
            .aspectRatio(w / h, contentMode: .fit)
            .frame(maxHeight: 320)
    }
}

extension UIImage {
    /// 방향 정보를 제거한 CGImage (스크린샷은 대부분 .up 이지만 안전하게)
    func normalizedCGImage() -> CGImage {
        if imageOrientation == .up, let cg = cgImage { return cg }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let img = renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
        return img.cgImage ?? cgImage!
    }
}
