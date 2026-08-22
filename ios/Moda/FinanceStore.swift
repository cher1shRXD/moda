import Foundation

@MainActor
final class FinanceStore: ObservableObject {
    @Published private(set) var state: FinanceState
    @Published private(set) var isLoadingRemoteData = false
    @Published private(set) var hasCompletedInitialFetch = false
    @Published private(set) var remoteErrorMessage: String?
    @Published private(set) var lastRemoteSyncAt: Date?
    @Published private(set) var pendingRemoteChangeCount = 0

    private let fileName = "moda-finance-state.json"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let backend: BackendClient

    init(backend: BackendClient = BackendClient()) {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.backend = backend

        state = FinanceState.empty
        load()
    }

    func addGoal(title: String, targetAmount: Int, dueDate: Date) {
        let goal = SavingsGoal(
            title: title,
            targetAmount: max(targetAmount, 0),
            dueDate: dueDate
        )
        state.goals.append(goal)
        save()
        Task {
            await runRemoteMutation {
                let createdGoal = try await backend.createGoal(
                    title: title,
                    targetAmount: max(targetAmount, 0),
                    dueDate: dueDate
                )
                replaceGoal(id: goal.id, with: createdGoal)
            }
        }
    }

    func updateGoal(id: SavingsGoal.ID, title: String, targetAmount: Int, dueDate: Date) {
        guard let index = state.goals.firstIndex(where: { $0.id == id }) else {
            return
        }

        state.goals[index] = SavingsGoal(
            id: id,
            title: title,
            targetAmount: max(targetAmount, 0),
            dueDate: dueDate,
            status: state.goals[index].status,
            completedAt: state.goals[index].completedAt
        )
        save()
        Task {
            await runRemoteMutation {
                let updatedGoal = try await backend.updateGoal(
                    id: id,
                    title: title,
                    targetAmount: max(targetAmount, 0),
                    dueDate: dueDate
                )
                replaceGoal(id: id, with: updatedGoal)
            }
        }
    }

    func useGoalAmount(id: SavingsGoal.ID) {
        guard let goal = state.goals.first(where: { $0.id == id }) else {
            return
        }

        let usedAmount = min(allocatedBalance(for: goal), state.currentBalance)
        state.currentBalance = max(state.currentBalance - usedAmount, 0)
        resolveGoal(id: id, status: .used)
        save()
        Task {
            await runRemoteMutation {
                let updatedGoal = try await backend.useGoal(id: id)
                replaceGoal(id: id, with: updatedGoal)
            }
        }
    }

    func releaseGoal(id: SavingsGoal.ID) {
        resolveGoal(id: id, status: .released)
        save()
        Task {
            await runRemoteMutation {
                let updatedGoal = try await backend.releaseGoal(id: id)
                replaceGoal(id: id, with: updatedGoal)
            }
        }
    }

    func borrowFromFuture(amount: Int) {
        state.today.adjustment += max(amount, 0)
        save()
        syncTodayBudget()
    }

    func deferAllowance(amount: Int) {
        state.today.adjustment -= max(amount, 0)
        save()
        syncTodayBudget()
    }

    func updateMinimumBalance(_ amount: Int) {
        state.minimumBalance = max(amount, 0)
        save()
        Task {
            await runRemoteMutation {
                let balance = try await backend.updateMinimumBalance(max(amount, 0))
                state.minimumBalance = balance.minimumBalance
                save()
            }
        }
    }

    func selectPreviousMonth() {
        moveSelectedMonth(by: -1)
    }

    func selectNextMonth() {
        moveSelectedMonth(by: 1)
    }

    var remainingGoalAmount: Int {
        state.activeGoals.reduce(0) { total, goal in
            total + remainingAmount(for: goal)
        }
    }

    func allocatedBalance(for goal: SavingsGoal) -> Int {
        goalBalanceAllocations[goal.id] ?? 0
    }

    func remainingAmount(for goal: SavingsGoal) -> Int {
        max(goal.targetAmount - allocatedBalance(for: goal), 0)
    }

    func progress(for goal: SavingsGoal) -> Double {
        guard goal.targetAmount > 0 else { return 0 }
        return min(Double(allocatedBalance(for: goal)) / Double(goal.targetAmount), 1)
    }

