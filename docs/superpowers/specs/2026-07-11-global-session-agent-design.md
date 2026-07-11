# WUDAX 全局 Agent · Session 独立 Context · AI 窗口 — 设计文档

日期: 2026-07-11
分支: main(与另一 agent 并行开发;本设计的代码尽量落在新文件,现有文件只做最小修改)

## 用户手绘架构的映射

```
┌─ WudaXAgent(App 级全局,唯一实例)──────────────┐
│  LocalLLMService(模型只加载一次,全局共享)        │
│  AgentDataBus(数据总线:全量快照 + 前方路线前瞻)   │
│  ┌─ session ctx ─┐ ┌─ session ctx ─┐ ┌─ ... ─┐   │
│  │ 对话历史        │ │ 对话历史        │            │
│  │ 播报记忆/冷却    │ │ 播报记忆/冷却   │            │
│  └───────────────┘ └───────────────┘             │
└──────────────────────────────────────────────────┘
```

- **Agent 全局**:`WudaXAgent` 是 `@StateObject`,App 启动即存在,跨 session 存活;LLM 容器只加载一次。
- **Session 内独立 context**:每次进入 `.inTrip` 新建一个 `AgentSessionContext`(id、路线名、开始时间、消息流、信号记忆)。喂给 LLM 的对话历史**只来自当前 context**;session 结束后 context 归档到内存列表,互不污染。
- **Data Bus**:`AgentDataBus` 把 TripSession / matcher / HealthKit / 路线库 / 行走 log 的数据组装成结构化中文快照,按需分全量(问答用)与精简(主动播报用)两级。

## 核心行为

### 1. 主动播报(agent 主动说话)

触发 = **信号变化检测 + 冷却**,不是定时轮询。信号集(`AgentSignal`):

| 信号 | 触发条件 | 对应用户诉求 |
|---|---|---|
| sessionStart | 到达起点自动开始记录 | 开场:路线前瞻(总距离/爬升/风险点/日落窗口) |
| verdictChanged | 规则引擎判级变化(继续↔谨慎↔降级↔撤退) | 安全结论变化 |
| offRouteChanged | 偏航出现 / 回到路线 | 路线 |
| heartRateShift | 心率较 session 基线漂移 ≥15 bpm,或进入 ≥150 高区 | **心率等数据变化** |
| paceBandChanged | planDeltaMin 跨 -20 / -40 阈值 | 配速变化 |
| sunsetWindow | 距日落跨 3h / 2h | 时间余量 |
| upcomingRiskPoint | 距最高点/长下坡起点 <600 m | **路线未来情况** |
| progressMilestone | 走过 25% / 50% / 75% | 进度 |
| checkinSubmitted | 三问提交后 | 状态确认总结 |

冷却:同信号 8 分钟,全局最短间隔 90 秒;LLM 正在生成时不叠加。
生成:`规则引擎结论 + 变化描述 + 精简快照` → LLM 一句话(≤80 token);**LLM 不可用(模拟器/加载失败/生成异常)静默降级为规则引擎现成中文文案**(watchHint / reason)。安全判级永远来自规则引擎,LLM 只做表达 —— 延续既定架构。

### 2. 对话(用户问 agent)

用户在 AI 窗口发消息 → prompt = `系统人设 + 全量快照(AgentDataBus.fullSnapshot)+ 本 context 对话历史` → 流式生成。
**全量快照尽可能暴露所有数据**(Qwen3 0.6B 的 context 窗口足够大,512 只是生成上限):

- 路线:名称、距离、爬升/下降、最高海拔、预计耗时(个性化)、环线/原路返回、水源数、质量分、风险点及所在里程
- 原作者:署名、录制日期、用时、配速、来源软件
- 用户画像:经验上限(最难距离/拔高/海拔/耗时)、疲劳档案(下坡耐受/耗水率)、健康注意项
- 计划:出发时间、带水/食物 vs 建议、日落时间、装备清单、关键复核点
- 实时:跟踪状态、计时、已行进、剩余距离/爬升、ETA、planDelta、当前配速 vs 原作者配速、GPS 置信/偏航、下一航点
- **前方路线(RouteLookahead)**:前方 1 km 坡度与爬升、到下一风险点/最高点/航点距离、剩余每段概览
- 健康:HealthSnapshot 全部可用指标(值+采样时间+新鲜度),session 内心率变化趋势
- 行中事件:最近 5 条 TripEvent;规则引擎当前判级与建议动作
- 历史:这条路线的行走 log(次数、上次用时/结果)

