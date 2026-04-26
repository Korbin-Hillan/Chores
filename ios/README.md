# ios

SwiftUI iOS 17+ app for ChoresApp. The Xcode project is generated from `project.yml` by [XcodeGen](https://github.com/yonaskolb/XcodeGen) — that's why there's no `ChoresApp.xcodeproj` in the repo.

## First time setup

```bash
brew install xcodegen
xcodegen generate
open ChoresApp.xcodeproj
```

Then ⌘R in Xcode. The simulator will hit `http://localhost:8080` by default — start the backend first (`cd ../server && npm run dev`).

## When to regenerate the project

Re-run `xcodegen generate` whenever you:
- Add or remove a top-level source folder
- Add a new dependency in `project.yml`
- Change Info.plist properties or build settings

Adding a new `.swift` file inside an existing folder doesn't require regen — `project.yml` uses folder-based source discovery.

## Layout

```
Sources/ChoresApp/
├── App/              ChoresAppApp, RootView, AppEnvironment
├── Features/         One folder per feature (Auth, Households, Chores, Generation, Feed, Profile)
├── Models/           Codable mirrors of API types (Phase 1+)
├── Networking/       APIClient, AuthStore (Phase 1+)
├── Persistence/      KeychainStore, SwiftData models (Phase 2+)
├── DesignSystem/     Reusable views, theme (Phase 5)
└── Resources/        Assets.xcassets, generated Info.plist
Tests/ChoresAppTests/
```

## Conventions

- Group code by **feature**, not by type. `Features/Chores/ChoreListView.swift`, not `Views/ChoreListView.swift`.
- View models are `@Observable` classes (iOS 17+). One per screen with logic.
- Networking goes through `APIClient`. Views call view models; view models call the client.
- No force-unwraps (`!`) outside `#Preview` blocks and tests.
- No `print(...)` in shipped code. Use `os.Logger`.
- `SWIFT_TREAT_WARNINGS_AS_ERRORS` is on. Fix warnings; don't suppress them.

## Build from CLI

```bash
xcodegen generate
xcodebuild -scheme ChoresApp \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug \
  build
```

## Tests

```bash
xcodebuild -scheme ChoresApp \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  test
```
