import Foundation
import Testing
@testable import MorningCompanion

@Suite("App icons")
struct AppIconChoiceTests {
    @Test("Classic is free and is the primary icon; every other choice is Premium")
    func premium() {
        #expect(AppIconChoice.classic.alternateIconName == nil)
        #expect(!AppIconChoice.classic.isPremium)
        for choice in AppIconChoice.allCases where choice != .classic {
            #expect(choice.isPremium)
            #expect(choice.alternateIconName != nil)
        }
    }

    @Test("A name the system reports maps back to its choice; an unknown one reads as Classic")
    func roundTrip() {
        for choice in AppIconChoice.allCases {
            #expect(AppIconChoice(alternateIconName: choice.alternateIconName) == choice)
        }
        #expect(AppIconChoice(alternateIconName: "AppIcon-Gone") == .classic)
    }

    @Test("Every alternate icon is built into the app")
    func bundled() throws {
        let icons = Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any]
        let alternates = try #require(icons?["CFBundleAlternateIcons"] as? [String: Any])
        for name in AppIconChoice.allCases.compactMap(\.alternateIconName) {
            #expect(alternates[name] != nil, "\(name) is missing from the app's alternate icons")
        }
    }
}
