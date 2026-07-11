import Foundation

// MARK: - 示例路线：泥峪河村 · 一脚踏三县（演示数据）

enum SampleData {
    static var niyuhe: Route {
        // 手工构造的海拔剖面：起点缓升 → 主升段 → 一脚踏三县最高点 → 长下坡
        let profile: [Double] = [
            980, 1030, 1110, 1210, 1330, 1470, 1610, 1760, 1900, 2030,
            2140, 2230, 2300, 2360, 2330, 2380, 2430, 2470, 2440, 2500,
            2540, 2560, 2520, 2470, 2400, 2270, 2110, 1940, 1760, 1580,
            1400, 1240, 1110, 1030, 990, 960
        ]
        return Route(
            name: "泥峪河村 · 一脚踏三县",
            distanceKm: 24.6,
            ascentM: 1780,
            descentM: 1810,
            estimatedHours: 9.5,
            elevationProfile: profile,
            riskPoints: [
                .init(profileIndex: 8, title: "石门", detail: "主升段入口，坡度骤增"),
                .init(profileIndex: 21, title: "鹰咀石 · 一脚踏三县", detail: "全线最高点、三县交界，风口失温风险"),
                .init(profileIndex: 27, title: "北头坡沟长下坡", detail: "连续下降，对膝盖压力大；南头坡沟为下撤口")
            ],
            hasUnverifiedSegment: true,
            isOutAndBack: false,
            waterSourceCount: 2
        )
    }

    static var plan: TripPlan {
        var p = TripPlan(route: niyuhe)
        p.riskLevel = .high
        p.topRisks = [
            "拔高与最高海拔均超过你走过最难的一次",
            "鹰咀石之后连续长下坡，对膝盖压力大",
            "北头坡沟—南头坡沟段无可靠水源"
        ]
        p.suggestedWaterL = 3.0
        p.suggestedFoodKcal = 2400
        p.checkpoints = ["石门 · 通过时间确认", "鹰咀石(最高点) · 补水与状态", "南头坡沟 · 下撤决策口"]
        var cal = Calendar.current
        cal.timeZone = .current
        p.sunsetTime = cal.date(bySettingHour: 19, minute: 12, second: 0, of: Date())
        return p
    }

    static let reviewQuestions: [ReviewEntry] = [
        .init(question: "今天最超预期的是哪一项？",
              options: ["路线难度", "补给消耗", "体能状态", "时间安排"], answer: nil),
        .init(question: "什么时候开始从「享受路线」变成「只想走出去」？",
              options: ["没有出现", "石门主升段", "鹰咀石之后", "北头坡沟长下坡"], answer: nil),
        .init(question: "补给从什么时候开始不够？",
              options: ["全程充足", "鹰咀石前", "长下坡段", "最后 1 小时"], answer: nil),
        .init(question: "体能最吃紧的是哪一段？",
              options: ["主升段", "鹰咀石最高点", "北头坡沟长下坡", "全程平稳"], answer: nil),
        .init(question: "如果重走一次，你会在哪里降级或撤退？",
              options: ["不会降级", "石门", "鹰咀石", "南头坡沟下撤口"], answer: nil)
    ]
}
