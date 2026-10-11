import MapKit
import SwiftUI

struct HoleMapView: View {
    let hole: Hole
    let flag: GeoPoint?
    let origin: GeoPoint?
    let usesGPS: Bool
    @Binding var tapPoint: GeoPoint?
    let onDoubleTapGreen: () -> Void
    var onHeadingChange: (Double) -> Void = { _ in }
    var terrainInspectionPoint: GeoPoint? = nil
    var onTargetInteractionBegan: () -> Void = {}
    var onTargetInteractionCancelled: () -> Void = {}
    var onTargetCommitted: (GeoPoint) -> Void = { _ in }
    var simulatedUserLocation: GeoPoint? = nil

    private var hasPlayerOrigin: Bool { usesGPS || simulatedUserLocation != nil }

    @State private var position: MapCameraPosition = .automatic
    @State private var cameraRevision = 0
    @State private var isDraggingTarget = false
    @GestureState private var targetGestureActive = false
    @State private var isZoomedIn = false

    var body: some View {
        MapReader { proxy in
            Map(position: $position, bounds: cameraBounds, interactionModes: isZoomedIn ? [.pan, .zoom] : [.zoom]) {
                if usesGPS && simulatedUserLocation == nil {
                    UserAnnotation()
                }

                #if DEBUG
                if let simulatedUserLocation {
                    Annotation("Simulated golfer", coordinate: simulatedUserLocation.coordinate) {
                        Label("DEV YOU", systemImage: "figure.golf")
                            .font(.caption2.bold())
                            .padding(6)
                            .foregroundStyle(.white)
                            .background(FairwayVectorColors.orange, in: Capsule())
                    }
                    .annotationTitles(.hidden)
                }
                #endif

                if let tee = hole.tee {
                    Annotation(hasPlayerOrigin ? "Tee" : "You", coordinate: tee.coordinate, anchor: .bottom) {
                        VStack(spacing: 3) {
                            Text(hasPlayerOrigin ? "TEE" : "YOU")
                                .font(.caption2.bold())
                                .foregroundStyle(PureLineStyle.ink)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 4)
                                .background(PureLineStyle.canvas, in: Capsule())
                            Image(systemName: "mappin.and.ellipse")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(PureLineStyle.accent)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                        }
                    }
                    .annotationTitles(.hidden)
                }

                ForEach(Array(hole.roughs.enumerated()), id: \.offset) { _, polygon in
                    MapPolygon(coordinates: polygon.map(\.coordinate))
                        .foregroundStyle(PureLineStyle.accent.opacity(0.10))
                }

                ForEach(Array(hole.fairways.enumerated()), id: \.offset) { _, polygon in
                    MapPolygon(coordinates: polygon.map(\.coordinate))
                        .foregroundStyle(PureLineStyle.accent.opacity(0.12))
                }

                if highlightBoundary.count >= 3 {
                    MapPolyline(coordinates: (highlightBoundary + [highlightBoundary[0]]).map(\.coordinate))
                        .stroke(PureLineStyle.accent.opacity(0.42), style: StrokeStyle(lineWidth: 7, lineJoin: .round))
                    MapPolyline(coordinates: (highlightBoundary + [highlightBoundary[0]]).map(\.coordinate))
                        .stroke(PureLineStyle.canvas.opacity(0.92), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                }

                if hole.green.count >= 3 {
                    MapPolygon(coordinates: hole.green.map(\.coordinate))
                        .foregroundStyle(PureLineStyle.accent.opacity(0.25))
                        .stroke(PureLineStyle.accent, lineWidth: 2)
                }

                if let flag {
                    Annotation("Flag", coordinate: flag.coordinate, anchor: .bottomLeading) {
                        Image(systemName: "flag.fill")
                            .font(.title3)
                            .foregroundStyle(PureLineStyle.accent)
                            .shadow(radius: 2)
                    }
                    .annotationTitles(.hidden)
                }

                if let terrainInspectionPoint {
                    Annotation("Terrain profile position", coordinate: terrainInspectionPoint.coordinate) {
                        Image(systemName: "mountain.2.fill")
                            .font(.caption.bold())
                            .foregroundStyle(PureLineStyle.canvas)
                            .padding(7)
                            .background(PureLineStyle.accent, in: Circle())
                    }
                    .annotationTitles(.hidden)
                }

                if let tapPoint {
                    if let origin {
                        MapPolyline(coordinates: [origin.coordinate, tapPoint.coordinate])
                            .stroke(PureLineStyle.accent, lineWidth: 3)
                    }
                    if let flag {
                        MapPolyline(coordinates: [tapPoint.coordinate, flag.coordinate])
                            .stroke(PureLineStyle.accent, lineWidth: 3)
                    }
                    Annotation("Target", coordinate: tapPoint.coordinate) {
                        ZStack {
                            Circle()
                                .fill(PureLineStyle.accent.opacity(0.18))
                                .frame(width: 96, height: 96)
                            Circle()
                                .fill(PureLineStyle.canvas)
                                .stroke(PureLineStyle.accent, lineWidth: 3)
                                .frame(width: 44, height: 44)
                            Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(PureLineStyle.accent)
                        }
                        .contentShape(Circle())
                    }
                    .annotationTitles(.hidden)
                }
            }
            .mapStyle(.imagery(elevation: .flat))
            .onMapCameraChange(frequency: .continuous) { context in
                onHeadingChange(context.camera.heading)
                cameraRevision &+= 1
                isZoomedIn = context.camera.distance < initialCameraDistance * 0.98
                if !isZoomedIn,
                   GolfGeometry.distance(GeoPoint(context.camera.centerCoordinate), initialCameraCenter) > 5 {
                    position = .camera(initialCamera)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .updating($targetGestureActive) { _, active, _ in active = true }
                    .onChanged { value in
                        guard let currentTarget = tapPoint else { return }
                        if !isDraggingTarget {
                            guard let markerPoint = proxy.convert(currentTarget.coordinate, to: .local) else { return }
                            let dx = value.startLocation.x - markerPoint.x
                            let dy = value.startLocation.y - markerPoint.y
                            guard hypot(dx, dy) <= 40 else { return }
                            isDraggingTarget = true
                            onTargetInteractionBegan()
                        }
                        if let coordinate = proxy.convert(value.location, from: .local) {
                            tapPoint = GeoPoint(coordinate)
                        }
                    }
                    .onEnded { value in
                        let genuineTargetDrag = isDraggingTarget
                        isDraggingTarget = false
                        if genuineTargetDrag {
                            if let coordinate = proxy.convert(value.location, from: .local) { tapPoint = GeoPoint(coordinate) }
                            if let tapPoint { onTargetCommitted(tapPoint) }
                        }
                    }
            )
            .simultaneousGesture(
                SpatialTapGesture(count: 2, coordinateSpace: .local)
                    .exclusively(before: SpatialTapGesture(count: 1, coordinateSpace: .local))
                    .onEnded { value in
                        switch value {
                        case .first(let tap):
                            guard let coordinate = proxy.convert(tap.location, from: .local),
                                  GolfGeometry.contains(GeoPoint(coordinate), in: hole.green) else { return }
                            onDoubleTapGreen()
                        case .second(let tap):
                            guard !isDraggingTarget, let coordinate = proxy.convert(tap.location, from: .local) else { return }
                            let point = GeoPoint(coordinate)
                            onTargetInteractionBegan()
                            tapPoint = point
                            onTargetCommitted(point)
                        }
                    }
            )
            .overlay {
                Canvas { context, size in
                    guard !visibleAreaPolygons.isEmpty else { return }
                    context.drawLayer { layer in
                        layer.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black.opacity(0.25)))
                        layer.blendMode = .destinationOut
                        for polygon in visibleAreaPolygons {
                            guard let first = polygon.first,
                                  let firstPoint = proxy.convert(first.coordinate, to: .local) else { continue }
                            var cutout = Path()
                            cutout.move(to: firstPoint)
                            for point in polygon.dropFirst() {
                                guard let screenPoint = proxy.convert(point.coordinate, to: .local) else { continue }
                                cutout.addLine(to: screenPoint)
                            }
                            cutout.closeSubpath()
                            layer.fill(cutout, with: .color(.black))
                        }
                    }
                }
                .id(cameraRevision)
                .allowsHitTesting(false)
            }
        }
        .onAppear(perform: frameHole)
        .onChange(of: hole.number) { frameHole() }
        .onChange(of: targetGestureActive) { _, active in
            // A cancelled recognizer resets gesture state without a release commit.
            if !active, isDraggingTarget {
                isDraggingTarget = false
                onTargetInteractionCancelled()
            }
        }
    }

    private var holeCoordinates: [CLLocationCoordinate2D] {
        (hole.path + hole.green + [hole.greenFront, hole.greenCenterPoint, hole.greenBack, hole.teeFront, hole.teeBack].compactMap { $0 }).map(\.coordinate)
    }

    private var boundaryPolygons: [[GeoPoint]] {
        if hole.usesPointOnlyGeometry { return [] }
        if !hole.roughs.isEmpty { return hole.roughs }
        if !hole.fairways.isEmpty { return hole.fairways }
        let fallback = GolfGeometry.corridorBoundary(for: hole.path)
        return fallback.isEmpty ? [] : [fallback]
    }

    private var highlightBoundary: [GeoPoint] {
        let polygons = boundaryPolygons + teeConnectors
        guard polygons.count > 1 else { return polygons.first ?? [] }
        return GolfGeometry.convexHull(of: polygons)
    }

    private var visibleAreaPolygons: [[GeoPoint]] {
        highlightBoundary.count >= 3 ? [highlightBoundary] : boundaryPolygons
    }

    private var teeConnectors: [[GeoPoint]] {
        let playableAreas = hole.roughs + hole.fairways
        guard !hole.tees.isEmpty, !playableAreas.isEmpty else { return [] }
        return hole.tees.compactMap { teePolygon in
            guard let teeCenter = GolfGeometry.centroid(of: teePolygon) else { return nil }
            let teeRadius = teePolygon.map { GolfGeometry.distance(teeCenter, $0) }.max() ?? 0
            let nearestAreaPoint = playableAreas
                .compactMap { polygon -> (point: GeoPoint, distance: Double)? in
                    guard let nearest = GolfGeometry.nearestPoint(onPath: polygon + [polygon[0]], to: teeCenter) else { return nil }
                    return (nearest, GolfGeometry.distance(teeCenter, nearest))
                }
                .min { $0.distance < $1.distance }?
                .point
            guard let nearestAreaPoint else { return nil }
            let boundary = GolfGeometry.smoothConnectorBoundary(
                from: teeCenter,
                to: nearestAreaPoint,
                radius: max(teeRadius + 5, 22)
            )
            return boundary.count >= 3 ? boundary : nil
        }
    }

    private var holeRect: MKMapRect {
        guard let first = holeCoordinates.first else { return .world }
        var rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 0, height: 0))
        for coordinate in holeCoordinates.dropFirst() {
            rect = rect.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
        }
        let paddingX = max(rect.size.width * 0.1, 18)
        let paddingY = max(rect.size.height * 0.1, 18)
        return rect.insetBy(dx: -paddingX, dy: -paddingY)
    }

    private var cameraBounds: MapCameraBounds {
        MapCameraBounds(
            centerCoordinateBounds: holeRect,
            minimumDistance: 1,
            maximumDistance: maximumCameraDistance
        )
    }

    private var maximumCameraDistance: Double {
        initialCameraDistance
    }

    private var initialCameraCenter: GeoPoint {
        guard let tee = hole.tee, let target = hole.greenCenter else { return hole.tee ?? GeoPoint(lat: 0, lon: 0) }
        return GolfGeometry.interpolate(tee, target, fraction: 0.65)
    }

    private var initialCamera: MapCamera {
        MapCamera(
            centerCoordinate: initialCameraCenter.coordinate,
            distance: initialCameraDistance,
            heading: hole.tee.flatMap { tee in hole.greenCenter.map { GolfGeometry.bearing(from: tee, to: $0) } } ?? 0,
            pitch: 0
        )
    }

    private var initialCameraDistance: Double {
        guard let tee = hole.tee, let target = hole.greenCenter else { return 500 }
        return max(GolfGeometry.distance(tee, target) * 3.8, 500)
    }

    /// Keeps the hole framed while preventing the camera from escaping the active hole bounds.
    private func frameHole() {
        guard hole.tee != nil, hole.greenCenter != nil else { return }
        isZoomedIn = false
        onHeadingChange(initialCamera.heading)
        position = .camera(initialCamera)
    }

}
