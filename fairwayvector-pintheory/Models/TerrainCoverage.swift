import Foundation

/// Each validated response retains its original path and every exact returned point.
/// Point history is implicit in these immutable response records; no provenance is deduplicated away.
nonisolated struct TerrainResponseRecord: Codable, Sendable {
    let path: [GeoPoint]
    let samples: [TerrainSample]
    let fetchedAt: Date
    var length: Double { TerrainGeometry.chainages(path).last ?? 0 }

    func sample(at chainage: Double, point: GeoPoint, distance: Double) -> TerrainSample? {
        guard let first = samples.first, let last = samples.last,
              chainage >= -0.000001, chainage <= length + 0.000001 else { return nil }
        if let exact = samples.first(where: { abs($0.distanceMeters - chainage) < 0.000001 }) {
            return TerrainSample(distanceMeters: distance, point: exact.point, elevationMeters: exact.elevationMeters,
                                 provenance: exact.provenance, locallyInterpolated: false)
        }
        guard chainage >= first.distanceMeters, chainage <= last.distanceMeters else { return nil }
        for (a, b) in zip(samples, samples.dropFirst()) where a.distanceMeters < chainage && b.distanceMeters > chainage {
            guard let low = a.elevationMeters, let high = b.elevationMeters else { return nil }
            let t = (chainage - a.distanceMeters) / (b.distanceMeters - a.distanceMeters)
            return TerrainSample(distanceMeters: distance, point: point, elevationMeters: low + (high - low) * t,
                                 provenance: Array(Set(a.provenance + b.provenance)), locallyInterpolated: true)
        }
        return nil
    }
}

nonisolated struct TerrainCourseCache: Codable, Sendable {
    var schemaVersion = 1
    let courseID: String
    var responses: [TerrainResponseRecord] = []

    func validate(expectedID: String) throws {
        guard schemaVersion == 1, courseID == expectedID else { throw TerrainError.cacheUnavailable }
        let synthetic = courseID.hasPrefix(DevelopmentAPIConfiguration.terrainNamespace)
        for response in responses {
            guard response.path.count >= 2, response.path.count <= 5_000,
                  response.path.allSatisfy(TerrainGeometry.valid), response.length > 0,
                                    response.length.isFinite,
                  (2...512).contains(response.samples.count), response.fetchedAt.timeIntervalSince1970.isFinite else {
                throw TerrainError.cacheUnavailable
            }
            for (i, sample) in response.samples.enumerated() {
                guard TerrainGeometry.valid(sample.point), let elevation = sample.elevationMeters, elevation.isFinite,
                      !sample.locallyInterpolated, sample.distanceMeters.isFinite,
                      abs(sample.distanceMeters - Double(i) / Double(response.samples.count - 1) * response.length) < 0.000001,
                      !sample.provenance.isEmpty,
                      sample.provenance.allSatisfy({ !$0.dataSource.isEmpty && $0.resolutionMeters.isFinite && $0.resolutionMeters > 0
                          && $0.fetchedAt.timeIntervalSince1970.isFinite
                          && $0.providerSampleIntervalMeters.isFinite && $0.providerSampleIntervalMeters > 0
                          && abs($0.providerSampleIntervalMeters - response.length / Double(response.samples.count - 1)) < 0.000001
                          && (synthetic
                              ? $0.isSynthetic && $0.verticalDatum == "Synthetic (not surveyed)" && $0.interpolation == "analytical synthetic surface"
                              : !$0.isSynthetic && $0.verticalDatum == "EGM2008" && $0.interpolation == "bilinear") }),
                                            TerrainGeometry.length(sample.point, TerrainGeometry.point(response.path, at: sample.distanceMeters))
                                                <= min(max(0.5, response.length * 0.00001), response.length / Double(response.samples.count - 1) * 0.4) else {
                    throw TerrainError.cacheUnavailable
                }
            }
            guard TerrainGeometry.length(response.samples[0].point, response.path[0]) <= TerrainGeometry.tolerance,
                  TerrainGeometry.length(response.samples.last!.point, response.path.last!) <= TerrainGeometry.tolerance else {
                throw TerrainError.cacheUnavailable
            }
        }
    }

    /// Exact coordinates can anchor unrelated paths, but NEVER establish line coverage.
    func pointSample(_ p: GeoPoint, distance: Double) -> TerrainSample? {
        for response in responses.reversed() {
            if let s = response.samples.first(where: { TerrainGeometry.length($0.point, p) < 0.000001 }) {
                return TerrainSample(distanceMeters: distance, point: p, elevationMeters: s.elevationMeters, provenance: s.provenance)
            }
        }
        return nil
    }
}

