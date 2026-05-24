//  OWLClient.swift
//  Findly

import UIKit

enum OWLError: Error, LocalizedError {
    case server(String)
    var errorDescription: String? {
        switch self { case .server(let m): return m }
    }
}

extension UIImage {
    /// Returns a new UIImage with .up orientation by redrawing the bitmap.
    /// This guarantees pixel coordinates match what SwiftUI displays.
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(origin: .zero, size: size))
        return UIGraphicsGetImageFromCurrentImageContext() ?? self
    }
}

final class OWLClient {
    static let shared = OWLClient()
    private let baseURL = URL(string: "https://findlyapp-b83j.onrender.com")!

    /// Detect and return the response *plus* the normalized image whose pixel
    /// space matches the returned box coordinates. The caller MUST display this
    /// normalized image (not the original) so coordinates line up.
    func detect(image: UIImage, query: String, threshold: Double = 0.15) async throws -> (OWLResponse, UIImage) {
        // 1) Normalize orientation BEFORE encoding so server and client agree.
        let normalized = image.normalizedOrientation()

        let url = baseURL.appendingPathComponent("detect")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"

        let boundary = "----owlv2-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let jpg = normalized.jpegData(compressionQuality: 0.9) else {
            throw OWLError.server("JPEG encode failed")
        }

        var body = Data()

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"query\"\r\n\r\n")
        body.append(query)
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"threshold\"\r\n\r\n")
        body.append(String(threshold))
        body.append("\r\n")

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpg)
        body.append("\r\n")

        body.append("--\(boundary)--\r\n")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP error"
            throw OWLError.server(msg)
        }
        let decoded = try JSONDecoder().decode(OWLResponse.self, from: data)
        return (decoded, normalized)
    }
}

private extension Data {
    mutating func append(_ s: String) { append(s.data(using: .utf8)!) }
}
