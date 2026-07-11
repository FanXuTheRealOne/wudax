# Gatekeeper Permission Reminders Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Only render unresolved offline-resource and permission reminders on the departure gate, hiding the entire reminder card once everything is ready.

**Architecture:** Add a pure `GatekeeperReadiness` value type that converts three readiness booleans into an ordered list of unresolved notices. `GatekeeperView` derives this value from its existing services, uses it for both gating and conditional rendering, and keeps the existing authorization request flow unchanged.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, XcodeGen, iOS 17+

## Global Constraints

- Keep the existing departure requirements unchanged: required equipment, offline resources, location, and notifications must all be ready.
- Render no success row for a ready item.
- Hide the entire “离线与权限” card when all three readiness inputs are true.
- Do not add cards, badges, gradients, Glass, or animation.
- Preserve the existing automatic permission requests on page appearance.

---

### Task 1: Readiness Model and Conditional Permission UI

**Files:**
- Create: `WudaX/Tests/GatekeeperReadinessTests.swift`
- Modify: `WudaX/Sources/Views/GatekeeperView.swift`
- Regenerate: `WudaX/WudaX.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `offlineResourcesReady: Bool`, `locationAuthorized: Bool`, `notificationsAuthorized: Bool`
- Produces: `GatekeeperReadiness.notices: [GatekeeperReadiness.Notice]`, where `Notice` is `offlineResources`, `locationPermission`, or `notificationPermission`

- [ ] **Step 1: Write the failing readiness tests**

Create `WudaX/Tests/GatekeeperReadinessTests.swift`:

```swift
import XCTest
@testable import WudaX

final class GatekeeperReadinessTests: XCTestCase {
    func testAllReadyProducesNoReminders() {
        let readiness = GatekeeperReadiness(
            offlineResourcesReady: true,
            locationAuthorized: true,
            notificationsAuthorized: true
        )

        XCTAssertEqual(readiness.notices, [])
    }

    func testOnlyMissingLocationProducesLocationReminder() {
        let readiness = GatekeeperReadiness(
            offlineResourcesReady: true,
            locationAuthorized: false,
            notificationsAuthorized: true
        )

        XCTAssertEqual(readiness.notices, [.locationPermission])
    }

    func testOnlyMissingNotificationProducesNotificationReminder() {
        let readiness = GatekeeperReadiness(
            offlineResourcesReady: true,
            locationAuthorized: true,
            notificationsAuthorized: false
        )

        XCTAssertEqual(readiness.notices, [.notificationPermission])
    }

    func testOnlyMissingOfflineResourcesProducesOfflineReminder() {
        let readiness = GatekeeperReadiness(
            offlineResourcesReady: false,
            locationAuthorized: true,
            notificationsAuthorized: true
        )

        XCTAssertEqual(readiness.notices, [.offlineResources])
    }

    func testMissingItemsUseStableDisplayOrder() {
        let readiness = GatekeeperReadiness(
            offlineResourcesReady: false,
            locationAuthorized: false,
            notificationsAuthorized: false
        )

        XCTAssertEqual(
            readiness.notices,
            [.offlineResources, .locationPermission, .notificationPermission]
        )
    }
}
```

- [ ] **Step 2: Regenerate the project and verify the new tests fail for the expected reason**

Run:

```bash
cd WudaX
xcodegen generate
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WudaX.xcodeproj \
  -scheme WudaX \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4' \
  -only-testing:WudaXTests/GatekeeperReadinessTests \
  test
```

Expected: FAIL because `GatekeeperReadiness` does not yet exist.

- [ ] **Step 3: Add the minimal pure readiness model**

Add above `GatekeeperView` in `WudaX/Sources/Views/GatekeeperView.swift`:

```swift
struct GatekeeperReadiness: Equatable {
    enum Notice: Hashable {
        case offlineResources
        case locationPermission
        case notificationPermission
    }

    let offlineResourcesReady: Bool
    let locationAuthorized: Bool
    let notificationsAuthorized: Bool

    var notices: [Notice] {
        var result: [Notice] = []
        if !offlineResourcesReady { result.append(.offlineResources) }
        if !locationAuthorized { result.append(.locationPermission) }
        if !notificationsAuthorized { result.append(.notificationPermission) }
        return result
    }
}
```

- [ ] **Step 4: Make the view render only unresolved notices**

In `GatekeeperView`, derive readiness from the existing services:

```swift
private var readiness: GatekeeperReadiness {
    GatekeeperReadiness(
        offlineResourcesReady: session.offlineResources.status.isReady,
        locationAuthorized: locationReady,
        notificationsAuthorized: session.notifications.authorizationGranted
    )
}
```

Change `gateReady` to use `readiness.notices.isEmpty`. In the scroll content, wrap `permissionCard` in:

```swift
if !readiness.notices.isEmpty {
    permissionCard
}
```

Replace the three unconditional rows with a `ForEach` over `readiness.notices`. Render `GPX / 路线资源 — 未准备`, `定位 — 请开启`, and `通知 — 请开启` for their respective cases. Show `integrityMessage` only when `.offlineResources` is present. Use the existing amber warning color and remove the unused success-state parameters from `auditRow`.

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run the targeted `xcodebuild` command from Step 2 again.

Expected: `** TEST SUCCEEDED **` and all five `GatekeeperReadinessTests` pass.

- [ ] **Step 6: Run the complete test suite and simulator build**

Run:

```bash
cd WudaX
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WudaX.xcodeproj \
  -scheme WudaX \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4' \
  test
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WudaX.xcodeproj \
  -scheme WudaX \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4' \
  build
```

Expected: both commands end with success and contain no new warnings caused by the changed files.

- [ ] **Step 7: Commit the implementation**

```bash
git add WudaX/Sources/Views/GatekeeperView.swift \
  WudaX/Tests/GatekeeperReadinessTests.swift \
  WudaX/WudaX.xcodeproj/project.pbxproj
git commit -m "fix: hide resolved departure permissions"
```

### Task 2: Merge Remote Main and Push

**Files:**
- Modify only files affected by an actual `origin/main` merge.

**Interfaces:**
- Consumes: verified local `main` commits and the fetched `origin/main`
- Produces: pushed `origin/main` containing both histories

- [ ] **Step 1: Fetch and merge the remote branch**

```bash
git fetch origin
git merge --no-edit origin/main
```

Expected: a clean merge, fast-forward, or “Already up to date.” If conflicts occur, resolve them while preserving both the permission behavior and unrelated remote work.

- [ ] **Step 2: Re-run tests after the merge**

```bash
cd WudaX
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project WudaX.xcodeproj \
  -scheme WudaX \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.4' \
  test
```

Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 3: Push verified main and confirm synchronization**

```bash
git push origin main
git status --short --branch
```

Expected: push succeeds and local `main` is aligned with `origin/main` with a clean working tree.
