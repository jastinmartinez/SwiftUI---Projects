# Crescendo

Crescendo is an iOS 18 provider-neutral playback application built with SwiftUI and the Composable Architecture. Jamendo supplies the current catalog and streaming resources, while AVFoundation provides playback through app-owned client interfaces.

## Project structure

- `Crescendo/App/` contains the application entry point, dependency composition, and root coordination.
- `Crescendo/Features/` contains the Search, Playback, and Provider Selection reducers and presentation.
- `Crescendo/Clients/` defines provider-neutral capability interfaces consumed by reducers.
- `Crescendo/Domain/` contains provider-neutral catalog, playback, provider, and search values.
- `Crescendo/Infrastructure/Providers/` contains provider implementations, including Jamendo API access and domain mapping.
- `Crescendo/Infrastructure/Playback/AVPlayerPlaybackEngine/` contains the temporary AVPlayer-backed engine selected by `AppComposition`; reducers receive only focused playback clients.
- `Crescendo/Shared/` contains cross-feature formatting, localization, and presentation utilities.
- `CrescendoTests/` mirrors these production responsibilities with focused tests.

## Local configuration

Create the ignored local configuration file from the checked-in example:

```sh
cp Config/Local.example.xcconfig Config/Local.xcconfig
```

Replace the example value in `Config/Local.xcconfig` with your Jamendo client ID. `Config/Base.xcconfig` optionally includes that local file, so secrets remain outside source control.

## Project generation

The checked-in Xcode project is generated from `project.yml` with XcodeGen 2.46.0 or newer:

```sh
xcodegen generate --spec project.yml
```

Filesystem-synchronized source folders discover new files without regenerating the project. Regenerate only after changing targets, dependencies, build settings, or other project structure in `project.yml`.

## Tests

Run the `Crescendo` scheme from Xcode, or provide an installed simulator destination to `xcodebuild`:

```sh
xcodebuild test \
  -project Crescendo.xcodeproj \
  -scheme Crescendo \
  -destination 'platform=iOS Simulator,name=iPhone 13,OS=18.6'
```
