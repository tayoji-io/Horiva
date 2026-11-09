import XCTest
@testable import ClockCore

final class ClockSettingsTests: XCTestCase {
    func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testSameInstantAcrossDatesAndOrder() {
        let settings = ClockSettings(zones: [ClockZone(id: "Asia/Shanghai", label: "上海"), ClockZone(id: "America/Los_Angeles", label: "LA")], format: "yyyy-MM-dd HH:mm")
        XCTAssertEqual(settings.title(at: date("2026-01-01T01:00:00Z")), "上海 2026-01-01 09:00 · LA 2025-12-31 17:00")
    }
    func testLabelVisibilityIsIndependentPerZone() {
        var settings = ClockSettings(zones: [
            ClockZone(id: "Asia/Shanghai", label: "上海"),
            ClockZone(id: "America/Los_Angeles", label: "LA", showLabel: false)
        ], format: "HH:mm")
        let instant = date("2026-01-01T01:00:00Z")
        XCTAssertEqual(settings.title(at: instant), "上海 09:00 · 17:00")
        settings.zones[0].showLabel = false
        XCTAssertEqual(settings.title(at: instant), "09:00 · 17:00")
        settings.zones[1].showLabel = true
        XCTAssertEqual(settings.title(at: instant), "09:00 · LA 17:00")
    }
    func testVisibilitySurvivesSaveAndNormalization() throws {
        let settings = ClockSettings(zones: [ClockZone(id: "Asia/Tokyo", label: "东京", showLabel: false)], format: "HH:mm")
        let restored = try JSONDecoder().decode(ClockSettings.self, from: JSONEncoder().encode(settings)).normalized()
        XCTAssertEqual(restored.title(at: date("2026-01-01T01:00:00Z")), "10:00")
        XCTAssertEqual(restored.zones[0].label, "东京")
    }
    func testOldSavedSettingsKeepNamesVisible() throws {
        let oldData = Data(#"{"zones":[{"id":"Asia/Tokyo","label":"原名称"}],"format":"HH:mm:ss"}"#.utf8)
        let restored = try JSONDecoder().decode(ClockSettings.self, from: oldData).normalized()
        XCTAssertEqual(restored.title(at: date("2026-01-01T01:00:00Z")), "原名称 10:00:00")
        XCTAssertEqual(restored.font, .system)
    }
    func testFontChoiceSurvivesSavingAndOtherSettingsChanges() throws {
        var settings = ClockSettings.defaults
        settings.font = .monospaced
        settings.zones[0].showLabel = false
        let restored = try JSONDecoder().decode(ClockSettings.self, from: JSONEncoder().encode(settings)).normalized()
        XCTAssertEqual(restored.font, .monospaced)
        XCTAssertFalse(restored.zones[0].showLabel)
        XCTAssertEqual(restored.title(at: date("2026-01-01T01:00:00Z")), "09:00 · 洛杉矶 17:00")
    }
    func testDSTCanBeFrozenAndResumed() throws {
        var settings = ClockSettings(zones: [ClockZone(id: "America/Los_Angeles", label: "LA")], format: "HH:mm")
        settings.setAutomaticallyAdjustDST(false, at: date("2026-01-01T00:00:00Z"))
        let summer = date("2026-07-01T12:00:00Z")
        XCTAssertEqual(settings.title(at: summer), "LA 04:00")
        let restored = try JSONDecoder().decode(ClockSettings.self, from: JSONEncoder().encode(settings)).normalized(at: summer)
        XCTAssertEqual(restored.title(at: summer), "LA 04:00")
        settings.setAutomaticallyAdjustDST(true, at: summer)
        XCTAssertEqual(settings.title(at: summer), "LA 05:00")
    }
    func testNewZoneWhileDSTFrozenAndComparison() {
        var settings = ClockSettings.defaults
        let summer = date("2026-07-01T01:00:00Z")
        settings.setAutomaticallyAdjustDST(false, at: summer)
        settings.zones.append(ClockZone(id: "Asia/Kolkata", label: "India"))
        settings = settings.normalized(at: summer)
        XCTAssertEqual(settings.fixedOffsets["Asia/Kolkata"], 19800)
        let comparison = settings.comparison(for: settings.zones[1], at: summer)
        XCTAssertEqual(comparison.offsetSeconds, -54000)
        XCTAssertEqual(comparison.dayDifference, -1)
    }
    func testLanguageSeparatorAndCalendarPersist() throws {
        var settings = ClockSettings(zones: [ClockZone(id: "UTC", label: "UTC"), ClockZone(id: "Asia/Tokyo", label: "Tokyo")], format: "EEE h:mm a")
        settings.language = .english
        settings.separator = .pipe
        settings.showCalendar = false
        let instant = date("2026-01-01T01:00:00Z")
        XCTAssertEqual(settings.title(at: instant), "UTC Thu 1:00 AM | Tokyo Thu 10:00 AM")
        settings.language = .simplifiedChinese
        XCTAssertTrue(settings.title(at: instant).contains("周四"))
        XCTAssertFalse(settings.title(at: instant).contains("Thu"))
        let restored = try JSONDecoder().decode(ClockSettings.self, from: JSONEncoder().encode(settings)).normalized()
        XCTAssertEqual(restored, settings)
        let old = try JSONDecoder().decode(ClockSettings.self, from: Data(#"{"zones":[{"id":"UTC","label":"UTC"}],"format":"HH:mm"}"#.utf8))
        XCTAssertTrue(old.automaticallyAdjustDST)
        XCTAssertTrue(old.showCalendar)
        XCTAssertEqual(old.separator, .dot)
    }
    func testRefreshCadenceHonorsQuotedFormatFields() {
        var settings = ClockSettings.defaults
        for pattern in ["HH:mm", "yyyy-MM-dd EEE", "HH:mm 'seconds ss'", "HH:mm 'it''s time'"] {
            settings.format = pattern
            XCTAssertEqual(settings.refreshInterval, 60, pattern)
        }
        for pattern in ["HH:mm:ss", "HH:mm:ss.SSS", "A", "'it''s' ss"] {
            settings.format = pattern
            XCTAssertEqual(settings.refreshInterval, 1, pattern)
        }
        settings.format = "HH:mm"
        XCTAssertEqual(settings.nextRefresh(after: date("2026-01-01T01:02:37Z")), date("2026-01-01T01:03:00Z"))
    }
    func testCachedRendererInvalidatesAfterPreferencesChange() {
        var settings = ClockSettings(zones: [ClockZone(id: "America/Los_Angeles", label: "LA")], format: "HH:mm")
        let renderer = ClockRenderer(settings: settings)
        let summer = date("2026-07-01T12:00:00Z")
        XCTAssertEqual(renderer.title(at: summer), "LA 05:00")
        XCTAssertEqual(renderer.string(for: settings.zones[0], at: summer, format: "HH:mm:ss"), "05:00:00")
        settings.setAutomaticallyAdjustDST(false, at: date("2026-01-01T00:00:00Z"))
        renderer.update(settings)
        XCTAssertEqual(renderer.title(at: summer), "LA 04:00")
        XCTAssertEqual(renderer.string(for: settings.zones[0], at: summer, format: "HH:mm:ss"), "04:00:00")
        settings.format = "EEE HH:mm"
        settings.language = .english
        renderer.update(settings)
        XCTAssertEqual(renderer.title(at: summer), "LA Wed 04:00")
    }
    func testDaylightSavingTransition() {
        let settings = ClockSettings(zones: [ClockZone(id: "America/Los_Angeles", label: "LA")], format: "HH:mm")
        XCTAssertEqual(settings.title(at: date("2026-03-08T09:59:00Z")), "LA 01:59")
        XCTAssertEqual(settings.title(at: date("2026-03-08T10:00:00Z")), "LA 03:00")
    }
    func testTwelveHourAndCustomFormat() {
        var settings = ClockSettings(zones: [ClockZone(id: "Asia/Shanghai", label: "上海")], format: "h:mm a")
        settings.language = .english
        XCTAssertEqual(settings.title(at: date("2026-01-01T17:04:05Z")), "上海 1:04 AM")
        settings.format = "MM/dd HH:mm:ss"
        XCTAssertEqual(settings.title(at: date("2026-01-01T17:04:05Z")), "上海 01/02 01:04:05")
    }
    func testNormalizeInvalidDuplicateAndEmptySettings() {
        let settings = ClockSettings(zones: [ClockZone(id: "invalid/zone", label: "bad"), ClockZone(id: "UTC", label: "  "), ClockZone(id: "UTC", label: "duplicate")], format: " ").normalized()
        XCTAssertEqual(settings.zones.count, 1)
        XCTAssertEqual(settings.zones[0].label, "UTC")
        XCTAssertEqual(settings.format, "HH:mm")
        XCTAssertFalse(ClockSettings(zones: [], format: "HH:mm").normalized().zones.isEmpty)
    }
    func testPersistenceAndBoundedUserInput() throws {
        let original = ClockSettings(zones: [ClockZone(id: "Asia/Tokyo", label: "东京")], format: "HH:mm:ss")
        let restored = try JSONDecoder().decode(ClockSettings.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored, original)
        let bounded = ClockSettings(zones: [ClockZone(id: "UTC", label: String(repeating: "长", count: 80))], format: String(repeating: "H", count: 200)).normalized()
        XCTAssertEqual(bounded.zones[0].label.count, 24)
        XCTAssertEqual(bounded.format.count, 100)
    }
}
