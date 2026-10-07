import Foundation

/// One Cat Naps puzzle: a square of cells cut into as many cushions as there are rows.
/// A cat goes on every cushion so that each row, each column and each cushion has
/// exactly one, and no two cats touch, not even at a corner. Each puzzle has one
/// answer.
///
/// Made from a seed, never stored: the same day makes the same puzzle on every
/// phone, so two people can talk about this morning's. The random numbers are our
/// own (`NapRandom`) rather than the standard library's, whose way of drawing a
/// number in a range is free to change between Swift versions.
nonisolated struct CatNapPuzzle: Equatable, Sendable {
    let size: Int
    /// The cushion each cell is on, row by row: `regions[row * size + column]`.
    let regions: [Int]
    /// The answer: the column of the cat in each row.
    let solution: [Int]

    func region(row: Int, column: Int) -> Int { regions[row * size + column] }

    func isCat(row: Int, column: Int) -> Bool { solution[row] == column }

    // MARK: - Making one

    /// The puzzle for `seed`: one answer, reached by reasoning alone, never by
    /// guessing, and needing no harder step than `steps` allows. A few milliseconds
    /// in a release build.
    static func generate(size: Int, seed: UInt64, steps: ClosedRange<Reasoning> = .single ... .groups) -> CatNapPuzzle {
        var random = NapRandom(seed: seed)
        while true {
            let cats = placeCats(size: size, random: &random)
            var regions = growCushions(size: size, cats: cats, random: &random)
            guard makeUnique(size: size, regions: &regions, cats: cats, random: &random) else { continue }
            let puzzle = CatNapPuzzle(size: size, regions: regions, solution: cats)
            if let hardest = puzzle.hardestStep(), steps.contains(hardest) { return puzzle }
        }
    }

    /// One cat a row and a column, none touching: a shuffled search, row by row.
    private static func placeCats(size: Int, random: inout NapRandom) -> [Int] {
        var columns: [Int] = []
        var used = Set<Int>()
        func place(_ row: Int) -> Bool {
            if row == size { return true }
            for column in random.shuffled(Array(0..<size)) where !used.contains(column) {
                if let above = columns.last, abs(above - column) < 2 { continue }
                columns.append(column)
                used.insert(column)
                if place(row + 1) { return true }
                columns.removeLast()
                used.remove(column)
            }
            return false
        }
        _ = place(0)
        return columns
    }

    /// Every cat's cell starts a cushion, and the cushions spread one cell at a time
    /// into their neighbours until the board is covered. Each has its own appetite,
    /// so some stay small and some sprawl, which is what makes a puzzle one can
    /// reason about.
    private static func growCushions(size: Int, cats: [Int], random: inout NapRandom) -> [Int] {
        var regions = [Int](repeating: -1, count: size * size)
        for (row, column) in cats.enumerated() { regions[row * size + column] = row }
        let appetite = (0..<size).map { _ in 1 + random.int(below: 6) }
        let total = appetite.reduce(0, +)
        var left = size * size - size
        while left > 0 {
            // A cushion by appetite, then one of the empty cells beside it.
            var pick = random.int(below: total)
            var region = 0
            while pick >= appetite[region] { pick -= appetite[region]; region += 1 }
            var edge: [Int] = []
            for cell in 0..<(size * size) where regions[cell] == -1 {
                if neighbours(of: cell, size: size).contains(where: { regions[$0] == region }) { edge.append(cell) }
            }
            guard !edge.isEmpty else { continue }
            regions[edge[random.int(below: edge.count)]] = region
            left -= 1
        }
        return regions
    }

    /// Moves cells from cushion to cushion until no second answer is left. A second
    /// answer puts a cat somewhere ours does not; handing that cell to a neighbouring
    /// cushion breaks that answer and never ours, as long as no cat's own cell moves
    /// and every cushion stays in one piece. False if it gives up.
    private static func makeUnique(size: Int, regions: inout [Int], cats: [Int], random: inout NapRandom) -> Bool {
        let catCells = Set(cats.enumerated().map { $0.offset * size + $0.element })
        for _ in 0..<(size * size * 2) {
            guard let other = secondSolution(size: size, regions: regions, avoiding: cats) else { return true }
            let rows = random.shuffled((0..<size).filter { other[$0] != cats[$0] })
            var moved = false
            for row in rows {
                let cell = row * size + other[row]
                guard !catCells.contains(cell) else { continue }
                let from = regions[cell]
                let choices = Set(neighbours(of: cell, size: size).map { regions[$0] }).subtracting([from])
                for to in random.shuffled(Array(choices).sorted()) {
                    regions[cell] = to
                    if isConnected(region: from, regions: regions, size: size) { moved = true; break }
                    regions[cell] = from
                }
                if moved { break }
            }
            if !moved { return false }
        }
        return false
    }

    // MARK: - Solving

    /// Every answer to a board, up to `limit`.
    static func solutions(size: Int, regions: [Int], limit: Int = 2) -> [[Int]] {
        var found: [[Int]] = []
        var columns: [Int] = []
        var usedColumns = 0
        var usedRegions = 0
        func place(_ row: Int) {
            if found.count >= limit { return }
            if row == size { found.append(columns); return }
            for column in 0..<size {
                let region = regions[row * size + column]
                if usedColumns & (1 << column) != 0 || usedRegions & (1 << region) != 0 { continue }
                if let above = columns.last, abs(above - column) < 2 { continue }
                columns.append(column)
                usedColumns |= 1 << column
                usedRegions |= 1 << region
                place(row + 1)
                columns.removeLast()
                usedColumns &= ~(1 << column)
                usedRegions &= ~(1 << region)
            }
        }
        place(0)
        return found
    }

    private static func secondSolution(size: Int, regions: [Int], avoiding answer: [Int]) -> [Int]? {
        solutions(size: size, regions: regions, limit: 2).first { $0 != answer }
    }

    /// The kinds of step a person takes, easiest first.
    enum Reasoning: Int, Comparable, Sendable {
        /// A row, column or cushion with one free cell left gets its cat.
        case single = 1
        /// A cell whose cat would leave some row, column or cushion nowhere to go is
        /// ruled out.
        case lookahead
        /// When some cushions fit only in as many rows (or columns), nothing else goes
        /// in those rows.
        case groups

        static func < (a: Reasoning, b: Reasoning) -> Bool { a.rawValue < b.rawValue }
    }

    /// Whether a person can solve it step by step with those three kinds of step.
    func canBeReasoned() -> Bool { hardestStep() != nil }

    /// The hardest kind of step solving it takes, always trying the easiest first;
    /// nil when it cannot be solved without a guess.
    func hardestStep() -> Reasoning? {
        var hardest = Reasoning.single
        let cellCount = size * size
        var free = [Bool](repeating: true, count: cellCount)
        var cats: [Int] = []
        var lines: [[Int]] = []
        for row in 0..<size { lines.append((0..<size).map { row * size + $0 }) }
        for column in 0..<size { lines.append((0..<size).map { $0 * size + column }) }
        for region in 0..<size { lines.append((0..<cellCount).filter { regions[$0] == region }) }

        func blocked(by cell: Int) -> [Int] {
            let row = cell / size, column = cell % size
            return (0..<cellCount).filter {
                $0 / size == row || $0 % size == column || regions[$0] == regions[cell]
                    || (abs($0 / size - row) <= 1 && abs($0 % size - column) <= 1)
            }
        }
        func hasCat(_ line: [Int]) -> Bool { line.contains { cats.contains($0) } }

        while cats.count < size {
            // A line with one free cell left.
            var step = false
            for line in lines where !hasCat(line) {
                let open = line.filter { free[$0] }
                if open.isEmpty { return nil }
                if open.count == 1 {
                    cats.append(open[0])
                    for cell in blocked(by: open[0]) { free[cell] = false }
                    step = true
                    break
                }
            }
            if step { continue }

            // A cell that would leave some line empty.
            for cell in 0..<cellCount where free[cell] {
                let gone = Set(blocked(by: cell))
                let starves = lines.contains { line in
                    !line.contains(cell) && !hasCat(line) && !line.contains { free[$0] && !gone.contains($0) }
                }
                if starves {
                    free[cell] = false
                    step = true
                    hardest = max(hardest, .lookahead)
                    break
                }
            }
            if step { continue }

            // k cushions that fit in only k rows (or columns).
            let open = (0..<size).filter { region in !cats.contains { regions[$0] == region } }
            search: for mask in 1..<(1 << open.count) where mask.nonzeroBitCount < open.count {
                let group = Set((0..<open.count).filter { mask & (1 << $0) != 0 }.map { open[$0] })
                let cells = (0..<cellCount).filter { free[$0] && group.contains(regions[$0]) }
                for byRow in [true, false] {
                    let taken = Set(cells.map { byRow ? $0 / size : $0 % size })
                    guard taken.count == group.count else { continue }
                    let others = (0..<cellCount).filter {
                        free[$0] && !group.contains(regions[$0]) && taken.contains(byRow ? $0 / size : $0 % size)
                    }
                    if !others.isEmpty {
                        for cell in others { free[cell] = false }
                        step = true
                        hardest = .groups
                        break search
                    }
                }
            }
            if !step { return nil }
        }
        return hardest
    }

    // MARK: - Cells

    /// Up, down, left and right.
    static func neighbours(of cell: Int, size: Int) -> [Int] {
        let row = cell / size, column = cell % size
        var result: [Int] = []
        if row > 0 { result.append(cell - size) }
        if row < size - 1 { result.append(cell + size) }
        if column > 0 { result.append(cell - 1) }
        if column < size - 1 { result.append(cell + 1) }
        return result
    }

    static func isConnected(region: Int, regions: [Int], size: Int) -> Bool {
        let cells = regions.indices.filter { regions[$0] == region }
        guard let first = cells.first else { return false }
        var seen: Set<Int> = [first]
        var queue = [first]
        while let cell = queue.popLast() {
            for next in neighbours(of: cell, size: size) where regions[next] == region && !seen.contains(next) {
                seen.insert(next)
                queue.append(next)
            }
        }
        return seen.count == cells.count
    }
}

