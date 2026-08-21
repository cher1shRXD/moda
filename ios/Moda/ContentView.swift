import Charts
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: FinanceStore
    @State private var goalSheet: GoalSheet?
    @State private var adjustmentSheet: AllowanceAdjustmentSheet?
    @State private var calendarDaySheet: CalendarDaySheet?
    @State private var selectedCalendarDay: Date?
    @State private var isMinimumBalanceSheetPresented = false
    @State private var hasAppeared = false

    var body: some View {
        let showsSkeleton = store.isLoadingRemoteData && !store.hasCompletedInitialFetch

        ZStack {
            AifiTheme.Color.background
                .ignoresSafeArea()

            NavigationStack {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: AifiTheme.Space.section) {
                        header
                            .staggeredEntrance(index: 0, isActive: hasAppeared)
                        Group {
                            if showsSkeleton {
                                initialAllowanceSkeletonLine
                            } else {
                                initialAllowanceLine
                            }
                        }
                            .staggeredEntrance(index: 1, isActive: hasAppeared)
                        Group {
                            if showsSkeleton {
                                todayHeroSkeleton
                            } else {
                                todayHero
                            }
                        }
                            .staggeredEntrance(index: 2, isActive: hasAppeared)
                        Group {
                            if showsSkeleton {
                                allowanceActionsSkeleton
                            } else {
                                allowanceActions
                            }
                        }
                            .staggeredEntrance(index: 3, isActive: hasAppeared)
                        Group {
                            if showsSkeleton {
                                goalAreaSkeleton
                            } else {
                                goalArea
                            }
                        }
                            .staggeredEntrance(index: 4, isActive: hasAppeared)
                        Group {
                            if showsSkeleton {
                                reportPanelSkeleton
                            } else {
                                reportPanel
                            }
                        }
                            .staggeredEntrance(index: 5, isActive: hasAppeared)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 92)
                }
                .ignoresSafeArea(.container, edges: .bottom)
                .background(AifiTheme.Color.background.ignoresSafeArea())
                .navigationBarHidden(true)
                .onAppear {
                    guard !hasAppeared else { return }
                    DispatchQueue.main.async {
                        hasAppeared = true
                    }
                }
                .onChange(of: store.state.selectedMonth) { _, _ in
                    selectedCalendarDay = nil
                    calendarDaySheet = nil
                }
                .task {
                    await store.loadRemoteDataIfNeeded()
                }
                .sheet(item: $goalSheet) { sheet in
                    switch sheet {
                    case .add:
                        GoalEditorView(goal: nil) { title, target, dueDate in
                            store.addGoal(
                                title: title,
                                targetAmount: target,
                                dueDate: dueDate
                            )
                        }
                    case .edit(let goal):
                        let isGoalReached = store.remainingAmount(for: goal) == 0

                        GoalEditorView(goal: goal, isGoalReached: isGoalReached, onResolveGoal: {
                            if isGoalReached {
                                store.useGoalAmount(id: goal.id)
                            } else {
                                store.releaseGoal(id: goal.id)
                            }
                        }) { title, target, dueDate in
                            store.updateGoal(
                                id: goal.id,
                                title: title,
                                targetAmount: target,
                                dueDate: dueDate
                            )
                        }
                    }
                }
                .sheet(item: $adjustmentSheet) { sheet in
                    AllowanceAdjustmentView(kind: sheet) { amount in
                        switch sheet {
                        case .borrow:
                            store.borrowFromFuture(amount: amount)
                        case .defer:
                            store.deferAllowance(amount: amount)
                        }
                    }
                    .presentationDetents([.height(430)])
                    .presentationDragIndicator(.visible)
                }
                .sheet(item: $calendarDaySheet) { sheet in
                    let totals = store.dailyTotals(on: sheet.date)

                    DailySpendingView(
                        date: sheet.date,
                        income: totals.income,
                        expense: totals.expense,
                        amount: store.finalSpending(on: sheet.date)
                    )
                    .presentationDetents([.height(320)])
                        .presentationDragIndicator(.visible)
                }
                .sheet(isPresented: $isMinimumBalanceSheetPresented) {
                    MinimumBalanceView(amount: store.state.minimumBalance) { amount in
                        store.updateMinimumBalance(amount)
                    }
                    .presentationDetents([.height(330)])
                    .presentationDragIndicator(.visible)
                }
            }

            GeometryReader { proxy in
                edgeFade(.top)
                    .frame(width: proxy.size.width + 160, height: 112)
                    .position(x: proxy.size.width / 2, y: 26)

                edgeFade(.bottom)
                    .frame(width: proxy.size.width + 160, height: 164)
                    .position(x: proxy.size.width / 2, y: proxy.size.height - 24)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .tint(AifiTheme.Color.purple)
        .preferredColorScheme(.dark)
        .environment(\.countUpEnabled, store.hasCompletedInitialFetch)
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("모다.")
                    .font(AifiTheme.Font.logo)
                    .fontWeight(.heavy)
                    .foregroundStyle(AifiTheme.Color.text)
            }

            Spacer()
        }
    }

    private var todayHero: some View {
        let todaySpentAmount = store.todaySpentAmount
        let currentAllowance = store.state.today.currentAllowance
        let remaining = currentAllowance - todaySpentAmount
        let available = max(remaining, 0)
        let usage = min(currentAllowance > 0 ? Double(todaySpentAmount) / Double(currentAllowance) : 1, 1)
        let usagePercent = "\(Int((usage * 100).rounded()))%"

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(AifiTheme.Color.heroGradient)

            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("오늘")
                        .font(AifiTheme.Font.label)
                        .foregroundStyle(.white.opacity(0.72))

                    CountUpText(value: available)
                        .font(AifiTheme.Font.display)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.58)
                        .contentTransition(.numericText())
                }

                Spacer(minLength: 22)

                GeometryReader { proxy in
                    let fillWidth = min(proxy.size.width, max(8, proxy.size.width * usage))

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(.white.opacity(0.22))

                        Capsule()
                            .fill(.white)
                            .frame(width: fillWidth)

                        HStack {
                            Spacer()
                            Text(usagePercent)
                                .font(AifiTheme.Font.microStrong)
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(.trailing, 10)
                        }

                        HStack {
                            Spacer()
                            Text(usagePercent)
                                .font(AifiTheme.Font.microStrong)
                                .foregroundStyle(AifiTheme.Color.purple)
                                .padding(.trailing, 10)
                        }
                        .mask(alignment: .leading) {
                            Rectangle()
                                .frame(width: fillWidth)
                        }
                    }
                }
                .frame(height: 22)
            }
            .padding(22)
        }
        .frame(minHeight: 184)
    }

    private func edgeFade(_ edge: VerticalEdge) -> some View {
        Rectangle()
            .fill(edge == .top ? AifiTheme.Color.topEdgeFade : AifiTheme.Color.bottomEdgeFade)
            .blur(radius: edge == .top ? 5 : 8)
    }

    private var initialAllowanceLine: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("오늘 예산")
                .font(AifiTheme.Font.caption)
                .foregroundStyle(AifiTheme.Color.muted)

            Spacer()

            CountUpText(value: store.state.today.initialAllowance)
                .font(AifiTheme.Font.metric)
                .foregroundStyle(AifiTheme.Color.text)
        }
    }

    private var initialAllowanceSkeletonLine: some View {
        HStack {
            SkeletonBlock(width: 72, height: 15, cornerRadius: 8)
            Spacer()
            SkeletonBlock(width: 112, height: 20, cornerRadius: 10)
        }
    }

    private var todayHeroSkeleton: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(AifiTheme.Color.heroGradient)

            VStack(alignment: .leading, spacing: 20) {
                SkeletonBlock(width: 44, height: 14, cornerRadius: 7, opacity: 0.28)
                SkeletonBlock(width: 210, height: 56, cornerRadius: 18, opacity: 0.34)
                Spacer(minLength: 22)
                SkeletonBlock(height: 22, cornerRadius: 11, opacity: 0.28)
            }
            .padding(22)
        }
        .frame(minHeight: 184)
    }

    private var allowanceActions: some View {
        HStack(spacing: 12) {
            Button {
                adjustmentSheet = .borrow
            } label: {
                Text("당겨쓰기")
            }
            .buttonStyle(AifiActionButtonStyle(kind: .filled))

            Button {
                adjustmentSheet = .defer
            } label: {
                Text("미뤄쓰기")
            }
            .buttonStyle(AifiActionButtonStyle(kind: .plain))
        }
    }

    private var allowanceActionsSkeleton: some View {
        HStack(spacing: 12) {
            SkeletonBlock(height: 54, cornerRadius: 27)
            SkeletonBlock(height: 54, cornerRadius: 27)
        }
    }

    private var goalArea: some View {
        VStack(spacing: 10) {
            goalPanel
            minimumBalanceButton
        }
    }

    private var goalAreaSkeleton: some View {
        VStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    SkeletonBlock(width: 56, height: 22, cornerRadius: 9)
                    SkeletonBlock(width: 98, height: 15, cornerRadius: 7)
                    Spacer()
                    SkeletonBlock(width: 34, height: 34, cornerRadius: 17)
                }

                VStack(spacing: 18) {
                    ForEach(0..<3, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                SkeletonBlock(width: index == 1 ? 58 : 74, height: 15, cornerRadius: 7)
                                Spacer()
                                SkeletonBlock(width: 42, height: 15, cornerRadius: 7)
                            }
                            SkeletonBlock(width: index == 2 ? 190 : 230, height: 12, cornerRadius: 6)
                        }
                    }
                }
            }
            .padding(20)
            .background(AifiTheme.Color.panelSoft, in: RoundedRectangle(cornerRadius: 28, style: .continuous))

            SkeletonBlock(height: 50, cornerRadius: 25)
        }
    }

    private var goalPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("목표")
                    .font(AifiTheme.Font.title)
                    .foregroundStyle(AifiTheme.Color.text)

                CountUpText(value: store.remainingGoalAmount)
                    .font(AifiTheme.Font.goalRemaining)
                    .foregroundStyle(AifiTheme.Color.muted)

                Spacer()

                Button {
                    goalSheet = .add
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(AifiIconButtonStyle())
            }

            VStack(spacing: 0) {
                ForEach(store.state.activeGoals) { goal in
                    goalRowButton(goal)

                    if goal.id != store.state.activeGoals.last?.id {
                        Divider()
                            .overlay(AifiTheme.Color.stroke)
                            .padding(.vertical, 14)
                    }
                }
            }
        }
        .padding(20)
        .background(AifiTheme.Color.panelSoft, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private var minimumBalanceButton: some View {
        Button {
            isMinimumBalanceSheetPresented = true
        } label: {
            MinimumBalanceRow(amount: store.state.minimumBalance)
        }
        .buttonStyle(.plain)
    }

    private var reportPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                Text("이번 달 흐름")
                    .font(AifiTheme.Font.title)
                    .foregroundStyle(AifiTheme.Color.text)

                Spacer()

                monthControl
            }

            monthlyGraph
                .padding(.bottom, 32)
            WeekCalendarStrip(
                month: store.state.selectedMonth,
                selectedDay: $selectedCalendarDay,
                expenses: { day in
                    store.expenses(on: day)
                }
            ) { day in
                calendarDaySheet = CalendarDaySheet(date: day)
            }
            .padding(.bottom, 24)
        }
    }

    private var reportPanelSkeleton: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SkeletonBlock(width: 106, height: 22, cornerRadius: 9)
                Spacer()
                SkeletonBlock(width: 96, height: 32, cornerRadius: 16)
            }

            VStack(alignment: .leading, spacing: 18) {
                SkeletonBlock(height: 190, cornerRadius: 24)
                    .padding(.top, 16)

                HStack(spacing: 22) {
                    SkeletonBlock(height: 38, cornerRadius: 12)
                    Rectangle()
                        .fill(AifiTheme.Color.stroke)
                        .frame(width: 1, height: 34)
                    SkeletonBlock(height: 38, cornerRadius: 12)
                }
            }
            .padding(.bottom, 48)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 8) {
                ForEach(0..<35, id: \.self) { index in
                    VStack(spacing: 7) {
                        SkeletonBlock(width: 16, height: 11, cornerRadius: 5)
                        SkeletonBlock(width: index % 4 == 0 ? 10 : 7, height: index % 4 == 0 ? 10 : 7, cornerRadius: 5)
                    }
                    .frame(height: 42)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 24)
        }
    }

    private var monthControl: some View {
        HStack(spacing: 2) {
            Button {
                store.selectPreviousMonth()
            } label: {
                Image(systemName: "play.fill")
                    .rotationEffect(.degrees(180))
            }
            .buttonStyle(AifiMiniButtonStyle())

            Text(store.state.selectedMonth.shortMonthTitle)
                .font(AifiTheme.Font.captionStrong)
                .foregroundStyle(AifiTheme.Color.text)
                .frame(minWidth: 34)

            Button {
                store.selectNextMonth()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(AifiMiniButtonStyle())
        }
    }

    private var monthlyGraph: some View {
        VStack(alignment: .leading, spacing: 18) {
            Chart(store.monthlySpendingSummaries) { summary in
                AreaMark(
                    x: .value("월", summary.month.shortMonthTitle),
                    y: .value("소비", summary.spentAmount)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(AifiTheme.Color.chartFill)

                LineMark(
                    x: .value("월", summary.month.shortMonthTitle),
                    y: .value("소비", summary.spentAmount)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .foregroundStyle(AifiTheme.Color.purple)

                PointMark(
                    x: .value("월", summary.month.shortMonthTitle),
                    y: .value("소비", summary.spentAmount)
                )
                .symbolSize(42)
                .foregroundStyle(AifiTheme.Color.purple)

            }
            .frame(height: 190)
            .padding(.top, 16)
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label)
                                .foregroundStyle(AifiTheme.Color.muted)
                                .font(AifiTheme.Font.micro)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let amount = value.as(Int.self) {
                            Text("\(amount / 10_000)")
                                .foregroundStyle(AifiTheme.Color.muted)
                                .font(AifiTheme.Font.micro)
                        }
                    }
                }
            }

            comparisonSummary
        }
    }

    private var comparisonSummary: some View {
        let selected = store.summary(for: store.state.selectedMonth)
        let previousMonth = Calendar.current.date(byAdding: .month, value: -1, to: store.state.selectedMonth)
        let previous = previousMonth.flatMap { store.summary(for: $0) }
        let delta = (selected?.spentAmount ?? 0) - (previous?.spentAmount ?? 0)
        let amountToCut = selected?.amountToCut ?? 0

        return HStack(spacing: 22) {
            GraphMetric(
                title: "직전 달 대비",
                amount: abs(delta),
                prefix: delta >= 0 ? "+" : "-",
                tint: AifiTheme.Color.purple
            )

            Rectangle()
                .fill(AifiTheme.Color.stroke)
                .frame(width: 1, height: 34)

            GraphMetric(
                title: "줄일 금액",
                amount: amountToCut,
                tint: AifiTheme.Color.purple
            )
        }
    }

    private func goalRowButton(_ goal: SavingsGoal) -> some View {
        Button {
            goalSheet = .edit(goal)
        } label: {
            GoalRow(
                goal: goal,
                progress: store.progress(for: goal),
                remainingAmount: store.remainingAmount(for: goal)
            )
        }
        .buttonStyle(.plain)
    }
}

