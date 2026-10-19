#if DEBUG
import Foundation

/// Local-only deterministic core; UI supplies randomness. Never touches GPS or a provider.
enum DevelopmentScoringPosition {
    static func distanceRange(plan: ScoringShotPlan, target: GeoPoint, tee: GeoPoint) -> ClosedRange<Double>? {
        guard TerrainGeometry.valid(target), TerrainGeometry.valid(tee),
              let threshold = plan.maxFullCarryM, threshold.isFinite, threshold > 0 else { return nil }
        // Stay short of both personal scoring boundary and tee; leave ample
        // margin for spherical vs CLLocation ellipsoidal measurement differences.
        let upper = min(threshold * 0.8, GolfGeometry.distance(target, tee) * 0.9)
        guard upper.isFinite, upper >= 0.2 else { return nil }
        let lower = min(upper, max(min(3, upper), threshold * 0.25))
        return lower...upper
    }

    static func make(plan: ScoringShotPlan, target: GeoPoint, tee: GeoPoint,
                     fraction: Double, jitterDeg: Double) -> GeoPoint? {
        guard fraction.isFinite, jitterDeg.isFinite,
              let range = distanceRange(plan: plan, target: target, tee: tee),
              let threshold = plan.maxFullCarryM else { return nil }
        let bearing = GolfGeometry.bearing(from: target, to: tee) + max(-20, min(20, jitterDeg))
        var distance = range.lowerBound + (range.upperBound - range.lowerBound) * max(0, min(1, fraction))
        // Validate using EXACTLY the recommendation capture's distance method.
        // A bounded shrink fails closed rather than returning an out-of-range origin.
        for _ in 0..<3 {
            let point = GolfGeometry.destination(from: target, distanceM: distance, bearingDeg: bearing)
            let measured = GolfGeometry.distance(point, target)
            if TerrainGeometry.valid(point), measured.isFinite, measured > 0.1,
               measured <= threshold * 0.99, plan.isScoring(distanceM: measured) { return point }
            distance *= 0.8
        }
        return nil
    }
}
#endif