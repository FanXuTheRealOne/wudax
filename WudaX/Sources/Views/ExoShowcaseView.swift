import SwiftUI
import SceneKit

enum ExoModelResource {
    static func scene(in bundle: Bundle = .main) -> SCNScene? {
        guard let url = bundle.url(forResource: "exoskeleton", withExtension: "usdz") else { return nil }
        return try? SCNScene(url: url)
    }
}

// MARK: - SceneKit 模型视图

struct ExoModelView: UIViewRepresentable {
    @Binding var loadState: Bool?
    var reduceMotion: Bool

    init(loadState: Binding<Bool?> = .constant(nil), reduceMotion: Bool = false) {
        _loadState = loadState
        self.reduceMotion = reduceMotion
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        view.scene = scene

        // 加载 Meshy 生成的 USDZ
        if let modelScene = ExoModelResource.scene() {
            let node = SCNNode()
            for child in modelScene.rootNode.childNodes {
                node.addChildNode(child)
            }
            // 居中并归一化尺寸
            let (minV, maxV) = node.boundingBox
            let size = SCNVector3(maxV.x - minV.x, maxV.y - minV.y, maxV.z - minV.z)
            let maxDim = max(size.x, max(size.y, size.z))
            let scale = 2.2 / maxDim
            node.scale = SCNVector3(scale, scale, scale)
            node.position = SCNVector3(
                -(minV.x + size.x / 2) * scale,
                -(minV.y + size.y / 2) * scale,
                -(minV.z + size.z / 2) * scale
            )

            let pivot = SCNNode()
            pivot.addChildNode(node)
            scene.rootNode.addChildNode(pivot)

            // 缓慢自转
            if !reduceMotion {
                let spin = CABasicAnimation(keyPath: "rotation")
                spin.fromValue = SCNVector4(0, 1, 0, 0)
                spin.toValue = SCNVector4(0, 1, 0, Float.pi * 2)
                spin.duration = 24
                spin.repeatCount = .infinity
                pivot.addAnimation(spin, forKey: "spin")
            }
            DispatchQueue.main.async { loadState = true }
        } else {
            DispatchQueue.main.async { loadState = false }
        }

        // 相机
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.fieldOfView = 38
        camera.position = SCNVector3(0, 0.2, 4.2)
        scene.rootNode.addChildNode(camera)

        // 灯光：柔和主光 + 琥珀轮廓光 + 环境光
        let key = SCNNode()
        key.light = SCNLight()
        key.light?.type = .directional
        key.light?.intensity = 850
        key.light?.color = UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1)
        key.eulerAngles = SCNVector3(-0.5, 0.6, 0)
        scene.rootNode.addChildNode(key)

        let rim = SCNNode()
        rim.light = SCNLight()
        rim.light?.type = .directional
        rim.light?.intensity = 420
        rim.light?.color = UIColor(red: 0.85, green: 0.51, blue: 0.17, alpha: 1)
        rim.eulerAngles = SCNVector3(0.35, -2.4, 0)
        scene.rootNode.addChildNode(rim)

        let ambient = SCNNode()
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 260
        ambient.light?.color = UIColor(red: 0.56, green: 0.64, blue: 0.60, alpha: 1)
        scene.rootNode.addChildNode(ambient)

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}
}