private enum GoalSheet: Identifiable {
    case add
    case edit(SavingsGoal)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let goal):
            return goal.id.uuidString
        }
    }
}

private enum AllowanceAdjustmentSheet: String, Identifiable {
    case borrow
    case `defer`

    var id: String { rawValue }

    var title: String {
        switch self {
        case .borrow:
            return "얼마나 당겨쓸까요?"
        case .defer:
            return "얼마나 미뤄쓸까요?"
        }
    }

    var actionTitle: String {
        switch self {
        case .borrow:
            return "당겨쓰기"
        case .defer:
            return "미뤄쓰기"
        }
    }
}

private struct CalendarDaySheet: Identifiable {
    let date: Date

    var id: Date { date }
}

private struct GoalRow: View {
    let goal: SavingsGoal
    let progress: Double
    let remainingAmount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(goal.title)
                    .font(AifiTheme.Font.goalTitle)
                    .foregroundStyle(AifiTheme.Color.text)

                Spacer()

                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(AifiTheme.Font.goalValue)
                    .foregroundStyle(AifiTheme.Color.purple)
            }

            HStack {
                HStack(spacing: 2) {
                    Text("남은 금액")
                    CountUpText(value: remainingAmount)
                }
                Spacer()
                Text(goal.dueDate.formatted(.dateTime.year().month().day()))
            }
            .font(AifiTheme.Font.goalMeta)
            .foregroundStyle(AifiTheme.Color.muted)
        }
        .padding(.vertical, 2)
    }
}

