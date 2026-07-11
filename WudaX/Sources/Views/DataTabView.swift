import SwiftUI

/// 「数据」Tab —— 本 App 用户自己的疲劳档案与健康数据(与轨迹原作者严格区分)。
struct DataTabView: View {
    @EnvironmentObject var session: TripSession
    @EnvironmentObject var library: RouteLibraryStore

    private var profile: FatigueProfile { session.profile }
    private var experience: HikerExperience { session.planning.experience }

    var body: some View {
        ZStack {
            WDColor.inkPine.ignoresSafeArea()
            ContourBackground().ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    fatigueSection
                    routeCapabilitySection
                    capabilityRadarSection
                    statsSection
                    healthSection
                    Spacer(minLength: 96)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
            }
        }
        .task {
            await session.refreshAppleHealthAccess()
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

    private var routeCapabilitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("当前线路能力", systemImage: "mountain.2")
                .font(WDFont.heading(17))
                .foregroundStyle(WDColor.ricePaper)

            capabilityZoneCard(
                title: "舒适区",
                subtitle: "可稳定完成，余量相对充足",
                icon: "checkmark.seal.fill",
                color: WDColor.bamboo,
                details: ["8–12 km / 600–900 m 爬升", "明确路迹 / 当日往返"]
            )
            capabilityZoneCard(
                title: "挑战区",
                subtitle: "需要节奏控制与完整准备",
                icon: "figure.hiking",
                color: WDColor.amber,
                details: ["12–18 km / 900–1400 m 爬升", "中等长下坡 / 需严格补给"]
            )
            capabilityZoneCard(
                title: "红线区",
                subtitle: "风险叠加时不建议进入",
                icon: "exclamationmark.triangle.fill",
                color: WDColor.cinnabar,
                details: ["长下坡 + 低补给 + 夜间风险", "路迹不确定 / 膝痛历史触发"]
            )
        }
    }

    private func capabilityZoneCard(title: String,
                                    subtitle: String,
                                    icon: String,
                                    color: Color,
                                    details: [String]) -> some View {
        InkCard {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(color.opacity(0.12)))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title)
                            .font(WDFont.heading(16))
                            .foregroundStyle(WDColor.ricePaper)
                        Spacer()
                        Text(subtitle)
                            .font(WDFont.caption(10))
                            .foregroundStyle(color)
                    }
                    ForEach(details, id: \.self) { detail in
                        HStack(alignment: .top, spacing: 7) {
                            Circle().fill(color.opacity(0.75)).frame(width: 5, height: 5).padding(.top, 6)
                            Text(detail)
                                .font(WDFont.body(13))
                                .foregroundStyle(WDColor.mist)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var capabilityRadarSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("能力维度", systemImage: "chart.xyaxis.line")
                .font(WDFont.heading(17))
                .foregroundStyle(WDColor.ricePaper)

            InkCard {
                VStack(spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("六维能力雷达")
                                .font(WDFont.heading(16))
                                .foregroundStyle(WDColor.ricePaper)
                            Text("根据个人档案与历史表现估算")
                                .font(WDFont.caption(10))
                                .foregroundStyle(WDColor.mist)
                        }
                        Spacer()
                        Text("持续校准")
                            .font(WDFont.caption(10).weight(.semibold))
                            .foregroundStyle(WDColor.bamboo)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(Capsule().fill(WDColor.bamboo.opacity(0.12)))
                    }

                    CapabilityRadarChart(dimensions: capabilityDimensions)
                        .frame(height: 280)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                        ForEach(capabilityDimensions) { dimension in
                            HStack(spacing: 7) {
                                Circle().fill(dimension.color).frame(width: 7, height: 7)
                                Text(dimension.name)
                                    .font(WDFont.caption(11))
                                    .foregroundStyle(WDColor.mist)
                                Spacer()
                                Text("\(Int((dimension.score * 100).rounded()))")
                                    .font(WDFont.mono(11))
                                    .foregroundStyle(WDColor.ricePaper)
                            }
                        }
                    }

                    Text("负重维度暂以长时程与爬升经历保守估算；完成更多带负重、补给和恢复记录后会逐步替换为真实能力值。")
                        .font(WDFont.caption(10))
                        .foregroundStyle(WDColor.mist.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var capabilityDimensions: [CapabilityDimension] {
        let hasExperience = experience.isComplete
        let endurance = hasExperience
            ? normalized(experience.hardestDistanceKm * 0.65, target: 18 * 0.65,
                         plus: experience.longestDurationH * 0.35, plusTarget: 10 * 0.35)
            : 0.56
        let climbing = experience.hardestAscentM > 0
            ? normalized(experience.hardestAscentM, target: 1_400)
            : 0.54
        let descending = normalized(profile.descentToleranceKm, target: 12)
        let loadBearing = hasExperience
            ? min(0.85, 0.35 + normalized(experience.longestDurationH, target: 12) * 0.3
                  + normalized(experience.hardestAscentM, target: 1_600) * 0.2)
            : 0.45
        let supplyManagement = min(0.88, 0.48 + Double(min(profile.tripsRecorded, 10)) * 0.04)
        let sleepHours = (session.latestHealthSnapshot ?? session.planning.healthSnapshot)?
            .reading(.sleepDuration)?.value ?? 7
        let recovery = min(0.9, normalized(profile.drowsinessAfterHours, target: 10) * 0.65
                           + normalized(sleepHours, target: 8) * 0.35)

        return [
            .init(name: "耐力", score: endurance, color: WDColor.bamboo),
            .init(name: "爬坡", score: climbing, color: WDColor.bamboo),
            .init(name: "下坡", score: descending, color: WDColor.amber),
            .init(name: "负重", score: loadBearing, color: WDColor.amber),
            .init(name: "补给管理", score: supplyManagement, color: WDColor.bamboo),
            .init(name: "恢复能力", score: recovery, color: WDColor.mist)
        ]
    }

    private func normalized(_ value: Double, target: Double) -> Double {
        min(max(value / max(target, 0.01), 0.2), 1)
    }

    private func normalized(_ value: Double,
                            target: Double,
                            plus: Double,
                            plusTarget: Double) -> Double {
        min(max((value + plus) / max(target + plusTarget, 0.01), 0.2), 1)
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
            HStack {
                Label("Apple Health", systemImage: "heart.text.square")
                    .font(WDFont.heading(17)).foregroundStyle(WDColor.ricePaper)
                Spacer()
                Text("Apple Watch / iPhone")
                    .font(WDFont.caption(10)).foregroundStyle(WDColor.bamboo)
            }

            if let snapshot = session.latestHealthSnapshot ?? session.planning.healthSnapshot,
               !snapshot.readings.isEmpty {
                healthHeartCard(snapshot)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    healthMetricCard(snapshot, metric: .restingHeartRate,
                                     title: "静息心率", icon: "heart", unit: "bpm", tint: WDColor.amber)
                    healthMetricCard(snapshot, metric: .heartRateVariability,
                                     title: "心率变异性", icon: "waveform.path.ecg", unit: "ms", tint: WDColor.bamboo)
                    healthMetricCard(snapshot, metric: .oxygenSaturation,
                                     title: "血氧", icon: "lungs.fill", unit: "%", tint: WDColor.bamboo)
                    healthMetricCard(snapshot, metric: .respiratoryRate,
                                     title: "呼吸频率", icon: "wind", unit: "次/分", tint: WDColor.mist)
                    healthMetricCard(snapshot, metric: .sleepDuration,
                                     title: "最近睡眠", icon: "bed.double.fill", unit: "h", tint: WDColor.mist)
                    healthMetricCard(snapshot, metric: .vo2Max,
                                     title: "最大摄氧量", icon: "figure.run", unit: "", tint: WDColor.amber)
                }

                healthActivityCard(snapshot)

                Text("更新于 \(healthTime(snapshot.capturedAt)) · 行程中每分钟尝试刷新一次")
                    .font(WDFont.caption(10)).foregroundStyle(WDColor.mist.opacity(0.72))
            } else {
                InkCard {
                    Text("尚未读取到健康数据。请在“设置 → Apple Health 授权”中连接；授权后这里会显示与徒步相关的指标。")
                        .font(WDFont.caption()).foregroundStyle(WDColor.mist)
                }
            }
        }
    }

    private func healthHeartCard(_ snapshot: HealthSnapshot) -> some View {
        let sample = snapshot.reading(.heartRate)
            ?? snapshot.reading(.walkingHeartRateAverage)
            ?? snapshot.reading(.restingHeartRate)
        let value = sample.map { String(format: "%.0f", $0.value) } ?? "—"
        let source = sample?.sourceName ?? "Apple Health"

        return InkCard {
            HStack(spacing: 16) {
                ZStack {
                    Circle().fill(WDColor.cinnabar.opacity(0.12)).frame(width: 56, height: 56)
                    Circle().stroke(WDColor.cinnabar.opacity(0.25), lineWidth: 1).frame(width: 45, height: 45)
                    Image(systemName: "heart.fill")
                        .font(.system(size: 22, weight: .medium)).foregroundStyle(WDColor.cinnabar)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("最近心率").font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(value).font(WDFont.mono(32)).foregroundStyle(WDColor.ricePaper)
                        Text("bpm").font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                    }
                    Text(sample.map { "\(source) · \(healthTime($0.sampledAt))" } ?? "等待手表同步心率样本")
                        .font(WDFont.caption(10)).foregroundStyle(WDColor.mist.opacity(0.72))
                }
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 28, weight: .light)).foregroundStyle(WDColor.cinnabar.opacity(0.7))
            }
        }
    }

    private func healthMetricCard(_ snapshot: HealthSnapshot,
                                  metric: HealthMetric,
                                  title: String,
                                  icon: String,
                                  unit: String,
                                  tint: Color) -> some View {
        let sample = snapshot.reading(metric)
        let value = sample.map { healthValue($0.value, metric: metric) } ?? "—"
        return InkCard {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(tint)
                Text(title).font(WDFont.caption(10)).foregroundStyle(WDColor.mist)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value).font(WDFont.mono(18)).foregroundStyle(WDColor.ricePaper)
                    if !unit.isEmpty {
                        Text(unit).font(WDFont.caption(9)).foregroundStyle(WDColor.mist)
                    }
                }
                Text(sample.map { healthTime($0.sampledAt) } ?? "暂无样本")
                    .font(WDFont.caption(9)).foregroundStyle(WDColor.mist.opacity(0.65))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func healthActivityCard(_ snapshot: HealthSnapshot) -> some View {
        InkCard {
            VStack(alignment: .leading, spacing: 13) {
                Text("今日活动").font(WDFont.heading(15)).foregroundStyle(WDColor.ricePaper)
                activityBar(snapshot, metric: .steps, title: "步数", unit: "步", goal: 10_000, tint: WDColor.bamboo)
                activityBar(snapshot, metric: .activeEnergy, title: "活动能量", unit: "kcal", goal: 600, tint: WDColor.amber)
                activityBar(snapshot, metric: .exerciseTime, title: "运动时间", unit: "min", goal: 30, tint: WDColor.cinnabar)
                activityBar(snapshot, metric: .walkingRunningDistance, title: "步行跑步距离", unit: "km",
                            goal: 8_000, tint: WDColor.mist, divisor: 1_000)
            }
        }
    }

    private func activityBar(_ snapshot: HealthSnapshot,
                             metric: HealthMetric,
                             title: String,
                             unit: String,
                             goal: Double,
                             tint: Color,
                             divisor: Double = 1) -> some View {
        let rawValue = snapshot.reading(metric)?.value ?? 0
        let displayed = rawValue / divisor
        return VStack(spacing: 6) {
            HStack {
                Text(title).font(WDFont.caption(11)).foregroundStyle(WDColor.mist)
                Spacer()
                Text("\(String(format: divisor == 1 ? "%.0f" : "%.1f", displayed)) \(unit)")
                    .font(WDFont.mono(11)).foregroundStyle(WDColor.ricePaper)
            }
            ProgressView(value: min(max(rawValue / goal, 0), 1))
                .tint(tint)
                .background(WDColor.mist.opacity(0.12))
        }
    }

    private func healthValue(_ value: Double, metric: HealthMetric) -> String {
        switch metric {
        case .oxygenSaturation, .bodyFat, .walkingAsymmetry, .walkingDoubleSupport:
            return String(format: "%.0f", value <= 1 ? value * 100 : value)
        case .heartRate, .restingHeartRate, .walkingHeartRateAverage, .respiratoryRate,
             .heartRateVariability, .vo2Max:
            return String(format: "%.0f", value)
        default:
            return String(format: "%.1f", value)
        }
    }

    private func healthTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "今天 HH:mm" : "MM/dd HH:mm"
        return formatter.string(from: date)
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

}

