import SwiftUI
import AVFoundation
import Vision

// MARK: - Thread-safe date wrapper

final class ThreadSafeDate: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date.distantPast
    
    func get() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
    
    func set(_ newValue: Date) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
    }
}

// MARK: - Model

struct LiveTextDetection: Identifiable {
    let id = UUID()
    let text: String
    /// Normalized bounding box (Vision coordinates, origin bottom-left, 0–1)
    let boundingBox: CGRect
    let confidence: Float
    /// Original VNRecognizedTextObservation for getting word-level bounding boxes
    let observation: VNRecognizedTextObservation?
    let candidate: VNRecognizedText?

    func rect(in size: CGSize) -> CGRect {
        let w = boundingBox.width * size.width
        let h = boundingBox.height * size.height
        let x = boundingBox.minX * size.width
        // Fix: Vision uses bottom-left origin, SwiftUI uses top-left
        // Convert by using minY instead of maxY for proper alignment
        let y = (1.0 - boundingBox.minY - boundingBox.height) * size.height
        return CGRect(x: x, y: y, width: w, height: h)
    }
}

// MARK: - Capture + OCR manager

@MainActor
final class LiveTextPreviewManager: NSObject, ObservableObject {
    @Published var detections: [LiveTextDetection] = []
    @Published var errorMessage: String?
    @Published var isSessionRunning = false
    @Published var currentZoomFactor: CGFloat = 1.0  // ⬅️ NEW: Track current zoom
    
    nonisolated let session = AVCaptureSession()
    private var captureDevice: AVCaptureDevice?  // ⬅️ NEW: Store device reference
    private let maxZoomFactor: CGFloat = 4.0  // ⬅️ NEW: Max zoom limit
    
    private let queue = DispatchQueue(label: "LiveTextPreviewManager.queue")
    private let lastRequestTime = ThreadSafeDate()
    private let requestInterval: TimeInterval = 0.3   // 3x per second for better responsiveness
    
    override init() {
        super.init()
    }
    
    func setup() {
        Task.detached { [weak self] in
            await self?.configureSession()
        }
    }
    
    // ⬅️ NEW: Method to set camera zoom
    func setZoom(_ factor: CGFloat) {
        guard let device = captureDevice else {
            print("⚠️ No capture device available for zoom")
            return
        }
        
        // Clamp zoom factor between 1.0 and min(maxZoomFactor, device's max)
        let deviceMax = device.activeFormat.videoMaxZoomFactor
        let clampedFactor = min(max(factor, 1.0), min(maxZoomFactor, deviceMax))
        
        print("📸 Setting zoom to \(clampedFactor) (requested: \(factor), device max: \(deviceMax))")
        
        do {
            try device.lockForConfiguration()
            
            // Use smooth ramping for better user experience
            device.ramp(toVideoZoomFactor: clampedFactor, withRate: 4.0)
            
            device.unlockForConfiguration()
            
            Task { @MainActor [weak self] in
                self?.currentZoomFactor = clampedFactor
            }
        } catch {
            print("⚠️ Failed to set zoom: \(error)")
        }
    }
    
    nonisolated private func configureSession() async {
        print("📸 Starting camera configuration...")
        
        session.beginConfiguration()
        
        // Use photo preset for 4:3 aspect ratio that better matches screen
        session.sessionPreset = .photo
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera,
                                                   for: .video,
                                                   position: .back) else {
            print("⚠️ No camera device found")
            await updateError("Camera not available")
            session.commitConfiguration()
            return
        }
        
        print("📸 Found camera device: \(device.localizedName)")
        print("📸 Max zoom factor: \(device.activeFormat.videoMaxZoomFactor)")
        
