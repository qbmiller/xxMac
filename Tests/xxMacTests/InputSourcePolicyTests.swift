import XCTest
@testable import xxMac

final class InputSourcePolicyTests: XCTestCase {
    func testDomainBoundaryAndNormalization() {
        var rule = InputSourceWebsiteRule(pattern: " Example.COM. ", match: .domainAndSubdomains, sourceID: "en")
        XCTAssertTrue(rule.matches(URL(string: "https://example.com/a")!))
        XCTAssertTrue(rule.matches(URL(string: "https://docs.example.com")!))
        XCTAssertFalse(rule.matches(URL(string: "https://notexample.com")!))
        rule.match = .domain
        XCTAssertFalse(rule.matches(URL(string: "https://docs.example.com")!))
        rule.pattern = ""
        XCTAssertFalse(rule.matches(URL(string: "https://example.com")!))
    }

    func testPrefixRespectsOriginAndPathBoundary() {
        let rule = InputSourceWebsiteRule(pattern: "https://example.com/docs", match: .urlPrefix, sourceID: "en")
        XCTAssertTrue(rule.matches(URL(string: "https://example.com/docs/a")!))
        XCTAssertFalse(rule.matches(URL(string: "https://example.com/docs-evil")!))
        XCTAssertFalse(rule.matches(URL(string: "https://example.com.evil/docs")!))
        XCTAssertFalse(rule.matches(URL(string: "http://example.com/docs")!))
    }

    func testAddressWebsiteAppAndDefaultPriority() {
        var settings = InputSourceSettings()
        settings.enabled = true
        settings.defaultSourceID = "fallback"
        settings.addressBarSourceID = "address"
        settings.appRules = [.init(bundleID: "com.google.Chrome", name: "Chrome", policy: .fixed, sourceID: "app")]
        settings.websiteRules = [.init(pattern: "example.com", sourceID: "site")]
        var context = InputSourceContext(bundleID: "com.google.Chrome", url: URL(string: "https://example.com"))
        XCTAssertEqual(InputSourcePolicy.resolve(settings: settings, context: context, memory: [:]).sourceID, "site")
        context.addressBarFocused = true
        XCTAssertEqual(InputSourcePolicy.resolve(settings: settings, context: context, memory: [:]).sourceID, "address")
        context.addressBarFocused = false
        context.url = nil
        XCTAssertEqual(InputSourcePolicy.resolve(settings: settings, context: context, memory: [:]).sourceID, "app")
        context.bundleID = "other"
        XCTAssertEqual(InputSourcePolicy.resolve(settings: settings, context: context, memory: [:]).sourceID, "fallback")
    }

    func testKeepCurrentStopsFallbackAndDisabledRulesAreSkipped() {
        var settings = InputSourceSettings()
        settings.enabled = true
        settings.defaultSourceID = "en"
        settings.appRules = [.init(bundleID: "app", name: "App", policy: .keepCurrent)]
        let context = InputSourceContext(bundleID: "app")
        XCTAssertNil(InputSourcePolicy.resolve(settings: settings, context: context, memory: [:]).sourceID)
        settings.appRules[0].enabled = false
        XCTAssertEqual(InputSourcePolicy.resolve(settings: settings, context: context, memory: [:]).sourceID, "en")
        settings.enabled = false
        XCTAssertNil(InputSourcePolicy.resolve(settings: settings, context: context, memory: [:]).sourceID)
    }

    func testMemoryAndOrderedBrowserScopedRules() {
        var settings = InputSourceSettings()
        settings.enabled = true
        settings.appRules = [.init(bundleID: "com.google.Chrome", name: "Chrome", policy: .remember)]
        var context = InputSourceContext(bundleID: "com.google.Chrome", url: URL(string: "https://example.com"))
        XCTAssertEqual(InputSourcePolicy.resolve(settings: settings, context: context, memory: [context.bundleID: "remembered"]).sourceID, "remembered")
        settings.websiteRules = [
            .init(pattern: "example.com", sourceID: "safari", browserID: "com.apple.Safari"),
            .init(pattern: "example.com", sourceID: "first"),
            .init(pattern: "example.com", sourceID: "second")
        ]
        XCTAssertEqual(InputSourcePolicy.resolve(settings: settings, context: context, memory: [:]).sourceID, "first")
        context.bundleID = "com.apple.Safari"
        XCTAssertEqual(InputSourcePolicy.resolve(settings: settings, context: context, memory: [:]).sourceID, "safari")
    }

    func testAutomaticChangesAreNotRememberedAndManualChoicesAre() {
        var state = InputSourceSelectionState()
        state.beginAutomaticSelection(target: "en", now: 10)
        XCTAssertFalse(state.shouldRemember(sourceID: "en", now: 10.1))
        XCTAssertTrue(state.shouldRemember(sourceID: "zh", now: 10.2))
        // Once confirmed, a deliberate return to the source is a new manual choice.
        state.beginAutomaticSelection(target: "ja", now: 10.3)
        XCTAssertTrue(state.shouldRemember(sourceID: "en", now: 10.4))
        XCTAssertFalse(state.shouldRemember(sourceID: "ja", now: 10.5))
        XCTAssertTrue(state.shouldRemember(sourceID: "en", now: 15))
    }

    func testBrowserFocusEventInvalidatesInFlightQueryAndNextReadIsAccepted() {
        var state = InputSourceBrowserRequestState()
        let first = state.begin(invalidateCurrent: false)!
        XCTAssertNil(state.begin(invalidateCurrent: true))
        XCTAssertNil(state.begin(invalidateCurrent: true))
        XCTAssertFalse(state.finish(first))
        let latest = state.begin(invalidateCurrent: false)!
        XCTAssertTrue(state.finish(latest))
    }

    func testAppIndicatorWaitsForRuleResolutionAndActualInputSource() {
        var request = InputSourceAppIndicatorRequest()
        request.request()
        XCTAssertFalse(request.takeIfReady(currentSourceID: "en"))
        request.resolve(target: "zh")
        XCTAssertFalse(request.takeIfReady(currentSourceID: "en"))
        XCTAssertTrue(request.takeIfReady(currentSourceID: "zh"))
        XCTAssertFalse(request.takeIfReady(currentSourceID: "zh"))
    }

    func testDefaultSettingsArePassiveAndRoundTripIncludesModes() throws {
        let settings = InputSourceSettings()
        XCTAssertFalse(settings.enabled)
        XCTAssertTrue(settings.defaultSourceID.isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(InputSourceSettings.self, from: JSONEncoder().encode(settings)), settings)
        XCTAssertNotEqual(InputSourceDescriptor(sourceID: "ime", modeID: "a", name: "A").id,
                          InputSourceDescriptor(sourceID: "ime", modeID: "b", name: "B").id)
    }
}