/// SplitMix64: small, fast, and the same numbers everywhere for the same seed.
nonisolated struct NapRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// 0 ..< `bound`.
    mutating func int(below bound: Int) -> Int {
        Int(next().multipliedFullWidth(by: UInt64(bound)).high)
    }

    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var items = items
        guard items.count > 1 else { return items }
        for i in stride(from: items.count - 1, to: 0, by: -1) {
            items.swapAt(i, int(below: i + 1))
        }
        return items
    }
}

/// How hard a puzzle is: a bigger board, and harder steps to solve it.
nonisolated enum CatNapLevel: Int, CaseIterable, Identifiable, Sendable {
    case easy, medium, hard

    var id: Int { rawValue }

    var size: Int {
        switch self {
        case .easy: 5
        case .medium: 7
        case .hard: 8
        }
    }

    /// Easy needs nothing but a line with one free cell left; medium never needs to
    /// weigh cushions against rows; hard always does, at least once.
    var steps: ClosedRange<CatNapPuzzle.Reasoning> {
        switch self {
        case .easy: .single ... .single
        case .medium: .single ... .lookahead
        case .hard: .groups ... .groups
        }
    }

    var title: String {
        switch self {
        case .easy: String(localized: "Easy", comment: "Cat Naps level")
        case .medium: String(localized: "Medium", comment: "Cat Naps level")
        case .hard: String(localized: "Hard", comment: "Cat Naps level")
        }
    }

    var next: CatNapLevel? { CatNapLevel(rawValue: rawValue + 1) }
}

