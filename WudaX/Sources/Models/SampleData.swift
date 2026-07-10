import Foundation

// MARK: - 示例路线：武功山 龙山村-发云界（演示数据）

enum SampleData {
    static var wugongshan: Route {
        // 手工构造的海拔剖面：起点缓升 → 主升段 → 山脊起伏 → 长下坡
        let profile: [Double] = [
            420, 460, 530, 610, 720, 850, 990, 1130, 1260, 1380,
            1470, 1540, 1600, 1650, 1620, 1660, 1700, 1740, 1710, 1760,
            1790, 1810, 1780, 1750, 1700, 1600, 1470, 1330, 1180, 1020,
            870, 730, 610, 520, 460, 430
        ]
        return Route(
            name: "武功山 · 龙山村—发云界",
            distanceKm: 24.6,
            ascentM: 1780,
            descentM: 1750,
            estimatedHours: 9.5,
            elevationProfile: profile,
            riskPoints: [
                .init(profileIndex: 12, title: "绝望坡顶", detail: "主升段结束，风口失温风险"),
                .init(profileIndex: 21, title: "发云界", detail: "最后补水点，此后无水源"),
                .init(profileIndex: 26, title: "长下坡起点", detail: "连续下降 1200m，对膝盖压力大")
            ],
            hasUnverifiedSegment: true,
            isOutAndBack: false,
            waterSourceCount: 2
        )
    }

    static var plan: TripPlan {
        var p = TripPlan(route: wugongshan)
        p.riskLevel = .mediumHigh
        p.topRisks = [
            "长下坡：后半程连续下降 1200m",
            "时间：按当前计划 17:40 后仍在复杂地形",
            "补水：发云界之后无可靠水源"
        ]
        p.suggestedWaterL = 3.0
        p.suggestedFoodKcal = 1600
        p.checkpoints = ["绝望坡顶 · 10:30 前通过", "发云界 · 13:30 前补水", "下坡起点 · 15:00 前进入"]
        var cal = Calendar.current
        cal.timeZone = .current
        p.sunsetTime = cal.date(bySettingHour: 19, minute: 12, second: 0, of: Date())
        return p
    }

    static let reviewQuestions: [ReviewEntry] = [
        .init(question: "今天最超预期的是哪一项？",
              options: ["路线难度", "补给消耗", "膝盖疼痛", "困倦程度"], answer: nil),
        .init(question: "什么时候开始从「享受路线」变成「只想走出去」？",
              options: ["没有出现", "山脊段", "长下坡上半段", "最后 5 km"], answer: nil),
        .init(question: "补给从什么时候开始不够？",
              options: ["全程充足", "13:00 左右", "下坡段", "最后 1 小时"], answer: nil),
        .init(question: "膝痛从哪一段开始？",
              options: ["没有膝痛", "主升段", "长下坡前段", "长下坡后段"], answer: nil),
        .init(question: "如果重走一次，你会在哪里降级或撤退？",
              options: ["不会降级", "绝望坡顶", "发云界", "下坡起点"], answer: nil)
    ]
}
