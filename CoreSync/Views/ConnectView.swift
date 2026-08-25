import SwiftUI

struct ConnectView: View {
    @EnvironmentObject private var auth: SupabaseAuth
    @StateObject private var sensor = ActiveSensorManager()
    @State private var activeSession: RunSession?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                statusHeader

                if sensor.connectionState == .connected {
                    connectedContent
                } else {
                    scanList
                }

                if !PendingSessionStore.loadAll().isEmpty {
                    pendingSyncBanner
                }

                Spacer()
            }
            .padding()
            .navigationTitle("CoreSync")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Log Out") { auth.logout() }
                }
            }
            .onAppear { sensor.startScanning() }
            .onDisappear { sensor.stopScanning() }
            .fullScreenCover(item: $activeSession) { session in
                RecordingView(sensor: sensor, session: session)
            }
        }
    }

    private var statusHeader: some View {
        VStack(spacing: 4) {
            Image(systemName: sensor.connectionState == .connected ? "thermometer.medium" : "antenna.radiowaves.left.and.right")
                .font(.system(size: 40))
                .foregroundStyle(sensor.connectionState == .connected ? .green : .secondary)
            Text(statusText)
                .font(.headline)
        }
        .padding(.top, 20)
    }

    private var statusText: String {
        switch sensor.connectionState {
        case .disconnected: return "Not connected"
        case .scanning: return "Scanning for CORE sensors…"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        }
    }

    private var scanList: some View {
        List(sensor.discoveredPeripherals) { peripheral in
            Button {
                sensor.connect(to: peripheral)
            } label: {
                HStack {
                    VStack(alignment: .leading) {
                        Text(peripheral.name).font(.body)
                        Text("RSSI \(peripheral.rssi) dBm").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if sensor.connectionState == .connecting {
                        ProgressView()
                    }
                }
            }
            .disabled(sensor.connectionState == .connecting)
        }
        .listStyle(.plain)
        .frame(maxHeight: 300)
        .overlay {
            if sensor.discoveredPeripherals.isEmpty {
                ContentUnavailableView(
                    "Looking for CORE sensors",
                    systemImage: "antenna.radiowaves.left.and.right",
                    description: Text("Make sure your sensor is powered on and nearby.")
                )
            }
        }
    }

    private var connectedContent: some View {
        VStack(spacing: 16) {
            if let battery = sensor.batteryPercent {
                Label("\(battery)% battery", systemImage: batteryIcon(for: battery))
                    .foregroundStyle(.secondary)
            }

            Button {
                activeSession = RunSession()
            } label: {
                Text("Start Session")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button("Disconnect", role: .destructive) {
                sensor.disconnect()
            }
        }
    }

    private var pendingSyncBanner: some View {
        Label("You have a session waiting to sync - reopen it from Start Session once connected.", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            .font(.footnote)
            .foregroundStyle(.orange)
            .multilineTextAlignment(.leading)
    }

    private func batteryIcon(for percent: Int) -> String {
        switch percent {
        case ..<20: return "battery.25"
        case ..<50: return "battery.50"
        case ..<80: return "battery.75"
        default: return "battery.100"
        }
    }
}

#Preview {
    ConnectView().environmentObject(SupabaseAuth())
}
