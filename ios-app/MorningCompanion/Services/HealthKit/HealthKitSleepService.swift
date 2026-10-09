import Foundation
import HealthKit

actor HealthKitSleepService: HealthKitServiceProtocol {
    // HKHealthStore() creation is deferred until first use to avoid blocking app startup.
    // HKHealthStore() involves entitlement parsing and daemon IPC (~100ms on first call).
    private var _healthStore: HKHealthStore?
    private var healthStore: HKHealthStore {
        if let existing = _healthStore { return existing }
        let store = HKHealthStore()
        _healthStore = store
        return store
    }
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private var requestedAuthorization = false
    private var receivedAuthorizationDenial = false

    init(
        calendar: Calendar = .current,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.calendar = calendar
        self.now = now
    }

    func authorizationState() async -> HealthKitAuthorizationState {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        if receivedAuthorizationDenial { return .denied }
        return requestedAuthorization ? .authorized : .notDetermined
    }

    func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw HealthKitServiceError.healthDataUnavailable
        }
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitServiceError.sleepTypeUnavailable
        }

        do {
            try await healthStore.requestAuthorization(toShare: [], read: [sleepType])
            requestedAuthorization = true
            receivedAuthorizationDenial = false
        } catch let error as HKError where error.code == .errorAuthorizationDenied {
            receivedAuthorizationDenial = true
            throw HealthKitServiceError.authorizationDenied
        } catch {
            throw HealthKitServiceError.queryFailed(underlying: error)
        }
    }

    func lastNightSleepDuration() async throws -> TimeInterval? {
        let wakeDay = calendar.startOfDay(for: now())
        let interval = try sleepWindow(endingOn: wakeDay)
        let samples = try await sleepSamples(in: interval)
        let duration = Self.asleepDuration(in: samples, clippedTo: interval)
        return duration > 0 ? duration : nil
    }

    func sleepHistory(days: Int) async throws -> [SleepEntry] {
        guard days > 0 else { return [] }

        let today = calendar.startOfDay(for: now())
        guard let earliestWakeDay = calendar.date(byAdding: .day, value: -(days - 1), to: today) else {
            return []
        }
        let firstWindow = try sleepWindow(endingOn: earliestWakeDay)
        let lastWindow = try sleepWindow(endingOn: today)
        let queryInterval = DateInterval(start: firstWindow.start, end: lastWindow.end)
        let samples = try await sleepSamples(in: queryInterval)

        return try (0..<days).compactMap { offset in
            guard let wakeDay = calendar.date(byAdding: .day, value: offset, to: earliestWakeDay) else {
                return nil
            }
            let interval = try sleepWindow(endingOn: wakeDay)
            let relevantSamples = samples.filter {
                $0.endDate > interval.start && $0.startDate < interval.end
            }
            let asleep = Self.asleepDuration(in: relevantSamples, clippedTo: interval)
            guard asleep > 0 else { return nil }
            let inBed = Self.inBedDuration(in: relevantSamples, clippedTo: interval)
            return SleepEntry(date: wakeDay, duration: asleep, inBedDuration: inBed)
        }
        .sorted { $0.date > $1.date }
    }

    private func sleepWindow(endingOn wakeDay: Date) throws -> DateInterval {
        guard let previousDay = calendar.date(byAdding: .day, value: -1, to: wakeDay),
              let start = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: previousDay),
              let end = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: wakeDay) else {
            throw HealthKitServiceError.queryFailed(underlying: SleepWindowError.invalidDate)
        }
        return DateInterval(start: start, end: end)
    }

    private func sleepSamples(in interval: DateInterval) async throws -> [HKCategorySample] {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            throw HealthKitServiceError.sleepTypeUnavailable
        }

        let predicate = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: .strictEndDate
        )

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let hkError = error as? HKError, hkError.code == .errorAuthorizationDenied {
                    continuation.resume(throwing: HealthKitServiceError.authorizationDenied)
                    return
                }
                if let error {
                    continuation.resume(throwing: HealthKitServiceError.queryFailed(underlying: error))
                    return
                }
                continuation.resume(returning: samples as? [HKCategorySample] ?? [])
            }
            healthStore.execute(query)
        }
    }

    nonisolated static func asleepDuration(
        in samples: [HKCategorySample],
        clippedTo window: DateInterval
    ) -> TimeInterval {
        mergedDuration(of: samples.filter { $0.isAsleep }, clippedTo: window)
    }

    nonisolated static func inBedDuration(
        in samples: [HKCategorySample],
        clippedTo window: DateInterval
    ) -> TimeInterval {
        let inBedSamples = samples.filter {
            $0.value == HKCategoryValueSleepAnalysis.inBed.rawValue || $0.isAsleep
        }
        return mergedDuration(of: inBedSamples, clippedTo: window)
    }

    nonisolated private static func mergedDuration(
        of samples: [HKCategorySample],
        clippedTo window: DateInterval
    ) -> TimeInterval {
        let intervals = samples
            .compactMap { sample -> DateInterval? in
                let start = max(sample.startDate, window.start)
                let end = min(sample.endDate, window.end)
                return end > start ? DateInterval(start: start, end: end) : nil
            }
            .sorted { $0.start < $1.start }

        guard var current = intervals.first else { return 0 }
        var total: TimeInterval = 0

        for interval in intervals.dropFirst() {
            if interval.start <= current.end {
                current = DateInterval(start: current.start, end: max(current.end, interval.end))
            } else {
                total += current.duration
                current = interval
            }
        }
        return total + current.duration
    }
}

private extension HKCategorySample {
    nonisolated var isAsleep: Bool {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM:
            return true
        default:
            return false
        }
    }
}

private enum SleepWindowError: LocalizedError {
    case invalidDate

    var errorDescription: String? { "Unable to construct the sleep query window." }
}
