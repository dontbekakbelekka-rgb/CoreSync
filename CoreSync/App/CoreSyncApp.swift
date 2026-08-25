import SwiftUI

// The Simulator can't drive real CoreBluetooth hardware, so every Simulator
// build swaps in MockCoreSensorManager - same public surface as
// CoreSensorManager, so ConnectView/RecordingView are written once against
// this alias and never branch on which one they got.
#if targetEnvironment(simulator)
typealias ActiveSensorManager = MockCoreSensorManager
#else
typealias ActiveSensorManager = CoreSensorManager
#endif

@main
struct CoreSyncApp: App {
    @StateObject private var auth = SupabaseAuth()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(auth)
        }
    }
}