    func expenses(on day: Date) -> Int {
        finalSpending(on: day)
    }

    func finalSpending(on day: Date) -> Int {
        let totals = dailyTotals(on: day)
        return totals.expense - totals.income
    }

    func dailyTotals(on day: Date) -> (income: Int, expense: Int) {
        let calendar = Calendar.current
        let dayTransactions = state.transactions.filter { calendar.isDate($0.date, inSameDayAs: day) }

        let expenses = dayTransactions
            .filter { $0.kind == .expense }
            .reduce(0) { $0 + $1.amount }
        let income = dayTransactions
            .filter { $0.kind == .income }
            .reduce(0) { $0 + $1.amount }

        return (income, expenses)
    }

    var todaySpentAmount: Int {
        let calendar = Calendar.current
        let todayTransactions = state.transactions.filter { calendar.isDateInToday($0.date) }

        if todayTransactions.isEmpty {
            return state.today.spentAmount
        }

        return finalSpending(on: Date())
    }

    var monthlySpendingSummaries: [MonthlySummary] {
        let calendar = Calendar.current
        let months = Set(state.transactions.map {
            calendar.date(from: calendar.dateComponents([.year, .month], from: $0.date)) ?? $0.date
        })

        return months
            .sorted()
            .map { month in
                MonthlySummary(
                    month: month,
                    spentAmount: finalSpending(in: month),
                    targetAmount: monthlyTargetAmount(for: month)
                )
            }
    }

    func summary(for month: Date) -> MonthlySummary? {
        let calendar = Calendar.current

        return monthlySpendingSummaries.first {
            calendar.isDate($0.month, equalTo: month, toGranularity: .month)
        }
    }

    func loadRemoteDataIfNeeded() async {
        guard !hasCompletedInitialFetch else { return }
        await reloadRemoteData()
    }

    func reloadRemoteData() async {
        guard pendingRemoteChangeCount == 0 else {
            remoteErrorMessage = "서버에 반영되지 않은 변경사항이 있어요."
            hasCompletedInitialFetch = true
            return
        }

        isLoadingRemoteData = true
        remoteErrorMessage = nil
        defer {
            isLoadingRemoteData = false
            hasCompletedInitialFetch = true
        }

        do {
            let snapshot = try await backend.fetchSnapshot()
            apply(snapshot: snapshot)
            lastRemoteSyncAt = Date()
            pendingRemoteChangeCount = 0
            save()
        } catch where error.isCancellation {
        } catch {
            remoteErrorMessage = error.localizedDescription
        }
    }

    func dismissRemoteError() {
        remoteErrorMessage = nil
    }

    private func finalSpending(in month: Date) -> Int {
        let calendar = Calendar.current
        let monthTransactions = state.transactions.filter {
            calendar.isDate($0.date, equalTo: month, toGranularity: .month)
        }

        let expenses = monthTransactions
            .filter { $0.kind == .expense }
            .reduce(0) { $0 + $1.amount }
        let income = monthTransactions
            .filter { $0.kind == .income }
            .reduce(0) { $0 + $1.amount }

        return expenses - income
    }

    private func hasTransactions(in month: Date) -> Bool {
        let calendar = Calendar.current
        return state.transactions.contains {
            calendar.isDate($0.date, equalTo: month, toGranularity: .month)
        }
    }

    private func monthlyTargetAmount(for month: Date) -> Int {
        let calendar = Calendar.current
        return state.monthlySummaries.first {
            calendar.isDate($0.month, equalTo: month, toGranularity: .month)
        }?.targetAmount ?? 0
    }

