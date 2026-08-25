import Foundation

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Double

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }
}

enum SupabaseAuthError: Error {
    case invalidCredentials
    case server(status: Int, message: String?)
    case network(Error)
    case decoding
    case notAuthenticated
}

// GoTrue's error body shape, e.g. {"error_description":"Invalid login
// credentials"} or {"msg":"..."} depending on the failure - decoded so the
// actual reason reaches the login screen instead of a generic message that
// looks identical whether the password is wrong or the request itself is
// malformed.
private struct GoTrueErrorBody: Decodable {
    let error: String?
    let errorDescription: String?
    let msg: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
        case msg
    }

    var message: String? { errorDescription ?? msg ?? error }
}

// Talks directly to Supabase's GoTrue REST API (the plain email/password
// grant) - the same auth backend the web app's own Supabase client uses,
// just without pulling in the full supabase-swift SDK for what's two
// endpoints. Tokens are cached in the Keychain (see KeychainStore) and
// refreshed silently on demand, so the app doesn't ask for a password every
// launch the way a normal Supabase mobile client wouldn't either.
@MainActor
final class SupabaseAuth: ObservableObject {
    @Published private(set) var isAuthenticated: Bool
    @Published private(set) var lastError: String?

    private let accessTokenKey = "supabase.accessToken"
    private let refreshTokenKey = "supabase.refreshToken"
    private let expiresAtKey = "supabase.expiresAt"

    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date?

    init() {
        let accessToken = KeychainStore.get("supabase.accessToken")
        let refreshToken = KeychainStore.get("supabase.refreshToken")
        var expiresAt: Date?
        if let raw = KeychainStore.get("supabase.expiresAt"), let interval = Double(raw) {
            expiresAt = Date(timeIntervalSince1970: interval)
        }
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.isAuthenticated = accessToken != nil && refreshToken != nil
    }

    func login(email: String, password: String) async {
        lastError = nil
        do {
            let url = URL(string: "\(Secrets.supabaseURL.absoluteString)/auth/v1/token?grant_type=password")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["email": email, "password": password])

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SupabaseAuthError.network(URLError(.badServerResponse)) }
            guard http.statusCode == 200 else {
                let body = try? JSONDecoder().decode(GoTrueErrorBody.self, from: data)
                throw SupabaseAuthError.server(status: http.statusCode, message: body?.message)
            }

            let token = try JSONDecoder().decode(TokenResponse.self, from: data)
            store(accessToken: token.accessToken, refreshToken: token.refreshToken, expiresIn: token.expiresIn)
        } catch SupabaseAuthError.server(let status, let message) {
            // "Invalid login credentials" is GoTrue's real wrong-password
            // message; anything else here (bad apikey, malformed request,
            // rate limit, ...) is a different problem and shown verbatim
            // rather than mislabeled as a credentials error.
            if message == "Invalid login credentials" {
                lastError = "Incorrect email or password."
            } else {
                lastError = "Server error (\(status)): \(message ?? "no details")"
            }
        } catch {
            lastError = "Couldn't reach the server: \(error.localizedDescription)"
        }
    }

    func logout() {
        accessToken = nil
        refreshToken = nil
        expiresAt = nil
        KeychainStore.remove(accessTokenKey)
        KeychainStore.remove(refreshTokenKey)
        KeychainStore.remove(expiresAtKey)
        isAuthenticated = false
    }

    // Every authenticated CoreTempAPI call routes through this rather than
    // reading accessToken directly, so a token nearing expiry gets refreshed
    // transparently instead of the request failing with a 401.
    func validAccessToken() async throws -> String {
        guard let refreshToken else { throw SupabaseAuthError.notAuthenticated }
        if let accessToken, let expiresAt, expiresAt.timeIntervalSinceNow > 60 {
            return accessToken
        }

        let url = URL(string: "\(Secrets.supabaseURL.absoluteString)/auth/v1/token?grant_type=refresh_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["refresh_token": refreshToken])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            logout()
            throw SupabaseAuthError.notAuthenticated
        }
        let token = try JSONDecoder().decode(TokenResponse.self, from: data)
        store(accessToken: token.accessToken, refreshToken: token.refreshToken, expiresIn: token.expiresIn)
        return token.accessToken
    }

    private func store(accessToken: String, refreshToken: String, expiresIn: Double) {
        let expiresAt = Date().addingTimeInterval(expiresIn)
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        KeychainStore.set(accessToken, forKey: accessTokenKey)
        KeychainStore.set(refreshToken, forKey: refreshTokenKey)
        KeychainStore.set(String(expiresAt.timeIntervalSince1970), forKey: expiresAtKey)
        isAuthenticated = true
    }
}
