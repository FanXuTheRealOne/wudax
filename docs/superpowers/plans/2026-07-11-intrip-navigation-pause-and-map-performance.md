# WUDAX 行中导航暂停与地图性能 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** 为行中页加入有效运动暂停、耗时/配速/里程工具栏，并让地图跟随尊重用户手势且不因高频 GPS 更新卡顿。

**Architecture:** `TripSession` 负责暂停状态和有效时长；`TripDashboardView` 呈现有效指标与主操作；`RouteMapView.Coordinator` 负责增量更新、节流和相机策略。暂停不停止 GPS/地图，但不写入记录器或运动统计。

**Tech Stack:** Swift 5.9, SwiftUI, MapKit, Core Location, Combine, XCTest, Xcode project `WudaX/WudaX.xcodeproj`.

## Global Constraints

- 暂停时 GPS/地图继续更新，运动计时、里程、平均配速、记录器和风险计时冻结。
- 唯一主动作是“暂停/继续”；结束移入详情并保留确认。
- 地图手势优先于自动跟随；朝向更新不能触发相机或路线重建。
- 兼容弱 GPS、偏航、无网、check-in、撤退和行后复盘，不新增图片、渐变或过度 Glass。

## 文件映射

- `WudaX/Sources/Agent/TripSession.swift`: 暂停状态、有效时长、记录器与风险闸门。
- `WudaX/Sources/Views/TripDashboardView.swift`: 三项指标、平均配速、暂停/继续状态与按钮。
- `WudaX/Sources/Views/RouteMapView.swift`: 相机节流、手势挂起、位置/朝向分离。
- `WudaX/Tests/TripSessionTests.swift` 或现有等价测试文件：暂停生命周期与指标。
- `WudaX/Tests/RouteMapViewTests.swift`: 可抽取的地图跟随判定测试。

### Task 1: 锁定暂停生命周期与有效时长

**Files:** Modify `TripSession.swift`; add/modify `TripSessionTests.swift`.

**Interfaces:** `@Published private(set) var isWorkoutPaused: Bool`; `pauseWorkout(at:)`; `resumeWorkout(at:)`; `activeElapsedHours(at:)`。

- [ ] 写失败测试：开始于 `t=1000`，`t=1600` 暂停，`t=2200` 仍为 600 秒有效时长；`t=2800` 恢复后，`t=3400` 为 1200 秒；暂停期间注入定位不得增加 `recorder.points` 或 `distanceMeters`。
- [ ] 运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project WudaX/WudaX.xcodeproj -scheme WudaX -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test -only-testing:WudaXTests/TripSessionTests`，确认测试因 API/行为缺失而失败。
- [ ] 添加 `pausedAt`、`accumulatedPausedDuration`，使用 `date - start - accumulated - openPause` 计算有效秒数。暂停幂等、停止 recorder/risk timer；恢复累计暂停时长、重启 risk timer，不重置 `hikeStartDate`。
- [ ] 让 `handleLocation` 在暂停时继续更新视觉匹配但跳过 recorder；让 `evaluateActiveStatus` 在暂停时跳过耗时和风险推进。
- [ ] 重跑该测试目标并提交：`git commit -m "feat: pause active hiking session without counting break"`。

### Task 2: 实现行中底部工具栏与平均配速

**Files:** Modify `TripDashboardView.swift`; add/modify metric tests.

**Interfaces:** 纯函数 `paceText(distanceKm:elapsedHours:) -> String`；距离 `< 0.05` km 或时长无效返回 `—`，否则返回 `mm′ss″/km`。

- [ ] 写并运行失败测试：`paceText(0, 1) == "—"`、`paceText(5, 1) == "12′00″/km"`。
- [ ] 将 recording 面板改为“导航中/在轨迹上 + GPS 状态”、`运动耗时/平均配速/本次里程`三列、`剩余/剩余爬升/距日落`次级行。
- [ ] 计时使用 `session.activeElapsedHours(at:)`；里程使用 recorder 的有效距离；暂停态数字保持不变并显示“已暂停 · GPS 与地图仍在更新”。
- [ ] 将“暂停/继续行程”设为 52–56pt 高主按钮；详情为次级按钮；结束移入 `TripDetailSheet` 并保留确认对话框。
- [ ] 跑 metric tests 与 simulator build，提交：`git commit -m "feat: add active pace pause controls to trip dashboard"`。

### Task 3: 修复地图跟随卡顿与缩放抢夺

**Files:** Modify `RouteMapView.swift`; add/modify `RouteMapViewTests.swift`.

**Interfaces:** 抽取纯 `MapFollowDecision.shouldRecenter(distanceMeters:secondsSinceLastUpdate:isSuspended:isExplicit:) -> Bool`，供 Coordinator 和 XCTest 共用。

- [ ] 写失败测试：3m 抖动为 false；手势挂起时 30m 为 false；未挂起 30m 为 true；显式定位请求始终为 true。
- [ ] 运行 map-only test，确认判定类型不存在或结果错误。
- [ ] 在 Coordinator 记录最近跟随位置/时间，自动跟随最小移动阈值 12m、最小时间间隔 0.5s，并增加可视安全边界判断；用户手势期间永不 `setCenter`。
- [ ] 朝向只更新 `UserNavigationPuckView`；路线、端点、精度圈、引导线继续使用现有缓存；自动跟随不动画，路线聚焦/用户显式定位才动画。
- [ ] 跑 map-only 与全量测试，提交：`git commit -m "fix: smooth live map camera follow"`。

### Task 4: 真机与回归验收

**Files:** 无，除非验收暴露缺陷。

- [ ] 用 README 的 simulator build/test 命令验证工程。
- [ ] 真机连续 10 秒拖动/缩放：GPS 更新不得把视口拉回；点击定位只发生一次明确回归。
- [ ] 点击暂停后移动：地图位置可更新，但耗时、里程、配速不变；恢复后只计算后续活动间隔。
- [ ] 验证弱 GPS、偏航、check-in、撤退、无网、Dynamic Type、Reduce Motion、结束复盘。
- [ ] 记录确切 build/test 结果；只提交本功能产生的修复。

## Self-review

- Spec 覆盖：Task 1 覆盖暂停语义，Task 2 覆盖底部 UI/指标，Task 3 覆盖地图性能，Task 4 覆盖状态与可访问性。
- 无 `TBD`、`TODO` 或未定义的占位步骤；每个任务都有文件、接口、测试和提交点。
- 类型一致：Task 1 先提供 `isWorkoutPaused`、`pauseWorkout`、`resumeWorkout`、`activeElapsedHours`，Task 2 再消费；地图判定只由 Task 3 引入并测试。
