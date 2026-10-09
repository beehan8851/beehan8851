import Foundation

/// The rhythm of a wind-down: a slow breath in, a longer one out. Six breaths a
/// minute, with the out-breath longer than the in-breath — the pattern that slows the
/// heart rather than the one that sounds calm.
struct BreathPacer: Equatable {
    enum Phase: Equatable { case breatheIn, breatheOut }

    var inhale: TimeInterval = 4
    var exhale: TimeInterval = 6

    var cycle: TimeInterval { inhale + exhale }

    struct Moment: Equatable {
        let phase: Phase
        /// How far through the phase, 0–1.
        let progress: Double
        /// The breath itself, -1 (all out) to 1 (all in), eased at both ends.
        let breath: Double
        /// Counts every phase since the start, so a change can be noticed.
        let index: Int
    }

    func moment(at elapsed: TimeInterval) -> Moment {
        let t = max(elapsed, 0)
        let cycles = Int(t / cycle)
        let within = t - Double(cycles) * cycle
        if within < inhale {
            let p = within / inhale
            return Moment(phase: .breatheIn, progress: p, breath: -cos(p * .pi), index: cycles * 2)
        } else {
            let p = (within - inhale) / exhale
            return Moment(phase: .breatheOut, progress: p, breath: cos(p * .pi), index: cycles * 2 + 1)
        }
    }

    /// A length rounded to whole breaths, so a session never ends half-way through one.
    func wholeBreaths(in minutes: Int) -> TimeInterval {
        let breaths = max(1, (Double(minutes) * 60 / cycle).rounded())
        return breaths * cycle
    }
}