    private var goalBalanceAllocations: [SavingsGoal.ID: Int] {
        let goals = state.activeGoals
        var allocations = Dictionary(uniqueKeysWithValues: goals.map { ($0.id, 0) })
        var remainingBalance = max(state.currentBalance - state.minimumBalance, 0)
        var activeGoals = goals.filter { $0.targetAmount > 0 }

        while remainingBalance > 0 && !activeGoals.isEmpty {
            activeGoals.sort { lhs, rhs in
                if lhs.dueDate == rhs.dueDate {
                    return lhs.id.uuidString < rhs.id.uuidString
                }

                return lhs.dueDate < rhs.dueDate
            }

            let share = remainingBalance / activeGoals.count
            let remainder = remainingBalance % activeGoals.count

            if share == 0 {
                for goal in activeGoals.prefix(remainder) {
                    let current = allocations[goal.id, default: 0]
                    guard current < goal.targetAmount else { continue }

                    allocations[goal.id] = current + 1
                    remainingBalance -= 1
                }
            } else {
                for (index, goal) in activeGoals.enumerated() {
                    let current = allocations[goal.id, default: 0]
                    let room = max(goal.targetAmount - current, 0)
                    let proposed = share + (index < remainder ? 1 : 0)
                    let granted = min(proposed, room)

                    allocations[goal.id] = current + granted
                    remainingBalance -= granted
                }
            }

            activeGoals = activeGoals.filter {
                allocations[$0.id, default: 0] < $0.targetAmount
            }
        }

        return allocations
    }

    private func resolveGoal(id: SavingsGoal.ID, status: SavingsGoal.Status) {
        guard let index = state.goals.firstIndex(where: { $0.id == id }) else {
            return
        }

        state.goals[index].status = status
        state.goals[index].completedAt = Date()
    }

    private func syncTodayBudget() {
        let initialAllowance = state.today.initialAllowance
        let adjustment = state.today.adjustment
        Task {
            await runRemoteMutation {
                let today = try await backend.updateToday(
                    initialAllowance: initialAllowance,
                    adjustment: adjustment
                )
                state.today.initialAllowance = today.initialAllowance
                state.today.adjustment = today.adjustment
                save()
            }
        }
    }

    private func runRemoteMutation(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            lastRemoteSyncAt = Date()
            pendingRemoteChangeCount = max(pendingRemoteChangeCount - 1, 0)
            remoteErrorMessage = nil
        } catch where error.isCancellation {
        } catch {
            pendingRemoteChangeCount += 1
            remoteErrorMessage = error.localizedDescription
        }
    }

    private func apply(snapshot: BackendSnapshot) {
        state = FinanceState(
            goals: snapshot.goals.map {
                $0.savingsGoal
            },
            currentBalance: snapshot.balance.currentBalance,
            minimumBalance: snapshot.balance.minimumBalance,
            today: DailyBudget(
                initialAllowance: snapshot.today.initialAllowance,
                spentAmount: state.today.spentAmount,
                adjustment: snapshot.today.adjustment
            ),
            transactions: snapshot.transactions.map {
                Transaction(
                    id: $0.id,
                    date: $0.date,
                    title: $0.title,
                    amount: $0.amount,
                    kind: $0.kind
                )
            },
            monthlySummaries: state.monthlySummaries,
            selectedMonth: state.selectedMonth
        )
    }

    private func replaceGoal(id: SavingsGoal.ID, with backendGoal: BackendGoal) {
        guard let index = state.goals.firstIndex(where: { $0.id == id }) else {
            return
        }

        state.goals[index] = backendGoal.savingsGoal
        save()
    }

    private func moveSelectedMonth(by value: Int) {
        let calendar = Calendar.current

        guard let nextMonth = calendar.date(byAdding: .month, value: value, to: state.selectedMonth) else {
            return
        }

        state.selectedMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: nextMonth)) ?? nextMonth
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL) else {
            save()
            return
        }

        do {
            state = try decoder.decode(FinanceState.self, from: data)
        } catch {
            state = .empty
            save()
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(state)
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: storeURL, options: [.atomic])
        } catch {
            assertionFailure("Failed to save finance state: \(error)")
        }
    }

    private var storeURL: URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return directory.appendingPathComponent(fileName)
    }
}

private extension Error {
    var isCancellation: Bool {
        if self is CancellationError {
            return true
        }

        if let urlError = self as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = self as NSError
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        let description = localizedDescription.lowercased()
        return description.contains("cancel") || description.contains("취소")
    }
}

private extension BackendGoal {
    var savingsGoal: SavingsGoal {
        SavingsGoal(
            id: id,
            title: title,
            targetAmount: targetAmount,
            dueDate: dueDate,
            status: status,
            completedAt: completedAt
        )
    }
}
