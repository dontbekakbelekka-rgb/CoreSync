import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var auth: SupabaseAuth

    var body: some View {
        if auth.isAuthenticated {
            ConnectView()
        } else {
            LoginView()
        }
    }
}

#Preview {
    ContentView().environmentObject(SupabaseAuth())
}
