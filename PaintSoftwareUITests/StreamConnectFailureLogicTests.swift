import XCTest
import Network

/// TODO.md item (101): **why the iPad could not connect, classified from the `NWError` values the
/// transport actually produces** — no socket, no `NWConnection`, just
/// `StreamConnectFailure.classify(_:)` driven directly against every case `ScreenStreamClient`
/// reaches it from (`.failed`/`.waiting`'s `NWError`, and `receive`'s completion error).
///
/// **The one case this file cannot drive is the one the owner asked for by name** —
/// `.localNetworkPermissionDenied` surfaces on-device as `NWError.dns(-65570)`
/// (`kDNSServiceErr_PolicyDenied`), a documented but unconfirmed-in-this-suite mapping: nothing
/// in the simulator or this repo can manufacture a real policy-denied connection to prove the
/// *transport* actually reports that code for a plain IP connect with no Bonjour involved (STREAM.md
/// itself already carries an "unconfirmed, verify on device" note for the Nearby browser for the
/// same reason). What *is* pinned here is `classify`'s own contract — `dns(-65570)` maps to the
/// permission case and every other `dns` code does not — so a future correction to the real code
/// only has to change one line and this test still says what it is testing.
final class StreamConnectFailureLogicTests: XCTestCase {

    // MARK: - refused

    func testConnectionRefusedIsRefused() {
        XCTAssertEqual(StreamConnectFailure.classify(.posix(.ECONNREFUSED)), .refused)
    }

    // MARK: - unreachable

    func testTimedOutIsUnreachable() {
        XCTAssertEqual(StreamConnectFailure.classify(.posix(.ETIMEDOUT)), .unreachable)
    }

    func testHostUnreachableIsUnreachable() {
        XCTAssertEqual(StreamConnectFailure.classify(.posix(.EHOSTUNREACH)), .unreachable)
    }

    func testNetworkUnreachableIsUnreachable() {
        XCTAssertEqual(StreamConnectFailure.classify(.posix(.ENETUNREACH)), .unreachable)
    }

    // MARK: - localNetworkPermissionDenied

    func testDnsPolicyDeniedIsLocalNetworkPermissionDenied() {
        XCTAssertEqual(StreamConnectFailure.classify(.dns(-65570)), .localNetworkPermissionDenied)
    }

    func testADifferentDnsCodeIsNotThePermissionCase() {
        let result = StreamConnectFailure.classify(.dns(-65563))
        XCTAssertNotEqual(result, .localNetworkPermissionDenied)
        XCTAssertEqual(result, .other("That name could not be looked up. Check the address."))
    }

    // MARK: - other, for everything this client already names itself

    func testConnectionResetIsOther() {
        XCTAssertEqual(StreamConnectFailure.classify(.posix(.ECONNRESET)), .other("The connection was dropped."))
    }

    func testBrokenPipeIsOther() {
        XCTAssertEqual(StreamConnectFailure.classify(.posix(.EPIPE)), .other("The connection was dropped."))
    }

    func testAnUnrecognisedPosixCodeIsOtherAndNamesTheCode() {
        let result = StreamConnectFailure.classify(.posix(.EACCES))
        guard case .other(let sentence) = result else {
            return XCTFail("expected .other, got \(result)")
        }
        // `POSIXErrorCode`'s default description has no case name, only its raw value (13 for
        // EACCES) — still enough to look up, which is the bar this catch-all clears.
        XCTAssertTrue(sentence.contains("13"), "an unrecognised code should still be visible: \(sentence)")
    }

    func testTlsIsOther() {
        XCTAssertEqual(StreamConnectFailure.classify(.tls(-9805)), .other("Could not connect."))
    }

    // MARK: - sentence(host:) — what the sheet and the bar both render

    func testRefusedNamesTheStreamerAndTheTypedHost() {
        let sentence = StreamConnectFailure.refused.sentence(host: "desktop-cbr0fl6")
        XCTAssertTrue(sentence.contains("desktop-cbr0fl6"), "the sentence should name the address the artist typed")
        XCTAssertTrue(sentence.contains("PaintStreamer"), "refused should say what to do about it")
    }

    func testUnreachableNamesTheHostAndDoesNotBlameTheStreamer() {
        let sentence = StreamConnectFailure.unreachable.sentence(host: "100.104.85.111")
        XCTAssertTrue(sentence.contains("100.104.85.111"))
        XCTAssertFalse(sentence.contains("PaintStreamer"), "unreachable is about the computer, not the app on it")
    }

    func testLocalNetworkPermissionDeniedNamesSettings() {
        let sentence = StreamConnectFailure.localNetworkPermissionDenied.sentence(host: "desktop-cbr0fl6")
        XCTAssertTrue(sentence.contains("Local Network"))
        XCTAssertTrue(sentence.contains("Settings"))
    }

    func testOtherRendersItsOwnSentenceVerbatimRegardlessOfHost() {
        let failure = StreamConnectFailure.other("The computer sent something this app could not read.")
        XCTAssertEqual(failure.sentence(host: "irrelevant"),
                       "The computer sent something this app could not read.")
    }

    // MARK: - the Settings button

    func testOnlyThePermissionCaseOffersTheSettingsButton() {
        XCTAssertTrue(StreamConnectFailure.localNetworkPermissionDenied.offersLocalNetworkSettingsButton)
        XCTAssertFalse(StreamConnectFailure.refused.offersLocalNetworkSettingsButton)
        XCTAssertFalse(StreamConnectFailure.unreachable.offersLocalNetworkSettingsButton)
        XCTAssertFalse(StreamConnectFailure.other("anything").offersLocalNetworkSettingsButton)
    }

    // MARK: - ScreenStreamCoordinator.ConnectFailure — the sheet's own answer

    func testConnectFailureRendersTheSameSentenceAndButtonAsItsReason() {
        let failure = ScreenStreamCoordinator.ConnectFailure(reason: .localNetworkPermissionDenied,
                                                              host: "desktop-cbr0fl6")
        XCTAssertEqual(failure.sentence, StreamConnectFailure.localNetworkPermissionDenied.sentence(host: "desktop-cbr0fl6"))
        XCTAssertTrue(failure.offersLocalNetworkSettingsButton)
    }
}