### 3. 前方路线计算 `RouteLookahead`

从 `PreparedGPXRoute.vertices`(每顶点累计距离/剩余距离/剩余爬升/海拔)+ 当前 `routeProgressMeters` 计算:前方 1 km 爬升与平均坡度、其后每 2 km 分段一句话(缓升/陡降 X m)、下一 waypoint 与距离、`Route.riskPoints`(profileIndex → 换算沿线里程)距离。纯函数,可单测。

## 新增文件(避免与并行 agent 冲突)

| 文件 | 内容 |
|---|---|
| `Sources/Agent/AgentDataBus.swift` | 快照组装(全量/精简)、RouteLookahead、`AgentSignalDetector`(纯函数信号检测 + `AgentSignalMemory`) |
| `Sources/Agent/WudaXAgent.swift` | 全局 agent、`AgentSessionContext`、订阅 TripSession(phase 驱动 context 开/关,objectWillChange 节流驱动信号检测)、主动播报与 ask() |
| `Sources/Views/SessionAgentView.swift` | AI 窗口(sheet) |
| `Tests/AgentDataBusTests.swift` | lookahead / 快照内容 / 信号检测与冷却 |

## 最小修改的现有文件(改前基于磁盘最新版)

| 文件 | 修改 |
|---|---|
| `WudaXApp.swift` | +`@StateObject agent`、注入 environmentObject、`agent.attach(session:)` |
| `LocalLLMService.swift` | +`respond(system:history:maxTokens:)` 纯生成接口(不动 ChatView 的 messages 状态);send() 复用 |
| `TripDashboardView.swift` | 地图控制列上方 + AI 圆钮(未读 badge);顶部胶囊下方 + 主动播报 banner(点击进 AI 窗口,8s 自动收起);+sheet |

`TripSession.swift` **零修改**:WudaXAgent 通过 Combine 订阅其 @Published 状态。

## AI 窗口 UI(SessionAgentView)

- sheet(detents: large/medium),沿用清新山野设计系统
- 顶部:呼吸状态点 + 「WUDAX Agent」+ 路线名 + 模型状态(加载中/离线就绪/本机不可用-已用规则文案)
- 消息流:
  - 主动播报:琥珀左侧竖条 + 信号图标 + 时间戳(与普通回答视觉区分)
  - 用户消息:右对齐墨绿胶囊;assistant:左对齐正文
- 底部:快捷问题 chips(「前面路怎么样?」「我现在状态怎么样?」「还要走多久?」「水够吗?」)+ 输入框
- 入口:行中页地图右侧控制列 AI 圆钮(未读数 badge);新播报时顶部 banner 浮出

## 并行开发纪律

- 另一 agent 正在改:PlanningCoordinator / BudgetCardView / MapTabView / PlanningChatView / 相关测试 —— 本设计不触碰这些文件
- 提交只 `git add` 本设计列出的文件(+xcodegen 重新生成的 project.pbxproj,其中会同时包含双方新文件,合并安全)
- 集成点(WudaXApp/TripDashboardView/LocalLLMService)改动量小且他未在改,最后整合冲突可控

## 错误处理

- 模拟器无 Metal:LLM loadState=failed → 全部播报走规则文案,窗口顶部提示「本机模型不可用,当前为规则引擎文案」;问答输入禁用并说明
- 生成超时/异常:该条播报回退规则文案;问答显示失败并可重试
- session 结束(endTrip):context 标记 ended 并归档;新 session 重新开 context

## 非目标(本轮不做)

- transcript 持久化到 StoredTrip / 行走 log 回看(下一轮)
- Live Activity / 灵动岛承载播报(M3)
- 语音播报
