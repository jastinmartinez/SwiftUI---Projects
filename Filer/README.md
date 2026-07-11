# Filer

A SwiftUI iOS app for managing media files backed by **Supabase Storage**. Import
photos and videos from your library, upload them **resumably** (TUS), download them
back on demand (resumable HTTP range requests), cache them on disk, and preview them
in‑app — with live progress, retry, and cancellation.

Built with [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)
(TCA) and a set of small, single‑purpose, injectable clients.

- **Platform:** iOS 26.2+ · SwiftUI
- **Language:** Swift 5 mode (approachable concurrency)
- **Backend:** Supabase Storage
- **Tests:** 132, Swift Testing

---

## Quick start

**Requirements:** Xcode with the iOS 26 SDK, and a Supabase project with a Storage bucket.

1. **Add your Supabase credentials.** Create `Filer/Secrets.xcconfig` (git‑ignored):

   ```xcconfig
   SUPABASE_URL = https:$()//YOUR-PROJECT.supabase.co
   SUPABASE_ANON_KEY = your-anon-key
   SUPABASE_BUCKET = your-bucket-name
   ```

   > ⚠️ In `.xcconfig`, `//` starts a comment — the `$()` between `https:` and `//`
   > escapes it so the URL survives. These keys flow into `Info.plist` and are read
   > at launch by `SupabaseConfig.loadFromBundle` (a missing key fails loudly).

2. **Open and run:**

   ```sh
   open Filer.xcodeproj      # select the "Filer" scheme, then Run (⌘R)
   ```

That's it — the Files screen loads your bucket. Tap the toolbar picker to import media
(uploads on import); tap a remote row to download it; tap a local row to preview it.

---

## How it works

The UI is thin; all behavior lives in TCA reducers, which talk to **one facade client**
that orchestrates the real work. Everything below the facade is a swappable seam.

```
SwiftUI views
   → Features (reducers)      FilesFeature · FileFeature · MediaImportFeature
      → MediaTransferClient   facade: list / upload / download
         → per‑concern clients   Import · Cache · Upload · Download · Remote
            → transport ports      HTTPTransport · ConnectivityMonitor · Sleeper
               → system            URLSession · Network · Supabase
```

### Clients (`Filer/Clients/Media/`)

| Client | Responsibility |
| --- | --- |
| `MediaTransferClient` | **Facade** the features depend on; composes the four below into `list`/`upload`/`download` |
| `MediaImportClient` | Load picked photos/videos into memory |
| `MediaCacheClient` | On‑disk cache for imports + downloads, with TTL expiry |
| `MediaUploadClient` | TUS **resumable upload** engine (chunking, offset resume, reconnect budget) |
| `MediaDownloadClient` | HTTP **ranged / resumable download** engine |
| `MediaRemoteClient` | Supabase Storage: list files, build upload/download requests |

### Transport ports (`Filer/Clients/Media/Transport/`)

Injectable primitives, each with a `.live` adapter over a system framework (tests
inject stubs instead):

| Port | Live adapter over |
| --- | --- |
| `HTTPTransport` | `URLSession` (normalized to `HTTPResponse`) |
| `ConnectivityMonitor` | `NWPathMonitor` |
| `Sleeper` | `Task.sleep` |
| `MediaRemoteTransferPolicy` | *(value)* chunk size, retry/resume budgets, backoff |

---

## Project layout

```
Filer/
├── Filer.xcodeproj
├── Filer.xctestplan
├── Filer/                     # app source
│   ├── FilerApp.swift         # @main → FilesFeatureView
│   ├── Core/                  # value types: FileItem, MediaMetadata, ImportedMedia, TransferProgress…
│   ├── Features/Files/        # reducers, presentation models, and SwiftUI views
│   ├── Clients/Media/         # the clients + transport ports above
│   └── Secrets.xcconfig       # git‑ignored — you create this
└── FilerTests/                # Swift Testing suite
    └── Support/               # shared fixtures & client doubles
```

---

## Tests

Run the whole suite (any iOS 26 simulator):

```sh
xcodebuild test -scheme Filer \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

The suite drives the real engines over stubbed transports and asserts **observable
behavior** — exact bytes, user‑facing strings, and effect ordering — rather than mock
call counts.
