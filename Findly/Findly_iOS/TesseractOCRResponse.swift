//
//  TesseractOCRResponse.swift
//  Findly
//
//  Created by Lingling on 9/19/25.
//

import CoreGraphics
struct OCRBoxDetection: Decodable {
    let text: String
    let conf: Double
    let box: [Int]   // [x, y, w, h] in pixels (server returns ints after scaling)
}

struct OCRBoxesResponse: Decodable {
    let width: Int
    let height: Int
    let detections: [OCRBoxDetection]
}

