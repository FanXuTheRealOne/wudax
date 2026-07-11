import SwiftUI

// MARK: - 印章徽标（风险等级 / Agent 结论用）

struct SealBadge: View {
    let text: String
    let color: Color
    var size: CGFloat = 72

    var body: some View {
        Text(text)
            .font(.system(size: size * 0.3, weight: .bold, design: .serif))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.16)
                    .stroke(color, lineWidth: 2.5)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.16)
                            .fill(color.opacity(0.08))
                    )
            )
            .rotationEffect(.degrees(-3))
    }
}

// MARK: - 宣纸卡片

struct InkCard<Content: View>: View {
    var light = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(WDColor.deepMoss)
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(WDColor.line, lineWidth: 1))
                    .shadow(color: WDColor.ink.opacity(0.06), radius: 14, y: 6)
            )
    }
}

// MARK: - 主按钮

struct PillButton: View {
    let title: String
    var color: Color = WDColor.ink
    var textColor: Color = WDColor.onDark
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WDFont.body(16).weight(.semibold))
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(color)
                    .shadow(color: color.opacity(0.22), radius: 10, y: 6))
        }
        .buttonStyle(.plain)
    }
}

struct GhostButton: View {
    let title: String
    var color: Color = WDColor.ink
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(WDFont.body(15).weight(.medium))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 等高线背景

struct ContourBackground: View {
    var opacity: Double = 0.06

    var body: some View {
        Canvas { ctx, size in
            for i in 0..<7 {
                var path = Path()
                let baseY = size.height * (0.15 + Double(i) * 0.13)
                path.move(to: CGPoint(x: -20, y: baseY))
                var x: CGFloat = -20
                while x < size.width + 20 {
                    let y = baseY + sin((x / size.width) * .pi * 2 + Double(i) * 1.3) * 18
                        + cos((x / size.width) * .pi * 5 + Double(i)) * 7
                    path.addLine(to: CGPoint(x: x, y: y))
                    x += 8
                }
                ctx.stroke(path, with: .color(WDColor.mist.opacity(opacity)), lineWidth: 0.8)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 海拔剖面图

struct ElevationProfileView: View {
    let points: [Double]          // 海拔序列
    var riskIndices: [Int] = []   // 风险点位置
    var markerIndex: Int? = nil   // 当前位置 / 不可逆点
    var markerColor: Color = WDColor.cinnabar
    var height: CGFloat = 120

    var body: some View {
        GeometryReader { geo in
            let pts = computePoints(in: geo.size)

            ZStack {
                // 填充
                Path { p in
                    p.move(to: CGPoint(x: 0, y: geo.size.height))
                    for pt in pts { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(
                    LinearGradient(
                        colors: [WDColor.bamboo.opacity(0.25), .clear],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                // 轮廓
                Path { p in
                    p.move(to: pts[0])
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(WDColor.ricePaper.opacity(0.85), lineWidth: 1.8)

                // 风险点
                ForEach(riskIndices, id: \.self) { i in
                    Circle()
                        .fill(WDColor.amber)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(WDColor.amber.opacity(0.35), lineWidth: 6))
                        .position(pts[min(i, pts.count - 1)])
                }

                // 当前位置 / 不可逆点
                if let m = markerIndex {
                    let p = pts[min(m, pts.count - 1)]
                    Path { path in
                        path.move(to: CGPoint(x: p.x, y: 4))
                        path.addLine(to: CGPoint(x: p.x, y: geo.size.height - 2))
                    }
                    .stroke(markerColor, style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                    Circle()
                        .fill(markerColor)
                        .frame(width: 10, height: 10)
                        .position(p)
                }
            }
        }
        .frame(height: height)
    }

    private func computePoints(in size: CGSize) -> [CGPoint] {
        let maxE = points.max() ?? 1
        let minE = points.min() ?? 0
        let range = max(maxE - minE, 1)
        let stepX = size.width / CGFloat(points.count - 1)
        return points.indices.map { i in
            CGPoint(
                x: CGFloat(i) * stepX,
                y: size.height * (1 - CGFloat((points[i] - minE) / range) * 0.85 - 0.05)
            )
        }
    }
}

// MARK: - 统计小片

struct StatChip: View {
    let icon: String
    let label: String
    let value: String
    var tint: Color = WDColor.mist

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(WDFont.caption(10)).foregroundStyle(WDColor.mist)
                Text(value).font(WDFont.mono(13)).foregroundStyle(WDColor.ricePaper)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(WDColor.mossSurface))
    }
}

// MARK: - 0-10 打分滑条

struct ScaleQuestion: View {
    let title: String
    let lowLabel: String
    let highLabel: String
    @Binding var value: Double
    var warnThreshold: Double = 4

    private var tint: Color {
        value >= warnThreshold + 3 ? WDColor.cinnabar
        : value >= warnThreshold ? WDColor.amber
        : WDColor.bamboo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                Spacer()
                Text("\(Int(value))")
                    .font(WDFont.mono(22))
                    .foregroundStyle(tint)
                    .contentTransition(.numericText())
            }
            Slider(value: $value, in: 0...10, step: 1)
                .tint(tint)
            HStack {
                Text(lowLabel).font(WDFont.caption()).foregroundStyle(WDColor.mist)
                Spacer()
                Text(highLabel).font(WDFont.caption()).foregroundStyle(WDColor.mist)
            }
        }
    }
}
