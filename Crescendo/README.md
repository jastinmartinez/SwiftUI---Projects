# Crescendo

Crescendo is an iOS 18 application that keeps music-provider details behind app-owned domain and dependency boundaries. The first live provider is Apple Music, while features consume provider-neutral values and operations.

## Project structure

- `Crescendo/App/` contains the root reducer, root view, and parent coordination.
- `Crescendo/Domain/` contains provider-neutral music values.
- `Crescendo/Localization/` contains typed access to localized strings.
- `Crescendo/Providers/` contains provider implementations and SDK mapping.
- `CrescendoTests/` mirrors production responsibilities with focused tests.

## Conventions

- Give every top-level production type its own file named after that type.
- Keep nested ownership types, such as a feature's `State`, `Action`, and `Delegate`, with their owner.
- Document top-level production types and non-obvious invariants with DocC comments.
- Keep provider SDK types inside their provider adapter.
- Route every user-facing string through `Locs` and `Localizable.xcstrings`.
- Format Swift with four spaces using the checked-in `.swift-format` configuration.
- Prefer small store-connected containers composed from reusable stateless views.

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
