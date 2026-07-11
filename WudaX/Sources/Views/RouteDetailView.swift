import SwiftUI

/// 历史记录点开后的路线详情/预览(对应参考图 1、2 的功能):
/// 地图上画出路线 + 原作者信息(明确区别于本 App 用户)+ 关键数据 + 行走记录 log + 开始规划。
struct RouteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var session: TripSession
    let record: RouteRecord
    let onStartPlanning: () -> Void

    private var prov: RouteProvenance { record.provenance }
    /// 这条路线的每一次行走记录(真实持久化数据,最近一次在前)。
    private var walkLogs: [StoredTrip] { session.tripStore.trips(forRoute: record.id) }

    var body: some View {
        ZStack {
            WDColor.inkPine.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        RouteMapView(points: record.document.points)
                            .frame(height: 260)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(WDColor.mossSurface, lineWidth: 1))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(record.name).font(WDFont.title(24)).foregroundStyle(WDColor.ricePaper)
                            Rectangle().fill(WDColor.amber).frame(width: 40, height: 2.5)
                        }

                        statsGrid
                        provenanceCard
                        walkLogCard

                        PillButton(title: "用这条路线开始规划") { onStartPlanning() }
                        Text("原作者数据仅供参考;开始规划后会结合你自己的身体状况重新评估。")
                            .font(WDFont.caption()).foregroundStyle(WDColor.mist.opacity(0.8))
                            .frame(maxWidth: .infinity, alignment: .center)
                        Spacer(minLength: 30)
                    }
                    .padding(22)
                }
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 17, weight: .medium)).foregroundStyle(WDColor.ricePaper)
            }
            Spacer()
            Text("路线详情").font(WDFont.heading(18)).foregroundStyle(WDColor.ricePaper)
            Spacer()
            Color.clear.frame(width: 17, height: 17)
        }
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var statsGrid: some View {
        HStack(spacing: 10) {
            statTile("距离", String(format: "%.1f km", record.distanceKm), "point.topleft.down.curvedto.point.bottomright.up")
            statTile("累计爬升", "\(Int(record.ascentMeters)) m", "mountain.2")
            statTile("最高海拔", prov.maxElevationMeters.map { "\(Int($0)) m" } ?? "—", "arrow.up.to.line")
        }
    }

    private func statTile(_ label: String, _ value: String, _ icon: String) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.system(size: 15, weight: .light)).foregroundStyle(WDColor.amber)
                Text(value).font(.system(size: 18, weight: .semibold, design: .serif)).foregroundStyle(WDColor.ricePaper)
                Text(label).font(WDFont.caption(10)).foregroundStyle(WDColor.mist)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var provenanceCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 30, weight: .light)).foregroundStyle(WDColor.bamboo)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("轨迹原作者").font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                        Text(prov.displayAuthor).font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                    }
                    Spacer()
                    if prov.isRecordedActivity {
                        Text("实测轨迹").font(WDFont.caption(10).weight(.medium))
                            .foregroundStyle(WDColor.bamboo)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Capsule().fill(WDColor.bamboo.opacity(0.15)))
                    }
                }
                Divider().overlay(WDColor.mist.opacity(0.15))
                HStack(spacing: 0) {
                    provItem("原作者用时", prov.recordedDurationText ?? "—")
                    provDivider
                    provItem("原作者配速", prov.paceText ?? "—")
                    provDivider
                    provItem("记录日期", recordedDateText)
                }
                if let software = prov.creatorSoftware {
                    Text("来源:\(software) 导出的 GPX").font(WDFont.caption(10)).foregroundStyle(WDColor.mist.opacity(0.7))
                }
            }
        }
    }

    private func provItem(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(WDFont.mono(14)).foregroundStyle(WDColor.ricePaper)
            Text(label).font(WDFont.caption(10)).foregroundStyle(WDColor.mist)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var provDivider: some View {
        Rectangle().fill(WDColor.mist.opacity(0.15)).frame(width: 1, height: 30).padding(.horizontal, 6)
    }

    // MARK: 行走记录 log —— 每次走这条路线都会在此留一条

    private var walkLogCard: some View {
        InkCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("行走记录", systemImage: "figure.hiking")
                        .font(WDFont.heading(16)).foregroundStyle(WDColor.ricePaper)
                    Spacer()
                    if !walkLogs.isEmpty {
                        Text("\(walkLogs.count) 次").font(WDFont.caption()).foregroundStyle(WDColor.mist)
                    }
                }
                if walkLogs.isEmpty {
                    Text("还没有走过这条路线。开始规划并出发后,每一次行程都会记录在这里。")
                        .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                } else {
                    ForEach(Array(walkLogs.enumerated()), id: \.element.id) { index, trip in
                        walkLogRow(trip)
                        if index != walkLogs.count - 1 {
                            Divider().overlay(WDColor.line)
                        }
                    }
                }
            }
        }
    }

    private func walkLogRow(_ trip: StoredTrip) -> some View {
        HStack(spacing: 12) {
            Circle().fill(trip.summary.peakRisk.color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(logDateText(trip))
                        .font(WDFont.body(14).weight(.medium)).foregroundStyle(WDColor.ricePaper)
                    if trip.endedByRetreat == true {
                        Text("中途撤退").font(WDFont.caption(10).weight(.semibold))
                            .foregroundStyle(WDColor.cinnabar)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(WDColor.cinnabar.opacity(0.12)))
                    } else {
                        Text("完成").font(WDFont.caption(10).weight(.semibold))
                            .foregroundStyle(WDColor.bamboo)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(WDColor.bamboo.opacity(0.12)))
                    }
                }
                Text("\(logDurationText(trip)) · \(String(format: "%.1f km", trip.summary.actualDistanceKm)) · 峰值风险 \(trip.summary.peakRisk.rawValue)")
                    .font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private func logDateText(_ trip: StoredTrip) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy/MM/dd HH:mm"
        return f.string(from: trip.startedAt ?? trip.completedAt)
    }

    private func logDurationText(_ trip: StoredTrip) -> String {
        let hours = trip.summary.actualHours
        let h = Int(hours)
        let m = Int((hours - Double(h)) * 60)
        return "用时 \(h)h\(String(format: "%02d", m))m"
    }

    private var recordedDateText: String {
        guard let date = prov.recordedAt else { return "—" }
        let f = DateFormatter(); f.dateFormat = "yyyy/MM/dd"
        return f.string(from: date)
    }
}
