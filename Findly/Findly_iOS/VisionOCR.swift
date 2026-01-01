//  VisionTextOCR.swift
//  Findly

import Vision
import UIKit

public struct VisionTextBox: Identifiable, Sendable {
    public let id = UUID()
    public let text: String
    public let conf: Float
    public let box: [Int]
    public init(text: String, conf: Float, box: [Int]) {
        self.text = text; self.conf = conf; self.box = box
    }
}

public enum VisionTextMatchMode: String, Sendable {
    case contains = "contains"
    case exact = "exact"
}

public struct VisionTextOptions: Sendable {
    public var languages: [String] = ["en-US"]
    public var recognitionAccurate = true
    public var useLanguageCorrection = false
    public var minTextHeight: Float = 0.015      // normalized 0..1
    public var regionOfInterest: CGRect? = nil   // normalized ROI
    public var perWord = false
    public var words: [String] = []
    public var matchMode: VisionTextMatchMode = .contains
    public init() {}
}

// MARK: - file-private helpers

fileprivate func rectInPixels(_ r: CGRect, imageSize: CGSize) -> CGRect {
    let w = r.width * imageSize.width
    let h = r.height * imageSize.height
    let x = r.minX * imageSize.width
    let y = (1.0 - r.minY - r.height) * imageSize.height
    return CGRect(x: x, y: y, width: w, height: h)
}

fileprivate func cgOrientation(from ui: UIImage.Orientation) -> CGImagePropertyOrientation {
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

fileprivate func matches(_ text: String, words: [String], mode: VisionTextMatchMode) -> Bool {
    guard !words.isEmpty else { return true }
    switch mode {
    case .exact:
        return words.contains { $0.caseInsensitiveCompare(text) == .orderedSame }
    case .contains:
        let low = text.lowercased()
        return words.contains { low.contains($0.lowercased()) }
    }
}

// MARK: - Public API

public enum VisionTextOCR {
    public static func recognize(
        _ image: UIImage,
        options: VisionTextOptions = .init()
    ) async throws -> [VisionTextBox] {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do { cont.resume(returning: try recognizeSync(image, options: options)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    private static func recognizeSync(
        _ uiImage: UIImage,
        options: VisionTextOptions
    ) throws -> [VisionTextBox] {
        guard let cg = uiImage.cgImage else { return [] }

        let handler = VNImageRequestHandler(
            cgImage: cg,
            orientation: cgOrientation(from: uiImage.imageOrientation),
            options: [:]
        )
        let req = VNRecognizeTextRequest()
        req.recognitionLevel = options.recognitionAccurate ? .accurate : .fast
        req.usesLanguageCorrection = options.useLanguageCorrection
        req.recognitionLanguages = options.languages
        // ✅ Your SDK expects Float here:
        req.minimumTextHeight = options.minTextHeight
        if let roi = options.regionOfInterest { req.regionOfInterest = roi }
        if #available(iOS 15.0, *) {
            if !options.words.isEmpty { req.customWords = options.words }
        }

        try handler.perform([req])
        
        let observations = req.results ?? []
        let imgSize = CGSize(width: cg.width, height: cg.height)
        var out: [VisionTextBox] = []

        for obs in observations {
            guard let cand = obs.topCandidates(1).first else { continue }
            let lineText = cand.string
            let conf = cand.confidence
            guard conf >= 0.15 else { continue }   // ✅ Added threshold filter

            if options.perWord {
                lineText.enumerateSubstrings(
                    in: lineText.startIndex..<lineText.endIndex,
                    options: .byWords
                ) { (word, rng, _, _) in
                    // word is Optional<String>, rng is Range<String.Index> (non-optional)
                    guard let word = word,
                          let rectObs = try? cand.boundingBox(for: rng) else { return }

                    guard matches(word, words: options.words, mode: options.matchMode) else { return }

                    let r = rectInPixels(rectObs.boundingBox, imageSize: imgSize)
                    out.append(VisionTextBox(
                        text: word,
                        conf: conf,
                        box: [Int(r.minX.rounded()), Int(r.minY.rounded()),
                              Int(r.width.rounded()), Int(r.height.rounded())]
                    ))
                }
            } else {
                // unchanged line-level path
                guard matches(lineText, words: options.words, mode: options.matchMode) else { continue }
                let r = rectInPixels(obs.boundingBox, imageSize: imgSize)
                out.append(VisionTextBox(
                    text: lineText, conf: conf,
                    box: [Int(r.minX.rounded()), Int(r.minY.rounded()),
                          Int(r.width.rounded()), Int(r.height.rounded())]
                ))
            }

        }
        return out
    }
}
