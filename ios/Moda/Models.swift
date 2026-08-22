import Foundation

struct FinanceState: Codable, Equatable {
    var goals: [SavingsGoal]
    var currentBalance: Int
    var minimumBalance: Int
    var today: DailyBudget
    var transactions: [Transaction]
    var monthlySummaries: [MonthlySummary]
    var selectedMonth: Date

    var activeGoals: [SavingsGoal] {
        goals.filter { $0.status == .active }
    }

    static var empty: FinanceState {
        let now = Date()
        let monthStart = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now)) ?? now

        return FinanceState(
            goals: [],
            currentBalance: 0,
            minimumBalance: 0,
            today: .empty,
            transactions: [],
            monthlySummaries: [],
            selectedMonth: monthStart
        )
    }

    enum CodingKeys: String, CodingKey {
        case goal
        case goals
        case currentBalance
        case minimumBalance
        case today
        case transactions
        case monthlySummaries
        case selectedMonth
    }

    init(goals: [SavingsGoal], currentBalance: Int, minimumBalance: Int, today: DailyBudget, transactions: [Transaction], monthlySummaries: [MonthlySummary], selectedMonth: Date) {
        self.goals = goals
        self.currentBalance = currentBalance
        self.minimumBalance = minimumBalance
        self.today = today
        self.transactions = transactions
        self.monthlySummaries = monthlySummaries
        self.selectedMonth = selectedMonth
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let goals = try container.decodeIfPresent([SavingsGoal].self, forKey: .goals) {
            self.goals = goals
        } else if let goal = try container.decodeIfPresent(SavingsGoal.self, forKey: .goal) {
            self.goals = [goal]
        } else {
            self.goals = []
        }

        currentBalance = try container.decodeIfPresent(Int.self, forKey: .currentBalance) ?? FinanceState.empty.currentBalance
        minimumBalance = try container.decodeIfPresent(Int.self, forKey: .minimumBalance) ?? 0
        today = try container.decodeIfPresent(DailyBudget.self, forKey: .today) ?? .empty
        transactions = try container.decodeIfPresent([Transaction].self, forKey: .transactions) ?? []
        monthlySummaries = try container.decodeIfPresent([MonthlySummary].self, forKey: .monthlySummaries) ?? []
        selectedMonth = try container.decodeIfPresent(Date.self, forKey: .selectedMonth) ?? FinanceState.empty.selectedMonth
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(goals, forKey: .goals)
        try container.encode(currentBalance, forKey: .currentBalance)
        try container.encode(minimumBalance, forKey: .minimumBalance)
        try container.encode(today, forKey: .today)
        try container.encode(transactions, forKey: .transactions)
        try container.encode(monthlySummaries, forKey: .monthlySummaries)
        try container.encode(selectedMonth, forKey: .selectedMonth)
    }
}

struct SavingsGoal: Codable, Identifiable, Equatable {
    enum Status: String, Codable {
        case active
        case used
        case released
    }

    var id: UUID
    var title: String
    var targetAmount: Int
    var dueDate: Date
    var status: Status
    var completedAt: Date?

    init(id: UUID = UUID(), title: String, targetAmount: Int, dueDate: Date, status: Status = .active, completedAt: Date? = nil) {
        self.id = id
        self.title = title
        self.targetAmount = targetAmount
        self.dueDate = dueDate
        self.status = status
        self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case targetAmount
        case dueDate
        case status
        case completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decode(String.self, forKey: .title)
        targetAmount = try container.decode(Int.self, forKey: .targetAmount)
        dueDate = try container.decode(Date.self, forKey: .dueDate)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .active
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }
}

struct DailyBudget: Codable, Equatable {
    var initialAllowance: Int
    var spentAmount: Int
    var adjustment: Int

    static let empty = DailyBudget(initialAllowance: 0, spentAmount: 0, adjustment: 0)

    var currentAllowance: Int {
        max(initialAllowance + adjustment, 0)
    }

    var remainingAmount: Int {
        currentAllowance - spentAmount
    }

    var usage: Double {
        guard currentAllowance > 0 else { return 1 }
        return Double(spentAmount) / Double(currentAllowance)
    }
}

struct Transaction: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case income
        case expense
    }

    var id: UUID
    var date: Date
    var title: String
    var amount: Int
    var kind: Kind
}

struct MonthlySummary: Codable, Identifiable, Equatable {
    var id: Date { month }
    var month: Date
    var spentAmount: Int
    var targetAmount: Int

    var amountToCut: Int {
        max(spentAmount - targetAmount, 0)
    }
}
