# 设置页内嵌外骨骼 3D 模型 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将现有 SceneKit 外骨骼展示直接嵌入设置页，移除 sheet，同时完整保留模型交互、自动旋转、相机和光照体验。

**Architecture:** `SettingsTabView` 直接承载 `ExoModelView` 和真实状态文案；`ExoShowcaseView.swift` 删除全屏容器，仅保留模型组件与可测试的本地资源加载入口。加载失败通过绑定回传给设置页。

**Tech Stack:** SwiftUI, SceneKit, USDZ, XCTest, iOS 17+.

## Global Constraints

- 不引入 RealityKit、WebView 或网络资源。
- 复用现有旋转、缩放、自动转动、相机、灯光和入场动效。
- 删除缩略图入口、sheet 和全屏展开能力。
- 不显示虚构电量、连接版本或制动余量。

---

### Task 1: 可测试的本地模型加载

**Files:** Modify `WudaX/Sources/Views/ExoShowcaseView.swift`; modify `WudaX/Tests/TripTrackRecorderTests.swift`.

**Interfaces:** `ExoModelResource.scene(in bundle: Bundle = .main) -> SCNScene?`。

- [ ] 添加失败测试，使用空临时 bundle URL 验证资源缺失返回 `nil`，并验证 App bundle 中 `exoskeleton.usdz` 可解析。
- [ ] 运行 `TripTrackRecorderTests`，确认新接口缺失导致失败。
- [ ] 将现有 `SCNScene(url:)` 读取提取到 `ExoModelResource`，`ExoModelView` 继续使用同一模型构建逻辑。
- [ ] 重跑聚焦测试并确认通过。

### Task 2: 设置页直接内嵌模型

**Files:** Modify `WudaX/Sources/Views/SettingsTabView.swift`; modify `WudaX/Sources/Views/ExoShowcaseView.swift`.

**Interfaces:** `ExoModelView(loadState:)` 通过 `Binding<Bool?>` 回传加载中/成功/失败状态。

- [ ] 删除 `showExo`、缩略图按钮和 `.sheet`。
- [ ] 添加 `exoskeletonSection`：标题、操作提示、300–340pt 模型区域、真实连接状态和失败提示。
- [ ] 删除全屏 `ExoShowcaseView` 容器，保留 SceneKit 组件的原相机、灯光、自动旋转和 camera control。
- [ ] 使用 `accessibilityReduceMotion` 仅在系统要求时关闭自动旋转和入场缩放。

### Task 3: 验证与提交

**Files:** All files above plus this plan.

- [ ] 运行 `git diff --check`。
- [ ] 运行聚焦测试和关闭并行的全量 XCTest。
- [ ] 构建 iPhone 模拟器目标，检查无新增编译警告。
- [ ] 只暂存本功能文件并提交，不包含队友工作区改动。

## Self-review

- Task 1 覆盖资源错误状态，Task 2 覆盖嵌入、交互复用和 Reduce Motion，Task 3 覆盖构建测试与干净提交。
- 接口命名在任务间一致，无占位要求或范围外硬件功能。
