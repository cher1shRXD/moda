import Foundation

struct BackendConfiguration {
    var baseURL: URL
    var apiKey: String

    static var current: BackendConfiguration {
        let defaults = UserDefaults.standard
        let bundle = Bundle.main

        let baseURLString = defaults.string(forKey: "MODAServerBaseURL")
            ?? bundle.object(forInfoDictionaryKey: "MODAServerBaseURL") as? String
            ?? "http://127.0.0.1:8080"
        let apiKey = defaults.string(forKey: "MODAServerAPIKey")
            ?? bundle.object(forInfoDictionaryKey: "MODAServerAPIKey") as? String
            ?? ""

        return BackendConfiguration(
            baseURL: URL(string: baseURLString) ?? URL(string: "http://127.0.0.1:8080")!,
            apiKey: apiKey
        )
    }
}

struct BackendClient {
    private let configuration: BackendConfiguration
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(configuration: BackendConfiguration = .current, session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
    }

    func fetchSnapshot() async throws -> BackendSnapshot {
        try await send(path: "/snapshot", method: "GET")
    }

    func createGoal(title: String, targetAmount: Int, dueDate: Date) async throws -> BackendGoal {
        try await send(
            path: "/goals",
            method: "POST",
            body: GoalPayload(title: title, targetAmount: targetAmount, dueDate: dueDate)
        )
    }

    func updateGoal(id: UUID, title: String, targetAmount: Int, dueDate: Date) async throws -> BackendGoal {
        try await send(
            path: "/goals/\(id.uuidString)",
            method: "PATCH",
            body: GoalPayload(title: title, targetAmount: targetAmount, dueDate: dueDate)
        )
    }

    func useGoal(id: UUID) async throws -> BackendGoal {
        try await send(path: "/goals/\(id.uuidString)/use", method: "POST")
    }

    func releaseGoal(id: UUID) async throws -> BackendGoal {
        try await send(path: "/goals/\(id.uuidString)/release", method: "POST")
    }

    func updateToday(initialAllowance: Int? = nil, adjustment: Int? = nil) async throws -> BackendDailyBudget {
        try await send(
            path: "/today",
            method: "PUT",
            body: TodayPayload(initialAllowance: initialAllowance, adjustment: adjustment)
        )
    }

    func updateMinimumBalance(_ amount: Int) async throws -> BackendBalance {
        try await send(
            path: "/balance/minimum",
            method: "PUT",
            body: MinimumBalancePayload(minimumBalance: amount)
        )
    }

    func registerDeviceToken(_ token: String, environment: String) async throws -> BackendDeviceToken {
        try await send(
            path: "/apns/device-tokens",
            method: "POST",
            body: DeviceTokenPayload(token: token, environment: environment)
        )
    }

    private func send<Response: Decodable>(path: String, method: String) async throws -> Response {
        try await send(path: path, method: method, body: Optional<String>.none)
    }

    private func send<RequestBody: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: RequestBody?
    ) async throws -> Response {
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let base = configuration.baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/\(cleanPath)") else {
            throw BackendClientError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        guard !configuration.apiKey.isEmpty else {
            throw BackendClientError.missingAPIKey
        }

        request.setValue(configuration.apiKey, forHTTPHeaderField: "X-MODA-API-KEY")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BackendClientError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8)
            throw BackendClientError.requestFailed(statusCode: httpResponse.statusCode, message: message)
        }

        return try decoder.decode(Response.self, from: data)
    }
}

enum BackendClientError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case requestFailed(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "앱 서버 API 키가 설정되지 않았어요."
        case .invalidResponse:
            return "서버 응답을 읽을 수 없어요."
        case .requestFailed(let statusCode, let message):
            return "서버 요청 실패 (\(statusCode)) \(message ?? "")"
        }
    }
}

struct BackendSnapshot: Decodable {
    let balance: BackendBalance
    let today: BackendDailyBudget
    let goals: [BackendGoal]
    let transactions: [BackendTransaction]
}

struct BackendBalance: Decodable {
    let currentBalance: Int
    let minimumBalance: Int
    let updatedAt: Date
}

struct BackendDailyBudget: Decodable {
    let initialAllowance: Int
    let adjustment: Int
    let updatedAt: Date
}

struct BackendGoal: Decodable {
    let id: UUID
    let title: String
    let targetAmount: Int
    let dueDate: Date
    let status: SavingsGoal.Status
    let completedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct BackendTransaction: Decodable {
    let id: UUID
    let externalId: String?
    let date: Date
    let title: String
    let amount: Int
    let kind: Transaction.Kind
    let createdAt: Date
    let updatedAt: Date
}

struct BackendDeviceToken: Decodable {
    let id: UUID
    let token: String
    let environment: String
    let createdAt: Date
    let updatedAt: Date
}

private struct GoalPayload: Encodable {
    let title: String
    let targetAmount: Int
    let dueDate: Date
}

private struct TodayPayload: Encodable {
    let initialAllowance: Int?
    let adjustment: Int?
}

private struct MinimumBalancePayload: Encodable {
    let minimumBalance: Int
}

private struct DeviceTokenPayload: Encodable {
    let token: String
    let environment: String
}
