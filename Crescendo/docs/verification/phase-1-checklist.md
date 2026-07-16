# Crescendo Phase 1 Verification

## Automated

Evidence date: 2026-07-16

Simulator: iPhone 13, iOS 26.2 (`765DD318-02F6-465C-ACFB-DCF2932B4589`)

- [x] Provider selection and identity-safe latest-wins switching pass.
- [x] Search access, cancellation, eligibility, failure, and stale responses pass.
- [x] Music transport and observation pass.
- [x] Video URL validation, replacement preservation, observation, pause, seek, and clear pass.
- [x] Music start pauses Video before provider Play.
- [x] Video opens only after music pause.
- [x] Overlapping transition and provider-switch requests are ignored.
- [x] Phase 1 boundary script passes.
- [x] Strict recursive Swift format lint passes.
- [x] The generic iOS build passes with signing disabled after the exact signed command reports only the missing development team.

Commands and results:

```sh
Crescendo/scripts/verify-phase1-boundaries.sh
# Phase 1 boundaries: PASS

xcodebuild test -project Crescendo/Crescendo.xcodeproj -scheme Crescendo \
  -destination 'platform=iOS Simulator,id=765DD318-02F6-465C-ACFB-DCF2932B4589'
# TEST SUCCEEDED: 97 tests in 19 suites

xcrun swift-format lint --recursive --strict \
  --configuration Crescendo/.swift-format \
  Crescendo/Crescendo Crescendo/CrescendoTests
# Exit 0 with no diagnostics

xcodebuild build -project Crescendo/Crescendo.xcodeproj -scheme Crescendo \
  -destination 'generic/platform=iOS'
# BUILD FAILED only because Crescendo requires a development team

xcodebuild build -project Crescendo/Crescendo.xcodeproj -scheme Crescendo \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
# BUILD SUCCEEDED
```

## Simulator

- [ ] A public HTTPS HLS URL prepares and plays manually. Date: pending manual verification; Device/OS: pending manual verification; URL: pending manual verification; Result: pending manual verification.
- [ ] A public HTTPS file URL prepares and plays manually. Date: pending manual verification; Device/OS: pending manual verification; URL: pending manual verification; Result: pending manual verification.
- [ ] Invalid, non-HTTPS, and unplayable URLs show localized recovery. Date: pending manual verification; Device/OS: pending manual verification; URLs: pending manual verification; Result: pending manual verification.
- [ ] Failed replacement preserves the old item. Date: pending manual verification; Device/OS: pending manual verification; URLs: pending manual verification; Result: pending manual verification.
- [ ] Loading never autoplays. Date: pending manual verification; Device/OS: pending manual verification; URL: pending manual verification; Result: pending manual verification.

## Physical device

- [ ] MusicKit authorization, denial, eligibility, search, and playback pass. Date: pending manual verification; Device/OS: pending manual verification; URL: not applicable; Result: pending manual verification.
- [ ] Video remains available after denied or ineligible MusicKit access. Date: pending manual verification; Device/OS: pending manual verification; URL: pending manual verification; Result: pending manual verification.
- [ ] Opening Video pauses music. Date: pending manual verification; Device/OS: pending manual verification; URL: pending manual verification; Result: pending manual verification.
- [ ] Closing Video pauses and clears the item. Date: pending manual verification; Device/OS: pending manual verification; URL: pending manual verification; Result: pending manual verification.
- [ ] Starting music after Video dismissal produces no simultaneous audio. Date: pending manual verification; Device/OS: pending manual verification; URL: pending manual verification; Result: pending manual verification.
- [ ] A pasted public HTTPS URL plays through AVKit controls. Date: pending manual verification; Device/OS: pending manual verification; URL: pending manual verification; Result: pending manual verification.