/// Segment-to-segment overlap mapping uses ORIGINAL vertices, not chords between response samples.
/// Chainage at a bend therefore interpolates within the provider's original path, including when
/// no returned sample happened to land on that bend. Reverse and self-intersecting paths are safe:
/// every mapping refers to one explicit requested segment and one explicit recorded segment.
nonisolated struct TerrainCoveragePlan: Sendable {
    struct Piece: Sendable {
        let lower: Double
        let upper: Double
        let recordIndex: Int
        let sourceLower: Double
        let sourceUpper: Double
        func source(at d: Double) -> Double {
            sourceLower + (sourceUpper - sourceLower) * (d - lower) / (upper - lower)
        }
    }
    let path: [GeoPoint]
    let chain: [Double]
    let pieces: [Piece]
    let uncovered: [ClosedRange<Double>]

    init(path raw: [GeoPoint], cache: TerrainCourseCache) throws {
        let path = try TerrainGeometry.clean(raw)
        self.path = path
        let chain = TerrainGeometry.chainages(path)
        self.chain = chain
        var pieces: [Piece] = []
        for i in 0..<max(0, path.count - 1) {
            let a = path[i], b = path[i + 1]
            // A segment-local metric frame avoids broad GPS snapping, large global projection error.
            let v = TerrainGeometry.vector(b, from: a)
            let vv = v.x * v.x + v.y * v.y
            guard vv > 0 else { continue }
            for (r, record) in cache.responses.enumerated() {
                let rc = TerrainGeometry.chainages(record.path)
                for j in 0..<record.path.count - 1 {
                    let c = TerrainGeometry.vector(record.path[j], from: a)
                    let d = TerrainGeometry.vector(record.path[j + 1], from: a)
                    let tc = (c.x * v.x + c.y * v.y) / vv
                    let td = (d.x * v.x + d.y * v.y) / vv
                    let pc = hypot(c.x - tc * v.x, c.y - tc * v.y)
                    let pd = hypot(d.x - td * v.x, d.y - td * v.y)
                    // Both endpoints must lie on the same supporting line, within TWO CENTIMETRES.
                    guard pc <= TerrainGeometry.tolerance, pd <= TerrainGeometry.tolerance, abs(td - tc) > 1e-12 else { continue }
                    let low = max(0, min(tc, td)), high = min(1, max(tc, td))
                    guard high > low else { continue }
                    let sourceLow = rc[j] + (low - tc) / (td - tc) * (rc[j + 1] - rc[j])
                    let sourceHigh = rc[j] + (high - tc) / (td - tc) * (rc[j + 1] - rc[j])
                    pieces.append(Piece(lower: chain[i] + low * (chain[i + 1] - chain[i]),
                                        upper: chain[i] + high * (chain[i + 1] - chain[i]), recordIndex: r,
                                        sourceLower: sourceLow, sourceUpper: sourceHigh))
                }
            }
        }
        self.pieces = pieces
        // Union covered intervals; never bridge real holes or infer coverage from isolated points.
        var cursor = 0.0
        var gaps: [ClosedRange<Double>] = []
        for p in pieces.sorted(by: { $0.lower < $1.lower }) {
            if p.lower > cursor + 0.000001 { gaps.append(cursor...p.lower) }
            cursor = max(cursor, p.upper)
        }
        if let length = chain.last, length > cursor + 0.000001 { gaps.append(cursor...length) }
        uncovered = gaps
    }

    func profile(cache: TerrainCourseCache, straight: Bool) -> TerrainProfile {
        var distances = chain
        for p in pieces {
            distances += [p.lower, p.upper]
            for s in cache.responses[p.recordIndex].samples {
                let low = min(p.sourceLower, p.sourceUpper), high = max(p.sourceLower, p.sourceUpper)
                if s.distanceMeters > low && s.distanceMeters < high {
                    distances.append(p.lower + (s.distanceMeters - p.sourceLower) / (p.sourceUpper - p.sourceLower) * (p.upper - p.lower))
                }
            }
        }
        // Explicit missing sample in EVERY uncovered interval prevents the chart joining anchors.
        for gap in uncovered { distances += [gap.lowerBound, (gap.lowerBound + gap.upperBound) / 2, gap.upperBound] }
        distances.sort()
        var unique: [Double] = []
        for d in distances where unique.last.map({ abs($0 - d) > 0.000001 }) ?? true { unique.append(d) }
        let samples = unique.map { d -> TerrainSample in
            let point = TerrainGeometry.point(path, at: d)
            if uncovered.contains(where: { abs(d - ($0.lowerBound + $0.upperBound) / 2) < 0.000001 }) {
                return TerrainSample(distanceMeters: d, point: point, elevationMeters: nil)
            }
            if let exact = cache.pointSample(point, distance: d) { return exact }
            // Newest response wins overlaps, while retaining all versions on disk.
            for p in pieces.sorted(by: { $0.recordIndex > $1.recordIndex }) where d >= p.lower - 0.000001 && d <= p.upper + 0.000001 {
                let source = min(cache.responses[p.recordIndex].length, max(0, p.source(at: d)))
                if let sample = cache.responses[p.recordIndex].sample(at: source, point: point, distance: d) { return sample }
            }
            return TerrainSample(distanceMeters: d, point: point, elevationMeters: nil)
        }
        return TerrainProfile(samples: samples, isStraightLine: straight)
    }
}