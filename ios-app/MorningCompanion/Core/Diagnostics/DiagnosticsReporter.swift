import Foundation
import MetricKit
import os

/// Receives the daily MetricKit payloads and writes a summary to the system log.
///
/// There is no server to send these to, and this app deliberately carries no analytics
/// SDK, so the payloads stay on the device. What it buys is the ability to attach a
/// phone — a tester's, or your own after a bad night — and read why the app hung or
/// died, which is otherwise the one thing that cannot be reproduced on demand.
///
/// Summaries are written at `.notice` so they survive in the system log rather than
/// only appearing in a live stream. The full payload goes to `.debug`, where it costs
/// nothing until someone goes looking.
///
/// Nothing is sent anywhere and nothing identifies anyone: MetricKit aggregates
/// payloads before the app ever sees them.
final class DiagnosticsReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsReporter()

    private let log = Logger(subsystem: Log.subsystem, category: "Diagnostics")

    func start() {
        MXMetricManager.shared.add(self)
        log.debug("MetricKit subscriber registered")
    }

    // MARK: - MXMetricManagerSubscriber

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            log.debug("Metric payload: \(String(decoding: payload.jsonRepresentation(), as: UTF8.self), privacy: .public)")
        }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            let disk = payload.diskWriteExceptionDiagnostics?.count ?? 0
            let cpu = payload.cpuExceptionDiagnostics?.count ?? 0
            guard crashes + hangs + disk + cpu > 0 else { continue }

            log.notice("""
                Diagnostics — crashes \(crashes, privacy: .public), hangs \(hangs, privacy: .public), \
                disk-write \(disk, privacy: .public), cpu \(cpu, privacy: .public)
                """)

            for crash in payload.crashDiagnostics ?? [] {
                log.error("""
                    Crash: type \(crash.exceptionType?.stringValue ?? "unknown", privacy: .public), \
                    code \(crash.exceptionCode?.stringValue ?? "—", privacy: .public), \
                    signal \(crash.signal?.stringValue ?? "—", privacy: .public), \
                    build \(crash.metaData.applicationBuildVersion, privacy: .public)
                    """)
            }
            // A hang in an alarm app is not a cosmetic problem: the ring screen is the
            // one place the user cannot wait.
            for hang in payload.hangDiagnostics ?? [] {
                log.error("Hang of \(hang.hangDuration.value, privacy: .public) \(hang.hangDuration.unit.symbol, privacy: .public)")
            }

            log.debug("Diagnostic payload: \(String(decoding: payload.jsonRepresentation(), as: UTF8.self), privacy: .public)")
        }
    }
}
