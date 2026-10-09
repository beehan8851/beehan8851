import Foundation
import os

/// Versioned container for the persisted alarm list.
///
/// Two shapes live under the same UserDefaults key: v1 wrote a bare JSON array of
/// alarms, v2 writes this envelope. The shape is therefore its own version marker,
/// and reading is the only place that has to know. `Alarm`'s own decoder handles the
/// renamed fields (see `AlarmSchemaV1`), so everything above this type sees v2.
struct AlarmEnvelope: Codable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let alarms: [Alarm]

    init(alarms: [Alarm]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.alarms = alarms
    }

    // MARK: - Fault-tolerant decoding

    private enum CodingKeys: String, CodingKey { case schemaVersion, alarms }

    /// Decodes each alarm independently so that one corrupt entry never destroys valid ones.
    init(from decoder: Decoder) throws {
        // A v1 store is a bare array at this key, with no envelope around it.
        if let raw = try? decoder.singleValueContainer().decode([FaultTolerantAlarm].self) {
            // Read into a local first: the log call captures its arguments in an
            // escaping autoclosure, which cannot reach a half-initialised self.
            let migrated = Self.surviving(raw)
            schemaVersion = 1
            alarms = migrated
            Log.storage.info("AlarmEnvelope: read \(migrated.count, privacy: .public) alarm(s) from the v1 schema")
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        alarms = Self.surviving((try? container.decode([FaultTolerantAlarm].self, forKey: .alarms)) ?? [])
    }

    /// Keeps every alarm that decoded and reports the ones that did not, rather than
    /// letting a single bad entry take the list down with it.
    private static func surviving(_ raw: [FaultTolerantAlarm]) -> [Alarm] {
        var valid: [Alarm] = []
        var corruptCount = 0
        for item in raw {
            switch item.result {
            case .success(let alarm):
                valid.append(alarm)
            case .failure(let error):
                corruptCount += 1
                Log.storage.error("AlarmEnvelope: skipping corrupt alarm entry: \(error.localizedDescription, privacy: .public)")
            }
        }
        if corruptCount > 0 {
            Log.storage.warning("AlarmEnvelope: \(corruptCount, privacy: .public) of \(raw.count, privacy: .public) alarm(s) were corrupt and skipped.")
        }
        return valid
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(alarms, forKey: .alarms)
    }

    /// Whether what was read is older than what this build writes, and so should be
    /// written back in the current shape.
    var needsUpgrade: Bool { schemaVersion < Self.currentSchemaVersion }

    func migrate() throws -> [Alarm] {
        // Field-level migration already happened in Alarm's decoder; a version from
        // the future is the only thing this cannot make sense of.
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw AlarmRepositoryError.migrationRequired(
                fromVersion: schemaVersion,
                toVersion: Self.currentSchemaVersion
            )
        }
        return alarms
    }
}

// MARK: - Fault-tolerant element wrapper

/// Wraps Alarm decoding so that a corrupt element is captured as .failure rather than
/// propagating a throw that would abort the entire [Alarm] array decode.
private struct FaultTolerantAlarm: Decodable {
    let result: Result<Alarm, Error>

    init(from decoder: Decoder) throws {
        // Never throws — the outer [FaultTolerantAlarm] decode always advances past this element.
        do {
            result = .success(try Alarm(from: decoder))
        } catch {
            result = .failure(error)
        }
    }
}
