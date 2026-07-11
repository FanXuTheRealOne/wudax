# WudaX Coding Handoff

Last updated: 2026-07-11

Active branch: `main`

Repository: `https://github.com/FanXuTheRealOne/wudax.git`

## Current product state

WudaX is an iPhone hiking app. The current implementation has a working planning flow, GPX import and parsing, an offline GPX route-preprocessing/matching engine, local live-location integration, route status UI, and off-route notification plumbing. The route-matching path is designed to run locally without a backend.

## Implemented in the latest work (2026-07-11)

### Session flow rework

- Phase machine is now `home → planningChat → budgetCard → inTrip → review`. The former `gate` phase was merged away: `BudgetCardView` ("行前报告") now contains the match report AND the interactive equipment checklist + permission audit, with the depart CTA. `GatekeeperView.swift` was deleted (`CheckToggleStyle` moved to `DesignSystem/Components.swift`).
- Two entries into a session: (1) history GPX record → `RouteDetailView` → plan; (2) "开始规划" → GPX import. New routes are upserted to the top of the route library at `finalizePlanning`.
- Per-route walk logs: `StoredTrip` gained optional `routeRecordID` / `startedAt` / `endedByRetreat`. `TripSession.activeRouteRecordID` links both entries to the library record; `TripStore.trips(forRoute:)` queries logs; `RouteDetailView` shows a "行走记录" card per route.

### Live session page (TripDashboardView rewrite)

- Full-screen map with status pill (waitingGPS / toStart / recording), bottom live panel (ticking hh:mm:ss timer via TimelineView, remaining km from matcher, walked km, ETA, remaining ascent, GPS confidence), detail sheet with the old cards, end-trip confirmation dialog.
- Approach-to-start: after depart, `LiveTrackingState` guides the user to the route start with a dashed amber `GuidePolyline` (user → start flag). Within 60 m of the start (or when the matcher reports high-confidence on-route) recording auto-begins: `hikeStartDate` set, recorder starts, timers/risk evaluation activate. Off-route alerts and check-ins are suppressed until recording.
- `RouteMapView`: start/end flag annotations, dashed guide overlay, and a camera fix — initial region is set via `setRegion` (safe pre-layout) instead of `setVisibleMapRect` with edge padding, which degraded to a world view on zero-sized maps. During toStart the camera keeps both the user and start flag on screen; while recording it follows the user.
- `WUDAX_PHASE=trip` now loads a seed-library route and runs the real `depart()` flow, so the live map/matching can be exercised in the simulator (`simctl location set` + `applesimutils --setPermissions notifications=YES,location=always,health=YES`).

### Earlier: GPX planning/import, offline preprocessing, matching

- See `docs/superpowers/specs/` for the GPX route matching and dual-entry session designs. Core files unchanged: `RouteMatching/*`, `GPX/*`.

## Verification already completed

- Simulator test suite: 37 tests passing (TripStore route-log linkage + legacy JSON decode covered; PlanningCoordinator/HikingRuleTools tests updated to the current experience-based API).
- Simulator end-to-end: dashed guide at 2.0 km from start → moved to start → auto-start recording with ticking timer, remaining km, ETA.

## Production gaps / next priorities

1. Field-calibrate matching thresholds using real hikes covering canyon drift, forest cover, switchbacks, loops and parallel trails.
2. Add recorded GPS replay fixtures and long-duration regression tests for loss/recovery and off-route hysteresis.
3. Verify HealthKit capability, signing, authorization and real data reads on the target physical iPhone.
4. Package a true offline base-map tile/vector dataset (M2 of the 2026-07-11 session-map design).
5. Live Activity / Dynamic Island session banner (M3) and proactive-AI banner rework (M4).
6. Validate background tracking over long sessions for battery, thermal behavior and iOS suspension/relaunch.

## Operational notes

- Work is integrated directly into `main` per the owner's instruction. Sync main before coding (`git fetch origin main`).
- Project is generated with xcodegen — after adding/deleting source files run `xcodegen generate` in `WudaX/`.
- Local Xcode needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.
- Location background mode requires the final signing/capability configuration and truthful `Info.plist` usage descriptions before App Store distribution.
