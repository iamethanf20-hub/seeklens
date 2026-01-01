//  OWLBoxOverlay.swift
//  Findly
//
//  Created by Lingling on 9/2/25.
//

import SwiftUI

struct OWLDetection: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let score: CGFloat     // 0..1
    let box: [CGFloat]     // [x, y, w, h] in *pixel* space of the source image
}

// MARK: - Arrow primitives

/// Straight shaft from start -> end.
struct ArrowShaftShape: Shape {
    var start: CGPoint
    var end: CGPoint
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: start)
        p.addLine(to: end)
        return p
    }
}

/// Filled triangular arrowhead at `end`, oriented along vector (start->end).
struct ArrowHeadShape: Shape {
    var start: CGPoint
    var end: CGPoint
    var headLength: CGFloat = 14
    var headWidth: CGFloat = 12
    func path(in rect: CGRect) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let len = max(1, hypot(dx, dy))
        let ux = dx / len, uy = dy / len
        let px = -uy, py = ux
        let bx = end.x - ux * headLength
        let by = end.y - uy * headLength
        let left  = CGPoint(x: bx + px * (headWidth / 2), y: by + py * (headWidth / 2))
        let right = CGPoint(x: bx - px * (headWidth / 2), y: by - py * (headWidth / 2))
        var p = Path()
        p.move(to: end)
        p.addLine(to: left)
        p.addLine(to: right)
        p.closeSubpath()
        return p
    }
}

// MARK: - Overlay

struct OWLBoxOverlay: View {
    let image: UIImage
    let pixelSize: CGSize
    let detections: [OWLDetection]
    var minScore: Double = 0.15
    var showDebugFrame: Bool = false
    var showArrows: Bool = true
    var fillContainer: Bool = true

    /// How much larger boxes should appear (1.1 = 10% bigger)
    var boxScale: CGFloat = 1.1

    var body: some View {
        GeometryReader { geo in
            let container = geo.size

            // Compute drawn rect for the image (fill or aspect-fit)
            let drawnRect: CGRect = {
                if fillContainer {
                    return CGRect(origin: .zero, size: container)
                } else {
                    let scale = min(
                        container.width  / max(pixelSize.width,  1),
                        container.height / max(pixelSize.height, 1)
                    )
                    let w = pixelSize.width  * scale
                    let h = pixelSize.height * scale
                    return CGRect(
                        x: (container.width  - w) / 2,
                        y: (container.height - h) / 2,
                        width: w, height: h
                    )
                }
            }()

            let sx = drawnRect.width  / max(pixelSize.width,  1) // pixels -> displayed points (x)
            let sy = drawnRect.height / max(pixelSize.height, 1) // pixels -> displayed points (y)

            ZStack(alignment: .topLeading) {
                // Image
                Image(uiImage: image)
                    .resizable()
                    .frame(width: drawnRect.width, height: drawnRect.height)
                    .clipped()
                    .position(x: drawnRect.midX, y: drawnRect.midY)

                if showDebugFrame {
                    Rectangle()
                        .stroke(.orange, style: StrokeStyle(lineWidth: 1, dash: [4,4]))
                        .frame(width: drawnRect.width, height: drawnRect.height)
                        .position(x: drawnRect.midX, y: drawnRect.midY)
                }

                ForEach(detections.filter { $0.score >= minScore }) { d in
                    if d.box.count == 4 {
                        // Original (pixel-space) rect
                        let rPx = CGRect(x: d.box[0], y: d.box[1], width: d.box[2], height: d.box[3])

                        // Base displayed rect (before scaling)
                        let baseDisp = CGRect(
                            x: drawnRect.minX + rPx.minX * sx,
                            y: drawnRect.minY + rPx.minY * sy,
                            width:  rPx.width  * sx,
                            height: rPx.height * sy
                        )

                        // Enlarged rect around center (pure expression, no mutation)
                        let dw = baseDisp.width  * (boxScale - 1)
                        let dh = baseDisp.height * (boxScale - 1)
                        let disp = baseDisp.insetBy(dx: -dw / 2, dy: -dh / 2)

                        // --- Box ---
                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.orange.opacity(0.20))
                                .frame(width: disp.width, height: disp.height)
                                .position(x: disp.midX, y: disp.midY)

                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.orange, lineWidth: 1)
                                .frame(width: disp.width, height: disp.height)
                                .position(x: disp.midX, y: disp.midY)
                        }

                        // --- Arrow (solid red, angled; straight near borders) ---
                        if showArrows {
                            let arrowEnd = CGPoint(x: disp.midX, y: disp.minY)

                            // Distances to borders around arrow end (within drawn image area)
                            let spaceLeft  = arrowEnd.x - drawnRect.minX
                            let spaceRight = drawnRect.maxX - arrowEnd.x
                            let spaceAbove = arrowEnd.y - drawnRect.minY

                            let start: CGPoint = {
                                let borderMargin: CGFloat = 24
                                let isNearBorder =
                                    spaceLeft  < borderMargin ||
                                    spaceRight < borderMargin ||
                                    spaceAbove < borderMargin

                                // Shorter arrows: reduced from 42/36 to 24/20
                                let maxHoriz: CGFloat = 24
                                let maxVert: CGFloat  = 20

                                if isNearBorder {
                                    // Straight vertical up, clamped inside drawnRect
                                    let dy = min(maxVert, max(6, spaceAbove - 6))
                                    return CGPoint(x: arrowEnd.x, y: arrowEnd.y - dy)
                                } else {
                                    // Angled: toward side with more space, but shorter
                                    let goRight = spaceRight >= spaceLeft
                                    let dx = min(maxHoriz, (goRight ? spaceRight : spaceLeft) - 12)
                                    let dy = min(maxVert, spaceAbove - 12)
                                    let rawX = arrowEnd.x + (goRight ? dx : -dx)
                                    let clampedX = min(max(drawnRect.minX + 8, rawX), drawnRect.maxX - 8)
                                    let clampedY = max(drawnRect.minY + 8, arrowEnd.y - dy)
                                    return CGPoint(x: clampedX, y: clampedY)
                                }
                            }()

                            ArrowShaftShape(start: start, end: arrowEnd)
                                .stroke(Color.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))

                            ArrowHeadShape(start: start, end: arrowEnd, headLength: 14, headWidth: 12)
                                .fill(Color.red)
                        }
                    }
                }
            }
        }
        .contentShape(Rectangle())
    }
}