private struct MinimumBalanceRow: View {
    let amount: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("남겨둘 돈")
                .font(AifiTheme.Font.goalTitle)
                .foregroundStyle(AifiTheme.Color.text)

            Spacer()

            CountUpText(value: amount)
                .font(AifiTheme.Font.goalValue)
                .foregroundStyle(AifiTheme.Color.purple)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(AifiTheme.Color.panelSoft.opacity(0.78), in: Capsule())
    }
}

private struct AllowanceAdjustmentView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Int = 10_000

    let kind: AllowanceAdjustmentSheet
    let onApply: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text(kind.title)
                .font(AifiTheme.Font.title)
                .foregroundStyle(AifiTheme.Color.text)

            HStack(spacing: 8) {
                TextField("금액 입력", value: $amount, format: .number)
                    .font(AifiTheme.Font.title)
                    .foregroundStyle(AifiTheme.Color.text)
                    .keyboardType(.numberPad)

                Text("원")
                    .font(AifiTheme.Font.title)
                    .foregroundStyle(AifiTheme.Color.muted)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(AifiTheme.Color.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AifiTheme.Color.stroke)
            }
            .onChange(of: amount) { _, newValue in
                amount = max(0, newValue)
            }

            HStack(spacing: 10) {
                ForEach([1_000, 5_000, 10_000], id: \.self) { value in
                    Button {
                        amount += value
                    } label: {
                        Text("+\(value.wonText)")
                    }
                    .buttonStyle(AifiAmountChipStyle(isSelected: false))
                }
            }

            Spacer(minLength: 0)

            Button {
                onApply(amount)
                dismiss()
            } label: {
                Text(kind.actionTitle)
            }
            .buttonStyle(AifiActionButtonStyle(kind: .filled))
            .disabled(amount <= 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 40)
        .padding(.bottom, 18)
        .safeAreaPadding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AifiTheme.Color.background)
        .preferredColorScheme(.dark)
    }
}

