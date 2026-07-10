# WUDAX 浏览器 UI 预览

这是一个与 SwiftUI 主工程并行的浏览器原型，用于在 Windows 上快速调整页面结构、状态、文案和交互流程。它不替代 iOS App，也不验证 SwiftUI 的真实渲染。

## 启动

```bash
cd preview
npm install
npm run dev
```

浏览器打开终端给出的本地地址。保存源码后会自动热更新。

## 两套设计并行预览

- 新版「清新山野」：`http://localhost:4173/`
- 旧版「深绿水墨」：`http://localhost:4173/?version=legacy`

入口由 `src/router.js` 根据 URL 参数选择版本。新版源码是 `src/fresh.js` 与 `src/fresh.css`；旧版继续使用原来的 `src/main.js` 与 `src/style.css`，两套代码相互独立。

## 当前流程

行程首页 → 行前确认 → 出发守门 → 行中 → 状态问询 → 撤退决策 → 行后复盘。

## 新版视觉方向

新版遵循仓库根目录 `AGENTS.md` 的「清新的山野工具」方向：晨雾白、暖纸白、松针绿、浅苔绿、山泉青和少量日照橙。Glass 只用于地图浮层，风险与下撤信息使用高对比实色表面。

首页和复盘页使用仓库已有的本地山景素材，复制到 `public/assets/` 后随预览打包，断网仍可显示。