        // ⬅️ NEW: Store device reference for zoom control
        await MainActor.run { [weak self] in
            self?.captureDevice = device
        }
        
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            print("⚠️ Failed to create camera input")
            await updateError("Failed to access camera")
            session.commitConfiguration()
            return
        }
        
        guard session.canAddInput(input) else {
            print("⚠️ Cannot add camera input to session")
            await updateError("Camera configuration failed")
            session.commitConfiguration()
            return
        }
        
        session.addInput(input)
        print("✅ Added camera input")
        
        // Configure camera for better text recognition
        do {
            try device.lockForConfiguration()
            
            // Enable auto-focus for text
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            
            // Enable auto-exposure for better lighting
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            
            // Enable auto white balance
            if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.whiteBalanceMode = .continuousAutoWhiteBalance
            }
            
            // ⬅️ NEW: Set initial zoom to 1.0
            device.videoZoomFactor = 1.0
            
            device.unlockForConfiguration()
            print("✅ Configured camera settings")
        } catch {
            print("⚠️ Failed to configure camera: \(error)")
        }
        
        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        
        // Use standard pixel format for better compatibility
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        output.setSampleBufferDelegate(self, queue: queue)
        
        guard session.canAddOutput(output) else {
            print("⚠️ Cannot add video output")
            await updateError("Failed to configure video output")
            session.commitConfiguration()
            return
        }
        session.addOutput(output)
        print("✅ Added video output")
        
        if let connection = output.connection(with: .video),
           connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
            print("✅ Set video orientation to portrait")
        }
        
        session.commitConfiguration()
        print("✅ Camera configuration complete")
    }
    
    nonisolated private func updateError(_ message: String) async {
        await MainActor.run { [weak self] in
            self?.errorMessage = message
        }
    }
    
    nonisolated func start() {
        print("▶️ Starting camera session...")
        queue.async { [weak self] in
            guard let self else { return }
            if !self.session.isRunning {
                self.session.startRunning()
                print("✅ Camera session started")
                Task { @MainActor [weak self] in
                    self?.isSessionRunning = true
                }
            }
        }
    }

    nonisolated func stop() {
        print("⏸️ Stopping camera session...")
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
                print("✅ Camera session stopped")
                Task { @MainActor [weak self] in
                    self?.isSessionRunning = false
                }
            }
        }
    }
}

extension LiveTextPreviewManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        // Check throttle using thread-safe wrapper
        let now = Date()
        let lastTime = lastRequestTime.get()
        guard now.timeIntervalSince(lastTime) >= requestInterval else { return }
        lastRequestTime.set(now)
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Extract metadata on background queue
        var options: [VNImageOption: Any] = [:]
        if let attachments = CMCopyDictionaryOfAttachments(allocator: kCFAllocatorDefault,
                                                           target: sampleBuffer,
                                                           attachmentMode: kCMAttachmentMode_ShouldPropagate) as? [CFString: Any] {
            options = attachments.reduce(into: [:]) { partialResult, pair in
                partialResult[VNImageOption(rawValue: pair.key as String)] = pair.value
            }
        }
        
        // Create and perform request entirely on background queue
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false  // Disable for better detection of short words/abbreviations
        request.recognitionLanguages = ["en-US"]
        request.minimumTextHeight = 0.003  // Much lower threshold for short words and smaller text
        
        // Enable automatic language detection for better accuracy (iOS 16+)
        if #available(iOS 16.0, *) {
            request.automaticallyDetectsLanguage = true
        }
        
        // Set revision to latest for best accuracy
        if #available(iOS 16.0, *) {
            request.revision = VNRecognizeTextRequestRevision3
        }
        
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: .up,
                                            options: options)
        
        // Perform on background queue (already on queue from delegate)
        do {
            try handler.perform([request])
            
            // Process results on background queue
            let observations = (request.results) ?? []
            let newDetections: [LiveTextDetection] = observations.compactMap { obs in
                guard let candidate = obs.topCandidates(1).first,
                      candidate.confidence >= 0.2 else { return nil }  // Lower threshold for better detection of short words
                return LiveTextDetection(text: candidate.string,
                                         boundingBox: obs.boundingBox,
                                         confidence: candidate.confidence,
                                         observation: obs,
                                         candidate: candidate)
            }
            
            // ONLY update UI on main thread
            Task { @MainActor [weak self] in
                self?.detections = newDetections
            }
        } catch {
            print("⚠️ Failed to perform text request: \(error)")
        }
    }
}

