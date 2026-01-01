//
//  Untitled.swift
//  Findly
//
//  Created by Lingling on 9/1/25.
//

import CoreGraphics

struct APIDetection: Codable {
    let label: String
    let score: Double
    let box: [CGFloat]
}

struct OWLResponse: Codable {
    let width: Int
    let height: Int
    let detections: [APIDetection]
}
