# Crescendo

Crescendo is an iOS 18 application that keeps music-provider details behind app-owned domain and dependency boundaries. The first live provider is Apple Music, while features consume provider-neutral values and operations.

## Project structure

- `Crescendo/App/` contains the root reducer, root view, and parent coordination.
- `Crescendo/Domain/` contains provider-neutral music values.
- `Crescendo/Localization/` contains typed access to localized strings.
- `Crescendo/Providers/` contains provider implementations and SDK mapping.
- `CrescendoTests/` mirrors production responsibilities with focused tests.

## Project generation

The checked-in Xcode project is generated from `project.yml` with XcodeGen 2.45.4 or newer:

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

## Phase 1 verification

From the workspace root, run `Crescendo/scripts/verify-phase1-boundaries.sh` and record final evidence in the [Phase 1 verification checklist](docs/verification/phase-1-checklist.md).
