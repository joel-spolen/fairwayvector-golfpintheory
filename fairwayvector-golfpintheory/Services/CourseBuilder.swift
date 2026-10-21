import Foundation

enum CourseBuilderError: LocalizedError {
    case noHoles
    case missingOSMRelation

    var errorDescription: String? {
        switch self {
        case .noHoles: "No mapped holes were found for this course in OpenStreetMap."
        case .missingOSMRelation: "The selected course has no matching OpenStreetMap area."
        }
    }
}

enum CourseBuilder {
    static func build(
        reference: CourseReference,
        elements: [OverpassElement],
        osmRelationID: Int? = nil,
        fetchedAt: Date = .now
    ) throws -> Course {
        guard let osmRelationID = osmRelationID ?? reference.osmRelationID else {
            throw CourseBuilderError.missingOSMRelation
        }
        let greens: [[GeoPoint]] = elements
            .filter { $0.type == "way" && $0.tags?["golf"] == "green" }
            .compactMap { $0.geometry }
            .filter { $0.count >= 3 }

        let pins: [GeoPoint] = elements
            .filter { $0.type == "node" && $0.tags?["golf"] == "pin" }
            .compactMap { element in
                guard let lat = element.lat, let lon = element.lon else { return nil }
                return GeoPoint(lat: lat, lon: lon)
            }

        let holeElements = elements
            .filter { $0.type == "way" && $0.tags?["golf"] == "hole" }
            .compactMap { element -> (hole: Hole, end: GeoPoint)? in
                guard let number = element.tags?["ref"].flatMap({ Int($0) }),
                      let path = element.geometry, path.count >= 2,
                      let end = path.last else { return nil }
                let green = matchGreen(for: end, in: greens) ?? []
                let pin = pins.first { GolfGeometry.contains($0, in: green) }
                let handicapIndex = ["handicap", "stroke_index", "si"]
                    .compactMap { element.tags?[$0].flatMap(Int.init) }
                    .first
                return (
                    Hole(
                        number: number,
                        par: element.tags?["par"].flatMap { Int($0) },
                        handicapIndex: handicapIndex,
                        path: path,
                        green: green,
                        pin: pin
                    ),
                    end
                )
            }
            .sorted { $0.hole.number < $1.hole.number }

        guard !holeElements.isEmpty else { throw CourseBuilderError.noHoles }

        var holes = holeElements.map(\.hole)
        for element in elements where element.type == "way" {
            guard let feature = element.tags?["golf"], feature == "fairway" || feature == "rough",
                  let polygon = element.geometry, polygon.count >= 3,
                  let center = GolfGeometry.centroid(of: polygon) else { continue }
            let nearestHole = holes.indices
                .compactMap { index -> (index: Int, distance: Double)? in
                    guard let distance = GolfGeometry.distance(center, toPath: holes[index].path) else { return nil }
                    return (index, distance)
                }
                .min { $0.distance < $1.distance }
            guard let nearestHole, nearestHole.distance <= 500 else { continue }
            if feature == "fairway" {
                holes[nearestHole.index].fairways.append(polygon)
            } else {
                holes[nearestHole.index].roughs.append(polygon)
            }
        }

        for element in elements where element.type == "way" && element.tags?["golf"] == "tee" {
            guard let polygon = element.geometry, polygon.count >= 3,
                  let center = GolfGeometry.centroid(of: polygon) else { continue }
            let nearestHole = holes.indices
                .compactMap { index -> (index: Int, distance: Double)? in
                    guard let tee = holes[index].tee else { return nil }
                    return (index, GolfGeometry.distance(center, tee))
                }
                .min { $0.distance < $1.distance }
            guard let nearestHole, nearestHole.distance <= 300 else { continue }
            holes[nearestHole.index].tees.append(polygon)
        }

        return Course(osmRelationID: osmRelationID, name: reference.courseName, holes: holes, fetchedAt: fetchedAt)
    }

    private static func matchGreen(for end: GeoPoint, in greens: [[GeoPoint]]) -> [GeoPoint]? {
        if let containing = greens.first(where: { GolfGeometry.contains(end, in: $0) }) {
            return containing
        }
        let maxMatchDistance = 60.0
        return greens
            .compactMap { green -> (green: [GeoPoint], distance: Double)? in
                guard let center = GolfGeometry.centroid(of: green) else { return nil }
                return (green, GolfGeometry.distance(center, end))
            }
            .filter { $0.distance <= maxMatchDistance }
            .min { $0.distance < $1.distance }?
            .green
    }
}
