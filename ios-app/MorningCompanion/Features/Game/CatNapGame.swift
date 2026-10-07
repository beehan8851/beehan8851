import Foundation

/// A game of Cat Naps under way: what is on each cell, the clock, and whether every
/// cat is asleep. The rules only — the screen reports taps and strokes, and reads back
/// which cells clash and which cats are awake.
///
/// A cat put too close to another (same row, column or cushion, or touching) wakes
/// up, and so does the one it woke: the board says what is wrong without a word.
@MainActor
@Observable
final class CatNapGame {
    enum Cell: Int, Codable, Equatable {
        case empty, mark, cat
    }

    let number: Int
    let level: CatNapLevel
    let puzzle: CatNapPuzzle
    private(set) var cells: [Cell]
    private(set) var hints = 0
    private(set) var solved = false
    /// When each cat was put down, for its little drop onto the cushion.
    private(set) var placedAt: [Int: Date] = [:]
    /// Cells that share a row, column or cushion with another cat, or touch one.
    private(set) var clashing: Set<Int> = []
    /// Cats in a clash.
    private(set) var awake: Set<Int> = []

    private var history: [[Cell]] = []
    /// Time on the clock before the last resume.
    private var banked: TimeInterval
    private var runningSince: Date?

    var size: Int { puzzle.size }
    var canUndo: Bool { !history.isEmpty && !solved }
    var catCount: Int { cells.filter { $0 == .cat }.count }
    var isUntouched: Bool { cells.allSatisfy { $0 == .empty } }

    init(number: Int, level: CatNapLevel, puzzle: CatNapPuzzle, saved: CatNapProgress? = nil) {
        self.number = number
        self.level = level
        self.puzzle = puzzle
        let count = puzzle.size * puzzle.size
        if let saved, saved.number == number, saved.level == level.rawValue, saved.cells.count == count {
            cells = saved.cells.map { Cell(rawValue: $0) ?? .empty }
            banked = saved.seconds
            hints = saved.hints
        } else {
            cells = Array(repeating: .empty, count: count)
            banked = 0
        }
        refresh()
    }

    // MARK: - The clock

