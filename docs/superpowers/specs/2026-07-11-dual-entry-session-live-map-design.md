# WUDAX 双入口 Session 流程 + 实时行程页重做 — 设计文档

日期: 2026-07-11
分支: main

## 背景与目标

上一轮已完成:双入口(历史 GPX / 开始规划)进入规划、GPX 原作者模型、本地路线库 CRUD、离线路线匹配引擎。本轮解决四件事:

1. **Stage1 合并**:match report(行程预算卡)与「确认装备」目前是两个页面(budgetCard → gate),用户要求合并为一页 —— 看完报告、勾完装备、直接出发。
2. **路线行走 log**:从入口 1(历史 GPX)进入并完成的每一次行程,都要作为一条 log 挂在这条 GPX 记录之下,UI 展示 + 数据真实持久化。
3. **入口 2 置顶**:「开始规划」导入的新 GPX 完成规划后置顶显示在历史 GPX 列表(现有 `upsert` 已插入 index 0,本轮验证并保持)。
4. **实时 Session 页重做**:现页面(TripDashboardView)是卡片列表,地图小、无进行感。重做为**全屏大地图 + 常驻实时数据面板**,参考两步路「导航中」的功能(不抄 UI):必须有**计时**与**剩余公里**;距路线起点还有距离时画**虚线引导**,走到起点**自动开始记录**。

## 现状(已核实)

- 相位机 `TripSession.Phase`: `home / planningChat / budgetCard / gate / inTrip / review`。RootView 按 phase 整屏切换。
- 入口 1: HomeView 历史卡片 → RouteDetailView →「用这条路线开始规划」→ `planRecord(record)`(记录 `planningSourceRecordID`)。
- 入口 2: HomeView「开始规划」→ `startPlanning()` → 导入 GPX → `finalizePlanning()` 时 `library.upsert(新 RouteRecord)` 置顶入库。
- 行程持久化: `StoredTrip`(TripStore, JSON)含 summary/events/recordedTrack,**但没有 routeRecordID 字段**——无法按路线聚合 log。
- 行中: `depart()` 立即 `recorder.start()` + 30s 定时规则重算;`elapsedHours` 基于 `tripStartDate`;matcher 输出 `remainingDistanceMeters` 等已齐备。
- 地图: `RouteMapView`(UIViewRepresentable/MKMapView)画路线 polyline、用户箭头、匹配标注、精度圈;无起终点旗标、无虚线引导。

## 设计

### A. Stage1 合并页(match report + 装备确认)

- `BudgetCardView` 改为「行前报告」单页:保留现有风险印章/对比/剖面/分析/补给卡,把 GatekeeperView 的**装备勾选清单**(带 required 校验)与**离线与权限卡**(定位/通知/离线资源)合并进来,页尾 CTA 变为「接受风险并出发」→ 直接 `session.depart()`。
- 删除 `.gate` 相位与 `GatekeeperView.swift`;`CheckToggleStyle` 移入 DesignSystem/Components.swift;`confirmBudget()` 删除。
- 调试跳转 `WUDAX_PHASE=gate` 映射到 `.budgetCard`。
- 权限请求时机不变(进入该页 `.task` 里请求定位/通知)。

### B. 路线行走 log(数据 + UI)

数据:
- `StoredTrip` 增加可选字段(Codable 向后兼容,旧 JSON 解码为 nil):
  - `routeRecordID: UUID?` — 本次行程走的是哪条库内路线;
  - `startedAt: Date?` — 出发时刻;
  - `endedByRetreat: Bool?` — 是否撤退结束。
- `TripStore` 增加 `trips(forRoute id: UUID) -> [StoredTrip]`(按 completedAt 倒序)。
- `TripSession.planningSourceRecordID` 改名 `activeRouteRecordID`:入口 1 = 所选记录 id;入口 2 = `finalizePlanning` 新建 `RouteRecord` 的 id(先建记录取 id 再 upsert)。`persistTrip()` 写入该 id。

