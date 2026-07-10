import SwiftUI

/// 由 GPX 经纬度折线绘制的路线形状缩略图(真实几何,非占位图)。
struct RouteShapeThumbnail: View {
    let coordinates: [(lat: Double, lon: Double)]
    var stroke: Color = WDColor.bamboo

    var body: some View {
        Canvas { ctx, size in
            guard coordinates.count >= 2 else { return }
            let lats = coordinates.map(\.lat)
            let lons = coordinates.map(\.lon)
            let minLat = lats.min()!, maxLat = lats.max()!
            let minLon = lons.min()!, maxLon = lons.max()!
            let spanLat = max(maxLat - minLat, 1e-6)
            let spanLon = max(maxLon - minLon, 1e-6)
            let span = max(spanLat, spanLon)
            let pad: CGFloat = 10
            let w = size.width - pad * 2
            let h = size.height - pad * 2
            let offX = (1 - spanLon / span) / 2
            let offY = (1 - spanLat / span) / 2

            func point(_ c: (lat: Double, lon: Double)) -> CGPoint {
                let nx = (c.lon - minLon) / span + offX
                let ny = (c.lat - minLat) / span + offY
                return CGPoint(x: pad + CGFloat(nx) * w,
                               y: pad + h - CGFloat(ny) * h) // 纬度向上翻转
            }

            var path = Path()
            path.move(to: point(coordinates[0]))
            for c in coordinates.dropFirst() { path.addLine(to: point(c)) }
            ctx.stroke(path, with: .color(stroke),
                       style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

            // 起点
            let start = point(coordinates[0])
            ctx.fill(Path(ellipseIn: CGRect(x: start.x - 3, y: start.y - 3, width: 6, height: 6)),
                     with: .color(WDColor.ricePaper))
        }
    }
}
