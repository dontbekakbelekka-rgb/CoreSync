# CoreSync

iOS app (SwiftUI + CoreBluetooth, iOS 17+) that connects to a greenTEG CORE
body-temperature sensor over Bluetooth LE during a run, records the session
locally, and syncs it to the [running-dashboard](https://github.com/dontbekakbelekka-rgb/STAYINTHEFIGHT)
Supabase backend when the run ends via its `app/api/core-temp/*` routes.

No live streaming or in-run alerts — a clean post-run sync, reviewed
afterward on the web dashboard or in conversation.

## Setup

This project's `.xcodeproj` is **not committed** — it's generated from
[`project.yml`](project.yml) via [XcodeGen](https://github.com/yonaskolb/XcodeGen),
so there's nothing to merge-conflict on. Regenerate it any time the project
structure changes (new file, new target, etc.).

```bash
brew install xcodegen
xcodegen generate
open CoreSync.xcodeproj
```

### Fill in your config

Copy the secrets template and fill in the real values (this file is
gitignored — it never gets committed):

```bash
cp CoreSync/Config/Secrets.swift.example CoreSync/Config/Secrets.swift
```

Edit `CoreSync/Config/Secrets.swift` with:

- `supabaseURL` — your Supabase project URL (Supabase dashboard → Project
  Settings → API)
- `supabaseAnonKey` — the **anon/public** key from the same page (never the
  service-role key)
- `apiBaseURL` — your running-dashboard's deployed Vercel URL (no trailing
  slash)

Re-run `xcodegen generate` after adding the file if Xcode doesn't pick it up
automatically.

### Build & run

- **Simulator**: works out of the box. `CoreBluetooth` can't talk to real
  hardware in the Simulator, so the app automatically uses
  `MockCoreSensorManager` there instead of `CoreSensorManager` (see
  `ActiveSensorManager` in `CoreSync/App/CoreSyncApp.swift`) — it fakes a
  nearby "CORE (Simulator)" peripheral and a stream of plausible skin-temp
  readings, so the whole connect → record → sync flow is testable without
  hardware.
- **Real device**: required for actually talking to a CORE sensor. Needs a
  free Apple ID for local signing (same as any other personal Xcode
  project) — no paid Apple Developer account needed to run on your own
  phone.
- **Tests**: `Cmd+U` in Xcode, or `xcodebuild test -scheme CoreSync -destination 'platform=iOS Simulator,name=iPhone 15'`.
  Covers `HealthThermometerDecoder`'s IEEE-11073 float decode against known
  byte sequences.

## Getting real core temperature working

Skin temperature and battery level are **fully working** today — the CORE
sensor exposes the standard Bluetooth SIG Health Thermometer Service
(`1809`) and Battery Service (`180F`), which `CoreSensorManager` reads
natively via CoreBluetooth.

The actual **core** temperature (not just skin temp) comes from a
proprietary greenTEG service (`00002100-5B1E-4347-B07C-97B514DAE121`,
confirmed present from greenTEG's own open-source Wear OS reference app),
but the specific characteristic UUID and byte format under that service
aren't public.

To unlock it:

1. Email **info@greenteg.com** — mention you're a CORE owner building a
   personal integration and ask for the **"CORE BLE Implementation Notes"**
   PDF (it's referenced in greenTEG's own public GitHub repos under the
   `CoreBodyTemp` org, so this is a normal ask).
2. Once you have the characteristic UUID and decode format, open
   `CoreSync/BLE/CoreSensorManager.swift` and:
   - Set `coreTemperatureCharacteristicUUID` to the real `CBUUID`.
   - Fill in the decode logic in `didUpdateValueFor` where it currently has
     a `// TODO: decode once greenTEG's Implementation Notes...` comment.
3. That's it — `currentCoreTempC`, session averages/maxes, and the sync
   payload all already thread a real value through once it stops being
   `nil`. Every screen already displays "Pending sensor calibration data"
   instead of a fake number when it's absent, so nothing else needs to
   change.

## Architecture

- `CoreSync/BLE/CoreSensorManager.swift` — CoreBluetooth scanning,
  connection, and characteristic parsing for real hardware, exposed as an
  `ObservableObject`.
- `CoreSync/BLE/MockCoreSensorManager.swift` — Simulator stand-in with the
  identical public surface, used automatically via the `ActiveSensorManager`
  typealias.
- `CoreSync/BLE/HealthThermometerDecoder.swift` — the IEEE-11073 32-bit
  FLOAT decode for the standard Temperature Measurement characteristic,
  unit-tested in `CoreSyncTests/`.
- `CoreSync/Session/RunSession.swift` — in-memory recording model and
  summary stat calculations (avg/max) for the current session.
- `CoreSync/Session/PendingSessionStore.swift` — persists a session to disk
  if the sync upload fails, so a bad connection at the end of a run never
  loses the recording; retried via `PendingSession`/`PendingSessionStore`.
- `CoreSync/Networking/SupabaseAuth.swift` — email/password login against
  Supabase's GoTrue REST API, with the access/refresh token pair cached in
  the Keychain (`KeychainStore.swift`) and refreshed silently.
- `CoreSync/Networking/CoreTempAPI.swift` — the two POST calls to
  `running-dashboard`'s `/api/core-temp/*` routes, authenticated via
  `Authorization: Bearer <token>`.
- `CoreSync/Views/` — `LoginView`, `ConnectView`, `RecordingView`,
  `SyncResultView`.

## Backend

Requires [`dontbekakbelekka-rgb/STAYINTHEFIGHT`](https://github.com/dontbekakbelekka-rgb/STAYINTHEFIGHT)
PRs **#119** (the `core_temp_sessions`/`core_temp_readings` tables and API
routes) and **#120** (Bearer-token auth support for those routes, needed
because this app has no cookie jar to authenticate the normal web-app way)
merged and deployed.
