# WUDAX 徒步风险 Agent — iOS App（MVP）

品牌内核：庄子「无待」——无感、自然、舒适。平时安静，关键时刻主动。

## 项目结构

```
wudax/
├── WudaX/                    # SwiftUI 原生工程（iOS 17+）
│   ├── project.yml           # xcodegen 配置（改动源码结构后重新 xcodegen generate）
│   ├── WudaX.xcodeproj
│   └── Sources/
│       ├── WudaXApp.swift    # 入口 + 五阶段路由
│       ├── DesignSystem/     # 设计系统：配色/字体/印章徽标/宣纸卡片/海拔剖面图
│       ├── Models/           # 路线、行程计划、行中状态、疲劳档案（含武功山演示数据）
│       ├── Agent/            # AgentEngine 决策引擎 + TripSession 五阶段状态机
│       ├── Views/            # 六大界面
│       └── Resources/        # 水墨插画、Logo、Meshy 生成的外骨骼 USDZ
├── design/                   # image2 生成的 9 张 UI 设计图 + 插画源文件
├── assets/3d/                # Meshy 6 生成的外骨骼模型（usdz / glb / 缩略图）
├── screenshots/              # 模拟器实机截图（7 张）
└── scripts/                  # 生图 / 生 3D 脚本（.venv 运行）
```

## 五阶段 Agent 流程（PRD 对应）

| 阶段 | 界面 | 说明 |
|------|------|------|
| 行前规划 | PlanningChatView | Agent 逐条追问出发时间/水量/食物，快捷回复 |
| 预算卡 | BudgetCardView | 印章式风险等级、海拔剖面 3 风险点、警惕 3 件事、补给建议、关键复核点 |
| 出发守门 | GatekeeperView | 补给对照建议下限、装备清单、增加补给/降低目标、接受风险出发 |
| 行中问询 | TripDashboardView + CheckinCardView | 演示模式压缩时间推进；定时/长下坡前/日落/进度触发三问卡（水量/膝痛/困倦），含手表端提示预览 |
| 撤退窗口 | RetreatDecisionView | 继续 vs 下撤对比、不可逆点标注、触发原因解释 |
| 行后复盘 | ReviewView | 黄昏水墨头图、5 问对话式复盘、失控点总结、疲劳档案更新 |

决策规则在 `Agent/AgentEngine.swift`：补给/膝痛×后续下坡/困倦/日照/进度/路线可信度多项余量叠加评分 → 继续/谨慎继续/建议降级/建议撤退。

## 构建与运行

```bash
cd WudaX
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project WudaX.xcodeproj -scheme WudaX \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

或直接用 Xcode 打开 `WudaX/WudaX.xcodeproj` 运行。

**调试跳转**：环境变量 `WUDAX_PHASE` = `budget` / `gate` / `trip` / `checkin` / `retreat` / `review` / `exo` 可直接进入对应阶段（用于截图与演示）。

## 素材生成脚本

```bash
.venv/bin/python scripts/gen_ui.py      # image2 生成 UI 设计图（9 张）
.venv/bin/python scripts/gen_assets.py  # 水墨插画头图
.venv/bin/python scripts/gen_3d.py      # Meshy 6 image-to-3D 外骨骼模型
```

## MVP 边界（遵循 PRD 非目标）

- 不接外骨骼实时数据（3D 展示页标注「v2.0 数据接入预留」）
- 不做医疗结论；行中行程推进为演示模拟（1 秒 ≈ 12 分钟）
- GPX 导入入口已留（当前加载武功山演示路线）