/// Which puzzles are whose day. Puzzle 1 was 1 October 2026; three a day since, one
/// at each level, the same for everyone on the same date.
nonisolated enum CatNapDay {
    static let firstDay = DateComponents(year: 2026, month: 10, day: 1)
    /// The number an unlimited puzzle goes by: it belongs to no day.
    static let unlimited = 0

    /// The puzzle a calendar day has, counting the first as 1.
    static func number(for date: Date, calendar: Calendar = .current) -> Int {
        let first = calendar.date(from: firstDay) ?? date
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: first),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        return max(1, days + 1)
    }

    /// The day a puzzle belongs to.
    static func date(of number: Int, calendar: Calendar = .current) -> Date {
        let first = calendar.date(from: firstDay) ?? .now
        return calendar.date(byAdding: .day, value: number - 1, to: calendar.startOfDay(for: first)) ?? first
    }

    static func puzzle(_ number: Int, level: CatNapLevel) -> CatNapPuzzle {
        let day = UInt64(truncatingIfNeeded: number) &* 0x2545_F491_4F6C_DD1D
        let seed = day ^ 0xCA7_0000_5EED ^ (UInt64(level.rawValue + 1) &* 0x9E37_79B9_7F4A_7C15)
        return CatNapPuzzle.generate(size: level.size, seed: seed, steps: level.steps)
    }

    /// An unlimited puzzle: a new board for every seed.
    static func puzzle(seed: UInt64, level: CatNapLevel) -> CatNapPuzzle {
        CatNapPuzzle.generate(size: level.size, seed: seed, steps: level.steps)
    }
}

/// Who may play unlimited puzzles: Premium, and every debug build that has not been
/// told to act as a free account (`-mc.debug.premium 0`), so they can be played
/// without end while the app is being made.
enum CatNapAccess {
    static func unlimited(isPremium: Bool) -> Bool {
        #if DEBUG
        if DebugLaunch.forcedTier == nil { return true }
        #endif
        return isPremium
    }
}
