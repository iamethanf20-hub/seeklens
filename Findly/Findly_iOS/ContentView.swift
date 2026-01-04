import SwiftUI
import UIKit
import Vision
import AVFoundation   // ⬅️ NEW: for live camera preview support elsewhere

// MARK: - Mode

enum InferenceMode: String, CaseIterable {
    case owl = "Find Objects"
    case ocr = "Find Words"
    case liveText = "Live Text (Beta)"   // ⬅️ NEW experimental mode
}

enum MatchMode: String, CaseIterable {
    case contains = "contains"
    case exact = "exact"
}

// MARK: - OCR Languages (Vision-only)

enum OCRLanguage: String, CaseIterable, Identifiable {
    case eng = "English"              // English (kept as is)
    case spa = "Español"              // Spanish
    case fra = "Français"             // French
    case deu = "Deutsch"              // German
    case ita = "Italiano"             // Italian
    case por = "Português"            // Portuguese
    case chi_sim = "中文（简体）"         // Chinese (Simplified)
    case jpn = "日本語"                 // Japanese
    case rus = "Русский"              // Russian

    var id: String { rawValue }

    var visionCode: String {
        switch self {
        case .eng: return "en-US"
        case .spa: return "es-ES"
        case .fra: return "fr-FR"
        case .deu: return "de-DE"
        case .ita: return "it-IT"
        case .por: return "pt-PT"
        case .chi_sim: return "zh-Hans"
        case .jpn: return "ja-JP"
        case .rus: return "ru-RU"
        }
    }
}

// MARK: - Photo Item Model

struct PhotoItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let pixelSize: CGSize
    var detections: [OWLDetection] = []
    var status: String = ""
    
    init(image: UIImage) {
        self.image = image
        if let cg = image.cgImage {
            self.pixelSize = CGSize(width: cg.width, height: cg.height)
        } else {
            self.pixelSize = image.size
        }
    }
}

// MARK: - Styling

