# Offline Hiking Fatigue Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox completion and require verification at each checkpoint.

**Goal:** 将现有 WUDAX 演示应用升级为可在 iPhone 上离线走通 Stage 1–3 的徒步疲劳 Agent，同时完全保留当前 UI 配色、组件和交互质感。

**Architecture:** HealthKit、问卷、GPX 和定位先归一化为带来源与时间戳的数据快照。纯 Swift 规则工具生成事实、风险和受控行动；Qwen3-0.6B 通过原生 tool call 调用这些工具，只负责聊天引导与解释。SwiftUI 用现有 WUDAX 组件呈现聊天卡片、报告、出发门禁、行中向导和复盘。

**Tech Stack:** Swift 5.9、SwiftUI、HealthKit、CoreLocation、UserNotifications、MapKit 本地 GPX 降级视图、SwiftData/FileManager、MLXLMCommon/Qwen3、XcodeGen、XCTest。

**Global Constraints:** 不提交用户原始 GPX；不新增品牌颜色、渐变、顶部白条、分隔线或无依据描边；所有风险结论必须由确定性规则兜底；不承诺 iOS 后台固定 30 秒轮询。

## Task 1: 测试基础与 GPX 数据管线

**Files:** `project.yml`, `Sources/Models/HikingModels.swift`, `Sources/GPX/GPXParser.swift`, `Sources/GPX/GPXAnalyzer.swift`, `Tests/Fixtures/sanitized-route.gpx`, `Tests/GPXParserTests.swift`

- [x] 添加 XCTest target 和脱敏 GPX fixture。
- [x] 先写解析、跨夜间隔、时间倒退、重复点和统计的失败测试。
- [x] 实现容错 GPX 解析和派生统计，区分计划与历史用途。
- [x] 运行测试/构建验证，提交并推送。

## Task 2: HealthKit 与 Stage 1 数据采集

**Files:** `Sources/Health/HealthKitService.swift`, `Sources/Planning/PlanningCoordinator.swift`, `Sources/Views/PlanningChatView.swift`, `Sources/Models/HikingModels.swift`, `Tests/ReadinessRuleTests.swift`

- [x] 先写数据新鲜度和准备度测试。
- [x] 实现徒步相关 HealthKit 类型、主动授权、查询和 observer。
- [x] 实现问卷补缺、来源/时间戳/可信度模型。
- [x] 将 HealthKit、问卷和 GPX 变成连续聊天内卡片。
- [x] 验证权限拒绝/无数据路径，提交并推送。

## Task 3: 确定性工具、报告与端侧模型编排

**Files:** `Sources/Rules/HikingRuleTools.swift`, `Sources/LocalLLM/AgentToolOrchestrator.swift`, `Sources/LocalLLM/LocalLLMService.swift`, `Sources/Views/PreTripReportView.swift`, `Tests/HikingRuleToolsTests.swift`

- [x] 先写路线负荷、挑战差距、补给、装备和行动白名单测试。
- [x] 实现十二个结构化规则工具与固定模板回退。
- [x] 接入 Qwen3 原生 tool call，校验参数和工具结果。
- [x] 在聊天流展示三分报告、补给和装备卡片。
- [x] 验证模型不可用时完整可用，提交并推送。

## Task 4: 离线资源与出发门禁

**Files:** `Sources/Offline/OfflineResourceManager.swift`, `Sources/Views/GatekeeperView.swift`, `Sources/Views/RouteMapView.swift`, `Tests/GatekeeperTests.swift`

- [x] 先写完整性和显式降级门禁测试。
- [x] 实现 GPX 本地路线地图、资源状态与仅路线离线模式。
- [x] 合并权限、补给、路线质量和资源检查。
- [x] 保持现有门禁卡片风格，验证后提交并推送。

## Task 5: Stage 2 定位、路线进度与主动风险

**Files:** `Sources/Trip/LocationService.swift`, `Sources/Trip/TripRecorder.swift`, `Sources/Rules/RiskEvaluator.swift`, `Sources/Notifications/NotificationService.swift`, `Sources/Views/TripDashboardView.swift`, `Tests/RiskEvaluatorTests.swift`

- [x] 先写路线匹配、风险叠加、升级和冷却测试。
- [x] 实现前后台定位、实际轨迹记录和最近路线进度。
- [x] 实现事件驱动评估与前台 30 秒节流，不使用伪实时模拟。
- [x] 实现本地通知、固定安全模板和主观状态确认。
- [x] 验证定位/通知拒绝与数据过旧路径，提交并推送。

## Task 6: Stage 3 复盘、基线与持久化

**Files:** `Sources/Persistence/TripStore.swift`, `Sources/Rules/ReviewEngine.swift`, `Sources/Views/ReviewView.swift`, `Tests/ReviewEngineTests.swift`

- [x] 先写总结、基线更新和训练建议测试。
- [x] 实现报告与轨迹本地持久化。
- [x] 展示计划/实际对比、风险时间线、复盘和训练卡片。
- [x] 完成历史行程入口，验证后提交并推送。

## Task 7: 全链路整合与回归

**Files:** `Sources/Agent/TripSession.swift`, `Sources/WudaXApp.swift`, `Sources/Views/HomeView.swift`, `project.yml`

- [x] 移除生产流程中的固定 SampleData 和 1 秒模拟依赖。
- [x] 配置 HealthKit、定位、后台定位和通知描述/entitlements。
- [x] 走通首页→Stage 1→门禁→Stage 2→Stage 3→首页。
- [x] 检查所有页面无顶部白条且只使用现有颜色与组件。
- [x] 运行全量测试、真机构建和静态检查，提交并推送。

