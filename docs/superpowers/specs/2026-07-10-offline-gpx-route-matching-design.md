# Offline GPX Route Matching Design

## Goal

Provide a completely offline, lightweight iPhone route-matching module that turns an imported GPX plan into a prepared route, continuously maps noisy GPS samples onto route segments, estimates short GPS outages, and emits structured progress and persistent off-route state for local UI and notifications.

## Selected approach

Use a stateful candidate-segment matcher over an immutable preprocessed route. This is more reliable than nearest-point snapping on switchbacks, loops, out-and-back routes, and nearby parallel sections, while remaining small enough to run on-device without a database or network service. The module keeps raw recorded GPS separate from matched or estimated progress.

## Route preprocessing

`GPXRoutePreprocessor` keeps the original `GPXDocument` unchanged and produces a Codable `PreparedGPXRoute` containing lightly deduplicated/simplified vertices and real route segments. Each vertex stores cumulative distance, elevation, remaining distance, and remaining ascent. Each segment stores start/end vertex references, length, grade, bearing, cumulative distance bounds, and a local-metre bounding box.

The preprocessor also projects waypoints onto the route, marks turns of at least 35 degrees, detects loops by start/end proximity, detects reversed nearby segment pairs for out-and-back routes, and records nearby parallel segment pairs as ambiguous matching zones. Disconnected GPX segments are not joined by an invented line.

## Runtime matching

`GPXRouteMatcher` owns a prepared route, an in-memory grid index, the last reliable match, recent motion, and an off-route evidence counter. For every valid GPS sample it:

1. queries nearby route segments from the local spatial grid;
2. projects the GPS coordinate onto every candidate segment;
3. scores distance, heading agreement, progress continuity, physically possible movement, altitude agreement, and ambiguous parallel geometry;
4. rejects implausible route-progress jumps;
5. selects the lowest-score candidate and assigns high, medium, low, or none confidence;
6. updates the last reliable progress only for high/medium GPS matches;
7. requires repeated evidence before declaring off-route.

The distance threshold is accuracy-aware. Poor `horizontalAccuracy` widens the tolerated corridor but lowers confidence. Heading is ignored when speed/course is invalid. The matcher allows modest backtracking but prevents rapid jumps to distant loop or switchback segments.

## GPS outage behavior

For a short outage, `locationUnavailable` estimates a progress interval from the last reliable progress, elapsed time, recent speed, and optional cadence. The result is marked `estimated` and never enters the raw GPS recorder. After the estimation horizon the module returns the last reliable position with `last_known` and confidence `none`; it does not manufacture an exact live location.

## Output contract

Every update returns `RouteMatchResult` with route progress, matched coordinate, distance to route, remaining distance/ascent, next waypoint and distance, confidence, off-route state and confidence, last reliable progress, location source, an optional estimated progress interval, and a human-readable reason.

## App integration

`TripSession` prepares the imported GPX before departure, stores the prepared route with offline resources, sends each `CLLocation` to the matcher, and uses matched progress rather than raw travelled distance for planned-route completion. Its existing 30-second local timer requests outage estimates when GPS becomes stale. Persistent off-route results create a local event, a dedicated local notification, haptic feedback, and an off-route check-in; transient misses do not alert.

`RouteMapView` renders the imported route, raw GPS position, and matched/estimated position. `TripDashboardView` displays confidence-specific copy, remaining distance/ascent, next waypoint, route distance, and the accuracy-aware off-route state.

## Safety and privacy constraints

- No server, geocoding, online map matching, analytics, or cloud dependency.
- Map tiles may be absent offline; the GPX polyline and matcher still operate.
- Raw GPX and raw recorded GPS remain separate from simplified and estimated data.
- An estimate never overwrites the last real GPS sample.
- A single distant GPS sample never triggers an off-route alert.

## Verification

Unit tests cover preprocessing metrics, segment projection, switchback/parallel disambiguation, teleport prevention, accuracy-aware confidence, persistent off-route detection, waypoint/remaining ascent output, and short/long GPS outages. Full iOS tests, simulator build, built-product plist verification, and a connected-device build are required before completion.
