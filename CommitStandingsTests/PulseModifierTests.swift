import Testing
import Foundation
@testable import CommitStandings

/// The "refreshing" pulse is driven by elapsed time and stops outright when it shouldn't run, so
/// an idle menu bar app does no per-frame work.
struct PulsePhaseTests {

    @Test func startsFullyOpaqueAndDimsHalfwayThroughAPeriod() {
        #expect(PulsePhase.opacity(elapsed: 0) == 1.0)
        #expect(abs(PulsePhase.opacity(elapsed: PulsePhase.period / 2) - 0.4) < 0.0001)
        #expect(abs(PulsePhase.opacity(elapsed: PulsePhase.period) - 1.0) < 0.0001)
    }

    @Test func staysBetweenDimmedAndOpaqueAcrossAPeriod() {
        for step in 0...200 {
            let opacity = PulsePhase.opacity(elapsed: PulsePhase.period * Double(step) / 100)
            #expect(opacity >= 0.4 - 0.0001 && opacity <= 1.0 + 0.0001)
        }
    }

    @Test func isContinuousAcrossThePeriodBoundary() {
        let before = PulsePhase.opacity(elapsed: PulsePhase.period - 0.001)
        let after = PulsePhase.opacity(elapsed: PulsePhase.period + 0.001)
        #expect(abs(before - after) < 0.01)
    }

    @Test func pulsesOnlyWhenActiveVisibleAndMotionAllowed() {
        #expect(PulsePhase.shouldPulse(active: true, reduceMotion: false, hostVisible: true))
        #expect(!PulsePhase.shouldPulse(active: false, reduceMotion: false, hostVisible: true))
        #expect(!PulsePhase.shouldPulse(active: true, reduceMotion: true, hostVisible: true))
        #expect(!PulsePhase.shouldPulse(active: true, reduceMotion: false, hostVisible: false))
    }
}
