import CoreLocation
import Foundation
import Testing
@testable import fairwayvector_pintheory

@MainActor
struct GolfGeometryTests {
    // ~20 m square green north of the origin.
    private let origin = GeoPoint(lat: 57.6200, lon: 12.0000)
    private var squareGreen: [GeoPoint] {
        let south = 57.6200 + 100 / 111_195.0
        let north = south + 20 / 111_195.0
        let halfWidthLon = 10 / (111_195.0 * cos(57.62 * .pi / 180))
        return [
            GeoPoint(lat: south, lon: 12.0 - halfWidthLon),
            GeoPoint(lat: south, lon: 12.0 + halfWidthLon),
            GeoPoint(lat: north, lon: 12.0 + halfWidthLon),
            GeoPoint(lat: north, lon: 12.0 - halfWidthLon),
        ]
    }

    @Test func distanceBetweenKnownPoints() {
        let north = GeoPoint(lat: origin.lat + 100 / 111_195.0, lon: origin.lon)
        #expect(abs(GolfGeometry.distance(origin, north) - 100) < 1)
    }

    @Test func bearingPointsNorthAndEast() {
        #expect(abs(GolfGeometry.bearing(from: origin, to: GeoPoint(lat: 57.63, lon: 12.0))) < 0.01)
        #expect(abs(GolfGeometry.bearing(from: origin, to: GeoPoint(lat: 57.62, lon: 12.01)) - 90) < 0.1)
    }

    @Test func centroidOfSquareIsItsMiddle() throws {
        let center = try #require(GolfGeometry.centroid(of: squareGreen))
        #expect(abs(GolfGeometry.distance(origin, center) - 110) < 0.5)
    }

    @Test func pointInPolygon() throws {
        let center = try #require(GolfGeometry.centroid(of: squareGreen))
        #expect(GolfGeometry.contains(center, in: squareGreen))
        #expect(!GolfGeometry.contains(origin, in: squareGreen))
    }

    @Test func frontAndBackAlongLineOfPlay() throws {
        let result = try #require(GolfGeometry.frontBack(from: origin, green: squareGreen))
        #expect(abs(result.front - 100) < 0.5)
        #expect(abs(result.back - 120) < 0.5)
    }

    @Test func distanceToHolePath() throws {
        let end = GeoPoint(lat: origin.lat + 200 / 111_195.0, lon: origin.lon)
        let besidePath = GeoPoint(lat: origin.lat + 100 / 111_195.0, lon: origin.lon + 30 / (111_195.0 * cos(origin.lat * .pi / 180)))
        let distance = try #require(GolfGeometry.distance(besidePath, toPath: [origin, end]))
        #expect(abs(distance - 30) < 0.5)
    }

    @Test func fairwayCorridorSurroundsTheHolePath() throws {
        let end = GeoPoint(lat: origin.lat + 200 / 111_195.0, lon: origin.lon)
        let boundary = GolfGeometry.corridorBoundary(for: [origin, end], halfWidth: 28)
        #expect(boundary.count == 4)
        let firstSideDistance = GolfGeometry.distance(origin, boundary[0])
        let otherSideDistance = GolfGeometry.distance(origin, boundary[3])
        #expect(abs(firstSideDistance - 28) < 0.5)
        #expect(abs(otherSideDistance - 28) < 0.5)
    }

    @Test func findsClosestPointOnHoleAreaEdge() throws {
        let point = GeoPoint(lat: origin.lat + 100 / 111_195.0, lon: origin.lon)
        let edgeStart = GeoPoint(lat: origin.lat, lon: origin.lon - 50 / (111_195.0 * cos(origin.lat * .pi / 180)))
        let edgeEnd = GeoPoint(lat: origin.lat, lon: origin.lon + 50 / (111_195.0 * cos(origin.lat * .pi / 180)))
        let closest = try #require(GolfGeometry.nearestPoint(onPath: [edgeStart, edgeEnd], to: point))
        #expect(GolfGeometry.distance(closest, origin) < 0.5)
    }

    @Test func smoothTeeConnectorUsesRoundedCaps() throws {
        let end = GeoPoint(lat: origin.lat, lon: origin.lon + 100 / (111_195.0 * cos(origin.lat * .pi / 180)))
        let boundary = GolfGeometry.smoothConnectorBoundary(from: origin, to: end, radius: 20)
        #expect(boundary.count == 34)
        #expect(abs(GolfGeometry.distance(origin, boundary[boundary.count - 1]) - 20) < 0.5)
        #expect(abs(GolfGeometry.distance(end, boundary[0]) - 20) < 0.5)
    }

    @Test func combinedHighlightBoundaryEnclosesHoleAndTeeAreas() throws {
        let holeArea = [
            origin,
            GeoPoint(lat: origin.lat, lon: origin.lon + 20 / (111_195.0 * cos(origin.lat * .pi / 180))),
            GeoPoint(lat: origin.lat + 20 / 111_195.0, lon: origin.lon + 20 / (111_195.0 * cos(origin.lat * .pi / 180))),
            GeoPoint(lat: origin.lat + 20 / 111_195.0, lon: origin.lon),
        ]
        let teeExtension = [
            GeoPoint(lat: origin.lat - 30 / 111_195.0, lon: origin.lon - 10 / (111_195.0 * cos(origin.lat * .pi / 180))),
            GeoPoint(lat: origin.lat - 30 / 111_195.0, lon: origin.lon + 10 / (111_195.0 * cos(origin.lat * .pi / 180))),
            GeoPoint(lat: origin.lat - 20 / 111_195.0, lon: origin.lon),
        ]
        let boundary = GolfGeometry.convexHull(of: [holeArea, teeExtension])
        let holeCenter = GeoPoint(lat: origin.lat + 10 / 111_195.0, lon: origin.lon + 10 / (111_195.0 * cos(origin.lat * .pi / 180)))
        let teeCenter = GeoPoint(lat: origin.lat - 25 / 111_195.0, lon: origin.lon)

        #expect(boundary.count >= 5)
        #expect(GolfGeometry.contains(teeCenter, in: boundary))
        #expect(GolfGeometry.contains(holeCenter, in: boundary))
    }
}

