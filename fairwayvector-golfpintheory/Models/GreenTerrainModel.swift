import Foundation
import SwiftUI
import simd

/// The green plus a strip of fringe as a 3D surface from the 1 m elevation model, heights exaggerated.
/// Local metres around the green's centre: x east, y up, z south.
struct GreenTerrainModel {
    static let exaggeration: Float = 3
    static let margin = 6.0
    static let contourInterval = 0.05
    static let fringeContourInterval = 0.25

    let slope: GreenSlopeMap
    let origin: GeoPoint
    let columns: Int
    let rows: Int
    let spacing: Double
    /// East/north metres of grid point (0, 0), the south-west corner.
    let minX: Double
    let minY: Double
    /// True heights in metres above the lowest grid point, row-major from the south-west corner.
    let heights: [Double]

    var width: Double { Double(columns - 1) * spacing }
    var depth: Double { Double(rows - 1) * spacing }

    static func make(terrain: CourseTerrain, hole: Hole) -> GreenTerrainModel? {
        guard let slope = GreenSlopeMap.make(terrain: terrain, hole: hole),
              let origin = GolfGeometry.centroid(of: slope.region) else { return nil }
        let local = slope.region.map { TerrainGeometry.vector($0, from: origin) }
        let minX = local.map(\.x).min()! - margin, maxX = local.map(\.x).max()! + margin
        let minY = local.map(\.y).min()! - margin, maxY = local.map(\.y).max()! + margin
        let spacing = max(0.5, max(maxX - minX, maxY - minY) / 150)
        let columns = Int(((maxX - minX) / spacing).rounded(.up)) + 1
        let rows = Int(((maxY - minY) / spacing).rounded(.up)) + 1

        var raw = [Double](repeating: 0, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let point = GreenSlopeMap.unproject(SIMD2(minX + Double(column) * spacing, minY + Double(row) * spacing),
                                                    origin: origin)
                guard let z = terrain.sample(at: point)?.elevation else { return nil }
                raw[row * columns + column] = z
            }
        }
        // Two 3 × 3 passes hide centimetre noise that the exaggeration would turn into bumps.
        var smooth = raw
        for _ in 0..<2 {
            let source = smooth
            for row in 0..<rows {
                for column in 0..<columns {
                    var sum = 0.0, count = 0.0
                    for r in max(0, row - 1)...min(rows - 1, row + 1) {
                        for c in max(0, column - 1)...min(columns - 1, column + 1) {
                            sum += source[r * columns + c]; count += 1
                        }
                    }
                    smooth[row * columns + column] = sum / count
                }
            }
        }
        let lowest = smooth.min() ?? 0
        return GreenTerrainModel(slope: slope, origin: origin, columns: columns, rows: rows, spacing: spacing,
                                 minX: minX, minY: minY, heights: smooth.map { $0 - lowest })
    }

    func local(_ point: GeoPoint) -> SIMD2<Double> { TerrainGeometry.vector(point, from: origin) }

    /// Bilinear true height at local east/north metres; nil outside the grid.
    func height(atLocal p: SIMD2<Double>) -> Double? {
        let fx = (p.x - minX) / spacing, fy = (p.y - minY) / spacing
        guard fx >= 0, fy >= 0, fx <= Double(columns - 1), fy <= Double(rows - 1) else { return nil }
        let c0 = min(Int(fx), columns - 2), r0 = min(Int(fy), rows - 2)
        let tx = fx - Double(c0), ty = fy - Double(r0)
        func h(_ c: Int, _ r: Int) -> Double { heights[r * columns + c] }
        let south = h(c0, r0) + (h(c0 + 1, r0) - h(c0, r0)) * tx
        let north = h(c0, r0 + 1) + (h(c0 + 1, r0 + 1) - h(c0, r0 + 1)) * tx
        return south + (north - south) * ty
    }

    /// Scene position on the exaggerated surface.
    func surfacePoint(_ point: GeoPoint) -> SIMD3<Float>? {
        let p = local(point)
        guard let h = height(atLocal: p) else { return nil }
        return SIMD3(Float(p.x), Float(h) * Self.exaggeration, Float(-p.y))
    }

    var positions: [SIMD3<Float>] {
        (0..<rows).flatMap { row in
            (0..<columns).map { column in
                SIMD3(Float(minX + Double(column) * spacing), Float(heights[row * columns + column]) * Self.exaggeration,
                      Float(-(minY + Double(row) * spacing)))
            }
        }
    }

    var normals: [SIMD3<Float>] {
        (0..<rows).flatMap { row in
            (0..<columns).map { column in
                func h(_ c: Int, _ r: Int) -> Float {
                    Float(heights[min(max(r, 0), rows - 1) * columns + min(max(c, 0), columns - 1)]) * Self.exaggeration
                }
                let dx = (h(column + 1, row) - h(column - 1, row)) / Float(2 * spacing)
                let dNorth = (h(column, row + 1) - h(column, row - 1)) / Float(2 * spacing)
                // z points south, so the z slope is the negated north slope.
                return simd_normalize(SIMD3(-dx, 1, dNorth))
            }
        }
    }

    /// Texture coordinates with v increasing northward, matching an image drawn north-up.
    var textureCoordinates: [SIMD2<Float>] {
        (0..<rows).flatMap { row in
            (0..<columns).map { column in
                SIMD2(Float(column) / Float(columns - 1), Float(row) / Float(rows - 1))
            }
        }
    }

    /// Two counter-clockwise triangles per grid cell, facing up.
    var indices: [UInt32] {
        var result: [UInt32] = []
        result.reserveCapacity((columns - 1) * (rows - 1) * 6)
        for row in 0..<(rows - 1) {
            for column in 0..<(columns - 1) {
                let a = UInt32(row * columns + column), b = a + 1
                let c = a + UInt32(columns), d = c + 1
                result += [a, b, c, b, d, c]
            }
        }
        return result
    }

    /// Contour segments every `interval` metres of true height, in local east/north metres.
    func contours(every interval: Double = contourInterval) -> [(SIMD2<Double>, SIMD2<Double>)] {
        var segments: [(SIMD2<Double>, SIMD2<Double>)] = []
        func point(_ c: Int, _ r: Int) -> SIMD2<Double> { SIMD2(minX + Double(c) * spacing, minY + Double(r) * spacing) }
        for row in 0..<(rows - 1) {
            for column in 0..<(columns - 1) {
                let corners = [(column, row), (column + 1, row), (column + 1, row + 1), (column, row + 1)]
                let values = corners.map { heights[$0.1 * columns + $0.0] }
                guard let low = values.min(), let high = values.max() else { continue }
                var level = (low / interval).rounded(.up) * interval
                while level < high {
                    var crossings: [SIMD2<Double>] = []
                    for edge in 0..<4 {
                        let a = values[edge], b = values[(edge + 1) % 4]
                        guard (a < level) != (b < level) else { continue }
                        let t = (level - a) / (b - a)
                        let p = point(corners[edge].0, corners[edge].1), q = point(corners[(edge + 1) % 4].0, corners[(edge + 1) % 4].1)
                        crossings.append(p + (q - p) * t)
                    }
                    if crossings.count >= 2 { segments.append((crossings[0], crossings[1])) }
                    if crossings.count == 4 { segments.append((crossings[2], crossings[3])) }
                    level += interval
                }
            }
        }
        return segments
    }

    /// Fringe colour, slope heatmap with downhill arrows, contours and the green's outline, drawn north-up.
    func texture(pointsPerMeter: Double = 10) -> CGImage? {
        let size = CGSize(width: width * pointsPerMeter, height: depth * pointsPerMeter)
        let toCanvas = { (p: SIMD2<Double>) in
            CGPoint(x: (p.x - minX) * pointsPerMeter, y: (minY + depth - p.y) * pointsPerMeter)
        }
        let canvas = Canvas { context, _ in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.36, green: 0.47, blue: 0.33)))
            slope.draw(in: &context) { toCanvas(local($0)) }
            func path(_ segments: [(SIMD2<Double>, SIMD2<Double>)]) -> Path {
                var lines = Path()
                for (a, b) in segments {
                    lines.move(to: toCanvas(a)); lines.addLine(to: toCanvas(b))
                }
                return lines
            }
            var outline = Path()
            outline.addLines(slope.region.map { toCanvas(local($0)) })
            outline.closeSubpath()
            context.stroke(path(contours(every: Self.fringeContourInterval)), with: .color(.white.opacity(0.3)), lineWidth: 0.6)
            var green = context
            green.clip(to: outline)
            green.stroke(path(contours()), with: .color(.white.opacity(0.45)), lineWidth: 0.6)
            context.stroke(outline, with: .color(.white.opacity(0.9)), lineWidth: 1.5)
        }
        .frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 2
        return renderer.cgImage
    }
}
