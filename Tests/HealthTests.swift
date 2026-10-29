import XCTest

final class StallWatchdogTests: XCTestCase {
    func testAQuietCameraIsRestartedOnlyOnceItPassesTheLimit() {
        var watchdog = StallWatchdog()
        XCTAssertFalse(watchdog.shouldRestart(now: 10, lastFrame: 9.5, sessionRunning: true), "half a second of quiet is normal")
        XCTAssertFalse(watchdog.shouldRestart(now: 10, lastFrame: 8.1, sessionRunning: true), "1.9 s is still under the limit")
        XCTAssertTrue(watchdog.shouldRestart(now: 10, lastFrame: 7.9, sessionRunning: true), "over two seconds without a frame is a stall")
    }

    func testAHealthyCameraIsLeftAlone() {
        var watchdog = StallWatchdog()
        for second in stride(from: 0.0, to: 60, by: 1) {
            XCTAssertFalse(watchdog.shouldRestart(now: second, lastFrame: second - 0.03, sessionRunning: true))
        }
    }

    func testASessionThatStoppedIsRestartedAtOnceEvenWithRecentFrames() {
        var watchdog = StallWatchdog()
        XCTAssertTrue(watchdog.shouldRestart(now: 5, lastFrame: 4.99, sessionRunning: false))
    }

    func testRestartsAreSpacedOutSoAGoneCameraIsNotHammered() {
        var watchdog = StallWatchdog()
        XCTAssertTrue(watchdog.shouldRestart(now: 10, lastFrame: 0, sessionRunning: true))
        XCTAssertFalse(watchdog.shouldRestart(now: 11, lastFrame: 0, sessionRunning: true))
        XCTAssertFalse(watchdog.shouldRestart(now: 13.9, lastFrame: 0, sessionRunning: true))
        XCTAssertTrue(watchdog.shouldRestart(now: 14.1, lastFrame: 0, sessionRunning: true), "and tries again if it is still quiet")
    }

    func testOnceFramesReturnNothingMoreHappens() {
        var watchdog = StallWatchdog()
        XCTAssertTrue(watchdog.shouldRestart(now: 10, lastFrame: 0, sessionRunning: true))
        XCTAssertFalse(watchdog.shouldRestart(now: 15, lastFrame: 14.97, sessionRunning: true))
    }
}

final class DropStreakTests: XCTestCase {
    func testNothingIsStalledBeforeAnyFrameIsDropped() {
        XCTAssertFalse(DropStreak().isStalled(at: 100))
    }

    func testAQueueThatStaysFullIsStalledAfterTheLimit() {
        var streak = DropStreak()
        streak.recordFull(at: 10)
        XCTAssertFalse(streak.isStalled(at: 11), "a second of dropped frames can be a busy moment")
        streak.recordFull(at: 11)
        XCTAssertTrue(streak.isStalled(at: 11.6), "1.5 s of a full queue means the extension isn't draining it")
    }

    func testAcceptedFrameClearsIt() {
        var streak = DropStreak()
        streak.recordFull(at: 10)
        streak.recordAccepted()
        XCTAssertFalse(streak.isStalled(at: 20))
    }

    func testABriefJamIsNotAStall() {
        var streak = DropStreak()
        streak.recordFull(at: 10)
        streak.recordFull(at: 10.2)
        streak.recordAccepted()
        streak.recordFull(at: 10.5)
        XCTAssertFalse(streak.isStalled(at: 11.8), "the jam restarted at 10.5, so only 1.3 s so far")
        XCTAssertTrue(streak.isStalled(at: 12.1))
    }
}
