import Foundation
import Testing
@testable import MorningCompanion

@Suite("Cat Naps")
@MainActor
struct CatNapTests {
    private let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Tashkent")!
        return calendar
    }()

    private func defaults() -> UserDefaults {
        let name = "CatNapTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func day(_ y: Int, _ m: Int, _ d: Int, hour: Int = 7) -> Date {
        Self.calendar.date(from: DateComponents(year: y, month: m, day: d, hour: hour))!
    }

    // MARK: - Puzzles

    @Test("Every puzzle has one answer, and that answer is the one it was built on")
    func oneAnswer() {
        for number in 1...12 {
            for level in CatNapLevel.allCases {
                let puzzle = CatNapDay.puzzle(number, level: level)
                let answers = CatNapPuzzle.solutions(size: puzzle.size, regions: puzzle.regions, limit: 3)
                #expect(answers == [puzzle.solution], "puzzle \(number) \(level)")
            }
        }
    }

    @Test("Each level is as hard as it says: easy needs only the simplest step, hard the hardest")
    func levels() {
        #expect(CatNapLevel.allCases.map(\.size) == [5, 7, 8])
        for number in 1...12 {
            #expect(CatNapDay.puzzle(number, level: .easy).hardestStep() == .single)
            #expect(CatNapDay.puzzle(number, level: .medium).hardestStep()! <= .lookahead)
            #expect(CatNapDay.puzzle(number, level: .hard).hardestStep() == .groups)
        }
        #expect(CatNapLevel.easy.next == .medium && CatNapLevel.medium.next == .hard && CatNapLevel.hard.next == nil)
    }

    @Test("Every puzzle is a fair one: rows, columns and cushions as the rules say")
    func wellFormed() {
        for number in 1...12 {
            let puzzle = CatNapDay.puzzle(number, level: .hard)
            let n = puzzle.size
            #expect(Set(puzzle.solution).count == n)
            #expect(Set(puzzle.regions) == Set(0..<n))
            for row in 0..<n {
                #expect(puzzle.region(row: row, column: puzzle.solution[row]) == row, "each cushion holds its own cat")
                if row > 0 { #expect(abs(puzzle.solution[row] - puzzle.solution[row - 1]) > 1, "no two cats touch") }
            }
            for region in 0..<n {
                #expect(CatNapPuzzle.isConnected(region: region, regions: puzzle.regions, size: n))
            }
            #expect(puzzle.canBeReasoned(), "puzzle \(number) needs a guess")
        }
    }

    @Test("The same day makes the same puzzle on every phone, and every version")
    func sameEverywhere() {
        #expect(CatNapDay.puzzle(4, level: .medium) == CatNapDay.puzzle(4, level: .medium))
        #expect(CatNapDay.puzzle(4, level: .medium) != CatNapDay.puzzle(5, level: .medium), "a new board every day")
        // Pinned: if these change, everyone's puzzle 1 changed with them.
        #expect(CatNapDay.puzzle(1, level: .easy).solution == [4, 1, 3, 0, 2])
        #expect(Array(CatNapDay.puzzle(1, level: .easy).regions.prefix(10)) == [1, 1, 0, 0, 0, 1, 1, 1, 1, 0])
        #expect(CatNapDay.puzzle(1, level: .medium).solution == [3, 5, 1, 4, 2, 6, 0])
        #expect(CatNapDay.puzzle(1, level: .hard).solution == [1, 6, 4, 2, 0, 7, 5, 3])
        #expect(Array(CatNapDay.puzzle(1, level: .hard).regions.prefix(10)) == [0, 0, 0, 1, 1, 1, 1, 1, 0, 2])
    }

    @Test("Puzzle 1 is 1 October 2026, one number a day")
    func numbering() {
        #expect(CatNapDay.number(for: day(2026, 10, 1), calendar: Self.calendar) == 1)
        #expect(CatNapDay.number(for: day(2026, 10, 4, hour: 23), calendar: Self.calendar) == 4)
        #expect(CatNapDay.number(for: day(2026, 11, 1), calendar: Self.calendar) == 32)
        #expect(CatNapDay.number(for: day(2026, 9, 20), calendar: Self.calendar) == 1)
        #expect(Self.calendar.isDate(CatNapDay.date(of: 32, calendar: Self.calendar), inSameDayAs: day(2026, 11, 1)))
    }

    // MARK: - Playing

    private func game(_ number: Int = 1, level: CatNapLevel = .medium) -> CatNapGame {
        CatNapGame(number: number, level: level, puzzle: CatNapDay.puzzle(number, level: level))
    }

    private func cell(_ game: CatNapGame, _ row: Int, _ column: Int) -> Int { row * game.size + column }

    @Test("A tap rules a cell out, a second puts a cat on it, a third clears it")
    func tapCycle() {
        let game = game()
        #expect(game.tap(0, at: t0) == .mark)
        #expect(game.tap(0, at: t0) == .cat)
        #expect(game.tap(0, at: t0) == .empty)
        #expect(game.isUntouched)
    }

    @Test("Two cats in a row, or touching, wake each other up")
    func clashes() {
        let game = game()
        game.tap(cell(game, 0, 0), at: t0); game.tap(cell(game, 0, 0), at: t0)
        #expect(game.clashing.isEmpty)
        game.tap(cell(game, 0, 4), at: t0); game.tap(cell(game, 0, 4), at: t0)
        #expect(game.awake == [cell(game, 0, 0), cell(game, 0, 4)])
        #expect((0..<game.size).allSatisfy { game.clashing.contains(cell(game, 0, $0)) }, "the whole row is striped")
        game.undo(at: t0); game.undo(at: t0)
        // Corner to corner, in different rows, columns and cushions or not: touching is enough.
        game.tap(cell(game, 1, 1), at: t0); game.tap(cell(game, 1, 1), at: t0)
        #expect(game.awake.contains(cell(game, 1, 1)))
        #expect(game.awake.contains(cell(game, 0, 0)))
    }

    @Test("The last cat in the right place puts them all to sleep and stops the clock")
    func solving() {
        let game = game()
        game.resume(at: t0)
        for (row, column) in game.puzzle.solution.enumerated() {
            #expect(!game.solved)
            game.tap(cell(game, row, column), at: t0)
            game.tap(cell(game, row, column), at: t0.addingTimeInterval(Double(row)))
        }
        #expect(game.solved)
        #expect(game.awake.isEmpty)
        let time = game.elapsed(at: t0.addingTimeInterval(100))
        #expect(time == Double(game.size - 1), "the clock stopped at the last cat")
        #expect(game.tap(0, at: t0) == game.cells[0], "a solved board takes no more moves")
    }

    @Test("A stroke rules out a run of cells, leaves cats alone, and undoes in one go")
    func stroke() {
        let game = game()
        game.tap(2, at: t0); game.tap(2, at: t0)
        game.beginStroke()
        for index in 0..<4 { game.paint(index, .mark, at: t0) }
        #expect(game.cells[0] == .mark && game.cells[1] == .mark && game.cells[3] == .mark)
        #expect(game.cells[2] == .cat)
        game.undo(at: t0)
        #expect(game.cells[0] == .empty && game.cells[1] == .empty && game.cells[2] == .cat)
    }

    @Test("A hint wakes a misplaced cat first, then puts one where it belongs")
    func hints() {
        let game = game()
        let n = game.size
        let wrong = (0..<n).first { $0 != game.puzzle.solution[0] }!
        game.tap(wrong, at: t0); game.tap(wrong, at: t0)
        #expect(game.hint(at: t0) == wrong)
        #expect(game.cells[wrong] == .mark)
        let placed = game.hint(at: t0)
        #expect(placed == game.puzzle.solution[0])
        #expect(game.cells[game.puzzle.solution[0]] == .cat)
        #expect(game.hints == 2)
        for _ in 1..<n { game.hint(at: t0) }
        #expect(game.solved)
    }

    @Test("A half-done board comes back as it was left")
    func resumes() {
        let store = defaults()
        let game = game()
        game.resume(at: t0)
        game.tap(5, at: t0)
        game.pause(at: t0.addingTimeInterval(42))
        CatNapRecord.save(game.progress, in: store)
        let back = CatNapGame(number: 1, level: .medium, puzzle: CatNapDay.puzzle(1, level: .medium),
                              saved: CatNapRecord.progress(1, level: .medium, in: store))
        #expect(back.cells == game.cells)
        #expect(back.elapsed(at: t0) == 42)
        // Another level's board is not this one's.
        #expect(CatNapRecord.progress(1, level: .easy, in: store) == nil)
        let other = CatNapGame(number: 1, level: .easy, puzzle: CatNapDay.puzzle(1, level: .easy),
                               saved: CatNapRecord.progress(1, level: .medium, in: store))
        #expect(other.isUntouched)
        CatNapRecord.forget(1, level: .medium, in: store)
        #expect(CatNapRecord.progress(1, level: .medium, in: store) == nil)
    }

    // MARK: - Record

    @Test("The record keeps the quicker time; any level solved on the day counts for the streak")
    func record() {
        let store = defaults()
        #expect(!CatNapRecord.submit(number: 3, level: .hard, seconds: 90, hints: 1, onTheDay: true, in: store))
        #expect(CatNapRecord.submit(number: 3, level: .hard, seconds: 70, hints: 0, onTheDay: false, in: store))
        #expect(CatNapRecord.solve(3, level: .hard, in: store) == .init(seconds: 70, hints: 0, onTheDay: true))
        #expect(CatNapRecord.solve(3, level: .easy, in: store) == nil)
        CatNapRecord.submit(number: 4, level: .easy, seconds: 50, hints: 0, onTheDay: true, in: store)
        CatNapRecord.submit(number: 2, level: .medium, seconds: 50, hints: 0, onTheDay: false, in: store)
        #expect(Set(CatNapRecord.solves(3, in: store).keys) == [.hard])
        #expect(CatNapRecord.streak(today: 4, in: store) == 2)
        // Today's not done yet: yesterday's run still stands.
        #expect(CatNapRecord.streak(today: 5, in: store) == 2)
        #expect(CatNapRecord.streak(today: 6, in: store) == 0)
    }

    // MARK: - Unlimited

    @Test("Unlimited puzzles are a new board every time, and as fair as the day's")
    func unlimitedBoards() {
        let store = defaults()
        let first = CatNapRecord.newUnlimitedSeed(.medium, in: store)
        let second = CatNapRecord.newUnlimitedSeed(.medium, in: store)
        #expect(first != second)
        #expect(CatNapRecord.unlimitedSeed(.medium, in: store) == second, "the newest is the one under way")
        let a = CatNapDay.puzzle(seed: first, level: .medium), b = CatNapDay.puzzle(seed: second, level: .medium)
        #expect(a != b)
        for puzzle in [a, b] {
            #expect(CatNapPuzzle.solutions(size: puzzle.size, regions: puzzle.regions, limit: 2) == [puzzle.solution])
            #expect(puzzle.hardestStep()! <= .lookahead)
        }
        #expect(CatNapDay.puzzle(seed: first, level: .medium) == a, "a seed always makes the same board, so one can be resumed")
    }

    @Test("Solving an unlimited puzzle counts it, keeps the best time, and clears the way for the next")
    func unlimitedStats() {
        let store = defaults()
        _ = CatNapRecord.newUnlimitedSeed(.easy, in: store)
        #expect(CatNapRecord.submitUnlimited(level: .easy, seconds: 40, in: store))
        #expect(CatNapRecord.unlimitedSeed(.easy, in: store) == nil)
        #expect(!CatNapRecord.submitUnlimited(level: .easy, seconds: 55, in: store))
        #expect(CatNapRecord.submitUnlimited(level: .easy, seconds: 30, in: store))
        #expect(CatNapRecord.stats(.easy, in: store) == .init(solved: 3, bestSeconds: 30))
        #expect(CatNapRecord.stats(.hard, in: store) == .init())
        // Unlimited solves are not the day's: no streak from them.
        #expect(CatNapRecord.streak(today: 4, in: store) == 0)
    }

    @Test("A free account gets three tries, then none")
    func freeTries() {
        let store = defaults()
        #expect(CatNapRecord.freeTriesLeft(in: store) == 3)
        for _ in 0..<5 { CatNapRecord.useFreeTry(in: store) }
        #expect(CatNapRecord.freeTriesLeft(in: store) == 0)
    }

    @Test("Unlimited is Premium's, and open in a debug build that is not acting as free")
    func unlimitedAccess() {
        #expect(CatNapAccess.unlimited(isPremium: true))
        #if DEBUG
        #expect(CatNapAccess.unlimited(isPremium: false), "tests run with no forced tier")
        #endif
    }

    @Test("Someone new starts on easy; after that, the level last played")
    func lastLevel() {
        let store = defaults()
        #expect(CatNapRecord.lastLevel(in: store) == .easy)
        CatNapRecord.setLastLevel(.hard, in: store)
        #expect(CatNapRecord.lastLevel(in: store) == .hard)
    }
}
