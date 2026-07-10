# WudaX Coding Handoff

Last updated: 2026-07-10

Active branch: `main`

Repository: `https://github.com/FanXuTheRealOne/wudax.git`

## Current product state

WudaX is an iPhone hiking app. The current implementation has a working planning flow, GPX import and parsing, an offline GPX route-preprocessing/matching engine, local live-location integration, route status UI, and off-route notification plumbing. The route-matching path is designed to run locally without a backend.

## Implemented in the latest work

### GPX planning and import

- GPX import is part of the “开始规划” flow rather than the home screen.
- The file picker is wired to an actionable import button.
- GPX parsing handles track points, route points, waypoints, elevation and timestamps more defensively.
- The original imported GPX data remains available while a prepared route representation is generated for matching.

### Offline GPX preprocessing

- Converts GPX points into continuous route segments.
- Removes duplicate/noisy points and applies light simplification.
- Precomputes cumulative route distance, elevation, grade, bearing, remaining distance and remaining ascent.
- Associates waypoints with along-route progress.
- Detects route characteristics needed for ambiguous matching, including loops, switchbacks/out-and-back behavior and nearby parallel segments.
- Builds a local spatial lookup structure for nearby candidate segments.

Core files:

- `WudaX/Sources/RouteMatching/RouteMatchingModels.swift`
- `WudaX/Sources/RouteMatching/GPXRoutePreprocessor.swift`

### Lightweight offline route matching

- Projects each GPS update onto nearby GPX segments instead of snapping to the nearest GPX point.
- Scores candidate segments using distance, heading, historical progress continuity, feasible speed/progress change and optional elevation agreement.
- Uses the previous reliable position to disambiguate loops, switchbacks and close parallel segments.
- Rejects implausible along-route jumps (“teleporting”).
- Produces route progress, matched coordinate, distance to route, remaining distance/ascent, next waypoint, confidence, off-route state, last reliable progress, location source and a human-readable reason.
- Supports `high`, `medium`, `low`, and `none` confidence levels.
- During short GPS loss, estimates a bounded progress interval from recent trustworthy progress/speed; long loss falls back to the last known reliable position.
- Estimated positions are explicitly marked and do not overwrite the real GPS track.
- Off-route detection uses accuracy-aware thresholds and repeated observations rather than alarming on a single noisy point.

Core file:

- `WudaX/Sources/RouteMatching/GPXRouteMatcher.swift`

### App integration

- `TripSession` owns route matcher state and feeds live location updates into it.
- The route map renders the planned GPX route, matched position and current tracking state.
- The trip dashboard exposes progress, remaining route information, confidence and unstable/off-route states.
- Local notification support is connected for sustained off-route events.
- Prepared route data is persisted through the offline resource layer.
- Background location startup no longer enables unsupported background updates and crash behavior was fixed.

Integration files:

- `WudaX/Sources/Agent/TripSession.swift`
- `WudaX/Sources/Models/Models.swift`
- `WudaX/Sources/Offline/OfflineResourceManager.swift`
- `WudaX/Sources/Views/RouteMapView.swift`
- `WudaX/Sources/Views/TripDashboardView.swift`
- `WudaX/Sources/Notifications/NotificationService.swift`
- `WudaX/Sources/Rules/HikingRuleTools.swift`

### Personal health and HealthKit context

- Personal-health questions are present in planning, including injury/surgery-related answers.
- HealthKit authorization is an iOS system prompt and must be requested from a signed app on a physical iPhone. The OS may not show the prompt again after the user has already answered; permissions are then managed in iOS Health/Settings.
- Do not claim full production HealthKit ingestion until physical-device authorization and representative read queries have been verified with the final App ID, signing team and HealthKit capability.

## Verification already completed

- Simulator test suite passed: 35 tests.
- Generic iOS/device build passed.
- App installation to a physical device succeeded; one launch attempt was blocked because the iPhone was locked, not by an application build failure.
- Route-matching unit coverage is in `WudaX/Tests/RouteMatchingTests.swift`.

## Production gaps / next priorities

1. Field-calibrate matching thresholds using real hikes covering canyon drift, forest cover, switchbacks, loops and parallel trails.
2. Add recorded GPS replay fixtures and long-duration regression tests for loss/recovery and off-route hysteresis.
3. Verify HealthKit capability, signing, authorization and real data reads on the target physical iPhone.
4. Package a true offline base-map tile/vector dataset. The GPX overlay and matcher are local, but a globally browsable offline basemap requires separately downloaded map resources.
5. Validate background tracking over long sessions for battery, thermal behavior and iOS suspension/relaunch.
6. Add production telemetry/exportable diagnostics that remain privacy-safe and can be shared voluntarily after a failed match.
7. “主动式 AI” is not yet a backend service. Current safety/rule behavior is local; any cloud AI backend, account sync or remote operations need a separately defined architecture and privacy policy.

## Operational notes

- Work is integrated directly into `main` per the owner’s instruction.
- Preserve unrelated local Xcode project-upgrade settings if they appear as unstaged changes; do not discard user changes.
- The Xcode “developer disk image could not be mounted” message is a Mac/Xcode/iOS device-support or trust/connection problem, not a GPX matcher crash. Update Xcode for the phone’s iOS version, unlock/trust the phone, reconnect it and retry Developer Mode pairing.
- Location background mode requires the final signing/capability configuration and truthful `Info.plist` usage descriptions before App Store distribution.

## Recent relevant commits

- `06a62b0` — design offline GPX route matching
- `687530c` — prevent location background startup crash
- `07b23f4` — harden GPX parsing and analysis
- `3030b2c` — make GPX import actionable during planning
- `46a5a58` — refresh planning choices after selection