    func elapsed(at now: Date) -> TimeInterval {
        banked + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    func resume(at now: Date) {
        guard runningSince == nil, !solved else { return }
        runningSince = now
    }

    func pause(at now: Date) {
        guard let since = runningSince else { return }
        banked += now.timeIntervalSince(since)
        runningSince = nil
    }

    // MARK: - Moves

    /// A tap: empty, then ruled out, then a cat, then empty again.
    @discardableResult
    func tap(_ index: Int, at now: Date) -> Cell {
        guard !solved, cells.indices.contains(index) else { return cells[safe: index] ?? .empty }
        history.append(cells)
        let next: Cell = switch cells[index] {
        case .empty: .mark
        case .mark: .cat
        case .cat: .empty
        }
        set(index, next, at: now)
        return next
    }

    /// A finger drawn across the board rules cells out (or clears them) one after
    /// another, as one move for undo. Cats stay where they are.
    func beginStroke() {
        guard !solved else { return }
        history.append(cells)
    }

    func paint(_ index: Int, _ cell: Cell, at now: Date) {
        guard !solved, cell != .cat, cells.indices.contains(index), cells[index] != .cat, cells[index] != cell else { return }
        set(index, cell, at: now)
    }

    func undo(at now: Date) {
        guard !solved, let last = history.popLast() else { return }
        cells = last
        refresh()
    }

    func clear(at now: Date) {
        guard !solved, !isUntouched else { return }
        history.append(cells)
        cells = Array(repeating: .empty, count: cells.count)
        placedAt = [:]
        refresh()
    }

    /// Wakes a cat that is in the wrong place, or, if none is, puts one where it
    /// belongs. Returns the cell it changed.
    @discardableResult
    func hint(at now: Date) -> Int? {
        guard !solved else { return nil }
        let n = size
        let target: Int
        let cell: Cell
        if let wrong = cells.indices.first(where: { cells[$0] == .cat && !puzzle.isCat(row: $0 / n, column: $0 % n) }) {
            target = wrong
            cell = .mark
        } else if let row = (0..<n).first(where: { cells[$0 * n + puzzle.solution[$0]] != .cat }) {
            target = row * n + puzzle.solution[row]
            cell = .cat
        } else {
            return nil
        }
        history.append(cells)
        hints += 1
        set(target, cell, at: now)
        return target
    }

    // MARK: - Checking

    private func set(_ index: Int, _ cell: Cell, at now: Date) {
        cells[index] = cell
        if cell == .cat { placedAt[index] = now } else { placedAt[index] = nil }
        refresh()
        if catCount == size && clashing.isEmpty {
            pause(at: now)
            solved = true
        }
    }

    private func refresh() {
        let n = size
        let cats = cells.indices.filter { cells[$0] == .cat }
        var clash = Set<Int>()
        var woken = Set<Int>()
        // Rows, columns and cushions with two cats or more: the whole of it.
        let lines: [(Int) -> Int] = [{ $0 / n }, { $0 % n }, { self.puzzle.regions[$0] }]
        for key in lines {
            let groups = Dictionary(grouping: cats, by: key)
            for (value, group) in groups where group.count > 1 {
                woken.formUnion(group)
                clash.formUnion(cells.indices.filter { key($0) == value })
            }
        }
        // Cats touching, corners too: just the two of them.
        for a in cats {
            for b in cats where b > a && abs(a / n - b / n) <= 1 && abs(a % n - b % n) <= 1 {
                woken.formUnion([a, b])
                clash.formUnion([a, b])
            }
        }
        clashing = clash
        awake = woken
    }

    var progress: CatNapProgress {
        CatNapProgress(number: number, level: level.rawValue, cells: cells.map(\.rawValue), seconds: elapsed(at: .now), hints: hints)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Kept between visits

/// A board left half done, to come back to.
nonisolated struct CatNapProgress: Codable, Equatable, Sendable {
    var number: Int
    var level: Int
    var cells: [Int]
    var seconds: TimeInterval
    var hints: Int
}

/// The puzzles solved on this device, and the boards left half done.
enum CatNapRecord {
    struct Solve: Codable, Equatable {
        var seconds: Int
        var hints: Int
        /// Solved on the puzzle's own day. Only these count for the streak.
        var onTheDay: Bool
    }

    private static let solvesKey = "com.morningcompanion.game.naps.solves"
    private static let progressKey = "com.morningcompanion.game.naps.progress"
    /// Half-done boards kept at most; the oldest go first.
    private static let progressKept = 9

    /// Stored as "number.level".
    private static func key(_ number: Int, _ level: CatNapLevel) -> String { "\(number).\(level.rawValue)" }

    private static func all(in defaults: UserDefaults) -> [String: Solve] {
        guard let data = defaults.data(forKey: solvesKey),
              let stored = try? JSONDecoder().decode([String: Solve].self, from: data) else { return [:] }
        return stored
    }

    static func solve(_ number: Int, level: CatNapLevel, in defaults: UserDefaults = .standard) -> Solve? {
        all(in: defaults)[key(number, level)]
    }

    /// Every level of one day that has been solved.
    static func solves(_ number: Int, in defaults: UserDefaults = .standard) -> [CatNapLevel: Solve] {
        let stored = all(in: defaults)
        var result: [CatNapLevel: Solve] = [:]
        for level in CatNapLevel.allCases {
            if let solve = stored[key(number, level)] { result[level] = solve }
        }
        return result
    }

    /// Keeps the quicker time and the fewer hints; once solved on the day, always so.
    /// Returns whether it beat an earlier time.
    @discardableResult
    static func submit(number: Int, level: CatNapLevel, seconds: Int, hints: Int, onTheDay: Bool,
                       in defaults: UserDefaults = .standard) -> Bool {
        var stored = all(in: defaults)
        let earlier = stored[key(number, level)]
        stored[key(number, level)] = Solve(
            seconds: min(seconds, earlier?.seconds ?? .max),
            hints: min(hints, earlier?.hints ?? .max),
            onTheDay: onTheDay || earlier?.onTheDay == true
        )
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: solvesKey) }
        return earlier.map { seconds < $0.seconds } ?? false
    }

    /// Days in a row with a puzzle of the day, any level, solved that day, up to
    /// today — or up to yesterday while today's are still open, so the run does not
    /// look lost at 7 am.
    static func streak(today: Int, in defaults: UserDefaults = .standard) -> Int {
        let stored = all(in: defaults)
        func solvedOnTheDay(_ number: Int) -> Bool {
            CatNapLevel.allCases.contains { stored[key(number, $0)]?.onTheDay == true }
        }
        var day = solvedOnTheDay(today) ? today : today - 1
        var count = 0
        while day >= 1, solvedOnTheDay(day) {
            count += 1
            day -= 1
        }
        return count
    }

    static func progress(_ number: Int, level: CatNapLevel, in defaults: UserDefaults = .standard) -> CatNapProgress? {
        allProgress(in: defaults).first { $0.number == number && $0.level == level.rawValue }
    }

    static func save(_ progress: CatNapProgress, in defaults: UserDefaults = .standard) {
        var all = allProgress(in: defaults).filter { !($0.number == progress.number && $0.level == progress.level) }
        all.append(progress)
        all = Array(all.sorted { ($0.number, $0.level) > ($1.number, $1.level) }.prefix(progressKept))
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: progressKey) }
    }

    static func forget(_ number: Int, level: CatNapLevel, in defaults: UserDefaults = .standard) {
        let all = allProgress(in: defaults).filter { !($0.number == number && $0.level == level.rawValue) }
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: progressKey) }
    }

    private static func allProgress(in defaults: UserDefaults) -> [CatNapProgress] {
        guard let data = defaults.data(forKey: progressKey) else { return [] }
        return (try? JSONDecoder().decode([CatNapProgress].self, from: data)) ?? []
    }

    // MARK: - Unlimited

    /// Unlimited puzzles are made from a random seed rather than a date. The seed of
    /// the one under way at each level is kept, so a half-done board can be picked
    /// up again; its progress is stored under puzzle number 0.
    private static func seedKey(_ level: CatNapLevel) -> String { "com.morningcompanion.game.naps.unlimited.seed.\(level.rawValue)" }
    private static let statsKey = "com.morningcompanion.game.naps.unlimited.stats"
    private static let triesKey = "com.morningcompanion.game.naps.unlimited.freeTries"
    /// Unlimited puzzles a free account may start, once, to see what Premium is.
    static let freeTries = 3

    struct UnlimitedStats: Codable, Equatable {
        var solved = 0
        var bestSeconds: Int?
    }

    static func unlimitedSeed(_ level: CatNapLevel, in defaults: UserDefaults = .standard) -> UInt64? {
        defaults.string(forKey: seedKey(level)).flatMap(UInt64.init)
    }

    /// A fresh seed for `level`, replacing the board under way there.
    static func newUnlimitedSeed(_ level: CatNapLevel, in defaults: UserDefaults = .standard) -> UInt64 {
        let seed = UInt64.random(in: 1 ... .max)
        defaults.set(String(seed), forKey: seedKey(level))
        forget(CatNapDay.unlimited, level: level, in: defaults)
        return seed
    }

    static func stats(_ level: CatNapLevel, in defaults: UserDefaults = .standard) -> UnlimitedStats {
        allStats(in: defaults)[String(level.rawValue)] ?? UnlimitedStats()
    }

    /// Counts the solve, keeps the best time, and lets the next one be new. Returns
    /// whether it was a best.
    @discardableResult
    static func submitUnlimited(level: CatNapLevel, seconds: Int, in defaults: UserDefaults = .standard) -> Bool {
        var all = allStats(in: defaults)
        var stats = all[String(level.rawValue)] ?? UnlimitedStats()
        let best = stats.bestSeconds.map { seconds < $0 } ?? true
        stats.solved += 1
        stats.bestSeconds = min(seconds, stats.bestSeconds ?? .max)
        all[String(level.rawValue)] = stats
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: statsKey) }
        defaults.removeObject(forKey: seedKey(level))
        forget(CatNapDay.unlimited, level: level, in: defaults)
        return best
    }

    private static func allStats(in defaults: UserDefaults) -> [String: UnlimitedStats] {
        guard let data = defaults.data(forKey: statsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: UnlimitedStats].self, from: data)) ?? [:]
    }

    /// Free tries left to start an unlimited puzzle.
    static func freeTriesLeft(in defaults: UserDefaults = .standard) -> Int {
        max(0, freeTries - defaults.integer(forKey: triesKey))
    }

    static func useFreeTry(in defaults: UserDefaults = .standard) {
        defaults.set(defaults.integer(forKey: triesKey) + 1, forKey: triesKey)
    }

    // MARK: - The level to open with

    private static let levelKey = "com.morningcompanion.game.naps.level"

    /// The level last played, or easy for someone new to it.
    static func lastLevel(in defaults: UserDefaults = .standard) -> CatNapLevel {
        CatNapLevel(rawValue: defaults.integer(forKey: levelKey)) ?? .easy
    }

    static func setLastLevel(_ level: CatNapLevel, in defaults: UserDefaults = .standard) {
        defaults.set(level.rawValue, forKey: levelKey)
    }
}
