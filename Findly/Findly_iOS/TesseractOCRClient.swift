//
//  TesseractOCRClient.swift
//  Findly
//
//  Created by Lingling on 9/19/25.
//

import Foundation
import UIKit

final class TesseractOCRClient {
    private let baseURL = URL(string: "https://findlyapp-b83j.onrender.com")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }
    
    func ocrBoxes(
        image: UIImage,
        lang: String = "eng",
        words: [String] = [],
        psm: Int = 8,
        oem: Int = 1,
        minConf: Double = 0.7,              // <-- changed: Double (0.0 ... 1.0)
        match: String = "contains"          // <-- optional: mirrors Colab flow
    ) async throws -> OCRBoxesResponse {

        // FIX 1: no leading slash here
        let url = baseURL.appendingPathComponent("ocr")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
            throw NSError(domain: "ocr.encode", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to JPEG-encode image"])
        }

        var body = Data()
        func append(_ string: String) { body.append(Data(string.utf8)) }

        // file field must be named EXACTLY "image"
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"frame.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpegData)
        append("\r\n")

        func addField(name: String, value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        addField(name: "lang", value: lang)
        if !words.isEmpty {
            addField(name: "words", value: words.joined(separator: ",")) // server expects comma-separated
        }
        addField(name: "psm", value: String(psm))
        addField(name: "oem", value: String(oem))
        addField(name: "boxes", value: "true")                 // word boxes mode
        addField(name: "min_conf", value: String(minConf))     // <-- Double in 0..1
        addField(name: "match", value: match)                  // "contains" or "exact"

        append("--\(boundary)--\r\n")

        request.httpBody = body
        request.timeoutInterval = 60

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            let msg = String(data: data, encoding: .utf8) ?? "No message"
            throw NSError(domain: "ocr.http", code: code, userInfo: [NSLocalizedDescriptionKey: "HTTP \(code): \(msg)"])
        }

        return try JSONDecoder().decode(OCRBoxesResponse.self, from: data)
    }
}

extension OCRBoxesResponse {
    /// Convert server [x,y,w,h] boxes into CGRects in **image pixel space**.
    var rectsInImageSpace: [CGRect] {
        detections.compactMap { det in
            guard det.box.count == 4 else { return nil }
            let x = CGFloat(det.box[0]), y = CGFloat(det.box[1])
            let w = CGFloat(det.box[2]), h = CGFloat(det.box[3])
            return CGRect(x: x, y: y, width: w, height: h)
        }
    }
}