extension View {
    func popStyle(primary: Bool = false) -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: primary
                        ? [Color.blue, Color.purple]
                        : [Color.gray.opacity(0.18), Color.gray.opacity(0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundColor(primary ? .white : .primary)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Title Bar

struct SeekLensTitleBar: View {
    var body: some View {
        HStack {
            Spacer()
            Text("SeekLens")
                .font(.system(size: 20, weight: .heavy, design: .rounded))
                .padding(.vertical, 8)
                .padding(.horizontal, 24)
                .background(
                    LinearGradient(colors: [.orange, .pink],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 4)
            Spacer()
        }
        .padding(.top, 10)
    }
}

// MARK: - ContentView

struct ContentView: View {
    // UI state
    @State private var mode: InferenceMode = .ocr
    @State private var showCamera = false
    
    // NEW: Multiple photos support
    @State private var photos: [PhotoItem] = []
    @State private var selectedPhotoIndex: Int = 0

    // Detections
    @State private var minScore: Double = 0.15

    // Inputs
    @State private var query: String = ""
    @State private var ocrWords: String = ""
    @State private var ocrMatch: MatchMode = .contains
    @State private var liveTextFilter: String = ""
    @State private var liveTextMatch: MatchMode = .contains
    @State private var liveTextPerWord: Bool = true

    // Status
    @State private var isBusy = false
    @State private var status: String = ""
    @State private var errorText: String? = nil

    @FocusState private var isInputFocused: Bool

    // Vision-only options
    @State private var ocrLang: OCRLanguage = .eng
    @State private var visionPerWord: Bool = true

    // OWL client
    private let owlClient = OWLClient()

    // Zoom state
    @State private var zoom: CGFloat = 1.0
    @State private var baseZoom: CGFloat = 1.0
    @State private var contentOffset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    // Monetization
    @ObservedObject private var iap = SubscriptionManager.shared
    @ObservedObject private var usage = UsageMeter.shared
    @State private var showUsesInfo = false
    @State private var showPaywall = false
    @EnvironmentObject var adMobManager: AdMobManager

    // Fullscreen image
    @State private var showFullscreenImage = false

    private var viewportHeight: CGFloat {
        max(360, UIScreen.main.bounds.height * 0.45)
    }
    
    // Computed properties for current photo
    private var currentPhoto: PhotoItem? {
        guard !photos.isEmpty, selectedPhotoIndex < photos.count else { return nil }
        return photos[selectedPhotoIndex]
    }
    
    private var currentImage: UIImage? {
        currentPhoto?.image
    }
    
    private var currentPixelSize: CGSize {
        currentPhoto?.pixelSize ?? .zero
    }
    
    private var currentDetections: [OWLDetection] {
        currentPhoto?.detections ?? []
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            backgroundGradient
            scrollContent
        }
        .ignoresSafeArea(.keyboard)
        .overlay(bottomOverlay, alignment: .bottom)
        .sheet(isPresented: $showCamera) {
            cameraSheet
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()   // assumes your PaywallView has no parameters now
        }
        .fullScreenCover(isPresented: $showFullscreenImage) {
            if mode == .liveText {
                FullscreenLiveTextView(
                    filterQuery: liveTextFilter,
                    matchMode: liveTextMatch,
                    showPerWord: liveTextPerWord
                )
            } else {
                FullscreenImageView(
                    image: currentImage,
                    pixelSize: currentPixelSize,
                    detections: currentDetections,
                    minScore: minScore
                )
            }
        }
        .alert("Usage Info", isPresented: $showUsesInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("SeekLens currently gives you access to both text detection and object detection. Object detection is in beta, so results may vary.")
        }
        .onAppear {
            usage.refreshMonthIfNeeded()
        }
    }

    // MARK: - Top-level pieces

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color(.systemGray6), Color(.systemGray5)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var scrollContent: some View {
        ScrollView(.vertical) {
            VStack(spacing: 12) {
                SeekLensTitleBar()
                modePicker

                if mode == .liveText {
                    // ⬇️ NEW: Text input for filtering live text
                    liveTextControls
                    
                    // ⬇️ UPDATED: Full screen Live Text preview with proper sizing AND ZOOM
                    GeometryReader { geo in
                        let magnify = MagnificationGesture()
                            .onChanged { v in
                                let proposed = baseZoom * v
                                let clamped = min(max(proposed, 1.0), 4.0)
                                if clamped != zoom { zoom = clamped }
                            }
                            .onEnded { v in
                                let proposed = baseZoom * v
                                baseZoom = min(max(proposed, 1.0), 4.0)
                            }

                        let drag = DragGesture()
                            .onChanged { value in
                                guard zoom > 1.001 else { contentOffset = .zero; return }
                                contentOffset = CGSize(
                                    width: baseOffset.width + value.translation.width,
                                    height: baseOffset.height + value.translation.height
                                )
                            }
                            .onEnded { _ in baseOffset = contentOffset }
                        
                        LiveTextPreviewView(
                            filterQuery: liveTextFilter,
                            matchMode: liveTextMatch,
                            showPerWord: liveTextPerWord,
                            cameraZoom: zoom  // ⬅️ NEW: Pass zoom to camera
                        )
                            .scaleEffect(zoom)
                            .offset(contentOffset)
                            .frame(maxWidth: .infinity)
                            .frame(height: UIScreen.main.bounds.height * 0.65)
                            .contentShape(Rectangle())
                            .gesture(drag.simultaneously(with: magnify))
                            .onTapGesture(count: 2) {
                                showFullscreenImage = true
                            }
                            .position(x: geo.size.width / 2, y: geo.size.height / 2)
                    }
                        .frame(maxWidth: .infinity)
                        .frame(height: UIScreen.main.bounds.height * 0.65)
                        .padding(.horizontal, 8)
                        .background(Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 6)

                    // Tiny status/info text reused
                    statusSection
                } else {
                    // Existing static-image pipeline
                    owlControls
                    ocrControls
                    
                    // NEW: Photo gallery when multiple photos exist
                    if !photos.isEmpty {
                        photoGallery
                    }
                    
                    viewport
                    controlButtons
                    statusSection
                }

                Color.clear.frame(height: 20)
            }
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .seeklensScrollModifiers()
    }

    // MARK: - Sections

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            Text(InferenceMode.ocr.rawValue).tag(InferenceMode.ocr)
            Text(InferenceMode.owl.rawValue).tag(InferenceMode.owl)
            Text(InferenceMode.liveText.rawValue).tag(InferenceMode.liveText)   // ⬅️ NEW
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .onChange(of: mode) { _ in
            // Reset zoom when switching modes
            resetZoom()
        }
    }
    
    // NEW: Photo Gallery View
    private var photoGallery: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Photos (\(photos.count))")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    photos.removeAll()
                    selectedPhotoIndex = 0
                    resetZoom()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                        Text("Clear All")
                    }
                    .font(.caption)
                }
                .popStyle()
            }
            .padding(.horizontal)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                        PhotoThumbnail(
                            photo: photo,
                            isSelected: index == selectedPhotoIndex,
                            index: index
                        )
                        .onTapGesture {
                            selectedPhotoIndex = index
                            resetZoom()
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                deletePhoto(at: index)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
                .padding(.horizontal)
            }
        }
    }

    // ⬇️ UPDATED: Controls for Live Text mode with match and box level options
    @ViewBuilder
    private var liveTextControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Filter text (leave empty to show all)", text: $liveTextFilter)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .focused($isInputFocused)
                    .submitLabel(.done)
                    .onSubmit { isInputFocused = false }

                Button("Clear") { liveTextFilter = "" }
                    .popStyle()
            }
            
            HStack(spacing: 10) {
                Picker("Match", selection: $liveTextMatch) {
                    Text("Contains").tag(MatchMode.contains)
                    Text("Exact").tag(MatchMode.exact)
                }
                .pickerStyle(.segmented)

                Picker("Box Level", selection: $liveTextPerWord) {
                    Text("Words").tag(true)
                    Text("Lines").tag(false)
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var owlControls: some View {
        if mode == .owl {
            HStack(spacing: 10) {
                TextField("Enter query (e.g. mug, apple)", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    .focused($isInputFocused)
                    .submitLabel(.done)
                    .onSubmit { isInputFocused = false }

                Button("Clear") { query = "" }
                    .popStyle()
            }
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var ocrControls: some View {
        if mode == .ocr {
            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    TextField("Enter query (comma-separated)", text: $ocrWords)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .focused($isInputFocused)
                        .submitLabel(.done)
                        .onSubmit { isInputFocused = false }

                    Button("Clear") { ocrWords = "" }
                        .popStyle()
                }

                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Picker("Match", selection: $ocrMatch) {
                            Text("Contains").tag(MatchMode.contains)
                            Text("Exact").tag(MatchMode.exact)
                        }
                        .pickerStyle(.segmented)

                        Picker("Box Level", selection: $visionPerWord) {
                            Text("Words").tag(true)
                            Text("Lines").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                    HStack {
                        Spacer()
                        Picker("Language", selection: $ocrLang) {
                            ForEach(OCRLanguage.allCases) { lang in
                                Text(lang.rawValue).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .accessibilityLabel(Text("Language"))
                        Spacer()
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private var viewport: some View {
        DetectionViewport(
            image: currentImage,
            pixelSize: currentPixelSize,
            detections: currentDetections,
            minScore: minScore,
            isBusy: isBusy,
            zoom: $zoom,
            baseZoom: $baseZoom,
            contentOffset: $contentOffset,
            baseOffset: $baseOffset,
            onDoubleTap: {
                if currentImage != nil {
                    showFullscreenImage = true
                }
            }
        )
        .frame(maxWidth: .infinity)
        .frame(height: viewportHeight)
        .padding(.horizontal, 16)
        .background(Color.clear)
        .ignoresSafeArea(.keyboard)
        .layoutPriority(1)
    }

    private var controlButtons: some View {
        HStack(spacing: 10) {
            Button(systemImage: "camera.fill", title: "Add Photo") {
                showCamera = true
            }
            .popStyle()

            Button(systemImage: "sparkles", title: photos.isEmpty ? "Find!" : "Find in All") {
                Task { await runFindTapped() }
            }
            .popStyle(primary: true)
            .disabled(photos.isEmpty || isBusy)
            .opacity((photos.isEmpty || isBusy) ? 0.6 : 1.0)

            Button {
                if iap.isSubscribed {
                    showUsesInfo = true
                } else {
                    showPaywall = true
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: iap.isSubscribed ? "infinity" : "clock")
                    if iap.isSubscribed {
                        Text("∞")
                    } else {
                        Text("\(usage.remainingText)T / \(usage.remainingObjects)I")
                    }
                }
                .font(.footnote.bold())
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var statusSection: some View {
        if !status.isEmpty {
            Text(status)
                .font(.footnote)
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
                .padding(.horizontal, 10)
                .background(.thinMaterial, in: Capsule())
        }

        if let err = errorText {
            Text(err)
                .font(.footnote)
                .foregroundColor(.red)
                .padding(8)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }

    // MARK: - Overlay / sheets

    @ViewBuilder
    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            if isInputFocused {
                HStack {
                    Spacer()
                    Button("Done") { isInputFocused = false }
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                }
                .background(.thinMaterial)
            } else if !iap.isSubscribed && adMobManager.isInitialized {
                AdMobBannerView()
                    .frame(height: 50)
                    .background(.ultraThinMaterial)
            }
        }
        .padding(.bottom, 0)
    }

    private var cameraSheet: some View {
        CameraPicker { img in
            let newPhoto = PhotoItem(image: img)
            photos.append(newPhoto)
            selectedPhotoIndex = photos.count - 1
            
            status = "Added photo \(photos.count): \(Int(newPhoto.pixelSize.width))×\(Int(newPhoto.pixelSize.height))"
            resetZoom()
        }
    }

    // MARK: - Helper functions
    
    private func resetZoom() {
        zoom = 1.0
        baseZoom = 1.0
        contentOffset = .zero
        baseOffset = .zero
    }
    
    private func deletePhoto(at index: Int) {
        photos.remove(at: index)
        if photos.isEmpty {
            selectedPhotoIndex = 0
        } else if selectedPhotoIndex >= photos.count {
            selectedPhotoIndex = photos.count - 1
        }
        resetZoom()
    }

    private func runFindTapped() async {
        await runCurrentMode()
    }

    private func runCurrentMode() async {
        // LiveText uses continuous camera preview, not static image
        if mode == .liveText {
            await MainActor.run {
                status = "Live Text mode: point your camera at text to see live boxes."
                errorText = nil
            }
            return
        }

        guard !photos.isEmpty else {
            await MainActor.run { status = "No photos loaded"; errorText = nil }
            return
        }
        
        await MainActor.run { isBusy = true; errorText = nil; status = "Processing \(photos.count) photo\(photos.count == 1 ? "" : "s")..." }
        defer { Task { await MainActor.run { isBusy = false } } }

        var totalResults = 0
        var processedCount = 0
        
        for index in 0..<photos.count {
            do {
                let img = photos[index].image
                
                switch mode {
                case .ocr:
                    let wordsArray: [String] = ocrWords
                        .split(separator: ",")
                        .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }

                    let vresults = try await visionDetections(
                        for: img,
                        languageCode: ocrLang.visionCode,
                        words: wordsArray,
                        perWord: visionPerWord,
                        matchMode: ocrMatch
                    )

                    await MainActor.run {
                        photos[index].detections = vresults
                        photos[index].status = "\(vresults.count) result\(vresults.count == 1 ? "" : "s")"
                        totalResults += vresults.count
                        processedCount += 1

                        if !iap.isSubscribed {
                            _ = usage.consumeTextDetection()
                        }
                    }

                case .owl:
                    let resp = try await owlClient.detect(image: img, query: query)
                    let mapped = resp.detections.map {
                        OWLDetection(label: $0.label, score: CGFloat($0.score), box: $0.box.map(CGFloat.init))
                    }
                    
                    await MainActor.run {
                        photos[index].detections = mapped
                        photos[index].status = "\(mapped.count) match\(mapped.count == 1 ? "" : "es")"
                        totalResults += mapped.count
                        processedCount += 1

                        if !iap.isSubscribed {
                            _ = usage.consumeObjectDetection()
                        }
                    }

                case .liveText:
                    // Handled by early return above; this case won't be hit.
                    break
                }
            } catch {
                await MainActor.run {
                    photos[index].status = "Error"
                    errorText = "Photo \(index + 1): \(error.localizedDescription)"
                }
            }
        }
        
        await MainActor.run {
            status = "Found \(totalResults) result\(totalResults == 1 ? "" : "s") across \(processedCount) photo\(processedCount == 1 ? "" : "s")"
        }
    }

    private func cgOrientation(from ui: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch ui {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }

    private func rectInPixels(_ r: CGRect, imageSize: CGSize) -> CGRect {
        CGRect(
            x: r.minX * imageSize.width,
            y: (1 - r.minY - r.height) * imageSize.height,
            width: r.width * imageSize.width,
            height: r.height * imageSize.height
        )
    }

    private func matches(_ text: String, words: [String], mode: MatchMode) -> Bool {
        guard !words.isEmpty else { return true }
        switch mode {
        case .exact:
            return words.contains { $0.caseInsensitiveCompare(text) == .orderedSame }
        case .contains:
            return words.contains { text.lowercased().contains($0.lowercased()) }
        }
    }

    private func visionDetections(
        for uiImage: UIImage,
        languageCode: String,
        words: [String],
        perWord: Bool,
        matchMode: MatchMode
    ) async throws -> [OWLDetection] {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self._visionDetectionsSync(
                        for: uiImage,
                        languageCode: languageCode,
                        words: words,
                        perWord: perWord,
                        matchMode: matchMode
                    )
                    cont.resume(returning: result)
                } catch { cont.resume(throwing: error) }
            }
        }
    }

    private func _visionDetectionsSync(
        for uiImage: UIImage,
        languageCode: String,
        words: [String],
        perWord: Bool,
        matchMode: MatchMode
    ) throws -> [OWLDetection] {
        guard let cg = uiImage.cgImage else { return [] }

        let handler = VNImageRequestHandler(
            cgImage: cg,
            orientation: cgOrientation(from: uiImage.imageOrientation),
            options: [:]
        )
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = .accurate
        req.usesLanguageCorrection = false
        req.recognitionLanguages = [languageCode]
        req.minimumTextHeight = 0.015
        if #available(iOS 15.0, *) {
            let ws = words.filter { !$0.isEmpty }
            if !ws.isEmpty { req.customWords = ws }
        }

        try handler.perform([req])

        let observations = req.results ?? []
        let imgSize = CGSize(width: cg.width, height: cg.height)
        var out: [OWLDetection] = []

        for obs in observations {
            guard let cand = obs.topCandidates(1).first else { continue }
            let lineText = cand.string
            let conf = cand.confidence
            guard conf >= 0.15 else { continue }

            if perWord {
                lineText.enumerateSubstrings(in: lineText.startIndex..<lineText.endIndex, options: .byWords) { word, rng, _, _ in
                    guard let word = word,
                          let rectObs = try? cand.boundingBox(for: rng),
                          matches(word, words: words, mode: matchMode)
                    else { return }
                    let r = rectInPixels(rectObs.boundingBox, imageSize: imgSize)
                    out.append(
                        OWLDetection(
                            label: word,
                            score: CGFloat(conf),
                            box: [r.minX, r.minY, r.width, r.height].map(CGFloat.init)
                        )
                    )
                }
            } else if matches(lineText, words: words, mode: matchMode) {
                let r = rectInPixels(obs.boundingBox, imageSize: imgSize)
                out.append(
                    OWLDetection(
                        label: lineText,
                        score: CGFloat(conf),
                        box: [r.minX, r.minY, r.width, r.height].map(CGFloat.init)
                    )
                )
            }
        }
        return out
    }
}

// MARK: - Photo Thumbnail

struct PhotoThumbnail: View {
    let photo: PhotoItem
    let isSelected: Bool
    let index: Int
    
    var body: some View {
        VStack(spacing: 4) {
            Image(uiImage: photo.image)
                .resizable()
                .scaledToFill()
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            
            VStack(spacing: 2) {
                Text("#\(index + 1)")
                    .font(.caption2.bold())
                    .foregroundColor(isSelected ? .blue : .secondary)
                
                if !photo.status.isEmpty {
                    Text(photo.status)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: 80)
    }
}

// MARK: - DetectionViewport

private struct DetectionViewport: View {
    let image: UIImage?
    let pixelSize: CGSize
    let detections: [OWLDetection]
    let minScore: Double
    let isBusy: Bool

    @Binding var zoom: CGFloat
    @Binding var baseZoom: CGFloat
    @Binding var contentOffset: CGSize
    @Binding var baseOffset: CGSize

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 6.0

    let onDoubleTap: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = image, pixelSize != .zero {
                    let container = geo.size
                    let aspect = img.size.width / max(img.size.height, 1)
                    let fitW = min(container.width, container.height * aspect)
                    let fitH = fitW / max(aspect, 0.0001)

                    let magnify = MagnificationGesture()
                        .onChanged { v in
                            let proposed = baseZoom * v
                            let clamped = min(max(proposed, minZoom), maxZoom)
                            if clamped != zoom { zoom = clamped }
                        }
                        .onEnded { v in
                            let proposed = baseZoom * v
                            baseZoom = min(max(proposed, minZoom), maxZoom)
                        }

                    let drag = DragGesture()
                        .onChanged { value in
                            guard zoom > 1.001 else { contentOffset = .zero; return }
                            contentOffset = CGSize(
                                width: baseOffset.width + value.translation.width,
                                height: baseOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in baseOffset = contentOffset }

                    OWLBoxOverlay(
                        image: img,
                        pixelSize: pixelSize,
                        detections: detections,
                        minScore: minScore,
                        showDebugFrame: false,
                        fillContainer: true
                    )
                    .frame(width: fitW, height: fitH)
                    .scaleEffect(zoom)
                    .offset(contentOffset)
                    .contentShape(Rectangle())
                    .gesture(drag.simultaneously(with: magnify))
                    .onTapGesture(count: 2) {
                        onDoubleTap()
                    }
                    .position(x: container.width/2, y: container.height/2)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.9))
                        .overlay(
                            VStack(spacing: 10) {
                                Image(systemName: "photo")
                                    .font(.system(size: 42, weight: .semibold))
                                    .foregroundColor(.gray)
                                Text("No photos yet")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                Text("Tap 'Add Photo' to capture images")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                        )
                        .padding(.horizontal, 6)
                        .padding(.vertical, 6)
                }

                if isBusy {
                    ProgressView().scaleEffect(1.2)
                        .padding()
                        .background(.thinMaterial, in: Capsule())
                        .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                }
            }
        }
    }
}

// MARK: - FullscreenImageView

struct FullscreenImageView: View {
    let image: UIImage?
    let pixelSize: CGSize
    let detections: [OWLDetection]
    let minScore: Double

    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1.0
    @State private var baseZoom: CGFloat = 1.0
    @State private var contentOffset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            if let _ = image, pixelSize != .zero {
                DetectionViewport(
                    image: image,
                    pixelSize: pixelSize,
                    detections: detections,
                    minScore: minScore,
                    isBusy: false,
                    zoom: $zoom,
                    baseZoom: $baseZoom,
                    contentOffset: $contentOffset,
                    baseOffset: $baseOffset,
                    onDoubleTap: {
                        dismiss()
                    }
                )
                .padding()
            } else {
                Text("No image")
                    .foregroundColor(.white)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.9))
                    .padding()
            }
        }
    }
}

// MARK: - FullscreenLiveTextView

struct FullscreenLiveTextView: View {
    let filterQuery: String
    let matchMode: MatchMode
    let showPerWord: Bool

    @Environment(\.dismiss) private var dismiss
    
    // Add this to ensure proper lifecycle
    @State private var isViewReady = false

    @State private var zoom: CGFloat = 1.0
    @State private var baseZoom: CGFloat = 1.0
    @State private var contentOffset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            GeometryReader { geo in
                let magnify = MagnificationGesture()
                    .onChanged { v in
                        let proposed = baseZoom * v
                        let clamped = min(max(proposed, 1.0), 4.0)
                        if clamped != zoom { zoom = clamped }
                    }
                    .onEnded { v in
                        let proposed = baseZoom * v
                        baseZoom = min(max(proposed, 1.0), 4.0)
                    }

                let drag = DragGesture()
                    .onChanged { value in
                        guard zoom > 1.001 else { contentOffset = .zero; return }
                        contentOffset = CGSize(
                            width: baseOffset.width + value.translation.width,
                            height: baseOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in baseOffset = contentOffset }
                
                if isViewReady {
                    LiveTextPreviewView(
                        filterQuery: filterQuery,
                        matchMode: matchMode,
                        showPerWord: showPerWord,
                        clipCorners: false,
                        cameraZoom: zoom  // ⬅️ NEW: Pass zoom to camera
                    )
                        .scaleEffect(zoom)
                        .offset(contentOffset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .gesture(drag.simultaneously(with: magnify))
                        .onTapGesture(count: 2) {
                            dismiss()
                        }
                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                } else {
                    // Show loading state while camera initializes
                    VStack {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                        Text("Initializing camera...")
                            .foregroundColor(.white)
                            .padding(.top, 8)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .onAppear {
                // Small delay to ensure proper camera initialization
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    isViewReady = true
                }
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white.opacity(0.9))
                    .padding()
            }
        }
    }
}
// MARK: - Tiny button helper

private extension Button where Label == HStack<TupleView<(Image, Text)>> {
    init(systemImage: String, title: String, action: @escaping () -> Void) {
        self.init(action: action) {
            HStack { Image(systemName: systemImage); Text(title) }
        }
    }
}

extension View {
    @ViewBuilder
    func seeklensScrollModifiers() -> some View {
        if #available(iOS 16.0, *) {
            self
                .scrollIndicators(.visible)
                .scrollDismissesKeyboard(.interactively)
        } else {
            self
        }
    }
}