UI:
- `RouteDetailView` 增加「行走记录」区:列出该路线的每次行程 log(日期、用时、实际距离、结果[完成/撤退]、峰值风险色点);为空显示「还没有走过这条路线」。数据源 `session.tripStore`。

### C. 实时 Session 页重做(全屏地图 + 进行感)

`TripSession` 新增行中跟踪状态机(仅 inTrip 内部):

```
enum LiveTrackingState { case waitingGPS, toStart(distanceMeters), recording }
```

- `depart()` 不再立刻 `recorder.start()`;进入 `waitingGPS`。
- 每个定位点:若未 recording,计算与路线起点(`preparedRoute.vertices.first`)直线距离:
  - ≤ 60 m → **自动开始记录**:`hikeStartDate = now`、`recorder.start()`、状态 `recording`、事件「到达起点,自动开始记录」+ 触觉反馈;
  - > 60 m → `toStart(distance)`,地图画**用户→起点虚线**并显示「距起点 X」;
  - 兜底:matcher 报告已在路线上(置信 high 且距路线 ≤ 60 m,即中途汇入)同样自动开始。
- 无 preparedRoute(调试跳转)→ 直接 recording。
- **计时基准改为 `hikeStartDate`**(到起点才开始计):`elapsedHours`、计划偏差、风险重算、行中三问都只在 recording 后生效;toStart 阶段不触发「进度落后」等误报,偏航告警也抑制。
- 结束行程写入 log(B)。

UI(重写 TripDashboardView 布局,保留结构组件):
- **全屏 `RouteMapView`**(ignoresSafeArea),相机默认跟随用户;保留「路线聚焦 / 自身定位」控制。
- RouteMapView 增加:起点/终点旗标注、`guideLineCoordinates`(虚线 MKPolyline,dash 渲染,琥珀色)。
- **顶部胶囊**:状态点(呼吸动画)+「前往起点 / 行程进行中」+ 距日落。
- **底部常驻面板**(不遮地图主体):
  - recording:三个大数字 —— **计时 hh:mm:ss**(TimelineView 每秒刷新)、**剩余 km**(matcher.remainingDistanceMeters,无匹配时用 总长−已行进)、**已行进 km**;次行小字:预计到达(按当前均速,均速无效时按计划配速)、剩余爬升、GPS/置信状态。
  - toStart:大数字 = **距起点距离**,提示「沿虚线走到起点,将自动开始记录」。
  - 按钮:「结束」(confirmationDialog 防误触)+「详情」(sheet 打开原有卡片:路线匹配、事件、离线资源、海拔剖面、手表预览)。
- 三问卡(CheckinCardView)与撤退 sheet 交互保持不变,叠加在地图上。

### D. 入口 2 置顶

`finalizePlanning` 现行为已满足(upsert 插 index 0,HomeView 取前 4 条)。本轮只把新建记录的 id 记为 `activeRouteRecordID`(见 B),行为回归测试保持。

## 错误处理

- GPS 拒绝授权:toStart/waitingGPS 停留并显示等待定位文案(现有 resourceCard 逻辑并入底部状态)。
- 起点判断仅用 ≥0 精度定位点;60 m 阈值对民用 GPS(5–15 m)与叠加误差留余量。
- 旧版持久化 JSON:新字段全部 optional,`decodeIfPresent` 兼容。

## 测试

- `TripStoreTests`:routeRecordID 往返编解码 + `trips(forRoute:)` 过滤排序 + 旧格式 JSON 兼容解码。
- 现有 35 项测试不回归(不动 matcher/parser 逻辑)。
- 模拟器构建 + 全量测试通过。

## 非目标(本轮不做)

- 离线瓦片、Live Activity/灵动岛、主动 AI 重构(见 2026-07-11-session-map-proactive-ai-design.md M2–M4)。
- 后台长时录制的电量与挂起恢复验证(真机项)。
