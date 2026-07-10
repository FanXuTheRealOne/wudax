import Foundation
import HealthKit
import Combine

@MainActor
final class HealthKitService: ObservableObject {
    enum AuthorizationState: Equatable {
        case notDetermined
        case requesting
        case granted
        case denied
        case unavailable
    }

    @Published private(set) var authorizationState: AuthorizationState
    @Published private(set) var lastSnapshot: HealthSnapshot?

    private let store = HKHealthStore()
    private var observerQueries: [HKQuery] = []

    init() {
        authorizationState = HKHealthStore.isHealthDataAvailable() ? .notDetermined : .unavailable
    }

    var requestedTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>()
        for descriptor in quantityDescriptors {
            if let type = HKObjectType.quantityType(forIdentifier: descriptor.identifier) { types.insert(type) }
        }
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { types.insert(sleep) }
        types.insert(HKObjectType.workoutType())
        return types
    }

    func requestAuthorization() async -> AuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else {
            authorizationState = .unavailable
            return .unavailable
        }
        authorizationState = .requesting
        do {
            try await store.requestAuthorization(toShare: [], read: requestedTypes)
            authorizationState = .granted
            startObservers()
        } catch {
            authorizationState = .denied
        }
        return authorizationState
    }

    func fetchSnapshot(asOf date: Date = Date()) async -> HealthSnapshot {
        guard HKHealthStore.isHealthDataAvailable(), authorizationState == .granted else {
            let snapshot = HealthSnapshot(capturedAt: date, readings: [:], unavailableMetrics: Set(HealthMetric.allCases), authorizationGranted: false)
            lastSnapshot = snapshot
            return snapshot
        }

        var readings: [HealthMetric: HealthReading] = [:]
        var unavailable = Set(HealthMetric.allCases)
        for descriptor in quantityDescriptors {
            guard let type = HKObjectType.quantityType(forIdentifier: descriptor.identifier),
                  let result = await latestQuantity(type: type, unit: descriptor.unit, since: date.addingTimeInterval(-30 * 24 * 3600)) else { continue }
            let metric = descriptor.metric
            readings[metric] = HealthReading(value: result.value, unit: descriptor.unit.unitString,
                                              sampledAt: result.date, sourceName: result.sourceName,
                                              freshness: freshness(for: result.date, comparedTo: date))
            unavailable.remove(metric)
        }

        if let sleep = await recentSleepDuration(asOf: date) {
            readings[.sleepDuration] = HealthReading(value: sleep.value, unit: "h", sampledAt: sleep.date,
                                                      sourceName: sleep.sourceName, freshness: freshness(for: sleep.date, comparedTo: date))
            unavailable.remove(.sleepDuration)
        }

        let snapshot = HealthSnapshot(capturedAt: date, readings: readings, unavailableMetrics: unavailable, authorizationGranted: true)
        lastSnapshot = snapshot
        return snapshot
    }

    func stopObservers() {
        observerQueries.forEach(store.stop)
        observerQueries.removeAll()
    }

    private func startObservers() {
        stopObservers()
        for descriptor in quantityDescriptors {
            guard let type = HKObjectType.quantityType(forIdentifier: descriptor.identifier) else { continue }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                completion()
                Task { @MainActor in
                    guard let self else { return }
                    self.lastSnapshot = await self.fetchSnapshot()
                }
            }
            observerQueries.append(query)
            store.execute(query)
        }
    }

    private func latestQuantity(type: HKQuantityType, unit: HKUnit, since: Date) async -> (value: Double, date: Date, sourceName: String?)? {
        await withCheckedContinuation { continuation in
            let predicate = HKQuery.predicateForSamples(withStart: since, end: Date(), options: .strictStartDate)
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                guard let sample = samples?.first as? HKQuantitySample else { continuation.resume(returning: nil); return }
                continuation.resume(returning: (sample.quantity.doubleValue(for: unit), sample.endDate, sample.sourceRevision.source.name))
            }
            self.store.execute(query)
        }
    }

    private func recentSleepDuration(asOf date: Date) async -> (value: Double, date: Date, sourceName: String?)? {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
        return await withCheckedContinuation { continuation in
            let start = date.addingTimeInterval(-36 * 3600)
            let predicate = HKQuery.predicateForSamples(withStart: start, end: date, options: .strictStartDate)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                let sleepSamples = (samples ?? []).compactMap { $0 as? HKCategorySample }
                    .filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue || $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue || $0.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue || $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue }
                guard !sleepSamples.isEmpty else { continuation.resume(returning: nil); return }
                let duration = sleepSamples.reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) } / 3600
                let latest = sleepSamples.max { $0.endDate < $1.endDate }!
                continuation.resume(returning: (duration, latest.endDate, latest.sourceRevision.source.name))
            }
            self.store.execute(query)
        }
    }

    private func freshness(for date: Date, comparedTo reference: Date) -> DataFreshness {
        let age = max(0, reference.timeIntervalSince(date))
        if age < 24 * 3600 { return .current }
        if age < 7 * 24 * 3600 { return .recent }
        return .stale
    }

    private struct QuantityDescriptor {
        var metric: HealthMetric
        var identifier: HKQuantityTypeIdentifier
        var unit: HKUnit
    }

    private var quantityDescriptors: [QuantityDescriptor] {
        [
            .init(metric: .height, identifier: .height, unit: .meter()),
            .init(metric: .weight, identifier: .bodyMass, unit: .gramUnit(with: .kilo)),
            .init(metric: .bmi, identifier: .bodyMassIndex, unit: .count()),
            .init(metric: .bodyFat, identifier: .bodyFatPercentage, unit: .percent()),
            .init(metric: .leanBodyMass, identifier: .leanBodyMass, unit: .gramUnit(with: .kilo)),
            .init(metric: .steps, identifier: .stepCount, unit: .count()),
            .init(metric: .walkingRunningDistance, identifier: .distanceWalkingRunning, unit: .meter()),
            .init(metric: .flightsClimbed, identifier: .flightsClimbed, unit: .count()),
            .init(metric: .activeEnergy, identifier: .activeEnergyBurned, unit: .kilocalorie()),
            .init(metric: .exerciseTime, identifier: .appleExerciseTime, unit: .minute()),
            .init(metric: .heartRate, identifier: .heartRate, unit: HKUnit.count().unitDivided(by: .minute())),
            .init(metric: .restingHeartRate, identifier: .restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute())),
            .init(metric: .walkingHeartRateAverage, identifier: .walkingHeartRateAverage, unit: HKUnit.count().unitDivided(by: .minute())),
            .init(metric: .heartRateVariability, identifier: .heartRateVariabilitySDNN, unit: .secondUnit(with: .milli)),
            .init(metric: .oxygenSaturation, identifier: .oxygenSaturation, unit: .percent()),
            .init(metric: .respiratoryRate, identifier: .respiratoryRate, unit: HKUnit.count().unitDivided(by: .minute())),
            .init(metric: .vo2Max, identifier: .vo2Max, unit: HKUnit.literUnit(with: .milli).unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute())),
            .init(metric: .walkingAsymmetry, identifier: .walkingAsymmetryPercentage, unit: .percent()),
            .init(metric: .walkingDoubleSupport, identifier: .walkingDoubleSupportPercentage, unit: .percent()),
            .init(metric: .walkingSpeed, identifier: .walkingSpeed, unit: .meter().unitDivided(by: .second())),
            .init(metric: .sixMinuteWalkDistance, identifier: .sixMinuteWalkTestDistance, unit: .meter())
        ]
    }
}
