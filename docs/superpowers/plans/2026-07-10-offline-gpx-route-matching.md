# Offline GPX Route Matching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a completely offline GPX preprocessing, stateful route matching, weak-GPS estimation, persistent off-route alerting, and live map/status UI pipeline.

**Architecture:** An immutable prepared route contains local-metre geometry and route metrics. A stateful matcher queries an in-memory grid and scores projected candidate segments using distance, heading, continuity, speed, altitude, and ambiguity; TripSession consumes the result without modifying raw GPS history.

**Tech Stack:** Swift 5.9, Foundation, CoreLocation, MapKit, SwiftUI, Combine, XCTest; iOS 17 minimum; no new dependencies.

## Global Constraints

- All matching and alerts run locally with no network service.
- Preserve original GPX and raw GPS recordings.
- Estimates are explicitly marked and never overwrite real GPS samples.
- Off-route alerts require multiple consecutive evidence samples and accuracy-aware thresholds.
- Existing user changes in `project.pbxproj` must be preserved.

---

### Task 1: Prepared route models and preprocessing

**Files:**
- Create: `WudaX/Sources/RouteMatching/RouteMatchingModels.swift`
- Create: `WudaX/Sources/RouteMatching/GPXRoutePreprocessor.swift`
- Test: `WudaX/Tests/RouteMatchingTests.swift`
- Modify: `WudaX/WudaX.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `GPXDocument`, `GPXTrackPoint`, `GPXWaypoint`
- Produces: `GPXRoutePreprocessor.prepare(_:) throws -> PreparedGPXRoute`

- [ ] Write failing tests for cumulative distance, remaining ascent, deduplication, turns, waypoint projection, loop/out-and-back, and parallel ambiguity.
- [ ] Run the new test class and verify missing prepared-route types fail compilation.
- [ ] Add Codable route vertex, segment, waypoint, flags, and prepared route types.
- [ ] Implement local coordinate conversion, light dedupe/simplification, route metrics, waypoint projection, and topology flags.
- [ ] Run the preprocessing tests and verify they pass.

### Task 2: Candidate scoring and weak-GPS state machine

**Files:**
- Create: `WudaX/Sources/RouteMatching/GPXRouteMatcher.swift`
- Modify: `WudaX/Tests/RouteMatchingTests.swift`

**Interfaces:**
- Consumes: `PreparedGPXRoute`, `RouteLocationInput`
- Produces: `GPXRouteMatcher.match(_:) -> RouteMatchResult`, `GPXRouteMatcher.locationUnavailable(at:cadenceStepsPerMinute:) -> RouteMatchResult`

- [ ] Write failing tests proving projection uses line segments, heading/history resolves nearby branches, and implausible progress jumps are rejected.
- [ ] Write failing tests for confidence, accuracy-aware off-route persistence, next waypoint/remaining ascent, and GPS outage sources.
- [ ] Run matcher tests and verify missing matcher APIs fail.
- [ ] Implement the spatial grid, projection, weighted scoring, hard jump gate, confidence classification, reliable-progress state, and off-route evidence counter.
- [ ] Implement bounded short-outage interval estimation and long-outage last-known output.
- [ ] Run all route matching tests and verify they pass.

### Task 3: Offline persistence and trip integration

**Files:**
- Modify: `WudaX/Sources/Offline/OfflineResourceManager.swift`
- Modify: `WudaX/Sources/Agent/TripSession.swift`
- Modify: `WudaX/Sources/Models/Models.swift`
- Modify: `WudaX/Sources/Notifications/NotificationService.swift`
- Test: `WudaX/Tests/RouteMatchingTests.swift`

**Interfaces:**
- Consumes: `PreparedGPXRoute`, `RouteMatchResult`, `CLLocation`
- Produces: `TripSession.routeMatch`, local off-route events and notifications, prepared-route file persistence

- [ ] Add a failing persistence test for encoding/decoding the prepared route.
- [ ] Store the prepared route beside the original GPX without changing raw data.
- [ ] Prepare/reset the matcher at planning/departure boundaries and feed real location metadata to it.
- [ ] Use reliable matched progress for status/profile calculations and request outage output from the existing timer.
- [ ] Add a dedicated local off-route notification cooldown and `.offRoute` check-in trigger.
- [ ] Run route matching and existing persistence/rule tests.

### Task 4: Live map and confidence UI

**Files:**
- Modify: `WudaX/Sources/Views/RouteMapView.swift`
- Modify: `WudaX/Sources/Views/TripDashboardView.swift`

**Interfaces:**
- Consumes: `TripSession.routeMatch`, raw `CLLocation`, imported GPX points
- Produces: route polyline, matched marker, confidence-specific route status copy

- [ ] Add raw and matched annotations plus an accuracy circle without changing the route geometry.
- [ ] Add high/medium/low/none copy and remaining route metrics to the dashboard.
- [ ] Render persistent off-route state in amber/red and estimated/last-known sources distinctly.
- [ ] Build the simulator target to verify SwiftUI/MapKit integration.

### Task 5: Verification and main integration

**Files:**
- Verify all files above

- [ ] Run `git diff --check` and inspect all user-owned unstaged changes.
- [ ] Run the complete XCTest suite and confirm zero failures.
- [ ] Build the generic iOS Simulator target.
- [ ] Build the connected iPhone target if available.
- [ ] Stage only route-matching changes, commit on `main`, and leave unrelated Xcode upgrade changes unstaged.
