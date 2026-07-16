#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

music_kit_matches="$(
  rg -n \
    '^[[:space:]]*(?:@preconcurrency[[:space:]]+)?import(?:[[:space:]]+(?:class|struct|enum|protocol|typealias|func|var|let))?[[:space:]]+MusicKit(?:\.|[[:space:]]|$)|\b(MusicAuthorization|MusicSubscription|MusicCatalogSearchRequest|ApplicationMusicPlayer)\b|(?<![A-Za-z0-9_"])Song(?![A-Za-z0-9_"])' \
    "$ROOT/Crescendo" "$ROOT/CrescendoTests" \
    --pcre2 \
    --glob '*.swift' \
    || true
)"
if [[ -n "$music_kit_matches" ]]; then
  music_kit_violations="$(
    print -r -- "$music_kit_matches" \
      | rg -v '/Crescendo/Providers/AppleMusic/' \
      || true
  )"
  if [[ -n "$music_kit_violations" ]]; then
    print -u2 -- "$music_kit_violations"
    exit 1
  fi
fi

av_imports="$(
  rg -n \
    '^[[:space:]]*(?:@preconcurrency[[:space:]]+)?import(?:[[:space:]]+(?:class|struct|enum|protocol|typealias|func|var|let))?[[:space:]]+(AVFoundation|AVKit)(?:\.|[[:space:]]|$)' \
    "$ROOT/Crescendo" "$ROOT/CrescendoTests" \
    --glob '*.swift' \
    || true
)"
if [[ -n "$av_imports" ]]; then
  av_violations="$(
    print -r -- "$av_imports" \
      | rg -v '/Crescendo/Video/(AVPlayerSession|VideoPlayableItemLoader|VideoPlayerView)\.swift:' \
      | rg -v '/CrescendoTests/Video/(AVPlayerSessionTests|VideoPlaybackClientLiveTests)\.swift:' \
      || true
  )"
  if [[ -n "$av_violations" ]]; then
    print -u2 -- "$av_violations"
    exit 1
  fi
fi

inline_copy_violations="$(
  rg -n \
    '\b(Text|Button|ProgressView|Label|ContentUnavailableView|TextField|SecureField|Toggle|Picker|Menu|Section|Link)\b[[:space:]]*\([[:space:]]*"|\bText\b[[:space:]]*\([[:space:]]*verbatim:[[:space:]]*"|\b(navigationTitle|alert|confirmationDialog)\b[[:space:]]*\([[:space:]]*"|\bString\b[[:space:]]*\([[:space:]]*describing:' \
    "$ROOT/Crescendo/App" "$ROOT/Crescendo/Search" \
    "$ROOT/Crescendo/Playback" "$ROOT/Crescendo/Video" \
    --glob '*.swift' \
    || true
)"
if [[ -n "$inline_copy_violations" ]]; then
  print -u2 -- "$inline_copy_violations"
  exit 1
fi

for forbidden in \
  PlaybackCoordinatorClient \
  SerialAsyncExecutor \
  HLSPlaybackFeature \
  HLSPlaybackClient \
  hlsSampleURL \
  AppConfiguration
do
  forbidden_violations="$(
    rg -n "$forbidden" "$ROOT/Crescendo" "$ROOT/CrescendoTests" || true
  )"
  if [[ -n "$forbidden_violations" ]]; then
    print -u2 -- "$forbidden_violations"
    exit 1
  fi
done

sample_url_violations="$(
  rg -n 'devstreaming-cdn\.apple\.com|bipbop' \
    "$ROOT/Crescendo" "$ROOT/CrescendoTests" \
    || true
)"
if [[ -n "$sample_url_violations" ]]; then
  print -u2 -- "$sample_url_violations"
  exit 1
fi

for required_file in \
  "$ROOT/Crescendo/Localization/Locs.swift" \
  "$ROOT/Crescendo/Localizable.xcstrings" \
  "$ROOT/project.yml"
do
  if [[ ! -f "$required_file" ]]; then
    print -u2 -- "Missing: $required_file"
    exit 1
  fi
done

if ! rg -q \
  'INFOPLIST_KEY_NSAppleMusicUsageDescription:[[:space:]]*[^[:space:]]' \
  "$ROOT/project.yml"
then
  print -u2 -- "Missing NSAppleMusicUsageDescription build setting in $ROOT/project.yml"
  exit 1
fi

info_plist_strings="$(
  rg --files "$ROOT" \
    --hidden \
    --no-ignore \
    --glob 'InfoPlist.strings' \
    || true
)"
if [[ -n "$info_plist_strings" ]]; then
  print -u2 -- "InfoPlist.strings must not be present:"
  print -u2 -- "$info_plist_strings"
  exit 1
fi

print "Phase 1 boundaries: PASS"