@MainActor
struct DistanceOriginTests {
    private let tee = GeoPoint(lat: 57.6200, lon: 12.0000)
    private var hole: Hole {
        Hole(
            number: 1,
            par: 4,
            path: [tee, GeoPoint(lat: tee.lat + 300 / 111_195.0, lon: tee.lon)],
            green: [],
            pin: nil
        )
    }

    @Test func usesGPSWhenFixIsNearHolePath() throws {
        let nearPath = CLLocation(latitude: tee.lat + 100 / 111_195.0, longitude: tee.lon)
        let origin = try #require(DistanceOrigin.resolve(location: nearPath, hole: hole))
        #expect(origin.usesGPS)
    }

    @Test func fallsBackToTeeWhenFixIsOffHole() throws {
        let offHole = CLLocation(latitude: tee.lat + 100 / 111_195.0, longitude: tee.lon + 250 / (111_195.0 * cos(tee.lat * .pi / 180)))
        let origin = try #require(DistanceOrigin.resolve(location: offHole, hole: hole))
        #expect(!origin.usesGPS)
        #expect(origin.point == tee)
    }
}

@MainActor
struct CourseBuilderTests {
    private let fixture = """
    {"elements":[
      {"type":"way","id":1,"tags":{"golf":"hole","ref":"2","par":"3"},
       "geometry":[{"lat":57.6200,"lon":12.0000},{"lat":57.6215,"lon":12.0000}]},
    {"type":"way","id":2,"tags":{"golf":"hole","ref":"1","par":"4","stroke_index":"7"},
       "geometry":[{"lat":57.6100,"lon":12.0000},{"lat":57.6130,"lon":12.0000}]},
      {"type":"way","id":3,"tags":{"golf":"green"},
       "geometry":[{"lat":57.6214,"lon":11.9998},{"lat":57.6214,"lon":12.0002},{"lat":57.6217,"lon":12.0002},{"lat":57.6217,"lon":11.9998},{"lat":57.6214,"lon":11.9998}]},
    {"type":"node","id":4,"lat":57.6216,"lon":12.0001,"tags":{"golf":"pin"}},
    {"type":"way","id":5,"tags":{"golf":"rough"},
     "geometry":[{"lat":57.6095,"lon":11.9995},{"lat":57.6095,"lon":12.0005},{"lat":57.6135,"lon":12.0005},{"lat":57.6135,"lon":11.9995},{"lat":57.6095,"lon":11.9995}]},
    {"type":"way","id":6,"tags":{"golf":"fairway"},
        "geometry":[{"lat":57.6100,"lon":11.9998},{"lat":57.6100,"lon":12.0002},{"lat":57.6130,"lon":12.0002},{"lat":57.6130,"lon":11.9998},{"lat":57.6100,"lon":11.9998}]},
          {"type":"way","id":7,"tags":{"golf":"tee"},
        "geometry":[{"lat":57.6099,"lon":11.9999},{"lat":57.6099,"lon":12.0001},{"lat":57.6101,"lon":12.0001},{"lat":57.6101,"lon":11.9999},{"lat":57.6099,"lon":11.9999}]}
    ]}
    """

    @Test func buildsSortedHolesAndMatchesGreens() throws {
        let elements = try OverpassClient.decode(Data(fixture.utf8))
        let course = try CourseBuilder.build(reference: .hills, elements: elements)

        #expect(course.holes.map(\.number) == [1, 2])
        #expect(course.holes[0].par == 4)
        #expect(course.holes[0].handicapIndex == 7)
        #expect(abs(course.holes[0].length - 334) < 1)
        #expect(course.holes[0].green.isEmpty)
        #expect(course.holes[0].roughs.count == 1)
        #expect(course.holes[0].fairways.count == 1)
        #expect(course.holes[0].tees.count == 1)
        #expect(course.holes[1].green.count == 5)
        #expect(course.holes[1].pin == GeoPoint(lat: 57.6216, lon: 12.0001))
    }

    @Test func throwsWhenNoHoles() throws {
        let elements = try OverpassClient.decode(Data(#"{"elements":[]}"#.utf8))
        #expect(throws: CourseBuilderError.self) {
            try CourseBuilder.build(reference: .hills, elements: elements)
        }
    }
}

@MainActor
struct DistanceUnitTests {
    @Test func convertsToYards() {
        #expect(DistanceUnit.meters.value(150) == 150)
        #expect(DistanceUnit.yards.value(150) == 164)
    }
}

@MainActor
struct CourseCatalogTests {
    @Test func bundledSwedenCatalogLoadsClubCourseAndTeeMetadata() throws {
        let catalog = SwedenCourseCatalogStore(bundle: Bundle(for: CourseStore.self)).catalog
        #expect(catalog.country == "Sweden")
        #expect(catalog.clubs.count == 394)

        let club = try #require(catalog.clubs.first { $0.name == "Hills Golf & Sports Club" })
        let course = try #require(club.courses.first { $0.name == "Hills Course" })
        let tee = try #require(course.ratings.first { $0.tee == "62" && $0.sex == "male" })
        let reference = CourseReference(selection: SelectedCourse(club: club, course: course, tee: tee))

        #expect(reference.clubName == club.name)
        #expect(reference.courseName == course.name)
        #expect(reference.teeName == "62")
        #expect(reference.totalPar == 71)
        #expect(reference.slopeRating == 140)
    }
}
