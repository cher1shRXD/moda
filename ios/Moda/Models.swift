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

    var primaryGoal: SavingsGoal {
        activeGoals.first ?? SavingsGoal.sample
    }

    static var sample: FinanceState {
        let calendar = Calendar.current
        let now = Date()
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now

        return FinanceState(
            goals: [
                SavingsGoal(
                    title: "비상금",
                    targetAmount: 5_000_000,
                    dueDate: calendar.date(byAdding: .month, value: 6, to: now) ?? now
                ),
                SavingsGoal(
                    title: "여행",
                    targetAmount: 2_000_000,
                    dueDate: calendar.date(byAdding: .month, value: 4, to: now) ?? now
                )
            ],
            currentBalance: 3_180_000,
            minimumBalance: 300_000,
            today: DailyBudget(
                initialAllowance: 32_000,
                spentAmount: 18_400,
                adjustment: 0
            ),
            transactions: Transaction.sampleTransactions(from: monthStart),
            monthlySummaries: MonthlySummary.samples(from: monthStart),
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
            self.goals = [SavingsGoal.sample]
        }

        currentBalance = try container.decodeIfPresent(Int.self, forKey: .currentBalance) ?? FinanceState.sample.currentBalance
        minimumBalance = try container.decodeIfPresent(Int.self, forKey: .minimumBalance) ?? 0
        today = try container.decode(DailyBudget.self, forKey: .today)
        transactions = try container.decode([Transaction].self, forKey: .transactions)
        monthlySummaries = try container.decode([MonthlySummary].self, forKey: .monthlySummaries)
        selectedMonth = try container.decode(Date.self, forKey: .selectedMonth)
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

    static var sample: SavingsGoal {
        SavingsGoal(title: "비상금", targetAmount: 5_000_000, dueDate: Date())
    }

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

    static func sampleTransactions(from monthStart: Date) -> [Transaction] {
        let calendar = Calendar.current
        let expenses = [
            (0, "점심", 9200),
            (1, "커피", 5200),
            (2, "교통", 1450),
            (4, "마트", 28400),
            (5, "저녁", 13200),
            (8, "구독", 14900),
            (10, "편의점", 7800),
            (12, "약국", 6500),
            (15, "선물", 42000),
            (17, "점심", 11000),
            (18, "카페", 4800)
        ]

        return expenses.compactMap { offset, title, amount in
            guard let date = calendar.date(byAdding: .day, value: offset, to: monthStart) else {
                return nil
            }

            return Transaction(id: UUID(), date: date, title: title, amount: amount, kind: .expense)
        }
    }
}

struct MonthlySummary: Codable, Identifiable, Equatable {
    var id: Date { month }
    var month: Date
    var spentAmount: Int
    var targetAmount: Int

    var amountToCut: Int {
        max(spentAmount - targetAmount, 0)
    }

    static func samples(from currentMonth: Date) -> [MonthlySummary] {
        let calendar = Calendar.current
        let values = [
            (-5, 920_000, 980_000),
            (-4, 1_080_000, 980_000),
            (-3, 970_000, 960_000),
            (-2, 1_140_000, 960_000),
            (-1, 1_020_000, 940_000),
            (0, 742_000, 930_000)
        ]

        return values.compactMap { offset, spent, target in
            guard let month = calendar.date(byAdding: .month, value: offset, to: currentMonth) else {
                return nil
            }

            return MonthlySummary(month: month, spentAmount: spent, targetAmount: target)
        }
    }
}