private struct CapabilityDimension: Identifiable {
    let name: String
    let score: Double
    let color: Color

    var id: String { name }
}

private struct CapabilityRadarChart: View {
    let dimensions: [CapabilityDimension]

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = min(geometry.size.width, geometry.size.height) * 0.31
            let values = dimensions.map(\.score)

            ZStack {
                ForEach(1...4, id: \.self) { level in
                    RadarPolygonShape(values: Array(repeating: Double(level) / 4, count: dimensions.count))
                        .stroke(WDColor.line.opacity(level == 4 ? 0.95 : 0.65), lineWidth: 1)
                }

                RadarAxesShape(axisCount: dimensions.count)
                    .stroke(WDColor.line.opacity(0.65), lineWidth: 1)

                RadarPolygonShape(values: values)
                    .fill(WDColor.bamboo.opacity(0.18))

                RadarPolygonShape(values: values)
                    .stroke(WDColor.bamboo, style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))

                ForEach(Array(dimensions.indices), id: \.self) { index in
                    let valuePoint = radarPoint(index: index,
                                                count: dimensions.count,
                                                radius: radius * dimensions[index].score,
                                                center: center)
                    Circle()
                        .fill(dimensions[index].color)
                        .overlay(Circle().stroke(WDColor.deepMoss, lineWidth: 2))
                        .frame(width: 9, height: 9)
                        .position(valuePoint)

                    let labelPoint = radarPoint(index: index,
                                                count: dimensions.count,
                                                radius: radius * 1.34,
                                                center: center)
                    Text(dimensions[index].name)
                        .font(WDFont.caption(11).weight(.medium))
                        .foregroundStyle(WDColor.ricePaper)
                        .position(labelPoint)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                dimensions.map { "\($0.name) \(Int(($0.score * 100).rounded())) 分" }
                    .joined(separator: "，")
            )
        }
    }
}

private struct RadarPolygonShape: Shape {
    let values: [Double]

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count >= 3 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.31

        for index in values.indices {
            let point = radarPoint(index: index,
                                   count: values.count,
                                   radius: radius * min(max(values[index], 0), 1),
                                   center: center)
            if index == values.startIndex {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}

private struct RadarAxesShape: Shape {
    let axisCount: Int

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard axisCount >= 3 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.31

        for index in 0..<axisCount {
            path.move(to: center)
            path.addLine(to: radarPoint(index: index,
                                        count: axisCount,
                                        radius: radius,
                                        center: center))
        }
        return path
    }
}

private func radarPoint(index: Int,
                        count: Int,
                        radius: CGFloat,
                        center: CGPoint) -> CGPoint {
    let angle = -CGFloat.pi / 2 + CGFloat(index) * 2 * CGFloat.pi / CGFloat(max(count, 1))
    return CGPoint(x: center.x + cos(angle) * radius,
                   y: center.y + sin(angle) * radius)
}