private struct MinimumBalanceView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var amount: Int

    let onSave: (Int) -> Void

    init(amount: Int, onSave: @escaping (Int) -> Void) {
        _amount = State(initialValue: amount)
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("남겨둘 돈")
                .font(AifiTheme.Font.title)
                .foregroundStyle(AifiTheme.Color.text)

            HStack(spacing: 8) {
                TextField("금액 입력", value: $amount, format: .number)
                    .font(AifiTheme.Font.title)
                    .foregroundStyle(AifiTheme.Color.text)
                    .keyboardType(.numberPad)

                Text("원")
                    .font(AifiTheme.Font.title)
                    .foregroundStyle(AifiTheme.Color.muted)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(AifiTheme.Color.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AifiTheme.Color.stroke)
            }
            .onChange(of: amount) { _, newValue in
                amount = max(0, newValue)
            }

            Spacer(minLength: 0)

            Button {
                onSave(amount)
                dismiss()
            } label: {
                Text("저장")
            }
            .buttonStyle(AifiActionButtonStyle(kind: .filled))
        }
        .padding(.horizontal, 22)
        .padding(.top, 40)
        .padding(.bottom, 18)
        .safeAreaPadding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AifiTheme.Color.background)
        .preferredColorScheme(.dark)
    }
}

private struct DailySpendingView: View {
    let date: Date
    let income: Int
    let expense: Int
    let amount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(date.formatted(.dateTime.month().day()))
                    .font(AifiTheme.Font.captionStrong)
                    .foregroundStyle(AifiTheme.Color.muted)

