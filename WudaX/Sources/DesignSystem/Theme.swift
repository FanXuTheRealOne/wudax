import SwiftUI

// MARK: - WUDAX 设计系统
// 品牌内核：庄子「无待」— 无感、自然、舒适。平时安静，关键时刻主动。

enum WDColor {
    /// 墨松绿 — 主背景
    static let inkPine = Color(hex: 0x0F1E18)
    /// 深苔绿 — 卡片深底 / 次级背景
    static let deepMoss = Color(hex: 0x1B2B25)
    /// 苔面 — 浮层
    static let mossSurface = Color(hex: 0x24352E)
    /// 宣纸白 — 亮色卡片 / 主文字
    static let ricePaper = Color(hex: 0xF5F1E8)
    /// 雾灰绿 — 次级文字
    static let mist = Color(hex: 0x8FA39A)
    /// 琥珀 — 谨慎 / 提醒
    static let amber = Color(hex: 0xD9822B)
    /// 朱砂 — 撤退 / 危险
    static let cinnabar = Color(hex: 0xC0452E)
    /// 竹青 — 安全 / 继续
    static let bamboo = Color(hex: 0x5F8D6B)
    /// 墨色 — 亮卡上的文字
    static let ink = Color(hex: 0x1C221F)
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