// MARK: - Camera preview wrapper

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        context.coordinator.previewLayer = layer
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
            context.coordinator.previewLayer?.session = session
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

// MARK: - SwiftUI live preview

struct LiveTextPreviewView: View {
    @StateObject private var manager = LiveTextPreviewManager()
    let filterQuery: String
    let matchMode: MatchMode
    let showPerWord: Bool
    var clipCorners: Bool = true
    var cameraZoom: CGFloat = 1.0  // ⬅️ NEW: Camera zoom parameter
    
    @State private var hasRequestedPermission = false
    
    private var filteredDetections: [LiveTextDetection] {
        let trimmedQuery = filterQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmedQuery.isEmpty else {
            return manager.detections
        }
        
        if showPerWord {
            // Hybrid approach: Try word-level first (fast), fall back to character-level (accurate)
            var wordDetections: [LiveTextDetection] = []
            
            for detection in manager.detections {
                let text = detection.text
                guard let candidate = detection.candidate else { continue }
                
                // Use Vision's word enumeration to get word ranges
                text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { word, range, _, _ in
                    guard let word = word else { return }
                    
                    let matches: Bool
                    switch matchMode {
                    case .exact:
                        matches = word.caseInsensitiveCompare(trimmedQuery) == .orderedSame
                    case .contains:
                        matches = word.lowercased().contains(trimmedQuery.lowercased())
                    }
                
                    if matches {
                        // For very short words (1-3 chars), skip word-level and go straight to character-level
                        // Word-level bounding boxes are often inaccurate for short words like "the", "a", "in", etc.
                        let useCharacterLevel = word.count <= 3
                        
                        if !useCharacterLevel {
                            // FAST PATH: Try word-level bounding box first (only for longer words)
                            if let wordBoxObs = try? candidate.boundingBox(for: range) {
                                let box = wordBoxObs.boundingBox
                                
                                // Strict validation for word-level boxes
                                let aspectRatio = box.width / box.height
                                let hasReasonableSize = box.width > 0.001 && box.height > 0.001
                                let hasReasonableAspect = aspectRatio > 0.5 && aspectRatio < 20
                                
                                if hasReasonableSize && hasReasonableAspect {
                                    // Word-level box looks good, add slight padding for better visual enclosure
                                    let padding: CGFloat = 0.02
                                    let paddedBox = CGRect(
                                        x: max(0, box.minX - padding),
                                        y: max(0, box.minY - padding),
                                        width: min(1.0 - max(0, box.minX - padding), box.width + (padding * 2)),
                                        height: box.height + (padding * 2)
                                    )
                                    
                                    wordDetections.append(LiveTextDetection(
                                        text: word,
                                        boundingBox: paddedBox,
                                        confidence: detection.confidence,
                                        observation: detection.observation,
                                        candidate: candidate
                                    ))
                                    return  // Success, skip character-level processing
                                }
                            }
                        }
                        
                        // CHARACTER-LEVEL PATH: For short words or when word-level fails
                        // Build tight bounding box from individual character boxes
                        var minX: CGFloat = 1.0
                        var minY: CGFloat = 1.0
                        var maxX: CGFloat = 0.0
                        var maxY: CGFloat = 0.0
                        var foundAnyChar = false
                        
                        // Get bounding box for each character in the word
                        var currentIndex = range.lowerBound
                        while currentIndex < range.upperBound {
                            let nextIndex = text.index(after: currentIndex)
                            let charRange = currentIndex..<nextIndex
                            
                            if let charBox = try? candidate.boundingBox(for: charRange) {
                                let box = charBox.boundingBox
                                minX = min(minX, box.minX)
                                minY = min(minY, box.minY)
                                maxX = max(maxX, box.maxX)
                                maxY = max(maxY, box.maxY)
                                foundAnyChar = true
                            }
                            
                            currentIndex = nextIndex
                        }
                        
                        // If we got character boxes, create a word detection from the union
                        if foundAnyChar {
                            let boxWidth = maxX - minX
                            let boxHeight = maxY - minY
                            
                            // Validate the character-level box isn't unreasonably large
                            // For short words, the box should be quite small
                            let maxReasonableWidth: CGFloat = word.count <= 2 ? 0.05 : 0.08
                            let maxReasonableHeight: CGFloat = 0.03
                            
                            // Also check aspect ratio - very short words shouldn't be too wide
                            let aspectRatio = boxWidth / boxHeight
                            let maxAspectRatio: CGFloat = word.count <= 2 ? 8.0 : 12.0
                            
                            guard boxWidth <= maxReasonableWidth,
                                  boxHeight <= maxReasonableHeight,
                                  aspectRatio <= maxAspectRatio else {
                                return  // Skip this detection - box is too large/malformed
                            }
                            
                            // Use smaller padding for short words to keep boxes tight
                            let padding: CGFloat = word.count <= 2 ? 0.015 : 0.02
                            let wordBox = CGRect(
                                x: max(0, minX - padding),
                                y: max(0, minY - padding),
                                width: min(1.0 - max(0, minX - padding), (maxX - minX) + (padding * 2)),
                                height: (maxY - minY) + (padding * 2)
                            )
                            
                            wordDetections.append(LiveTextDetection(
                                text: word,
                                boundingBox: wordBox,
                                confidence: detection.confidence,
                                observation: detection.observation,
                                candidate: candidate
                            ))
                        }
                    }
                }
            }
            
            return wordDetections
        } else {
            return manager.detections.filter { detection in
                switch matchMode {
                case .exact:
                    return detection.text.caseInsensitiveCompare(trimmedQuery) == .orderedSame
                case .contains:
                    return detection.text.lowercased().contains(trimmedQuery.lowercased())
                }
            }
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let errorMsg = manager.errorMessage {
                    // Show error message
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.yellow)
                        Text(errorMsg)
                            .font(.headline)
                            .foregroundColor(.white)
                            .multilineTextAlignment(.center)
                        Text("Check Settings → Privacy → Camera")
                            .font(.footnote)
                            .foregroundColor(.gray)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                } else {
                    CameraPreviewView(session: manager.session)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()

                    // Overlay for detections
                    let owlDetections: [OWLDetection] = filteredDetections.map { detection in
                        let rect = detection.rect(in: geometry.size)
                        return OWLDetection(
                            label: detection.text,
                            score: CGFloat(detection.confidence),
                            box: [rect.minX, rect.minY, rect.width, rect.height]
                        )
                    }
                    
                    let placeholderImage = UIImage()
                    
                    OWLBoxOverlay(
                        image: placeholderImage,
                        pixelSize: geometry.size,
                        detections: owlDetections,
                        minScore: 0.0,
                        showDebugFrame: false,
                        showArrows: true,
                        fillContainer: true,
                        boxScale: 1.0
                    )
                    
                    // Show status when camera is starting
                    if !manager.isSessionRunning && manager.errorMessage == nil {
                        VStack {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                            Text("Initializing camera...")
                                .foregroundColor(.white)
                                .padding(.top, 8)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.7))
                    }
                }
            }
        }
        .background(Color.black)
        .if(clipCorners) { view in
            view.clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        // ⬅️ NEW: Monitor zoom changes and update camera
        .onChange(of: cameraZoom) { newZoom in
            manager.setZoom(newZoom)
        }
        .onAppear {
            guard !hasRequestedPermission else { return }
            hasRequestedPermission = true
            
            print("🎬 LiveTextPreviewView appeared, requesting camera permission...")
            
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    print("📹 Camera permission granted: \(granted)")
                    if granted {
                        manager.setup()
                        // Give setup a moment to complete before starting
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            manager.start()
                        }
                    } else {
                        manager.errorMessage = "Camera access denied"
                    }
                }
            }
        }
        .onDisappear {
            print("👋 LiveTextPreviewView disappeared, stopping camera")
            manager.stop()
        }
    }
}

// ⬇️ Helper extension for conditional view modifiers
extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
