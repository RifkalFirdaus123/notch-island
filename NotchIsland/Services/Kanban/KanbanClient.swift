import Foundation
import Security

/// A card on the Resam Kanban board (`sla_tasks` on the API).
struct KanbanTask: Identifiable, Equatable, Decodable {
    let id: Int
    let title: String
    let status: KanbanStatus
    let product: String?
    let dueDate: Date?
    let slaColor: String?
    let slaPercentage: Double?

    var isOverdue: Bool { dueDate.map { $0 < Date() } ?? false }

    /// Opens the card's detail on the web board.
    var webURL: URL? { URL(string: "https://kanban.resam.id/sla/board?taskId=\(id)") }

    private enum CodingKeys: String, CodingKey {
        case id, title, status, product
        case dueDate = "due_date"
        case slaSummary = "sla_summary"
    }

    private struct SlaSummary: Decodable {
        let color: String?
        let percentage: Double?
    }

    init(id: Int, title: String, status: KanbanStatus, product: String? = nil, dueDate: Date? = nil,
         slaColor: String? = nil, slaPercentage: Double? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.product = product
        self.dueDate = dueDate
        self.slaColor = slaColor
        self.slaPercentage = slaPercentage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        title = (try? c.decode(String.self, forKey: .title)) ?? ""
        status = KanbanStatus(rawValue: (try? c.decode(String.self, forKey: .status)) ?? "") ?? .todo
        product = try? c.decodeIfPresent(String.self, forKey: .product)
        dueDate = (try? c.decodeIfPresent(String.self, forKey: .dueDate)).flatMap(KanbanTask.parseDate)
        let sla = try? c.decodeIfPresent(SlaSummary.self, forKey: .slaSummary)
        slaColor = sla?.color
        slaPercentage = sla?.percentage
    }

    /// Laravel sends ISO 8601 with fractions ("…T10:00:00.000000Z") or "Y-m-d H:i:s" in Asia/Jakarta.
    static func parseDate(_ string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }
        let plain = DateFormatter()
        plain.locale = Locale(identifier: "en_US_POSIX")
        plain.timeZone = TimeZone(identifier: "Asia/Jakarta")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd"] {
            plain.dateFormat = format
            if let date = plain.date(from: string) { return date }
        }
        return nil
    }
}

/// Board columns, in the order the web board shows them.
enum KanbanStatus: String, CaseIterable {
    case requested, todo, inProgress = "in_progress", review, completed, rejected, cancelled

    var isFinished: Bool { self == .completed || self == .rejected || self == .cancelled }

    /// Labels match the web board.
    var label: String {
        switch self {
        case .requested: "Diminta"
        case .todo: "To Do"
        case .inProgress: "Dikerjakan"
        case .review: "Review"
        case .completed: "Selesai"
        case .rejected: "Ditolak"
        case .cancelled: "Dibatalkan"
        }
    }
}

struct KanbanInstitution: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
}

/// Which cards to list, matching the web board's two checkboxes.
enum KanbanScope: String, CaseIterable, Identifiable {
    /// "Tugas saya": assigned to me.
    case assigned
    /// "Punya saya": requested by me.
    case requested

    var id: String { rawValue }

    var label: String {
        switch self {
        case .assigned: "Tugas saya"
        case .requested: "Punya saya"
        }
    }

    var queryItem: URLQueryItem {
        switch self {
        case .assigned: URLQueryItem(name: "my_tasks", value: "1")
        case .requested: URLQueryItem(name: "mine", value: "1")
        }
    }
}

enum KanbanError: LocalizedError {
    case unauthenticated
    case server(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .unauthenticated: String(localized: "Signed out of Resam Kanban. Sign in again in Settings.")
        case .server(let message): message
        case .badResponse: String(localized: "Unexpected response from Resam Kanban.")
        }
    }
}

/// The REST API behind kanban.resam.id (Laravel, bearer tokens).
struct KanbanClient {
    static let baseURL = URL(string: "https://resam.id/api")!
    var session: URLSession = .shared

    func institutions() async throws -> [KanbanInstitution] {
        let data = try await send(request(path: "institutions"), token: nil)
        return try JSONDecoder().decode([KanbanInstitution].self, from: data)
    }

    /// Returns the bearer token and the signed-in user's name.
    func login(username: String, password: String, institutionID: Int) async throws -> (token: String, name: String) {
        var req = request(path: "login")
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": username, "password": password, "institution_id": institutionID,
        ])
        let data = try await send(req, token: nil)
        struct Response: Decodable {
            struct User: Decodable { let token: String; let name: String?; let username: String? }
            let data: User
        }
        let user = try JSONDecoder().decode(Response.self, from: data).data
        return (user.token, user.name ?? user.username ?? username)
    }

    func logout(token: String) async {
        var req = request(path: "logout")
        req.httpMethod = "POST"
        _ = try? await send(req, token: token)
    }

    /// Every card for the scope, across all columns.
    func tasks(scope: KanbanScope, token: String) async throws -> [KanbanTask] {
        let data = try await send(request(path: "sla_tasks/board", query: [scope.queryItem]), token: token)
        return try Self.decodeBoard(data)
    }

    static func decodeBoard(_ data: Data) throws -> [KanbanTask] {
        struct Response: Decodable {
            struct Board: Decodable {
                let columns: [String: [KanbanTask]]
                init(from decoder: Decoder) throws {
                    let c = try decoder.container(keyedBy: CodingKeys.self)
                    // PHP encodes an empty map as [].
                    columns = (try? c.decode([String: [KanbanTask]].self, forKey: .columns)) ?? [:]
                }
                enum CodingKeys: String, CodingKey { case columns }
            }
            let data: Board
        }
        let columns = try JSONDecoder().decode(Response.self, from: data).data.columns
        return KanbanStatus.allCases.flatMap { columns[$0.rawValue] ?? [] }
    }

    private func request(path: String, query: [URLQueryItem] = []) -> URLRequest {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var req = URLRequest(url: components.url!, timeoutInterval: 20)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func send(_ request: URLRequest, token: String?) async throws -> Data {
        var request = request
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KanbanError.badResponse }
        if http.statusCode == 401 { throw KanbanError.unauthenticated }
        guard (200..<300).contains(http.statusCode) else {
            struct Message: Decodable { let message: String? }
            let message = (try? JSONDecoder().decode(Message.self, from: data))?.message
            throw KanbanError.server(message ?? String(localized: "Resam Kanban returned error \(http.statusCode)."))
        }
        return data
    }
}

/// The bearer token lives in the login keychain, not in UserDefaults.
enum KanbanKeychain {
    private static let service = "NotchIsland.ResamKanban"
    private static let account = "token"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func token() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setToken(_ token: String?) {
        SecItemDelete(query as CFDictionary)
        guard let token, let data = token.data(using: .utf8) else { return }
        var q = query
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