                Text("최종 지출")
                    .font(AifiTheme.Font.title)
                    .foregroundStyle(AifiTheme.Color.text)
            }

            CountUpText(value: amount)
                .font(AifiTheme.Font.sheetAmount)
                .foregroundStyle(AifiTheme.Color.purple)

            VStack(spacing: 12) {
                DailyAmountRow(title: "지출", amount: expense)
                DailyAmountRow(title: "수입", amount: income)
            }
            .padding(.top, 2)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 40)
        .padding(.bottom, 18)
        .safeAreaPadding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AifiTheme.Color.background)
        .preferredColorScheme(.dark)
    }
}

private struct DailyAmountRow: View {
    let title: String
    let amount: Int

    var body: some View {
        HStack {
            Text(title)
                .font(AifiTheme.Font.captionStrong)
                .foregroundStyle(AifiTheme.Color.muted)

            Spacer()

            CountUpText(value: amount)
                .font(AifiTheme.Font.captionStrong)
                .foregroundStyle(AifiTheme.Color.text)
        }
    }
}

private struct MetricPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AifiTheme.Font.caption)
                .foregroundStyle(AifiTheme.Color.muted)

            Text(value)
                .font(AifiTheme.Font.metric)
                .foregroundStyle(AifiTheme.Color.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AifiTheme.Color.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct FlowCard: View {
    let title: String
    let value: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AifiTheme.Font.caption)
                .foregroundStyle(AifiTheme.Color.muted)

            Text(value)
                .font(AifiTheme.Font.metric)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(AifiTheme.Color.panelSoft, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct GraphMetric: View {
    let title: String
    let amount: Int
    var prefix = ""
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AifiTheme.Font.micro)
                .foregroundStyle(AifiTheme.Color.muted)

            CountUpText(value: amount, prefix: prefix)
                .font(AifiTheme.Font.captionStrong)
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CountUpText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.countUpEnabled) private var countUpEnabled
    @State private var progress: Double = 0

    let value: Int
    var prefix = ""
    var suffix = "원"

    var body: some View {
        ZStack(alignment: .leading) {
            Text(finalText)
                .hidden()

            Text("")
                .modifier(CountUpTextModifier(
                    progress: progress,
                    targetText: targetText,
                    prefix: displayPrefix,
                    suffix: suffix
                ))
                .contentTransition(.numericText())
        }
        .monospacedDigit()
        .onAppear {
            if countUpEnabled {
                startCountUp()
            }
        }
        .onChange(of: value) { _, _ in
            if countUpEnabled {
                startCountUp()
            }
        }
        .onChange(of: countUpEnabled) { _, isEnabled in
            if isEnabled {
                startCountUp()
            } else {
                progress = 0
            }
        }
    }

    private var targetText: String {
        abs(value).formatted(.number)
    }

    private var displayPrefix: String {
        if value < 0 { return "-" }
        return prefix
    }

    private var finalText: String {
        "\(displayPrefix)\(targetText)\(suffix)"
    }

    private func startCountUp() {
        if reduceMotion {
            progress = 1
        } else {
            var transaction = SwiftUI.Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                progress = 0
            }

            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 1.08)) {
                    progress = 1
                }
            }
        }
    }
}

