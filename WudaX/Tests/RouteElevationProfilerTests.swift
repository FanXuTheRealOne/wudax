import XCTest
@testable import WudaX

final class RouteElevationProfilerTests: XCTestCase {

    /// 确定性伪随机噪声(LCG),模拟真实 GPX 的海拔抖动。
    private struct NoiseGenerator {
        var state: UInt64 = 88172645463325252
        mutating func next(amplitude: Double) -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double(state >> 11) / Double(UInt64.max >> 11)
            return (unit * 2 - 1) * amplitude
        }
    }

    /// 按「距离 → 海拔」函数构造预处理路线(11 m 点间距,对齐实测 GPX 密度)。
    private func makeRoute(lengthMeters: Double,
                           spacing: Double = 11,
                           elevation: (Double) -> Double) -> PreparedGPXRoute {
        let count = Int(lengthMeters / spacing) + 1
        let vertices = (0..<count).map { i -> PreparedRouteVertex in
            let distance = Double(i) * spacing
            return PreparedRouteVertex(
                coordinate: RouteCoordinate(latitude: 40, longitude: 116 + distance / 111_000),
                localXMeters: distance, localYMeters: 0,
                elevationMeters: elevation(distance),
                cumulativeDistanceMeters: distance,
                remainingDistanceMeters: lengthMeters - distance,
                remainingAscentMeters: 0,
                sourcePointIndex: i)
        }
        return PreparedGPXRoute(
            formatVersion: 1, name: "剖面测试", sourcePointCount: count, sourceSegmentCount: 1,
            origin: RouteCoordinate(latitude: 40, longitude: 116),
            vertices: vertices, segments: [], waypoints: [],
            turnVertexIndices: [], ambiguousSegmentPairs: [],
            flags: RouteTopologyFlags(isLoop: false, isOutAndBack: false, hasNearbyParallelSegments: false),
            totalDistanceMeters: lengthMeters, totalAscentMeters: 0)
    }

    /// 平路 + ±3 m GPS 噪声(实测轨迹特征):平滑后不得再出现「假爬升」。
    func testFlatRouteWithGPSNoiseIsNotMisreadAsClimbing() throws {
        var noise = NoiseGenerator()
        var jitters: [Double] = []
        let route = makeRoute(lengthMeters: 5_000) { _ in 25 }
        // 手工往顶点里注入噪声(逐点独立,模拟气压/GPS 海拔抖动)
        var noisyVertices = route.vertices
        for i in noisyVertices.indices {
            let j = noise.next(amplitude: 3)
            jitters.append(j)
            noisyVertices[i].elevationMeters = 25 + j
        }
        var noisyRoute = route
        noisyRoute.vertices = noisyVertices

        // 原始逐点累计的「假爬升」有多大(对照组)
        var rawAscent = 0.0
        for i in 1..<noisyVertices.count {
            rawAscent += max(noisyVertices[i].elevationMeters! - noisyVertices[i - 1].elevationMeters!, 0)
        }
        XCTAssertGreaterThan(rawAscent, 200, "噪声不足,测试前提失效")

        let profiler = try XCTUnwrap(RouteElevationProfiler(route: noisyRoute))
        let trend = try XCTUnwrap(profiler.trend(fromProgress: 0, spanMeters: 5_000))
        XCTAssertEqual(trend.pattern, .flat, "平路被误判为 \(trend.pattern.rawValue)")
        XCTAssertLessThan(trend.ascentMeters, rawAscent * 0.25, "平滑后仍保留 \(trend.ascentMeters) m 假爬升")
        XCTAssertEqual(trend.netMeters, 0, accuracy: 6)
    }

    /// 真实上坡 + 噪声:趋势与数值都要保住。
    func testSustainedClimbSurvivesSmoothing() throws {
        var noise = NoiseGenerator()
        let route = makeRoute(lengthMeters: 2_000) { d in 100 + d * 0.08 + noise.next(amplitude: 2) }
        let profiler = try XCTUnwrap(RouteElevationProfiler(route: route))
        let trend = try XCTUnwrap(profiler.trend(fromProgress: 0, spanMeters: 2_000))
        XCTAssertEqual(trend.pattern, .climb)
        XCTAssertEqual(trend.netMeters, 160, accuracy: 15)
        XCTAssertEqual(trend.averageGradePercent, 8, accuracy: 1.5)
    }

    /// 「等会路线是下坡吗」的核心场景:接近坡顶时,
    /// 马上一段仍是上坡,稍后一段转为下坡 —— 两个窗口都要答对。
    func testAnswersIsItDownhillSoonNearSummit() throws {
        // 5 km:前 2.5 km 上坡(+6%),后 2.5 km 下坡(-6%),坡顶在 2.5 km
        let route = makeRoute(lengthMeters: 5_000) { d in
            d <= 2_500 ? 1_000 + d * 0.06 : 1_000 + 2_500 * 0.06 - (d - 2_500) * 0.06
        }
        let lookahead = RouteLookahead.compute(route: route, progressMeters: 2_200, riskPoints: [])

        let immediate = try XCTUnwrap(lookahead.immediateTrend)
        XCTAssertEqual(immediate.pattern, .climb, "坡顶前 300m 应仍是上坡")

        let upcoming = try XCTUnwrap(lookahead.upcomingTrend)
        XCTAssertEqual(upcoming.pattern, .descent, "过坡顶后应识别为下坡")
        XCTAssertGreaterThan(upcoming.descentMeters, 50)

        XCTAssertNotNil(lookahead.currentElevationMeters)
        XCTAssertNotNil(lookahead.currentGradePercent)
        XCTAssertGreaterThan(lookahead.currentGradePercent ?? 0, 3, "坡顶前脚下坡度应为正")
        // 中文摘要可直接进快照
        XCTAssertTrue(upcoming.summary.contains("下坡"))
    }

    /// 先升后降的整段坡型分类。
    func testClimbThenDescentPattern() throws {
        let route = makeRoute(lengthMeters: 5_000) { d in
            d <= 2_500 ? 500 + d * 0.06 : 500 + 150 - (d - 2_500) * 0.06
        }
        let profiler = try XCTUnwrap(RouteElevationProfiler(route: route))
        let trend = try XCTUnwrap(profiler.trend(fromProgress: 0, spanMeters: 5_000))
        XCTAssertEqual(trend.pattern, .climbThenDescent)
    }

    /// 任意进度处的插值海拔与脚下坡度。
    func testElevationAndGradeInterpolation() throws {
        let route = makeRoute(lengthMeters: 1_000) { d in 200 + d * 0.1 }
        let profiler = try XCTUnwrap(RouteElevationProfiler(route: route))
        XCTAssertEqual(try XCTUnwrap(profiler.elevation(atProgress: 500)), 250, accuracy: 2)
        XCTAssertEqual(try XCTUnwrap(profiler.gradePercent(atProgress: 500)), 10, accuracy: 1.5)
    }
}
