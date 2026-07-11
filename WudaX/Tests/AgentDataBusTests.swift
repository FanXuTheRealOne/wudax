import XCTest
@testable import WudaX

final class AgentDataBusTests: XCTestCase {

    // MARK: RouteLookahead

    /// 构造一条 4 km 直线路线:前 2 km 爬升,后 2 km 下降,中途 1 个航点。
    private func makeRoute() -> PreparedGPXRoute {
        let step = 100.0
        let count = 41   // 0...4000m
        let vertices = (0..<count).map { i -> PreparedRouteVertex in
            let distance = Double(i) * step
            let elevation = distance <= 2_000 ? 1_000 + distance * 0.2 : 1_400 - (distance - 2_000) * 0.15
            return PreparedRouteVertex(
                coordinate: RouteCoordinate(latitude: 30, longitude: 100 + distance / 111_000),
                localXMeters: distance, localYMeters: 0,
                elevationMeters: elevation,
                cumulativeDistanceMeters: distance,
                remainingDistanceMeters: 4_000 - distance,
                remainingAscentMeters: 0,
                sourcePointIndex: i)
        }
        return PreparedGPXRoute(
            formatVersion: 1, name: "测试线", sourcePointCount: count, sourceSegmentCount: 1,
            origin: RouteCoordinate(latitude: 30, longitude: 100),
            vertices: vertices, segments: [],
            waypoints: [PreparedRouteWaypoint(name: "垭口",
                                              coordinate: RouteCoordinate(latitude: 30, longitude: 100.018),
                                              elevationMeters: 1_400,
                                              routeProgressMeters: 2_000,
                                              distanceFromRouteMeters: 0)],
            turnVertexIndices: [], ambiguousSegmentPairs: [],
            flags: RouteTopologyFlags(isLoop: false, isOutAndBack: false, hasNearbyParallelSegments: false),
            totalDistanceMeters: 4_000, totalAscentMeters: 400)
    }

    func testLookaheadComputesNextKilometerClimbAndWaypoint() {
        let lookahead = RouteLookahead.compute(route: makeRoute(), progressMeters: 500,
                                               riskPoints: [("最高点", 2_000)])
        // 500–1500 m 段每 100 m 升 20 m → 爬升约 200 m
        XCTAssertEqual(lookahead.nextKmAscentMeters, 200, accuracy: 25)
        XCTAssertEqual(lookahead.nextKmDescentMeters, 0, accuracy: 1)
        XCTAssertNotNil(lookahead.nextKmAvgGradePercent)
        XCTAssertEqual(lookahead.nextWaypoint?.title, "垭口")
        XCTAssertEqual(lookahead.nextWaypoint?.distanceMeters ?? 0, 1_500, accuracy: 1)
        XCTAssertEqual(lookahead.upcomingRiskPoints.first?.title, "最高点")
        XCTAssertEqual(lookahead.upcomingRiskPoints.first?.distanceMeters ?? 0, 1_500, accuracy: 1)
        XCTAssertFalse(lookahead.segmentSummaries.isEmpty)
    }

    func testLookaheadSkipsPassedRiskPoints() {
        let lookahead = RouteLookahead.compute(route: makeRoute(), progressMeters: 2_500,
                                               riskPoints: [("最高点", 2_000), ("下降段", 3_000)])
        XCTAssertEqual(lookahead.upcomingRiskPoints.map(\.title), ["下降段"])
        XCTAssertNil(lookahead.nextWaypoint)   // 航点已经过
    }

    // MARK: 信号检测

    private func recordingInput() -> AgentSignalInput {
        var input = AgentSignalInput()
        input.isRecording = true
        input.verdict = .proceed
        return input
    }

    func testSessionStartFiresOnceThenVerdictChangeFires() {
        var memory = AgentSignalMemory()
        let t0 = Date()
        XCTAssertEqual(AgentSignalDetector.detect(input: recordingInput(), memory: &memory, now: t0),
                       .sessionStart)
        // 全局冷却内不再触发
        XCTAssertNil(AgentSignalDetector.detect(input: recordingInput(), memory: &memory,
                                                now: t0.addingTimeInterval(10)))
        // 冷却过后,判级变化触发
        var worse = recordingInput()
        worse.verdict = .downgrade
        let signal = AgentSignalDetector.detect(input: worse, memory: &memory,
                                                now: t0.addingTimeInterval(120))
        XCTAssertEqual(signal, .verdictChanged(.downgrade))
        // 同信号 8 分钟冷却:再变回 proceed 不立即播报
        var back = recordingInput()
        back.verdict = .proceed
        XCTAssertNil(AgentSignalDetector.detect(input: back, memory: &memory,
                                                now: t0.addingTimeInterval(240)))
    }

