import Testing
import Foundation
@testable import MorningCompanion

@Suite("MissionKind")
struct MissionTypeTests {

    @Test("All 9 mission kinds exist")
    func allCasesCount() {
        #expect(MissionKind.allCases.count == 9)
    }

    @Test("Each kind has a non-empty system image")
    func systemImages() {
        for kind in MissionKind.allCases {
            #expect(!kind.systemImage.isEmpty)
        }
    }

    @Test("Each kind has a non-empty display name")
    func displayNames() {
        for kind in MissionKind.allCases {
            #expect(!kind.displayName.isEmpty)
        }
    }

    @Test("QR Code and Draw require setup; others do not")
    func requiresSetup() {
        #expect(MissionKind.qrCode.requiresSetup == true)
        #expect(MissionKind.draw.requiresSetup == true)
        #expect(MissionKind.math.requiresSetup == false)
        #expect(MissionKind.shake.requiresSetup == false)
        #expect(MissionKind.steps.requiresSetup == false)
        #expect(MissionKind.memory.requiresSetup == false)
        #expect(MissionKind.typing.requiresSetup == false)
        #expect(MissionKind.jump.requiresSetup == false)
    }

    @Test("MissionConfig round-trips through Codable")
    func codableRoundTrip() throws {
        let configs: [MissionConfig] = [
            .defaultMath, .defaultShake, .defaultSteps, .defaultQR,
            .defaultMemory, .defaultTyping, .defaultDraw, .defaultJump,
        ]
        for config in configs {
            let data = try JSONEncoder().encode(config)
            let decoded = try JSONDecoder().decode(MissionConfig.self, from: data)
            #expect(decoded == config)
        }
    }
}
