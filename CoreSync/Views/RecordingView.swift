import SwiftUI

// The live in-run screen plus the "End & Sync" flow. No network calls happen
// while recording - readings just accumulate in `session` via
// sensor.onReading, per the "no live streaming" requirement. Syncing only
// happens once, when the athlete taps End & Sync.
struct RecordingView: View {
    @EnvironmentObject private var auth: SupabaseAuth
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var sensor: ActiveSensorManager
    @ObservedObject var session: RunSession

    @State private var now = Date()
    @State private var phase: Phase = .recording
    @State private var ticker: Timer?

    private enum Phase {
        case recording
        case syncing
        case result(SyncResultView.Outcome)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .recording:
                    recordingContent
                case .syncing:
                    syncingContent
                case .result(let outcome):
                    SyncResultView(outcome: outcome, onDone: { dismiss() })
                }
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear(perform: startRecording)
        .onDisappear { ticker?.invalidate() }
        .interactiveDismissDisabled(isRecordingPhase)
    }

    private var isRecordingPhase: Bool {
        if case .recording = phase { return true }
        return false
    }

    private var recordingContent: some View {
        VStack(spacing: 28) {
            Text(formattedElapsed)
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()

            VStack(spacing: 20) {
                statRow(label: "Skin temp", value: formattedTemp(sensor.currentSkinTempC))
                statRow(label: "Session avg", value: formattedTemp(session.averageSkinTempC))
                statRow(label: "Core temp", value: coreTempText(sensor.currentCoreTempC))
                if let battery = sensor.batteryPercent {
                    statRow(label: "Battery", value: "\(battery)%")
                }
            }
            .padding()
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))

            Spacer()

            Button {
                endAndSync()
            } label: {
                Text("End & Sync")
                    .font(.title3.bold())
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
        }
    }

    private var syncingContent: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Syncing session…").foregroundStyle(.secondary)
            Spacer()
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.body.monospacedDigit())
        }
    }

    private var formattedElapsed: String {
        let interval = Int(now.timeIntervalSince(session.startedAt))
        return String(format: "%02d:%02d:%02d", interval / 3600, (interval % 3600) / 60, interval % 60)
    }

    private func formattedTemp(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f°C", value)
    }

    // Core temp has no fake fallback number - until greenTEG's proprietary
    // characteristic is wired up (see CoreSensorManager), this always reads
    // as explicitly pending rather than showing "—" like a normal missing
    // value would.
    private func coreTempText(_ value: Double?) -> String {
        value.map { formattedTemp($0) } ?? "Pending sensor calibration data"
    }

    private func startRecording() {
        sensor.onReading = { [weak session] reading in
            session?.record(reading)
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            now = Date()
        }
    }

    private func endAndSync() {
        session.end()
        sensor.onReading = nil
        phase = .syncing

        let summary = SyncResultView.Summary(
            avgSkinTempC: session.averageSkinTempC,
            maxSkinTempC: session.maxSkinTempC,
            avgCoreTempC: session.averageCoreTempC,
            maxCoreTempC: session.maxCoreTempC,
            readingCount: session.readings.count
        )

        Task {
            do {
                let api = CoreTempAPI(auth: auth)
                let sessionId = try await api.createSession(
                    CoreTempSessionPayload(
                        startedAt: session.startedAt,
                        endedAt: session.endedAt,
                        avgSkinTempC: summary.avgSkinTempC,
                        maxSkinTempC: summary.maxSkinTempC,
                        avgCoreTempC: summary.avgCoreTempC,
                        maxCoreTempC: summary.maxCoreTempC,
                        notes: nil
                    )
                )
                try await api.addReadings(
                    session.readings.map {
                        CoreTempReadingPayload(
                            recordedAt: $0.recordedAt,
                            skinTempC: $0.skinTempC,
                            coreTempC: $0.coreTempC,
                            batteryPct: $0.batteryPct
                        )
                    },
                    sessionId: sessionId
                )
                phase = .result(.success(summary))
            } catch {
                cacheLocallyAndReport(summary: summary)
            }
        }
    }

    // Keeps the recording rather than losing it - the athlete retries from
    // the connect screen next time the app is online, per the "no signal
    // shouldn't lose the run" requirement.
    private func cacheLocallyAndReport(summary: SyncResultView.Summary) {
        let pending = PendingSession(
            startedAt: session.startedAt,
            endedAt: session.endedAt ?? Date(),
            readings: session.readings.map {
                PendingSession.PendingReading(
                    recordedAt: $0.recordedAt,
                    skinTempC: $0.skinTempC,
                    coreTempC: $0.coreTempC,
                    batteryPct: $0.batteryPct
                )
            }
        )
        PendingSessionStore.save(pending)
        phase = .result(.failure(summary: summary, cachedLocally: true))
    }
}
