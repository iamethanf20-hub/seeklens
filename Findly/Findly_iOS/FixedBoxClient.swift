//
//  FixedBoxClient.swift
//  Findly
//
//  Created by Lingling on 9/25/25.
//

import UIKit

struct FixedBoxResponse: Decodable {
    struct ImageSize: Decodable { let width: Int; let height: Int }
    struct Box: Decodable { let x: Int; let y: Int; let w: Int; let h: Int; let score: Double; let label: String }
    let image_size: ImageSize
    let boxes: [Box]
}

final class FixedBoxClient {
    static let shared = FixedBoxClient()
    private let baseURL = URL(string: "https://findlyapp-b83j.onrender.com")!

    func fixedBox(image: UIImage) async throws -> FixedBoxResponse {
        var comps = URLComponents(url: baseURL.appendingPathComponent("debug/fixed_box"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [URLQueryItem(name: "return_json", value: "true")]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "POST"

        let boundary = "----fixedbox-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        guard let jpg = image.jpegData(compressionQuality: 0.9) else {
            throw OWLError.server("JPEG encode failed")
        }

        var body = Data()
        func append(_ s: String) { body.append(s.data(using: .utf8)!) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"photo.jpg\"\r\n")
        append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpg)
        append("\r\n--\(boundary)--\r\n")

        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP error"
            throw OWLError.server(msg)
        }
        return try JSONDecoder().decode(FixedBoxResponse.self, from: data)
    }
}

private extension Data { mutating func append(_ s: String) { append(s.data(using: .utf8)!) } }
