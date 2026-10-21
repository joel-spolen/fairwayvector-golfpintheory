import Foundation

enum GolfAPICourseBuilder {
    static func build(
        reference: CourseReference,
        payload: GolfAPICoursePayload,
        fetchedAt: Date = .now
    ) throws -> Course {
        guard let courseID = reference.golfAPICourseID,
              courseID == payload.detail.courseID else {
            throw GolfAPIError.invalidResponse("The selected course ID does not match the downloaded detail.")
        }
        guard let teeID = reference.golfAPITeeID,
              let tee = payload.detail.tees.first(where: { $0.teeID == teeID }) else {
            throw GolfAPIError.invalidResponse("The selected tee was not found in the downloaded detail.")
        }

        let sex = reference.teeSex
        let coursePars = sex == "female" ? payload.detail.parsWomen : payload.detail.parsMen
        let courseIndexes = sex == "female" ? payload.detail.indexesWomen : payload.detail.indexesMen
        let pars = tee.pars(for: sex, fallback: coursePars)
        let indexes = tee.indexes(for: sex, fallback: courseIndexes)
        let coordinateHoles = Dictionary(grouping: payload.coordinates, by: \.hole)
        let holeCount = max(reference.holeCount, coordinateHoles.keys.max() ?? 0)
        guard holeCount > 0 else { throw GolfAPIError.noGPSData(reference.courseName) }
        var holes: [Hole] = []

        for number in 1...holeCount {
            let points = coordinateHoles[number] ?? []
            let greenFront = points.first { $0.poi == 1 && $0.location == 1 }?.point
            let greenCenter = points.first { $0.poi == 1 && $0.location == 2 }?.point
            let greenBack = points.first { $0.poi == 1 && $0.location == 3 }?.point
            let teeFront = points.first { $0.poi == 11 }?.point
            let teeBack = points.first { $0.poi == 12 }?.point
            let teePoint = midpoint(teeFront, teeBack)
            let greenPoint = greenCenter ?? midpoint(greenFront, greenBack)

            guard let teePoint, let greenPoint else { continue }
            let index = number - 1
            holes.append(Hole(
                number: number,
                par: pars.indices.contains(index) ? pars[index] : nil,
                handicapIndex: indexes.indices.contains(index) ? indexes[index] : nil,
                path: [teePoint, greenPoint],
                green: [],
                pin: greenCenter,
                greenFront: greenFront,
                greenBack: greenBack,
                teeFront: teeFront,
                teeBack: teeBack,
                measuredLengthMeters: tee.lengthsMeters.indices.contains(index) ? tee.lengthsMeters[index] : nil,
                greenCenterPoint: greenPoint,
                usesPointOnlyGeometry: true
            ))
        }

        guard !holes.isEmpty else { throw GolfAPIError.noGPSData(reference.courseName) }
        if courseID == DevelopmentGolfAPIFixtures.courseID {
            // Fixture coordinates describe the common layout; selected synthetic tee length
            // locates that tee on its centerline. Real provider geometry is never adjusted.
            for i in holes.indices {
                guard let teePoint = holes[i].tee, let green = holes[i].greenCenter,
                      let length = holes[i].measuredLengthMeters, length > 0 else { continue }
                let actual = TerrainGeometry.length(green, teePoint)
                guard actual > 0 else { continue }
                holes[i].path[0] = TerrainGeometry.interpolate(green, teePoint, length / actual)
                holes[i].teeFront = TerrainGeometry.interpolate(green, teePoint, (length - 4) / actual)
                holes[i].teeBack = TerrainGeometry.interpolate(green, teePoint, (length + 4) / actual)
            }
        }
        return Course(golfAPICourseID: courseID, name: reference.courseName, holes: holes, fetchedAt: fetchedAt)
    }

    private static func midpoint(_ first: GeoPoint?, _ second: GeoPoint?) -> GeoPoint? {
        switch (first, second) {
        case let (first?, second?):
            GeoPoint(lat: (first.lat + second.lat) / 2, lon: (first.lon + second.lon) / 2)
        case let (point?, nil), let (nil, point?):
            point
        case (nil, nil):
            nil
        }
    }
}
