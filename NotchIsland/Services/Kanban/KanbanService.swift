import Combine
import Foundation

/// The signed-in user's unfinished Resam Kanban cards, for the Tasks tab.
@MainActor
final class KanbanService: ObservableObject {
    @Published private(set) var tasks: [KanbanTask] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isSignedIn: Bool
    @Published private(set) var userName: String
    @Published var scope: KanbanScope {
        didSet {
            guard scope != oldValue else { return }
            UserDefaults.standard.set(scope.rawValue, forKey: SettingsKeys.kanbanScope)
            tasks = []
            refresh(force: true)
        }
    }

    /// Opens Settings, where the sign-in form is.
    var onRequestSignIn: (() -> Void)?

    private let client: KanbanClient
    private var token: String?
    private var loadTask: Task<Void, Never>?
    /// The tab refreshes on open, but not more often than this.
    private static let minRefreshInterval: TimeInterval = 60

    init(client: KanbanClient = KanbanClient()) {
        self.client = client
        let token = KanbanKeychain.token()
        self.token = token
        isSignedIn = token != nil
        userName = UserDefaults.standard.string(forKey: SettingsKeys.kanbanUserName) ?? ""
        scope = KanbanScope(rawValue: UserDefaults.standard.string(forKey: SettingsKeys.kanbanScope) ?? "") ?? .assigned
    }

    /// Cards not yet done, rejected or cancelled, in board column order.
    var unfinishedTasks: [KanbanTask] { tasks.filter { !$0.status.isFinished } }

    func refresh(force: Bool = false) {
        guard let token else { return }
        if !force, isLoading { return }
        if !force, let lastUpdated, Date().timeIntervalSince(lastUpdated) < Self.minRefreshInterval { return }
        loadTask?.cancel()
        isLoading = true
        let scope = scope
        loadTask = Task { [client] in
            do {
                let tasks = try await client.tasks(scope: scope, token: token)
                guard !Task.isCancelled else { return }
                self.tasks = tasks
                self.errorMessage = nil
                self.lastUpdated = Date()
            } catch is CancellationError {
                return
            } catch KanbanError.unauthenticated {
                self.clearSession()
                self.errorMessage = KanbanError.unauthenticated.errorDescription
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = (error as? URLError)?.code == .cancelled ? nil : error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func institutions() async throws -> [KanbanInstitution] {
        try await client.institutions()
    }

    func signIn(username: String, password: String, institutionID: Int) async throws {
        let result = try await client.login(username: username, password: password, institutionID: institutionID)
        KanbanKeychain.setToken(result.token)
        UserDefaults.standard.set(result.name, forKey: SettingsKeys.kanbanUserName)
        UserDefaults.standard.set(institutionID, forKey: SettingsKeys.kanbanInstitutionID)
        token = result.token
        userName = result.name
        isSignedIn = true
        errorMessage = nil
        refresh(force: true)
    }

    func signOut() {
        if let token { Task { [client] in await client.logout(token: token) } }
        clearSession()
    }

    private func clearSession() {
        loadTask?.cancel()
        KanbanKeychain.setToken(nil)
        token = nil
        isSignedIn = false
        isLoading = false
        tasks = []
        lastUpdated = nil
    }
}