private struct CountUpTextModifier: @preconcurrency AnimatableModifier {
    var progress: Double
    let targetText: String
    let prefix: String
    let suffix: String

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        Text("\(prefix)\(animatedText)\(suffix)")
    }

    private var animatedText: String {
        targetText.map { character in
            guard let targetDigit = character.wholeNumberValue else {
                return String(character)
            }

            let currentDigit = Int((Double(targetDigit) * progress).rounded())
            return String(min(currentDigit, targetDigit))
        }
        .joined()
    }
}

private struct CountUpEnabledKey: EnvironmentKey {
    static let defaultValue = true
}

private extension EnvironmentValues {
    var countUpEnabled: Bool {
        get { self[CountUpEnabledKey.self] }
        set { self[CountUpEnabledKey.self] = newValue }
    }
}

private struct SkeletonBlock: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHighlighted = false

    var width: CGFloat?
    var height: CGFloat
    var cornerRadius: CGFloat
    var opacity: Double = 1

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        AifiTheme.Color.skeleton,
                        AifiTheme.Color.skeletonHighlight.opacity(isHighlighted ? 1 : 0.42),
                        AifiTheme.Color.skeleton
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .opacity(opacity)
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                    isHighlighted = true
                }
            }
    }
}

private struct StaggeredEntranceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let index: Int
    let isActive: Bool
    let step: Double
    let offset: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(isActive ? 1 : 0)
            .offset(y: reduceMotion || isActive ? 0 : offset)
            .animation(
                reduceMotion ? nil : .spring(response: 0.64, dampingFraction: 0.9)
                    .delay(Double(index) * step),
                value: isActive
            )
    }
}

private struct WeekCalendarStrip: View {
    let month: Date
    @Binding var selectedDay: Date?
    let expenses: (Date) -> Int
    let onSelect: (Date) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(days, id: \.self) { day in
                    Button {
                        selectedDay = day
                        onSelect(day)
                    } label: {
                        DayDot(day: day, amount: expenses(day), isSelected: isSelected(day))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 7)
    }

    private var days: [Date] {
        let calendar = Calendar.current
        guard
            let range = calendar.range(of: .day, in: .month, for: month),
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: month))
        else {
            return []
        }

        return range.compactMap { day in
            calendar.date(byAdding: .day, value: day - 1, to: monthStart)
        }
    }

    private func isSelected(_ day: Date) -> Bool {
        guard let selectedDay else { return false }
        return Calendar.current.isDate(day, inSameDayAs: selectedDay)
    }
}

private struct DayDot: View {
    let day: Date
    let amount: Int
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
            Text(day, format: .dateTime.day())
                .font(AifiTheme.Font.microStrong)
                .foregroundStyle(dayColor)

            Circle()
                .fill(dotColor)
                .frame(width: dotSize, height: dotSize)
        }
        .frame(height: 42)
        .frame(maxWidth: .infinity)
        .background(
            cellBackground,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }

    private var cellBackground: Color {
        if isSelected { return AifiTheme.Color.purple.opacity(0.18) }
        if Calendar.current.isDateInToday(day) { return AifiTheme.Color.purple.opacity(0.10) }
        return Color.clear
    }

    private var dayColor: Color {
        if isSelected { return AifiTheme.Color.text }
        return Calendar.current.isDateInToday(day) ? AifiTheme.Color.text : AifiTheme.Color.muted
    }

    private var dotColor: Color {
        if amount == 0 { return AifiTheme.Color.stroke }
        return AifiTheme.Color.purple
    }

    private var dotSize: CGFloat {
        if amount == 0 { return 4 }
        return amount > 30_000 ? 10 : 7
    }
}

private struct GoalEditorView: View {
    @Environment(\.dismiss) private var dismiss

    private let goal: SavingsGoal?
    private let isGoalReached: Bool
    @State private var title: String
    @State private var targetAmount: Int
    @State private var dueDate: Date
    @State private var showsResolveConfirmation = false

    let onSave: (String, Int, Date) -> Void
    let onResolveGoal: (() -> Void)?

