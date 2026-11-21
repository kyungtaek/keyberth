import XCTest
@testable import MicroCore

final class T3NavigationTests: XCTestCase {
    func testSameThreadAcrossEnvironments() throws {
        let first = try XCTUnwrap(T3Navigation.url(installedVersion: "0.1.7",
                                                    target: Key(environment: "one", thread: "same")))
        let second = try XCTUnwrap(T3Navigation.url(installedVersion: "0.1.7",
                                                     target: Key(environment: "two", thread: "same")))
        XCTAssertEqual(first.absoluteString, "t3code://threads/one/same")
        XCTAssertEqual(second.absoluteString, "t3code://threads/two/same")
        XCTAssertNotEqual(first, second)
    }
    func testVisibleThreadIncludesEnvironmentAndIgnoresQuery() throws {
        let route=try XCTUnwrap(URL(string:"t3code://app/#/env/thread?panel=right"))
        XCTAssertTrue(T3Navigation.matchesVisibleRoute(route,threadURL:URL(string:"t3code://threads/env/thread")!))
        XCTAssertFalse(T3Navigation.matchesVisibleRoute(route,threadURL:URL(string:"t3code://threads/another/thread")!))
    }
    func testRejectsVersionAndUntrustedComponents() {
        let key = Key(environment: "test", thread: "demo")
        for version in ["0.1.6", "0.1.8", "v0.1.7", "0.1.7-beta", ""] {
            XCTAssertNil(T3Navigation.url(installedVersion: version, target: key))
        }
        for value in ["", ".", "..", "../one", "https://example.invalid", "one%2Ftwo", "a?b", "a#b",
                      "host@other", "a\\b", "한글", "a\n", String(repeating: "a", count: 129)] {
            XCTAssertNil(T3Navigation.url(installedVersion: "0.1.7", target: Key(environment: value, thread: "x")))
            XCTAssertNil(T3Navigation.url(installedVersion: "0.1.7", target: Key(environment: "x", thread: value)))
        }
    }
}

extension T3NavigationTests {
    func testRefreshRejectsAQueuedPressInsteadOfNavigatingToNewOccupant() throws {
        let a = Key(environment: "env-a", thread: "same-name")
        let b = Key(environment: "env-b", thread: "same-name")
        var slots = Slots()
        let before = slots.update([a, b], now: 10)
        let initial = try XCTUnwrap(slots.resolve(0, generation: before, now: 11))
        XCTAssertEqual(T3Navigation.url(installedVersion: "0.1.7", target: initial)?.absoluteString,
                       "t3code://threads/env-a/same-name")

        let refreshed = slots.update([b, a], now: 12)
        XCTAssertNil(slots.resolve(0, generation: before, now: 12))
        let current = try XCTUnwrap(slots.resolve(1, generation: refreshed, now: 12))
        XCTAssertEqual(T3Navigation.url(installedVersion: "0.1.7", target: current)?.absoluteString,
                       "t3code://threads/env-a/same-name")
        slots.disconnect()
        XCTAssertNil(slots.resolve(1, generation: refreshed, now: 12))
    }
}
