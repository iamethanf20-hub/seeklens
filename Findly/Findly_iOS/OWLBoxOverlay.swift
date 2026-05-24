//  OWLBoxOverlay.swift
//  Findly

import SwiftUI

struct OWLDetection: Identifiable, Hashable {
    let id = UUID()
    let label: String
    let score: CGFloat
    let box: [CGFloat]     // [x, y, w, h] in pixel space of the image you display
}

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

struct OWLBoxOverlay: View {
    let image: UIImage                 // MUST be the normalized image returned by OWLClient.detect
    let pixelSize: CGSize              // server-reported width/height
    let detections: [OWLDetection]
    var minScore: Double = 0.15
    var showDebugFrame: Bool = false
    var showArrows: Bool = true
    var fillContainer: Bool = true     // kept for API compatibility
    var boxScale: CGFloat = 1.1

    var body: some View {
        GeometryReader { geo in
            let container = geo.size

            // Aspect-FILL math: scale by max so image covers the container; crop overflow.
            // Aspect-FIT math: scale by min so image fits inside; letterbox the slack.
            let fitScale = min(
                container.width  / max(pixelSize.width,  1),
                container.height / max(pixelSize.height, 1)
            )
            let fillScale = max(
                container.width  / max(pixelSize.width,  1),
                container.height / max(pixelSize.height, 1)
            )
            let scale = fillContainer ? fillScale : fitScale

            // The full scaled image rect, before clipping. With fill, this is
            // bigger than the container on one axis; with fit, smaller on one axis.
            let scaledW = pixelSize.width  * scale
            let scaledH = pixelSize.height * scale
            let imageRect = CGRect(
                x: (container.width  - scaledW) / 2,
                y: (container.height - scaledH) / 2,
                width: scaledW, height: scaledH
            )

            // The visible region (what's actually on screen). With fill, this
            // equals the container; with fit, it equals imageRect.
            let visibleRect = fillContainer
                ? CGRect(origin: .zero, size: container)
                : imageRect

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: fillContainer ? .fill : .fit)
                    .frame(width: container.width, height: container.height)
                    .clipped()

                if showDebugFrame {
                    Rectangle()
                        .stroke(.orange, style: StrokeStyle(lineWidth: 1, dash: [4,4]))
                        .frame(width: visibleRect.width, height: visibleRect.height)
                        .position(x: visibleRect.midX, y: visibleRect.midY)
                }

                ForEach(detections.filter { $0.score >= minScore }) { d in
                    if d.box.count == 4 {
                        let rPx = CGRect(x: d.box[0], y: d.box[1], width: d.box[2], height: d.box[3])

                        // Map pixel-space box -> screen-space using the SAME transform
                        // as the displayed image: scale uniformly, then offset by
                        // imageRect.origin (which is negative on the cropped axis
                        // when filling, so off-screen pixels map off-screen).
                        let baseDisp = CGRect(
                            x: imageRect.minX + rPx.minX * scale,
                            y: imageRect.minY + rPx.minY * scale,
                            width:  rPx.width  * scale,
                            height: rPx.height * scale
                        )

                        let dw = baseDisp.width  * (boxScale - 1)
                        let dh = baseDisp.height * (boxScale - 1)
                        let disp = baseDisp.insetBy(dx: -dw / 2, dy: -dh / 2)

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

                        if showArrows {
                            let arrowEnd = CGPoint(x: disp.midX, y: disp.minY)
                            let spaceLeft  = arrowEnd.x - visibleRect.minX
                            let spaceRight = visibleRect.maxX - arrowEnd.x
                            let spaceAbove = arrowEnd.y - visibleRect.minY

                            let start: CGPoint = {
                                let borderMargin: CGFloat = 24
                                let isNearBorder =
                                    spaceLeft  < borderMargin ||
                                    spaceRight < borderMargin ||
                                    spaceAbove < borderMargin

                                let maxHoriz: CGFloat = 24
                                let maxVert: CGFloat  = 20

                                if isNearBorder {
                                    let dy = min(maxVert, max(6, spaceAbove - 6))
                                    return CGPoint(x: arrowEnd.x, y: arrowEnd.y - dy)
                                } else {
                                    let goRight = spaceRight >= spaceLeft
                                    let dx = min(maxHoriz, (goRight ? spaceRight : spaceLeft) - 12)
                                    let dy = min(maxVert, spaceAbove - 12)
                                    let rawX = arrowEnd.x + (goRight ? dx : -dx)
                                    let clampedX = min(max(visibleRect.minX + 8, rawX), visibleRect.maxX - 8)
                                    let clampedY = max(visibleRect.minY + 8, arrowEnd.y - dy)
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
            .frame(width: container.width, height: container.height)
            .clipped()
        }
        .contentShape(Rectangle())
    }
}
