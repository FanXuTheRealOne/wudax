# WUDAX Session · 离线地图 · 主动 AI 重构 — 设计文档

日期: 2026-07-11
分支: main

## 背景与目标

参考两步路的功能(不参考其 UI)。把编号 1–3 的功能剥离,做成 WUDAX 自己的、可上线的真实逻辑:

1. **图1/2 = GPX 导入后预览**:地图上画出路线 + **原作者**信息(不是本 App 用户)+ 耗时/距离/爬升/最高海拔/配速。
2. **图3 = 点 GO 后进入真实离线地图**:GPX 叠加 + 申请 GPS + 画"当前位置↔路线"的偏离连线 + 剩余距离/ETA。
3. **图4 = session 常驻 banner**:iOS 灵动岛 / Live Activity,主动 AI 在此发声。
4. **主动 AI 重构**:干掉不停弹卡片的设计;行中轮询数据喂本地 LLM,只在有意义时于 banner 发声。

已锁定决策:
- 离线地图 = **MapKit + MKTileOverlay 本地栅格瓦片**(复用现有地图,依赖轻)。
- session banner = **iOS 灵动岛 / Live Activity**(新增 Widget Extension target)。

## 现状(已核实)

- 相位机 `TripSession.Phase`: `home / planningChat / budgetCard / gate / inTrip / review`。
- GPX 导入链:`PlanningCoordinator.importGPX → GPXParser → GPXAnalyzer`。原作者遥测**解析到了**但在 `GPXDocument.copyForPlanning()` 被剥离,`Route` 无原作者字段,`estimatedHours` 无视 `recordedDuration`。
- 地图 `Views/RouteMapView.swift` = MapKit,无离线瓦片;画了路线 polyline + 用户蓝点 + 精度圈 + matched 标注,**未画偏离连线**。
- 主动 AI = `activeCheckin` 卡片,30s 定时器 + 位置更新反复触发三连问;**LLM 完全没接入行程**,仅首页 `ChatView` 用。
- matcher `RouteMatchResult` 已输出 `routeProgressMeters / distanceToRouteMeters / matchedCoordinate / confidence / isOffRoute / nextWaypoint / remaining*`。

## 核心架构决策

**规则引擎 = 安全层;LLM = 表达层。**
- `AgentEngine` + `HikingRuleTools`(确定性规则)继续负责风险判级(继续/谨慎/降级/撤退)——离线、可靠、快,安全不依赖小模型。
- 本地 `LocalLLMService`(Qwen3-0.6B)只负责把"规则引擎结论 + 关键信号"翻译成一句自然、简短的提示,显示在 banner。小模型说错话不影响安全逻辑。
- 品牌「无待」:平时安静,只有状态发生有意义变化时才发声。

**原作者 ≠ App 用户(全局)。**
- 新增 `RouteProvenance`(原作者档案):作者名(GPX metadata 解析,取不到就为空,绝不冒认用户)、录制时间、录制时长、录制配速、距离、爬升、最高海拔、来源。
- 在 `copyForPlanning()` 剥离前从录制轨迹提取,挂到 `Route`,贯穿到 Stage1 预览与行中对比("原作者用时 X,你当前配速…")。
- 本 App 用户体能仍是独立的 `FatigueProfile`,两者不混。

## 分里程碑实施(每个里程碑独立可编译、真机可验)

### M1 — 数据模型 + Stage1 GPX 预览(低风险,先出效果)
- 新增 `RouteProvenance` 结构;`GPXParser` 解析 `metadata/author/name`、`metadata/name`、`metadata/time`、`trk/name`。
- `Route` 增加 `provenance: RouteProvenance?`;保留 `recordedDuration/配速`。
- 新增 Stage1 预览视图:静态地图(复用 RouteMapView 只读模式)画路线 + 原作者卡片 + 关键数据(距离/原作者用时/累计爬升/最高海拔/原作者均速)+「GO / 开始这条路线」按钮。
- 沿用现有水墨设计系统(WDColor/InkCard/PillButton),不破坏审美。

### M2 — 离线栅格地图 + 偏离连线
- `OfflineTileManager`:按路线 bbox + 缩放级算瓦片清单,规划时(WiFi)预下载到本地 SQLite/MBTiles,带进度;`OfflineResourceStatus.mode` 升级到 `.fullOfflineMap`。
- `OfflineTileOverlay: MKTileOverlay`:`loadTile(at:result:)` 读本地库,`canReplaceMapContent=true`,含 overzoom 兜底。
- `RouteMapView`:挂载离线 overlay;新增当前位置→`matchedCoordinate` 的 2 点 `MKPolyline` 偏离连线(图3)。
- 瓦片源许可:MVP 用有限 bbox 预取;上线需正规瓦片源(记为生产项)。

### M3 — Session + Live Activity(灵动岛)
- 形式化「session」:`depart()`(GO)开始,`endTrip()`结束。
- 新增 Widget Extension target `WudaXWidgets`(xcodegen 第二 target,iOS 16.1+);共享 `WudaXActivityAttributes`(进度%/剩余km/ETA/偏离状态/主动AI一句话)。
- 主 App `Info.plist` 加 `NSSupportsLiveActivities=YES`;`depart` 启动 Activity,状态变化 `update`,`endTrip` 结束。
- 灵动岛 compact/expanded + 锁屏样式,沿用品牌视觉。

### M4 — 主动 AI 重构(接 LLM 进行程,干掉弹卡片)
- 移除 `activeCheckin` 卡片弹窗机制(`TripDashboardView` 的 CheckinCardView 呈现 + `triggerCheckin` 调用)。
- 新增 `ProactiveAgent`:行中按**状态变化 + 冷却**(非纯定时)采集快照(进度%、相对原作者配速、偏离、剩余距离/爬升、日落剩余、时长、HR),经规则引擎判级后,把"结论+信号"给 LLM 生成一句话 → 推到 banner / Live Activity。
- 稀有情况下需用户输入时,banner 内联一个**上下文相关**的单问(不再是三连问 quiz)。
- 安全升级(降级/撤退)仍走规则引擎 + `RetreatDecisionView` + 本地通知。

## 风险 / 待验证
- Live Activity 免费个人团队真机验证(Widget Extension bundle id 显式注册)。
- 离线瓦片源许可与体积(按路线 bbox 限定)。
- 0.6B 模型行中生成延迟(异步、不阻塞;失败静默降级为规则文案)。
- 后台定位 + Live Activity 长时电量/发热(沿用现有后台定位配置)。

## 非目标(本轮不做)
- 云后端 / 账号同步 / 远程 AI。
- 矢量地图(MapLibre)。
- HealthKit 全量生产接入(仅在 M4 作为可选信号读取)。
