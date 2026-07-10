import SwiftUI

/// 「数据」Tab —— 本 App 用户自己的疲劳档案与健康数据(与轨迹原作者严格区分)。
struct DataTabView: View {
    @EnvironmentObject var session: TripSession
    @EnvironmentObject var library: RouteLibraryStore

    private var profile: FatigueProfile { session.profile }

    var body: some View {
        ZStack {
            WDColor.inkPine.ignoresSafeArea()
            ContourBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    fatigueSection
                    statsSection
                    healthSection
                    Spacer(minLength: 96)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("数据").font(WDFont.title(30)).foregroundStyle(WDColor.ricePaper)
            Rectangle().fill(WDColor.amber).frame(width: 40, height: 2.5)
        }
        .padding(.top, 8)
    }

    private var fatigueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("我的疲劳档案", systemImage: "doc.text").font(WDFont.heading(17)).foregroundStyle(WDColor.ricePaper)
            HStack(spacing: 12) {
                tile("figure.hiking", "下坡耐受", String(format: "%.1f km", profile.descentToleranceKm), "累计下降后膝痛出现")
                tile("drop", "补给习惯", String(format: "%.2f L/h", profile.waterRatePerHour), "平均耗水速率")
            }
            HStack(spacing: 12) {
                tile("moon.zzz", "困倦阈值", String(format: "%.1f h", profile.drowsinessAfterHours), "行进多久后易困倦")
                tile("calendar", "已记录", "\(profile.tripsRecorded) 次", "行程复盘累计")
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("路线库", systemImage: "square.stack.3d.up").font(WDFont.heading(17)).foregroundStyle(WDColor.ricePaper)
            InkCard {
                HStack(spacing: 0) {
                    summary("\(library.records.count)", "条路线")
                    divider
                    summary(String(format: "%.0f", library.records.reduce(0) { $0 + $1.distanceKm }), "累计 km")
                    divider
                    summary("\(Int(library.records.reduce(0) { $0 + $1.ascentMeters }))", "累计爬升 m")
                }
            }
        }
    }

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Apple Health", systemImage: "heart.text.square").font(WDFont.heading(17)).foregroundStyle(WDColor.ricePaper)
            InkCard {
                VStack(alignment: .leading, spacing: 10) {
                    if let snapshot = session.latestHealthSnapshot ?? session.planning.healthSnapshot,
                       !snapshot.readings.isEmpty {
                        HStack(spacing: 8) {
                            StatChip(icon: "bed.double", label: "睡眠", value: reading(snapshot, .sleepDuration, " h"), tint: WDColor.bamboo)
                            StatChip(icon: "heart", label: "静息心率", value: reading(snapshot, .restingHeartRate, " bpm"), tint: WDColor.amber)
                        }
                    } else {
                        Text("尚未读取到健康数据。在行前规划中连接 Apple Health 后,这里会显示与徒步相关的指标。")
                            .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                    }
                }
            }
        }
    }

    private func tile(_ icon: String, _ title: String, _ value: String, _ note: String) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon).font(.system(size: 18, weight: .light)).foregroundStyle(WDColor.bamboo)
                Text(title).font(WDFont.caption()).foregroundStyle(WDColor.mist)
                Text(value).font(WDFont.mono(17)).foregroundStyle(WDColor.ricePaper)
                Text(note).font(WDFont.caption(10)).foregroundStyle(WDColor.mist.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func summary(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 22, weight: .semibold, design: .serif)).foregroundStyle(WDColor.ricePaper)
            Text(label).font(WDFont.caption(10)).foregroundStyle(WDColor.mist)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(WDColor.mist.opacity(0.15)).frame(width: 1, height: 34)
    }

    private func reading(_ snapshot: HealthSnapshot, _ metric: HealthMetric, _ suffix: String) -> String {
        guard let value = snapshot.reading(metric)?.value else { return "—" }
        return "\(String(format: "%.1f", value))\(suffix)"
    }
}