    func testNotRecordingProducesNoSignals() {
        var memory = AgentSignalMemory()
        var input = recordingInput()
        input.isRecording = false
        XCTAssertNil(AgentSignalDetector.detect(input: input, memory: &memory, now: Date()))
    }

    func testHeartRateShiftAgainstBaseline() {
        var memory = AgentSignalMemory()
        let t0 = Date()
        _ = AgentSignalDetector.detect(input: recordingInput(), memory: &memory, now: t0) // sessionStart
        for _ in 0..<AgentSignalDetector.baselineSamples {
            AgentSignalDetector.recordHeartRate(120, memory: &memory)
        }
        var input = recordingInput()
        input.heartRateBPM = 124   // 漂移 <15,不触发
        XCTAssertNil(AgentSignalDetector.detect(input: input, memory: &memory,
                                                now: t0.addingTimeInterval(120)))
        input.heartRateBPM = 141   // 漂移 21 → 触发
        let signal = AgentSignalDetector.detect(input: input, memory: &memory,
                                                now: t0.addingTimeInterval(240))
        XCTAssertEqual(signal, .heartRateShift(bpm: 141, baselineBPM: 120))
        // 同一带宽内(冷却后)不重复播报
        input.heartRateBPM = 143
        XCTAssertNil(AgentSignalDetector.detect(input: input, memory: &memory,
                                                now: t0.addingTimeInterval(20 * 60)))
    }

    func testMilestoneAndRiskPointFireOncePerKey() {
        var memory = AgentSignalMemory()
        let t0 = Date()
        _ = AgentSignalDetector.detect(input: recordingInput(), memory: &memory, now: t0)

        var input = recordingInput()
        input.upcomingRisk = (title: "最高点", distanceMeters: 500)
        XCTAssertEqual(AgentSignalDetector.detect(input: input, memory: &memory,
                                                  now: t0.addingTimeInterval(120)),
                       .upcomingRiskPoint(title: "最高点", distanceMeters: 500))
        // 同一个风险点不重复
        input.upcomingRisk = (title: "最高点", distanceMeters: 300)
        XCTAssertNil(AgentSignalDetector.detect(input: input, memory: &memory,
                                                now: t0.addingTimeInterval(300)))

        var milestone = recordingInput()
        milestone.progressFraction = 0.52
        XCTAssertEqual(AgentSignalDetector.detect(input: milestone, memory: &memory,
                                                  now: t0.addingTimeInterval(600)),
                       .progressMilestone(percent: 25))   // 先补 25
        XCTAssertEqual(AgentSignalDetector.detect(input: milestone, memory: &memory,
                                                  now: t0.addingTimeInterval(720)),
                       .progressMilestone(percent: 50))
        XCTAssertNil(AgentSignalDetector.detect(input: milestone, memory: &memory,
                                                now: t0.addingTimeInterval(840)))
    }

    // MARK: 快照与文本

    @MainActor
    func testRiskPointProgressConversion() {
        var route = SampleData.niyuhe
        route.riskPoints = [.init(profileIndex: 18, title: "中点", detail: "")]
        // profile 36 点 → index 18 位于中间
        let points = AgentDataBus.riskPointProgress(route: route, totalDistanceMeters: 10_000)
        XCTAssertEqual(points.first?.progressMeters ?? 0, 10_000 * 18.0 / 35.0, accuracy: 1)
    }

    @MainActor
    func testFullSnapshotContainsCoreSections() {
        let session = TripSession()
        let snapshot = AgentDataBus.fullSnapshot(session: session)
        XCTAssertTrue(snapshot.contains("【路线】"))
        XCTAssertTrue(snapshot.contains("【实时】"))
        XCTAssertTrue(snapshot.contains("【安全结论"))
        XCTAssertTrue(snapshot.contains("【用户画像】"))
    }

    func testStripThinkingRemovesClosedAndOrphanBlocks() {
        XCTAssertEqual(LocalLLMService.stripThinking("<think>推理中</think>注意补水。"), "注意补水。")
        XCTAssertEqual(LocalLLMService.stripThinking("前方长下坡。<think>未闭合"), "前方长下坡。")
        XCTAssertEqual(LocalLLMService.stripThinking("  正常输出  "), "正常输出")
    }
}
