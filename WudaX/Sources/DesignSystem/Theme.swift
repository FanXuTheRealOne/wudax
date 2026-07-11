import SwiftUI

// MARK: - WUDAX 设计系统
// 品牌内核：庄子「无待」— 无感、自然、舒适。平时安静，关键时刻主动。

enum WDColor {
    // 清新山野 · 浅色主题(沿用队友 preview/fresh.css 的设计语言)
    // 名字保持不变以兼容全部视图,但语义重映射为浅色主题的角色。

    /// 主背景 — 清新米绿画布(原「墨松绿」角色 → 现浅底)
    static let inkPine = Color(hex: 0xF3F6F0)
    /// 卡片背景 — 宣纸白(原深卡 → 现白卡)
    static let deepMoss = Color(hex: 0xFCFBF6)
    /// 浅色表面 — 淡青绿(chips / 缩略图 / 开关底)
    static let mossSurface = Color(hex: 0xE7EFE5)
    /// 主文字 — 深墨绿(原「宣纸白正文」→ 现深字)
    static let ricePaper = Color(hex: 0x26352F)
    /// 次级文字 — 雾灰绿
    static let mist = Color(hex: 0x66766E)
    /// 琥珀 / 阳光橙 — 谨慎 / 提醒 / 强调
    static let amber = Color(hex: 0xE39A45)
    /// 朱砂 — 撤退 / 危险
    static let cinnabar = Color(hex: 0xC24A3E)
    /// 松绿 — 安全 / 继续 / 图形描边
    static let bamboo = Color(hex: 0x4C8163)
    /// 深松绿 — 主按钮填充 / 强调标题
    static let ink = Color(hex: 0x17382D)
    /// 深色表面上的浅字(主按钮 / 手表 mockup 文字)
    static let onDark = Color(hex: 0xF6FAF3)
    /// 分隔线
    static let line = Color(hex: 0xDCE4DC)
    /// 手表 / 灵动岛等刻意保持深色的表面
    static let nightSurface = Color(hex: 0x1B2B25)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

enum WDFont {
    /// 大标题 — 衬线（宋体气质）
    static func title(_ size: CGFloat = 28) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
    static func heading(_ size: CGFloat = 19) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular)
    }
    static func caption(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .regular)
    }
    static func mono(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .medium, design: .monospaced)
    }
}

// MARK: - 风险等级

enum RiskLevel: String, CaseIterable, Codable {
    case low = "低"
    case medium = "中"
    case mediumHigh = "中高"
    case high = "高"

    var color: Color {
        switch self {
        case .low: return WDColor.bamboo
        case .medium: return WDColor.mist
        case .mediumHigh: return WDColor.amber
        case .high: return WDColor.cinnabar
        }
    }

    var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .mediumHigh: return 2
        case .high: return 3
        }
    }
}

// MARK: - Agent 结论

enum AgentVerdict: String, Codable {
    case proceed = "继续"
    case cautious = "谨慎继续"
    case downgrade = "建议降级"
    case retreat = "建议撤退"

    var color: Color {
        switch self {
        case .proceed: return WDColor.bamboo
        case .cautious: return WDColor.amber
        case .downgrade: return WDColor.amber
        case .retreat: return WDColor.cinnabar
        }
    }

    var icon: String {
        switch self {
        case .proceed: return "arrow.up.forward"
        case .cautious: return "eye"
        case .downgrade: return "arrow.turn.right.down"
        case .retreat: return "arrow.uturn.backward"
        }
    }
}
