@testable import Filer
import Foundation
import Testing

struct MediaRemoteTransferPolicyTests {
    @Test func resumeBackoffGrowsExponentiallyThenCaps() {
        let policy = MediaRemoteTransferPolicy.default // base 1, ×2, cap 8

        #expect(policy.resumeBackoff(1) == 1)
        #expect(policy.resumeBackoff(2) == 2)
        #expect(policy.resumeBackoff(3) == 4)
        #expect(policy.resumeBackoff(4) == 8)
        #expect(policy.resumeBackoff(5) == 8) // capped
        #expect(policy.resumeBackoff(0) == 1) // guarded lower bound
    }

    @Test func defaultProvidesTimeoutKnobs() {
        let policy = MediaRemoteTransferPolicy.default

        #expect(policy.connectivityWaitTimeout == 20)
        #expect(policy.requestTimeout == 15)
    }
}
