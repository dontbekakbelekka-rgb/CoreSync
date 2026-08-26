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
  Covers `HealthThermometerDecoder`'s IEEE-11073 float decode and
  `CoreBodyTemperatureDecoder`'s fixed-point decode against known byte
  sequences.

## Core temperature

Skin temperature, battery level, and **actual core body temperature** are
all fully wired up:

- Skin temp + battery come from the standard Bluetooth SIG Health
  Thermometer Service (`1809`) and Battery Service (`180F`).
- Core temp comes from greenTEG's proprietary Core Body Temperature Service
  (`00002100-5B1E-4347-B07C-97B514DAE121`), characteristic
  `00002101-5B1E-4347-B07C-97B514DAE121`, decoded per the public "CORE
  SENSOR - Core Body Temperature Service Specification" v2.2 (published in
  the [`CoreBodyTemp/CoreBodyTemp`](https://github.com/CoreBodyTemp/CoreBodyTemp)
  GitHub repo — no vendor contact needed, it's publicly available). See
  `CoreSync/BLE/CoreBodyTemperatureDecoder.swift`.

That same repo's `CoreTemp Control Point` characteristic (`00002102-...`)
is for pairing an external ANT+/BLE heart rate monitor to the sensor, not
implemented here — out of scope for v1, but the spec covers it if it's ever
wanted.

There's no documented way to pull the sensor's own onboard "logging mode"
backlog (data buffered while worn without a connection) over BLE — the
public spec has no download/log command. greenTEG's own app can retrieve
one, but that appears to be a private mechanism outside this spec, not
something reproduced here.

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
- `CoreSync/BLE/CoreBodyTemperatureDecoder.swift` — the fixed-point decode
  for greenTEG's proprietary Core Body Temperature characteristic, also
  unit-tested.
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
