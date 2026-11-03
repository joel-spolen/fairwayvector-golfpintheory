import RealityKit
import SwiftUI

/// Rotatable 3D green: drag to orbit, pinch to zoom; heights exaggerated by `GreenTerrainModel.exaggeration`.
struct GreenTerrain3DView: View {
    let model: GreenTerrainModel
    let texture: CGImage
    let flag: GeoPoint
    /// Tee-to-green bearing in degrees; the first view looks along it, like walking onto the green.
    let approachBearing: Double

    @State private var yaw: Float = 0
    @State private var pitch: Float = 0.6
    @State private var distance: Float = 1
    @State private var dragStart: (yaw: Float, pitch: Float)?
    @State private var pinchStart: Float?

    init(model: GreenTerrainModel, texture: CGImage, flag: GeoPoint, approachBearing: Double) {
        self.model = model
        self.texture = texture
        self.flag = flag
        self.approachBearing = approachBearing
        _yaw = State(initialValue: Float(-approachBearing * .pi / 180))
        _distance = State(initialValue: Float(max(model.width, model.depth)) * 1.15)
    }

    private var defaultDistance: Float { Float(max(model.width, model.depth)) * 1.15 }
    private var approachYaw: Float { Float(-approachBearing * .pi / 180) }

    var body: some View {
        let pose = SIMD3(yaw, pitch, distance)
        RealityView { content in
            content.camera = .virtual
            guard let surface = try? await surfaceEntity() else { return }
            content.add(surface)
            if let pin = model.surfacePoint(flag) { content.add(flagEntity(at: pin)) }

            let light = DirectionalLight()
            light.light.intensity = 2_500
            light.look(at: .zero, from: SIMD3(-20, 30, 15), relativeTo: nil)
            content.add(light)

            let camera = PerspectiveCamera()
            camera.name = "camera"
            camera.camera.fieldOfViewInDegrees = 45
            content.add(camera)
            place(camera, pose: pose)
        } update: { content in
            if let camera = content.entities.first(where: { $0.name == "camera" }) { place(camera, pose: pose) }
        }
        .background(PureLineStyle.canvas)
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    let start = dragStart ?? (yaw, pitch)
                    dragStart = start
                    yaw = start.yaw - Float(value.translation.width) * 0.008
                    pitch = min(max(start.pitch + Float(value.translation.height) * 0.006, 0.15), 1.45)
                }
                .onEnded { _ in dragStart = nil }
                .simultaneously(with: MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStart ?? distance
                        pinchStart = start
                        distance = min(max(start / Float(value.magnification), defaultDistance * 0.3),
                                       defaultDistance * 2.5)
                    }
                    .onEnded { _ in pinchStart = nil })
        )
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 8) {
                Button(L("Reset view"), systemImage: "arrow.counterclockwise") { resetView() }
                Button(L("Top view"), systemImage: "square.dashed") {
                    withAnimation { yaw = approachYaw; pitch = 1.45 }
                }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .tint(PureLineStyle.ink)
            .padding(10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L("3D green. Heights are exaggerated three times."))
    }

    private func resetView() {
        withAnimation {
            yaw = approachYaw
            pitch = 0.6
            distance = defaultDistance
        }
    }

    private func place(_ camera: Entity, pose: SIMD3<Float>) {
        let (yaw, pitch, distance) = (pose.x, pose.y, pose.z)
        let target = SIMD3<Float>(0, Float(model.heights.max() ?? 0) * GreenTerrainModel.exaggeration / 2, 0)
        let offset = SIMD3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw)) * distance
        camera.look(at: target, from: target + offset, relativeTo: nil)
    }

    private func surfaceEntity() async throws -> ModelEntity {
        var descriptor = MeshDescriptor(name: "green")
        descriptor.positions = MeshBuffers.Positions(model.positions)
        descriptor.normals = MeshBuffers.Normals(model.normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(model.textureCoordinates)
        descriptor.primitives = .triangles(model.indices)
        let mesh = try await MeshResource(from: [descriptor])
        let resource = try await TextureResource(image: texture, options: .init(semantic: .color))
        var material = PhysicallyBasedMaterial()
        material.baseColor = .init(texture: .init(resource))
        material.roughness = .init(floatLiteral: 1)
        material.metallic = .init(floatLiteral: 0)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private func flagEntity(at pin: SIMD3<Float>) -> Entity {
        let flag = Entity()
        let pole = ModelEntity(mesh: .generateCylinder(height: 2.1, radius: 0.03),
                               materials: [SimpleMaterial(color: .white, isMetallic: false)])
        pole.position = SIMD3(0, 1.05, 0)
        let cloth = ModelEntity(mesh: .generateBox(width: 0.6, height: 0.4, depth: 0.02),
                                materials: [SimpleMaterial(color: UIColor(PureLineStyle.accent), isMetallic: false)])
        cloth.position = SIMD3(0.3, 1.88, 0)
        flag.addChild(pole)
        flag.addChild(cloth)
        flag.position = pin
        return flag
    }
}
