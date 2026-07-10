import SwiftUI
import SceneKit

// MARK: - 装备：膝关节外骨骼 3D 展示（v2.0 数据接入预留）

struct ExoShowcaseView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var appeared = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [WDColor.mossSurface, WDColor.inkPine, Color(hex: 0x0A1510)],
                startPoint: .top, endPoint: .bottom
            ).ignoresSafeArea()
            ContourBackground(opacity: 0.05).ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("装 备")
                        .font(WDFont.title(26)).foregroundStyle(WDColor.ricePaper)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(WDColor.mist.opacity(0.6))
                    }
                }
                .padding(.horizontal, 24).padding(.top, 20)

                ExoModelView()
                    .frame(maxHeight: .infinity)
                    .opacity(appeared ? 1 : 0)
                    .scaleEffect(appeared ? 1 : 0.92)

                VStack(spacing: 16) {
                    HStack(spacing: 5) {
                        ForEach(0..<3) { i in
                            Circle().fill(i == 0 ? WDColor.amber : WDColor.mist.opacity(0.3))
                                .frame(width: 5, height: 5)
                        }
                        Text("拖动旋转 · 双指缩放")
                            .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                            .padding(.leading, 6)
                    }

                    VStack(spacing: 6) {
                        Text("WUDAX 膝关节外骨骼")
                            .font(WDFont.title(22)).foregroundStyle(WDColor.ricePaper)
                        Text("即将支持 · 行中数据接入预留")
                            .font(WDFont.caption()).foregroundStyle(WDColor.amber)
                    }

                    HStack(spacing: 10) {
                        StatChip(icon: "gauge.with.needle", label: "制动余量", value: "—", tint: WDColor.mist)
                        StatChip(icon: "battery.75", label: "电量", value: "82%", tint: WDColor.bamboo)
                        StatChip(icon: "antenna.radiowaves.left.and.right",
                                 label: "连接", value: "v2.0", tint: WDColor.amber)
                    }

                    Text("未来版本中，外骨骼将以真实膝部力学状态替代部分手动问询——少问你，多懂你。")
                        .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                .padding(.bottom, 30)
            }
        }
        .onAppear { withAnimation(.spring(duration: 1.0).delay(0.2)) { appeared = true } }
    }
}

// MARK: - SceneKit 模型视图

struct ExoModelView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.backgroundColor = .clear
        view.allowsCameraControl = true
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling4X

        let scene = SCNScene()
        view.scene = scene

        // 加载 Meshy 生成的 USDZ
        if let url = Bundle.main.url(forResource: "exoskeleton", withExtension: "usdz"),
           let modelScene = try? SCNScene(url: url) {
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
            let spin = CABasicAnimation(keyPath: "rotation")
            spin.fromValue = SCNVector4(0, 1, 0, 0)
            spin.toValue = SCNVector4(0, 1, 0, Float.pi * 2)
            spin.duration = 24
            spin.repeatCount = .infinity
            pivot.addAnimation(spin, forKey: "spin")
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
