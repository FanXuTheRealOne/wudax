import SwiftUI

/// 首页「历史 GPX 记录」列表卡片。
struct RouteRecordCard: View {
    let record: RouteRecord
    var onMapTap: (() -> Void)?

    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd"
        return f.string(from: record.provenance.recordedAt ?? record.createdAt)
    }

    var body: some View {
        InkCard {
            HStack(spacing: 14) {
                miniMap

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top) {
                        Text(record.name)
                            .font(WDFont.heading(17)).foregroundStyle(WDColor.ricePaper)
                            .lineLimit(1).minimumScaleFactor(0.8)
                        Spacer(minLength: 6)
                        if record.riskLevel.rank >= RiskLevel.mediumHigh.rank { riskBadge }
                    }
                    Text("\(dateText) · by \(record.provenance.displayAuthor)")
                        .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                        .lineLimit(1)
                    HStack(spacing: 14) {
                        stat("point.topleft.down.curvedto.point.bottomright.up", "\(fmt(record.distanceKm)) km")
                        stat("mountain.2", "\(Int(record.ascentMeters)) m")
                        stat("clock", record.estimatedHoursText)
                    }
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 13)).foregroundStyle(WDColor.mist.opacity(0.7))
            }
        }
    }

    @ViewBuilder
    private var miniMap: some View {
        let preview = ZStack(alignment: .bottomLeading) {
            RouteShapeThumbnail(coordinates: record.coordinates, stroke: record.riskLevel.color)
                .padding(8)
            HStack(spacing: 4) {
                Image(systemName: "map.fill").font(.system(size: 8, weight: .semibold))
                Text("地图").font(WDFont.caption(9).weight(.semibold))
            }
            .foregroundStyle(WDColor.ricePaper)
            .padding(.horizontal, 7).padding(.vertical, 5)
            .background(.black.opacity(0.46), in: Capsule())
            .padding(6)
        }
        .frame(width: 82, height: 74)
        .background(RoundedRectangle(cornerRadius: 12).fill(WDColor.mossSurface))
        .clipShape(RoundedRectangle(cornerRadius: 12))

        if let onMapTap {
            Button(action: onMapTap) { preview }
                .buttonStyle(.plain)
                .accessibilityLabel("在地图中查看 \(record.name)")
        } else {
            preview
        }
    }

    private var riskBadge: some View {
        Label("\(record.riskLevel.rawValue)风险", systemImage: "exclamationmark.triangle.fill")
            .font(WDFont.caption(10).weight(.semibold))
            .foregroundStyle(record.riskLevel.color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Capsule().fill(record.riskLevel.color.opacity(0.15)))
    }

    private func stat(_ icon: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(WDColor.mist.opacity(0.8))
            Text(value).font(WDFont.mono(12)).foregroundStyle(WDColor.ricePaper.opacity(0.9))
        }
    }

    private func fmt(_ v: Double) -> String { String(format: "%.1f", v) }
}