    init(goal: SavingsGoal?, isGoalReached: Bool = false, onResolveGoal: (() -> Void)? = nil, onSave: @escaping (String, Int, Date) -> Void) {
        let defaultDueDate = Calendar.current.date(byAdding: .month, value: 6, to: Date()) ?? Date()
        self.goal = goal
        self.isGoalReached = isGoalReached
        _title = State(initialValue: goal?.title ?? "")
        _targetAmount = State(initialValue: goal?.targetAmount ?? 1_000_000)
        _dueDate = State(initialValue: goal?.dueDate ?? defaultDueDate)
        self.onResolveGoal = onResolveGoal
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("목표 이름", text: $title)
                    CurrencyInput(title: "목표 금액", value: $targetAmount)
                    DatePicker("목표 날짜", selection: $dueDate, displayedComponents: .date)
                }

                if goal != nil {
                    Section {
                        Button {
                            showsResolveConfirmation = true
                        } label: {
                            Text(resolveButtonTitle)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(AifiGoalResolveButtonStyle(kind: isGoalReached ? .use : .release))
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AifiTheme.Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .tint(AifiTheme.Color.purple)
            .preferredColorScheme(.dark)
            .confirmationDialog(resolveConfirmationTitle, isPresented: $showsResolveConfirmation, titleVisibility: .visible) {
                Button(resolveConfirmTitle, role: isGoalReached ? nil : .destructive) {
                    onResolveGoal?()
                    dismiss()
                }

                Button("취소", role: .cancel) {}
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") {
                        onSave(title, targetAmount, dueDate)
                        dismiss()
                    }
                }

                ToolbarItem(placement: .principal) {
                    Text("목표 설정")
                        .font(AifiTheme.Font.sheetTitle)
                        .foregroundStyle(AifiTheme.Color.text)
                }
            }
        }
    }

    private var resolveButtonTitle: String {
        isGoalReached ? "목표 금액 사용" : "목표 해제"
    }

    private var resolveConfirmationTitle: String {
        isGoalReached ? "목표 금액을 사용할까요?" : "목표를 해제할까요?"
    }

    private var resolveConfirmTitle: String {
        isGoalReached ? "사용하고 삭제" : "해제"
    }
}

private struct AifiGoalResolveButtonStyle: ButtonStyle {
    enum Kind {
        case use
        case release
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AifiTheme.Font.label)
            .foregroundStyle(foreground(isPressed: configuration.isPressed))
            .padding(.vertical, 15)
            .background(background(isPressed: configuration.isPressed), in: Capsule())
    }

    private func foreground(isPressed: Bool) -> Color {
        switch kind {
        case .use:
            return AifiTheme.Color.text.opacity(isPressed ? 0.64 : 1)
        case .release:
            return AifiTheme.Color.danger.opacity(isPressed ? 0.58 : 1)
        }
    }

    private func background(isPressed: Bool) -> Color {
        switch kind {
        case .use:
            return AifiTheme.Color.purple.opacity(isPressed ? 0.66 : 0.92)
        case .release:
            return AifiTheme.Color.danger.opacity(isPressed ? 0.10 : 0.16)
        }
    }
}

private struct CurrencyInput: View {
    let title: String
    @Binding var value: Int

    var body: some View {
        TextField(title, value: $value, format: .number)
            .keyboardType(.numberPad)
    }
}

private struct AifiCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AifiTheme.Font.captionStrong)
            .foregroundStyle(AifiTheme.Color.text.opacity(configuration.isPressed ? 0.62 : 1))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(AifiTheme.Color.purple.opacity(0.18), in: Capsule())
    }
}

private struct AifiIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(AifiTheme.Color.text.opacity(configuration.isPressed ? 0.52 : 1))
            .frame(width: 34, height: 34)
            .contentShape(Circle())
    }
}

private struct AifiAmountChipStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AifiTheme.Font.captionStrong)
            .foregroundStyle(AifiTheme.Color.text.opacity(configuration.isPressed ? 0.58 : 1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(chipBackground, in: Capsule())
    }

    private var chipBackground: Color {
        isSelected ? AifiTheme.Color.purple.opacity(0.28) : AifiTheme.Color.panel
    }
}

private struct AifiActionButtonStyle: ButtonStyle {
    enum Kind {
        case filled
        case plain
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AifiTheme.Font.label)
            .foregroundStyle(AifiTheme.Color.text)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 17)
            .background(background(isPressed: configuration.isPressed), in: Capsule())
    }

    private func background(isPressed: Bool) -> AnyShapeStyle {
        switch kind {
        case .filled:
            return AnyShapeStyle(AifiTheme.Color.purple.opacity(isPressed ? 0.72 : 1))
        case .plain:
            return AnyShapeStyle(AifiTheme.Color.panel.opacity(isPressed ? 0.64 : 1))
        }
    }
}

private struct AifiMiniButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AifiTheme.Font.captionStrong)
            .foregroundStyle(AifiTheme.Color.muted.opacity(configuration.isPressed ? 0.52 : 0.9))
            .frame(width: 30, height: 32)
            .contentShape(Rectangle())
    }
}

