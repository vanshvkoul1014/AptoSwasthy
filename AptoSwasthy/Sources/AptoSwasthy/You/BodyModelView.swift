import SwiftUI
import SceneKit

/// Renders the user's parametric HumanShape body model in a SceneKit view.
/// Vertices are reconstructed from a small PCA basis (mean + top-K eigenvectors)
/// driven by stature/BMI/sex via BodyShapeMapper.
struct BodyModelView: View {
    let profile: UserProfile
    var muscleMassPercent: Double = 30
    var fillsScreen: Bool = false
    @State private var yaw: Float = 0

    /// Color the avatar by BMI: blue (underweight) → mint green (healthy 18.5–25)
    /// → amber (overweight) → red (obese). Smoothly interpolated so the model
    /// reads as a quick visual health gauge.
    static func bmiColor(_ bmi: Double) -> UIColor {
        let healthy = (r: 0.55, g: 0.92, b: 0.78)   // mint
        let underweight = (r: 0.55, g: 0.78, b: 0.95)
        let overweight = (r: 0.98, g: 0.80, b: 0.40)
        let obese = (r: 0.95, g: 0.45, b: 0.40)

        func mix(_ a: (r: Double, g: Double, b: Double),
                 _ b: (r: Double, g: Double, b: Double),
                 _ t: Double) -> UIColor {
            let t = max(0, min(1, t))
            return UIColor(red: CGFloat(a.r + (b.r - a.r) * t),
                           green: CGFloat(a.g + (b.g - a.g) * t),
                           blue: CGFloat(a.b + (b.b - a.b) * t),
                           alpha: 1)
        }

        switch bmi {
        case ..<16:        return mix(underweight, underweight, 1)
        case 16..<18.5:    return mix(underweight, healthy, (bmi - 16) / 2.5)
        case 18.5..<25:    return mix(healthy, healthy, 1)
        case 25..<30:      return mix(healthy, overweight, (bmi - 25) / 5)
        case 30..<35:      return mix(overweight, obese, (bmi - 30) / 5)
        default:           return mix(obese, obese, 1)
        }
    }

    var body: some View {
        Group {
            if fillsScreen {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                content
                    .frame(height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .glassBackground(cornerRadius: 22)
                    .padding(.horizontal, 20)
            }
        }
        .id(modelIdentity)
    }

    /// Recreate the scene when the body-shape-defining profile fields change,
    /// so edits from PersonalDetailsEditView refresh the avatar immediately.
    private var modelIdentity: String {
        "\(profile.biologicalSex.rawValue)-\(Int(profile.heightCm))-\(Int(profile.weightKg))-\(profile.activityLevel.rawValue)-\(Int(muscleMassPercent))"
    }

    @ViewBuilder
    private var content: some View {
        if let body = ParametricBody.shared {
            SceneViewContainer(scene: makeScene(body: body), yaw: $yaw)
        } else {
            fallback
        }
    }

    private var fallback: some View {
        VStack(spacing: 6) {
            Image(systemName: "figure.stand")
                .font(.system(size: 48, weight: .light))
                .foregroundColor(.tertiaryText)
            Text("Body model unavailable")
                .font(.pearlSubheadline)
                .foregroundColor(.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func makeScene(body: ParametricBody) -> SCNScene {
        let scene = SCNScene()
        scene.background.contents = UIColor.clear

        let scores = BodyShapeMapper.scores(for: profile, kComponents: body.kComponents)
        let (girthScale, heightScale) = BodyShapeMapper.scale(for: profile,
                                                              muscleMassPercent: muscleMassPercent)
        let geometry = body.makeGeometry(scores: scores,
                                         girthScale: girthScale,
                                         heightScale: heightScale)

        // Clean PBR material - soft matte finish that reads as a polished
        // figurine rather than the harsh hologram shader we had before.
        let tint = Self.bmiColor(profile.bmi)

        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = tint
        material.metalness.contents = 0.0
        material.roughness.contents = 0.65
        material.isDoubleSided = false
        material.writesToDepthBuffer = true
        material.readsFromDepthBuffer = true
        material.blendMode = .alpha
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = "body"

        // Stature/BMI scaling is baked into the mesh itself (with a head
        // protection band), so node.scale stays identity and yaw rotates
        // the correctly proportioned mesh. Anchor the pivot at the feet so
        // rotation happens around a vertical axis at floor level (more
        // natural than spinning around the chest).
        let (minB, maxB) = geometry.boundingBox
        let pivotY = minB.y
        node.pivot = SCNMatrix4MakeTranslation(0, pivotY, 0)
        node.position = SCNVector3(0, pivotY, 0)
        scene.rootNode.addChildNode(node)

        // Camera. SCNCamera defaults `projectionDirection` to horizontal - on a
        // portrait iPhone that makes the 34° FOV apply across the narrow axis,
        // which inflates vertical FOV and renders the body squashed/short. Pin
        // FOV to vertical so the model's height fills the viewport consistently
        // regardless of aspect ratio.
        let bodyMidY = (minB.y + maxB.y) * 0.5
        let camNode = SCNNode()
        camNode.camera = SCNCamera()
        camNode.camera?.fieldOfView = 30
        camNode.camera?.projectionDirection = .vertical
        // Center the camera on the body's vertical midpoint so the figure is
        // framed from feet to head. Pulled back so the avatar sits with
        // breathing room. The stats card sits below the view in the layout,
        // so the model naturally appears to stand above it.
        camNode.position = SCNVector3(0, bodyMidY, 5.8)
        camNode.eulerAngles = SCNVector3(0, 0, 0)
        scene.rootNode.addChildNode(camNode)

        // Soft 3-point lighting - key + warm fill + cool back rim. Studio
        // photography style: shape the form without bleaching it. Intensities
        // tuned so the figure reads dimensional but not over-lit.
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 750
        key.light?.color = UIColor.white
        key.eulerAngles = SCNVector3(-0.45, 0.6, 0)
        scene.rootNode.addChildNode(key)

        let fill = SCNNode()
        fill.light = SCNLight()
        fill.light?.type = .ambient
        fill.light?.intensity = 380
        fill.light?.color = UIColor(white: 0.92, alpha: 1.0)
        scene.rootNode.addChildNode(fill)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 320
        rim.light?.color = UIColor(white: 0.95, alpha: 1.0)
        rim.eulerAngles = SCNVector3(0.15, -2.6, 0)
        scene.rootNode.addChildNode(rim)

        return scene
    }
}

private struct SceneViewContainer: UIViewRepresentable {
    let scene: SCNScene
    @Binding var yaw: Float

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = scene
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = true

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        view.addGestureRecognizer(pan)
        context.coordinator.scnView = view
        context.coordinator.yawBinding = $yaw
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        uiView.scene = scene
        if let body = scene.rootNode.childNode(withName: "body", recursively: false) {
            body.eulerAngles.y = yaw
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator: NSObject {
        weak var scnView: SCNView?
        var yawBinding: Binding<Float>?
        private var startYaw: Float = 0

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard let view = scnView,
                  let body = view.scene?.rootNode.childNode(withName: "body", recursively: false)
            else { return }
            let translation = gr.translation(in: view)
            switch gr.state {
            case .began:
                startYaw = body.eulerAngles.y
            case .changed:
                let radiansPerPoint: Float = .pi / 180.0   // 1° per pt of horizontal drag
                let newYaw = startYaw + Float(translation.x) * radiansPerPoint
                body.eulerAngles.y = newYaw
                yawBinding?.wrappedValue = newYaw
            default:
                break
            }
        }
    }
}
