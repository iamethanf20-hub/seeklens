//  OWLClient.swift
//  Findly
//
//  Created by Lingling on 9/1/25.
//

import UIKit

enum OWLError: Error, LocalizedError {
    case server(String)
    var errorDescription: String? {
        switch self { case .server(let m): return m }
    }
}

final class OWLClient {
    static let shared = OWLClient()
    private let baseURL = URL(string: "https://findlyapp-b83j.onrender.com")!

    func detect(image: UIImage, query: String, threshold: Double = 0.15) async throws -> OWLResponse {
        let url = baseURL.appendingPathComponent("detect")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"

        let boundary = "----owlv2-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let jpg = image.jpegData(compressionQuality: 0.9) else {
            throw OWLError.server("JPEG encode failed")
        }

        var body = Data()

        // query
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"query\"\r\n\r\n")
        body.append(query)
        body.append("\r\n")

        // threshold
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"threshold\"\r\n\r\n")
        body.append(String(0.15))        // ✅ hard-set threshold to 0.15
        body.append("\r\n")

        // image
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
        return try JSONDecoder().decode(OWLResponse.self, from: data)
    }
}

private extension Data {
    mutating func append(_ s: String) { append(s.data(using: .utf8)!) }
}
