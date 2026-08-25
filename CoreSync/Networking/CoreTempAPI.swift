import Foundation

struct CoreTempSessionPayload: Encodable {
    let startedAt: Date
    let endedAt: Date?
    let avgSkinTempC: Double?
    let maxSkinTempC: Double?
    let avgCoreTempC: Double?
    let maxCoreTempC: Double?
    let notes: String?
}

private struct CoreTempSessionResponse: Decodable {
    let id: String
}

struct CoreTempReadingPayload: Encodable {
    let recordedAt: Date
    let skinTempC: Double?
    let coreTempC: Double?
    let batteryPct: Int?
}

enum CoreTempAPIError: Error {
    case network(Error)
    case server(status: Int, body: String)
    case decoding
}

// Talks to this same account's running-dashboard API routes
// (app/api/core-temp/...) - not Supabase directly. Those routes accept an
// `Authorization: Bearer <token>` header from a non-browser client like this
// app (see lib/supabase/routeAuth.ts on the backend) and enforce the same
// RLS policies as the web app's own cookie-based session.
final class CoreTempAPI {
    private let auth: SupabaseAuth

    init(auth: SupabaseAuth) {
        self.auth = auth
    }

    // Returns the new session's id, to be passed to addReadings next.
    func createSession(_ payload: CoreTempSessionPayload) async throws -> String {
        let body = try encoder.encode(payload)
        let data = try await post(path: "/api/core-temp/sessions", body: body)
        do {
            return try decoder.decode(CoreTempSessionResponse.self, from: data).id
        } catch {
            throw CoreTempAPIError.decoding
        }
    }

    func addReadings(_ readings: [CoreTempReadingPayload], sessionId: String) async throws {
        struct ReadingsBody: Encodable { let readings: [CoreTempReadingPayload] }
        let body = try encoder.encode(ReadingsBody(readings: readings))
        _ = try await post(path: "/api/core-temp/sessions/\(sessionId)/readings", body: body)
    }

    private func post(path: String, body: Data) async throws -> Data {
        let token: String
        do {
            token = try await auth.validAccessToken()
        } catch {
            throw CoreTempAPIError.network(error)
        }

        guard let url = URL(string: Secrets.apiBaseURL.absoluteString + path) else {
            throw CoreTempAPIError.decoding
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = body

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw CoreTempAPIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw CoreTempAPIError.decoding }
        guard (200...299).contains(http.statusCode) else {
            throw CoreTempAPIError.server(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}
