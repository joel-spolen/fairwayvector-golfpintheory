import Foundation
import SwiftUI

struct GreenSlopeLegend: View {
    let available: Bool
    var mappedOutline = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Green slope · experimental")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(PureLineStyle.ink)
            if available {
                LinearGradient(colors: stride(from: 0.0, through: 5, by: 1).map { GreenSlopeMap.color(forSlope: $0) },
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: 120, height: 8)
                    .clipShape(Capsule())
                HStack {
                    Text(verbatim: "0%")
                    Spacer()
                    Text(verbatim: "5%+")
                }
                .font(.caption2.monospacedDigit())
                .foregroundStyle(PureLineStyle.muted)
                .frame(width: 120)
                Text("Arrows point downhill")
                    .font(.caption2)
                    .foregroundStyle(PureLineStyle.muted)
                if mappedOutline {
                    Text(verbatim: "© OpenStreetMap contributors")
                        .font(.system(size: 9))
                        .foregroundStyle(PureLineStyle.muted)
                }
            } else {
                Text("No detailed elevation for this green")
                    .font(.caption2)
                    .foregroundStyle(PureLineStyle.muted)
                    .frame(maxWidth: 140, alignment: .leading)
            }
        }
        .padding(10)
        .background(PureLineStyle.canvas.opacity(0.95), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// Estimated green slope from the downloaded course elevation: steepness and downhill direction per cell.
struct GreenSlopeMap {
    struct Cell {
        let row: Int
        let column: Int
        let corners: [GeoPoint]
        let center: GeoPoint
        let slopePercent: Double
        /// Unit vector (east, north) pointing downhill.
        let downhill: SIMD2<Double>
    }

    let cells: [Cell]
    let region: [GeoPoint]
    /// True when the region is a mapped OpenStreetMap outline rather than an estimated oval.
    let usesMappedOutline: Bool
    /// `region(for:)` when made; a changed value means the hole's outline changed and the map is stale.
    var basis: [GeoPoint]? = nil

    static let cellSize = 1.5
    /// Plane-fit radius; the 1 m grid is too noisy for slopes over a single metre.
    static let fitRadius = 2.5

    /// The server reports 1 m grid spacing for every tile, even when GPXZ samples ~30 m data,
    /// so detail is judged by source: only Lantmäteriet's 1 m model is fine enough for a green.
    static func hasDetailedSource(_ provenance: TerrainProvenance) -> Bool {
        let source = provenance.dataSource.lowercased()
        return source.contains("lantmateriet") || provenance.dataSource == DevelopmentAPIConfiguration.syntheticSource
    }

    static func make(terrain: CourseTerrain, hole: Hole) -> GreenSlopeMap? {
        guard let anchor = anchor(of: hole) ?? hole.greenCenter,
              let provenance = terrain.sample(at: anchor)?.provenance, hasDetailedSource(provenance) else { return nil }
        let mapped = hole.green.count >= 3 || hole.greenOutline.count >= 3
        guard let region = (mapped ? nil : detectedOutline(terrain: terrain, hole: hole)) ?? region(for: hole),
              region.count >= 3, let origin = GolfGeometry.centroid(of: region) else { return nil }

        let local = region.map { TerrainGeometry.vector($0, from: origin) }
        let minX = local.map(\.x).min()! - fitRadius, maxX = local.map(\.x).max()! + fitRadius
        let minY = local.map(\.y).min()! - fitRadius, maxY = local.map(\.y).max()! + fitRadius
        let columns = Int((maxX - minX).rounded(.up)) + 1, rows = Int((maxY - minY).rounded(.up)) + 1
        guard columns * rows <= 20_000 else { return nil }

        var heights = [Double?](repeating: nil, count: columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                let point = unproject(SIMD2(minX + Double(column), minY + Double(row)), origin: origin)
                heights[row * columns + column] = terrain.sample(at: point)?.elevation
            }
        }

        var cells: [Cell] = []
        let half = cellSize / 2
        var y = local.map(\.y).min()! + half
        var gridRow = 0
        while y < local.map(\.y).max()! {
            var x = local.map(\.x).min()! + half
            var gridColumn = 0
            while x < local.map(\.x).max()! {
                let center = unproject(SIMD2(x, y), origin: origin)
                if GolfGeometry.contains(center, in: region),
                   let gradient = planeGradient(at: SIMD2(x, y), heights: heights, columns: columns, rows: rows,
                                                minX: minX, minY: minY) {
                    let length = (gradient.x * gradient.x + gradient.y * gradient.y).squareRoot()
                    let corners = [SIMD2(x - half, y - half), SIMD2(x + half, y - half),
                                   SIMD2(x + half, y + half), SIMD2(x - half, y + half)]
                        .map { unproject($0, origin: origin) }
                    cells.append(Cell(row: gridRow, column: gridColumn, corners: corners, center: center,
                                      slopePercent: length * 100,
                                      downhill: length > 0 ? -gradient / length : .zero))
                }
                x += cellSize
                gridColumn += 1
            }
            y += cellSize
            gridRow += 1
        }
        return cells.isEmpty ? nil : GreenSlopeMap(cells: cells, region: region, usesMappedOutline: mapped,
                                                    basis: Self.region(for: hole))
    }

    /// Finds the green's edge in the 1 m elevation model when no outline is mapped: a green is smooth and
    /// gentle and usually ends where the ground steepens or roughens. Nil when the shape isn't believable.
    static func detectedOutline(terrain: CourseTerrain, hole: Hole) -> [GeoPoint]? {
        guard let front = hole.greenFront, let back = hole.greenBack else { return nil }
        let origin = TerrainGeometry.interpolate(front, back, 0.5)
        let frontToBack = TerrainGeometry.vector(back, from: front)
        let length = (frontToBack.x * frontToBack.x + frontToBack.y * frontToBack.y).squareRoot()
        guard length > 6 else { return nil }
        let half = length / 2, axis = frontToBack / length
        let radius = 32, size = 2 * radius + 1
        let index = { (column: Int, row: Int) in row * size + column }

        var heights = [Double](repeating: 0, count: size * size)
        for row in 0..<size {
            for column in 0..<size {
                let point = unproject(SIMD2(Double(column - radius), Double(row - radius)), origin: origin)
                guard let z = terrain.sample(at: point)?.elevation else { return nil }
                heights[index(column, row)] = z
            }
        }

        // Plane over each 5 × 5 window; on a symmetric window Σdx² = Σdy² = 50 and the cross terms vanish.
        var smooth = [Bool](repeating: false, count: size * size)
        for row in 2..<(size - 2) {
            for column in 2..<(size - 2) {
                let x = Double(column - radius), y = Double(row - radius)
                guard abs(x * axis.x + y * axis.y) <= half + 3, abs(-x * axis.y + y * axis.x) <= 22 else { continue }
                var sz = 0.0, sxz = 0.0, syz = 0.0
                for dy in -2...2 {
                    for dx in -2...2 {
                        let z = heights[index(column + dx, row + dy)]
                        sz += z; sxz += Double(dx) * z; syz += Double(dy) * z
                    }
                }
                let a = sz / 25, b = sxz / 50, c = syz / 50
                var squared = 0.0
                for dy in -2...2 {
                    for dx in -2...2 {
                        let r = heights[index(column + dx, row + dy)] - (a + b * Double(dx) + c * Double(dy))
                        squared += r * r
                    }
                }
                smooth[index(column, row)] = (b * b + c * c).squareRoot() * 100 < 10 && (squared / 25).squareRoot() < 0.06
            }
        }

        func dilate(_ mask: [Bool], _ k: Int) -> [Bool] {
            var out = mask
            for row in 0..<size {
                for column in 0..<size where mask[index(column, row)] {
                    for dy in -k...k {
                        for dx in -k...k where dx * dx + dy * dy <= k * k {
                            let c = column + dx, r = row + dy
                            if (0..<size).contains(c), (0..<size).contains(r) { out[index(c, r)] = true }
                        }
                    }
                }
            }
            return out
        }
        func erode(_ mask: [Bool], _ k: Int) -> [Bool] { dilate(mask.map(!), k).map(!) }
        func flood(_ mask: [Bool], from seed: Int) -> [Bool] {
            var filled = [Bool](repeating: false, count: size * size)
            var stack = [seed]
            while let next = stack.popLast() {
                guard mask[next], !filled[next] else { continue }
                filled[next] = true
                let column = next % size, row = next / size
                if column > 0 { stack.append(next - 1) }
                if column < size - 1 { stack.append(next + 1) }
                if row > 0 { stack.append(next - size) }
                if row < size - 1 { stack.append(next + size) }
            }
            return filled
        }

        // Eroding first cuts thin smooth bridges into the fringe and approach.
        let candidate = erode(smooth, 1)
        let center = index(radius, radius)
        let seed = (0..<(size * size)).filter { candidate[$0] }.min { a, b in
            let da = (a % size - radius) * (a % size - radius) + (a / size - radius) * (a / size - radius)
            let db = (b % size - radius) * (b % size - radius) + (b / size - radius) * (b / size - radius)
            return da < db
        }
        guard let seed, (seed % size - radius) * (seed % size - radius) + (seed / size - radius) * (seed / size - radius) <= 36
        else { return nil }
        let closed = erode(dilate(dilate(flood(candidate, from: seed), 1), 2), 2)
        let outside = flood(closed.map(!), from: 0)
        let green = outside.map(!)

        // Believable: covers the centre, roughly oval-sized and spans most of front to back.
        let area = Double(green.filter { $0 }.count)
        let ovalArea = Double.pi * half * min(half, 14)
        let alongs = (0..<(size * size)).filter { green[$0] }.map {
            Double($0 % size - radius) * axis.x + Double($0 / size - radius) * axis.y
        }
        guard green[center], (0.4...1.8).contains(area / ovalArea),
              let lowest = alongs.min(), let highest = alongs.max(), highest - lowest >= 0.6 * length else { return nil }

        // Edge along 72 rays from the centre, lightly smoothed.
        let radii = (0..<72).map { step -> Double in
            let angle = Double(step) / 72 * 2 * .pi
            var r = 0.0
            while r < Double(radius) {
                let column = radius + Int((cos(angle) * (r + 0.5)).rounded()), row = radius + Int((sin(angle) * (r + 0.5)).rounded())
                guard (0..<size).contains(column), (0..<size).contains(row), green[index(column, row)] else { break }
                r += 0.5
            }
            return r + 0.5
        }
        return (0..<72).map { step in
            let r = (-2...2).map { radii[(step + $0 + 72) % 72] }.reduce(0, +) / 5
            let angle = Double(step) / 72 * 2 * .pi
            return unproject(SIMD2(cos(angle) * r, sin(angle) * r), origin: origin)
        }
    }

    /// Where the hole's green should be: midway between front and back, else its centre point or pin.
    static func anchor(of hole: Hole) -> GeoPoint? {
        if let front = hole.greenFront, let back = hole.greenBack { return TerrainGeometry.interpolate(front, back, 0.5) }
        return hole.greenCenterPoint ?? hole.pin
    }

    /// The mapped green containing the hole's anchor; the one centred nearest wins if greens overlap.
    static func outline(for hole: Hole, among outlines: [[GeoPoint]]) -> [GeoPoint]? {
        guard let anchor = anchor(of: hole) else { return nil }
        return outlines
            .filter { GolfGeometry.contains(anchor, in: $0) }
            .min { a, b in
                GolfGeometry.distance(anchor, GolfGeometry.centroid(of: a) ?? anchor)
                    < GolfGeometry.distance(anchor, GolfGeometry.centroid(of: b) ?? anchor)
            }
    }

    /// Mapped green outline when known; otherwise an oval from the front and back points, or a circle at the centre.
    static func region(for hole: Hole) -> [GeoPoint]? {
        if hole.green.count >= 3 { return hole.green }
        if hole.greenOutline.count >= 3 { return hole.greenOutline }
        if let front = hole.greenFront, let back = hole.greenBack {
            let mid = TerrainGeometry.interpolate(front, back, 0.5)
            let axis = TerrainGeometry.vector(back, from: front)
            let halfLength = (axis.x * axis.x + axis.y * axis.y).squareRoot() / 2
            guard halfLength > 3 else { return nil }
            let halfWidth = min(halfLength, 14)
            let angle = atan2(axis.y, axis.x)
            return (0..<48).map { i in
                let t = Double(i) / 48 * 2 * .pi
                let ex = halfLength * cos(t), ey = halfWidth * sin(t)
                return unproject(SIMD2(ex * cos(angle) - ey * sin(angle), ex * sin(angle) + ey * cos(angle)), origin: mid)
            }
        }
        guard let center = hole.greenCenter else { return nil }
        return (0..<48).map { i in
            let t = Double(i) / 48 * 2 * .pi
            return unproject(SIMD2(12 * cos(t), 12 * sin(t)), origin: center)
        }
    }

    /// Least-squares plane z = a + bx + cy over the 1 m samples within `fitRadius`; returns (b, c).
    private static func planeGradient(at p: SIMD2<Double>, heights: [Double?], columns: Int, rows: Int,
                                      minX: Double, minY: Double) -> SIMD2<Double>? {
        var n = 0.0, sx = 0.0, sy = 0.0, sz = 0.0, sxx = 0.0, syy = 0.0, sxy = 0.0, sxz = 0.0, syz = 0.0
        let c0 = max(0, Int((p.x - fitRadius - minX).rounded(.down))), c1 = min(columns - 1, Int((p.x + fitRadius - minX).rounded(.up)))
        let r0 = max(0, Int((p.y - fitRadius - minY).rounded(.down))), r1 = min(rows - 1, Int((p.y + fitRadius - minY).rounded(.up)))
        guard c0 <= c1, r0 <= r1 else { return nil }
        for row in r0...r1 {
            for column in c0...c1 {
                guard let z = heights[row * columns + column] else { continue }
                let dx = minX + Double(column) - p.x, dy = minY + Double(row) - p.y
                guard dx * dx + dy * dy <= fitRadius * fitRadius else { continue }
                n += 1; sx += dx; sy += dy; sz += z
                sxx += dx * dx; syy += dy * dy; sxy += dx * dy; sxz += dx * z; syz += dy * z
            }
        }
        guard n >= 6 else { return nil }
        // Centre the sums so the 2×2 system for (b, c) is independent of the intercept.
        let cxx = sxx - sx * sx / n, cyy = syy - sy * sy / n, cxy = sxy - sx * sy / n
        let cxz = sxz - sx * sz / n, cyz = syz - sy * sz / n
        let det = cxx * cyy - cxy * cxy
        guard abs(det) > 1e-9 else { return nil }
        return SIMD2((cxz * cyy - cyz * cxy) / det, (cyz * cxx - cxz * cxy) / det)
    }

    static func unproject(_ v: SIMD2<Double>, origin: GeoPoint) -> GeoPoint {
        GeoPoint(lat: origin.lat + v.y / TerrainGeometry.radius * 180 / .pi,
                 lon: origin.lon + v.x / (TerrainGeometry.radius * cos(origin.lat * .pi / 180)) * 180 / .pi)
    }

    static func downhillPoint(of cell: Cell, meters: Double) -> GeoPoint {
        unproject(cell.downhill * meters, origin: cell.center)
    }

    /// Flat greens are green, 2.5 % yellow, 5 % and steeper red.
    static func color(forSlope percent: Double) -> Color {
        Color(hue: 0.33 * (1 - min(max(percent / 5, 0), 1)), saturation: 0.85, brightness: 0.95)
    }

    /// Blended colours clipped to the green, with white downhill arrows about 18 pt apart.
    func draw(in context: inout GraphicsContext, convert: (GeoPoint) -> CGPoint?) {
        guard let sample = cells.first, let a = convert(sample.corners[0]), let b = convert(sample.corners[1]) else { return }
        let cellPoints = max(hypot(b.x - a.x, b.y - a.y), 0.1)

        var outline = Path()
        for point in region {
            guard let screen = convert(point) else { continue }
            if outline.isEmpty { outline.move(to: screen) } else { outline.addLine(to: screen) }
        }
        outline.closeSubpath()

        var colours = context
        colours.clip(to: outline)
        colours.opacity = 0.6
        colours.addFilter(.blur(radius: min(cellPoints * 0.8, 14)))
        colours.drawLayer { layer in
            for cell in cells {
                var quad = Path()
                for corner in cell.corners {
                    guard let point = convert(corner) else { continue }
                    if quad.isEmpty { quad.move(to: point) } else { quad.addLine(to: point) }
                }
                quad.closeSubpath()
                // Slight overlap hides seams between neighbouring cells before the blur.
                layer.fill(quad, with: .color(Self.color(forSlope: cell.slopePercent)))
                layer.stroke(quad, with: .color(Self.color(forSlope: cell.slopePercent)), lineWidth: 1)
            }
        }

        let stride = max(1, Int((18 / cellPoints).rounded(.up)))
        let arrowLength = min(CGFloat(stride) * cellPoints * 0.7, 18)
        for cell in cells where cell.row % stride == 0 && cell.column % stride == 0 && cell.slopePercent >= 0.5 {
            guard let start = convert(cell.center),
                  let toward = convert(Self.downhillPoint(of: cell, meters: 1)) else { continue }
            let dx = toward.x - start.x, dy = toward.y - start.y
            let length = max(hypot(dx, dy), 0.001)
            let ux = dx / length, uy = dy / length
            let tail = CGPoint(x: start.x - ux * arrowLength / 2, y: start.y - uy * arrowLength / 2)
            let tip = CGPoint(x: start.x + ux * arrowLength / 2, y: start.y + uy * arrowLength / 2)
            var arrow = Path()
            arrow.move(to: tail)
            arrow.addLine(to: tip)
            arrow.move(to: CGPoint(x: tip.x - ux * 4 - uy * 2.6, y: tip.y - uy * 4 + ux * 2.6))
            arrow.addLine(to: tip)
            arrow.addLine(to: CGPoint(x: tip.x - ux * 4 + uy * 2.6, y: tip.y - uy * 4 - ux * 2.6))
            context.stroke(arrow, with: .color(.black.opacity(0.3)),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            context.stroke(arrow, with: .color(.white),
                           style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
    }
}