private enum AifiTheme {
    enum Color {
        static let background = SwiftUI.Color(hex: "#101114")
        static let panel = SwiftUI.Color(hex: "#1A1D24")
        static let panelSoft = SwiftUI.Color(hex: "#151820")
        static let stroke = SwiftUI.Color.white.opacity(0.10)
        static let text = SwiftUI.Color(hex: "#F6F7FA")
        static let muted = SwiftUI.Color(hex: "#8C93A3")
        static let purple = SwiftUI.Color(hex: "#7C5CFF")
        static let danger = SwiftUI.Color(hex: "#FF5C7A")
        static let skeleton = SwiftUI.Color.white.opacity(0.075)
        static let skeletonHighlight = SwiftUI.Color.white.opacity(0.15)
        static let heroGradient = LinearGradient(
            colors: [
                SwiftUI.Color(hex: "#A18DFF"),
                SwiftUI.Color(hex: "#7C5CFF"),
                SwiftUI.Color(hex: "#4A31C8")
            ],
            startPoint: UnitPoint(x: 0.12, y: 0.04),
            endPoint: UnitPoint(x: 0.92, y: 1.0)
        )
        static let purpleGradient = LinearGradient(
            colors: [SwiftUI.Color(hex: "#7C5CFF"), SwiftUI.Color(hex: "#7C5CFF").opacity(0.46)],
            startPoint: .leading,
            endPoint: .trailing
        )
        static let chartFill = LinearGradient(
            colors: [SwiftUI.Color(hex: "#7C5CFF").opacity(0.34), SwiftUI.Color(hex: "#7C5CFF").opacity(0.02)],
            startPoint: .bottom,
            endPoint: .top
        )
        static let topEdgeFade = LinearGradient(
            colors: [
                background,
                background.opacity(0.96),
                background.opacity(0.56),
                background.opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        static let bottomEdgeFade = LinearGradient(
            colors: [
                background.opacity(0),
                background.opacity(0.52),
                background.opacity(0.96),
                background
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    enum Font {
        private static func wantedSans(_ name: String, size: CGFloat) -> SwiftUI.Font {
            SwiftUI.Font.custom(name, size: size)
        }

        static let logo = wantedSans("Jua-Regular", size: 44)
        static let display = wantedSans("Jua-Regular", size: 56)
        static let sheetAmount = wantedSans("WantedSans-Black", size: 38)
        static let title = wantedSans("WantedSans-Bold", size: 20)
        static let metric = wantedSans("WantedSans-Bold", size: 18)
        static let sheetTitle = wantedSans("WantedSans-Bold", size: 16)
        static let goalTitle = wantedSans("WantedSans-SemiBold", size: 14)
        static let goalValue = wantedSans("WantedSans-SemiBold", size: 14)
        static let goalMeta = wantedSans("WantedSans-Medium", size: 11)
        static let goalRemaining = wantedSans("WantedSans-SemiBold", size: 13)
        static let body = wantedSans("WantedSans-Medium", size: 15)
        static let label = wantedSans("WantedSans-Bold", size: 15)
        static let caption = wantedSans("WantedSans-Medium", size: 13)
        static let captionStrong = wantedSans("WantedSans-Bold", size: 13)
        static let badge = wantedSans("WantedSans-Bold", size: 12)
        static let micro = wantedSans("WantedSans-Medium", size: 11)
        static let microStrong = wantedSans("WantedSans-Bold", size: 11)
    }

    enum Space {
        static let section: CGFloat = 18
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)

        let red: UInt64
        let green: UInt64
        let blue: UInt64

        switch cleaned.count {
        case 3:
            red = (value >> 8) * 17
            green = ((value >> 4) & 0xF) * 17
            blue = (value & 0xF) * 17
        default:
            red = value >> 16
            green = (value >> 8) & 0xFF
            blue = value & 0xFF
        }

        self.init(
            red: Double(red) / 255,
            green: Double(green) / 255,
            blue: Double(blue) / 255
        )
    }
}

private extension View {
    func staggeredEntrance(
        index: Int,
        isActive: Bool,
        step: Double = 0.12,
        offset: CGFloat = 34
    ) -> some View {
        modifier(StaggeredEntranceModifier(
            index: index,
            isActive: isActive,
            step: step,
            offset: offset
        ))
    }
}

private extension Int {
    var wonText: String {
        "\(formatted(.number))원"
    }
}

private extension Date {
    var monthTitle: String {
        formatted(.dateTime.year().month(.wide))
    }

    var shortMonthTitle: String {
        formatted(.dateTime.month(.abbreviated))
    }
}
