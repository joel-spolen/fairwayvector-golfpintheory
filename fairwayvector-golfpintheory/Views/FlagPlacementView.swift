import MapKit
import SwiftUI

struct FlagPlacementView: View {
    let hole: Hole
    let initialFlag: GeoPoint
    var greenSlope: GreenSlopeMap? = nil
    var slopeUnavailable = false
    /// Nil hides the slope switch (no course elevation, or elevation is off for this round).
    var showsSlope: Binding<Bool>? = nil
    var terrain: CourseTerrain? = nil
    let onSave: (GeoPoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var flag: GeoPoint
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var isDraggingFlag = false
    @State private var cameraRevision = 0
    @State private var showsGreen3D = false
    @State private var green3D: (model: GreenTerrainModel, texture: CGImage)?
    @State private var green3DUnavailable = false

    init(hole: Hole, initialFlag: GeoPoint, greenSlope: GreenSlopeMap? = nil, slopeUnavailable: Bool = false,
         showsSlope: Binding<Bool>? = nil, terrain: CourseTerrain? = nil, onSave: @escaping (GeoPoint) -> Void) {
        self.hole = hole
        self.initialFlag = initialFlag
        self.greenSlope = greenSlope
        self.slopeUnavailable = slopeUnavailable
        self.showsSlope = showsSlope
        self.terrain = terrain
        self.onSave = onSave
        _flag = State(initialValue: initialFlag)
    }

    private var approachBearing: Double {
        guard let center = hole.greenCenter, let tee = hole.tee else { return 0 }
        return GolfGeometry.bearing(from: tee, to: center)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showsSlope != nil, terrain != nil {
                    Picker(L("View"), selection: $showsGreen3D) {
                        Text(L("Map")).tag(false)
                        Text(verbatim: "3D").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .padding([.horizontal, .top])
                }

                Text(showsGreen3D ? L("Drag to rotate · pinch to zoom · heights ×3")
                     : hole.green.count >= 3
                     ? L("Tap the green or drag the flag to move it.")
                     : L("Tap near the mapped green center or drag the flag to move it."))
                    .font(.subheadline)
                    .foregroundStyle(PureLineStyle.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()

                if let showsSlope, !showsGreen3D {
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle(L("Show green slope"), isOn: showsSlope)
                            .font(.subheadline.weight(.medium))
                            .tint(PureLineStyle.accent)
                        Text("Experimental · may not match the green exactly")
                            .font(.caption)
                            .foregroundStyle(PureLineStyle.muted)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                }

                Group {
                    if showsGreen3D {
                        green3DView
                    } else {
                        mapView
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(PureLineStyle.canvas)
            .task(id: showsGreen3D) {
                guard showsGreen3D, green3D == nil, !green3DUnavailable, let terrain else { return }
                if let model = GreenTerrainModel.make(terrain: terrain, hole: hole), let texture = model.texture() {
                    green3D = (model, texture)
                } else {
                    green3DUnavailable = true
                }
            }
            .navigationTitle(L("Green & pin · Hole %@", "\(hole.number)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(flag) }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                if let center = hole.greenCenter {
                    cameraPosition = .camera(
                        MapCamera(centerCoordinate: center.coordinate, distance: 120, heading: approachBearing, pitch: 0)
                    )
                }
            }
        }
    }

    @ViewBuilder private var green3DView: some View {
        if let green3D {
            GreenTerrain3DView(model: green3D.model, texture: green3D.texture, flag: flag,
                               approachBearing: approachBearing)
                .overlay(alignment: .bottomLeading) {
                    GreenSlopeLegend(available: true, mappedOutline: green3D.model.slope.usesMappedOutline)
                        .padding(10)
                        .allowsHitTesting(false)
                }
        } else if green3DUnavailable {
            ContentUnavailableView(L("No detailed elevation for this green"), systemImage: "cube.transparent")
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var mapView: some View {
        MapReader { proxy in
            Map(position: $cameraPosition, interactionModes: []) {
                if hole.green.count >= 3 {
                    MapPolygon(coordinates: hole.green.map(\.coordinate))
                        .foregroundStyle(PureLineStyle.accent.opacity(0.22))
                        .stroke(PureLineStyle.accent, lineWidth: 2)
                }

                Annotation(L("Flag"), coordinate: flag.coordinate, anchor: .bottom) {
                    Image(systemName: "flag.fill")
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(PureLineStyle.accent)
                        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                        .frame(width: 72, height: 84)
                        .contentShape(Rectangle())
                }
                .annotationTitles(.hidden)
            }
            .mapStyle(.imagery(elevation: .flat))
            .onMapCameraChange(frequency: .continuous) { _ in cameraRevision &+= 1 }
            .overlay {
                if let greenSlope, showsSlope?.wrappedValue == true {
                    Canvas { context, _ in
                        greenSlope.draw(in: &context) { proxy.convert($0.coordinate, to: .local) }
                    }
                    .id(cameraRevision)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            // On top of the map so showing it never resizes the map under the heatmap.
            .overlay(alignment: .bottomLeading) {
                if showsSlope?.wrappedValue == true {
                    GreenSlopeLegend(available: !slopeUnavailable,
                                     mappedOutline: greenSlope?.usesMappedOutline == true)
                        .padding(10)
                        .allowsHitTesting(false)
                }
            }
            .onTapGesture { screenPoint in
                moveFlag(to: screenPoint, using: proxy)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        if !isDraggingFlag {
                            guard let markerPoint = proxy.convert(flag.coordinate, to: .local) else { return }
                            let dx = value.startLocation.x - markerPoint.x
                            let dy = value.startLocation.y - markerPoint.y
                            guard hypot(dx, dy) <= 60 else { return }
                            isDraggingFlag = true
                        }
                        moveFlag(to: value.location, using: proxy)
                    }
                    .onEnded { _ in isDraggingFlag = false }
            )
        }
    }

    private func moveFlag(to screenPoint: CGPoint, using proxy: MapProxy) {
        guard let coordinate = proxy.convert(screenPoint, from: .local) else { return }
        let candidate = GeoPoint(coordinate)
        if hole.green.count >= 3 {
            guard GolfGeometry.contains(candidate, in: hole.green) else { return }
        } else {
            guard let center = hole.greenCenter,
                  GolfGeometry.distance(candidate, center) <= 25 else { return }
        }
        flag = candidate
    }
}
