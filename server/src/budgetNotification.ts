import type { ApnsClient } from "./apns.js";
import type { ModaDatabase } from "./database.js";
import type { TransactionRecord } from "./types.js";

type BudgetSnapshot = {
  currentAllowance: number;
  spentAmount: number;
  availableAmount: number;
  overspentAmount: number;
  usagePercent: number;
};

type NotificationCheckResult = {
  changed: boolean;
  previousAvailableAmount?: number;
  current: BudgetSnapshot;
  sent: number;
  skipped: number;
  failures: Array<{ token: string; reason?: string; status?: number }>;
};

export type TestNotificationKind = "budgetChanged" | "daily";

type NotificationSendSummary = {
  sent: number;
  skipped: number;
  failures: Array<{ token: string; reason?: string; status?: number }>;
};

type NotificationPayload = {
  title: string;
  body: string;
  data?: Record<string, string | number | boolean | null>;
};

const LAST_AVAILABLE_AMOUNT_KEY = "budget:last_available_amount";
const LAST_CHANGE_AT_KEY = "budget:last_change_at";
const DAILY_SUMMARY_SENT_DATE_KEY = "budget:daily_summary_sent_date";

export class BudgetNotificationService {
  constructor(
    private readonly database: ModaDatabase,
    private readonly apnsClient: ApnsClient
  ) {}

  async checkAndNotify(): Promise<NotificationCheckResult> {
    const current = this.snapshot();
    const previousText = this.database.getNotificationState(LAST_AVAILABLE_AMOUNT_KEY);
    const previousAvailableAmount = previousText === undefined ? undefined : Number(previousText);
    const previousChangeAt = this.database.getNotificationState(LAST_CHANGE_AT_KEY);
    const latestChangeAt = this.latestTransactionChangeAt() ?? new Date().toISOString();

    if (previousAvailableAmount === undefined || previousAvailableAmount === current.availableAmount) {
      this.database.setNotificationState(LAST_AVAILABLE_AMOUNT_KEY, String(current.availableAmount));
      this.database.setNotificationState(LAST_CHANGE_AT_KEY, latestChangeAt);
      return {
        changed: false,
        previousAvailableAmount,
        current,
        sent: 0,
        skipped: 0,
        failures: []
      };
    }

    const recentSpending = this.recentSpending(previousChangeAt, latestChangeAt, previousAvailableAmount, current);
    const payload = {
      title: `지난 ${recentSpending.minutes}분간 ${won(recentSpending.amount)}을 사용했어요.`,
      body: `오늘 예산이 이제 ${won(current.availableAmount)} 남았어요.`,
      data: {
        kind: "budget_changed",
        minutes: recentSpending.minutes,
        spentAmount: recentSpending.amount,
        availableAmount: current.availableAmount,
        overspentAmount: current.overspentAmount,
        currentAllowance: current.currentAllowance,
        totalSpentAmount: current.spentAmount,
        usagePercent: current.usagePercent
      }
    };

    const results = await Promise.all(
      this.database.listDeviceTokens().map((token) => this.apnsClient.send(token, payload))
    );
    this.database.setNotificationState(LAST_AVAILABLE_AMOUNT_KEY, String(current.availableAmount));
    this.database.setNotificationState(LAST_CHANGE_AT_KEY, latestChangeAt);

    return {
      changed: true,
      previousAvailableAmount,
      current,
      sent: results.filter((result) => result.sent).length,
      skipped: results.filter((result) => !result.sent && result.reason === "APNs is not configured.").length,
      failures: results
        .filter((result) => !result.sent && result.reason !== "APNs is not configured.")
        .map((result) => ({
          token: result.token,
          reason: result.reason,
          status: result.status
        }))
    };
  }

  async sendDailySummary(): Promise<NotificationCheckResult & { alreadySent: boolean; date: string }> {
    const date = kstDateKey(new Date());
    const lastSentDate = this.database.getNotificationState(DAILY_SUMMARY_SENT_DATE_KEY);
    const current = this.snapshot();

    if (lastSentDate === date) {
      return {
        alreadySent: true,
        date,
        changed: false,
        current,
        sent: 0,
        skipped: 0,
        failures: []
      };
    }

    const payload = {
      title: "오늘 사용 가능한 예산을 계산 했어요",
      body: `오늘 예산은 총 ${won(current.currentAllowance)}이에요. 현재 ${current.usagePercent}% 사용했어요.`,
      data: {
        kind: "daily_budget_summary",
        date,
        availableAmount: current.availableAmount,
        overspentAmount: current.overspentAmount,
        currentAllowance: current.currentAllowance,
        spentAmount: current.spentAmount,
        usagePercent: current.usagePercent
      }
    };

    const results = await Promise.all(
      this.database.listDeviceTokens().map((token) => this.apnsClient.send(token, payload))
    );

    this.database.setNotificationState(DAILY_SUMMARY_SENT_DATE_KEY, date);
    this.database.setNotificationState(LAST_AVAILABLE_AMOUNT_KEY, String(current.availableAmount));
    this.database.setNotificationState(LAST_CHANGE_AT_KEY, this.latestTransactionChangeAt() ?? new Date().toISOString());

    return {
      alreadySent: false,
      date,
      changed: true,
      current,
      sent: results.filter((result) => result.sent).length,
      skipped: results.filter((result) => !result.sent && result.reason === "APNs is not configured.").length,
      failures: results
        .filter((result) => !result.sent && result.reason !== "APNs is not configured.")
        .map((result) => ({
          token: result.token,
          reason: result.reason,
          status: result.status
        }))
    };
  }

  async sendTestNotification(kind: TestNotificationKind): Promise<NotificationSendSummary & {
    kind: TestNotificationKind;
    current: BudgetSnapshot;
    tokenCount: number;
  }> {
    const current = this.snapshot();
    const tokenCount = this.database.listDeviceTokens().length;
    const latestChangeAt = this.latestTransactionChangeAt() ?? new Date().toISOString();
    const previousChangeAt = this.database.getNotificationState(LAST_CHANGE_AT_KEY);
    const recentSpending = this.recentSpending(previousChangeAt, latestChangeAt, undefined, current);
    const payload: NotificationPayload = kind === "budgetChanged"
      ? {
          title: `지난 ${recentSpending.minutes}분간 ${won(recentSpending.amount)}을 사용했어요.`,
          body: `오늘 예산이 이제 ${won(current.availableAmount)} 남았어요.`,
          data: {
            kind: "budget_changed_test",
            minutes: recentSpending.minutes,
            spentAmount: recentSpending.amount,
            availableAmount: current.availableAmount,
            overspentAmount: current.overspentAmount,
            currentAllowance: current.currentAllowance,
            totalSpentAmount: current.spentAmount,
            usagePercent: current.usagePercent
          }
        }
      : {
          title: "오늘 사용 가능한 예산을 계산 했어요",
          body: `오늘 예산은 총 ${won(current.currentAllowance)}이에요. 현재 ${current.usagePercent}% 사용했어요.`,
          data: {
            kind: "daily_budget_summary_test",
            date: kstDateKey(new Date()),
            availableAmount: current.availableAmount,
            overspentAmount: current.overspentAmount,
            currentAllowance: current.currentAllowance,
            spentAmount: current.spentAmount,
            usagePercent: current.usagePercent
          }
        };

    const summary = await this.sendToAll(payload);

    return {
      kind,
      current,
      tokenCount,
      ...summary
    };
  }

  private snapshot(): BudgetSnapshot {
    const budget = this.database.getDailyBudget();
    const currentAllowance = Math.max(budget.initialAllowance + budget.adjustment, 0);
    const spentAmount = netSpending(this.todayTransactions());
    const remainingAmount = currentAllowance - spentAmount;
    const usagePercent = currentAllowance > 0
      ? Math.max(0, Math.round((spentAmount / currentAllowance) * 100))
      : 100;

    return {
      currentAllowance,
      spentAmount,
      availableAmount: Math.max(remainingAmount, 0),
      overspentAmount: Math.max(-remainingAmount, 0),
      usagePercent
    };
  }

  private todayTransactions(): TransactionRecord[] {
    const { start, end } = todayRangeKst();
    return this.database.listTransactions({
      from: start.toISOString(),
      to: end.toISOString()
    });
  }

  private latestTransactionChangeAt(): string | undefined {
    return this.todayTransactions()
      .map((transaction) => transaction.updatedAt || transaction.createdAt)
      .sort()
      .at(-1);
  }

  private recentSpending(
    previousChangeAt: string | undefined,
    latestChangeAt: string,
    previousAvailableAmount: number | undefined,
    current: BudgetSnapshot
  ): { minutes: number; amount: number } {
    const latestTime = Date.parse(latestChangeAt);
    const previousTime = previousChangeAt ? Date.parse(previousChangeAt) : latestTime;
    const validPreviousTime = Number.isFinite(previousTime) ? previousTime : latestTime;
    const validLatestTime = Number.isFinite(latestTime) ? latestTime : validPreviousTime;
    const minutes = Math.max(1, Math.ceil((validLatestTime - validPreviousTime) / 60_000));
    const amount = this.todayTransactions()
      .filter((transaction) => {
        const changedAt = Date.parse(transaction.updatedAt || transaction.createdAt);
        return transaction.kind === "expense" &&
          Number.isFinite(changedAt) &&
          changedAt > validPreviousTime &&
          changedAt <= validLatestTime;
      })
      .reduce((total, transaction) => total + transaction.amount, 0);

    if (amount > 0) {
      return { minutes, amount };
    }

    const fallbackAmount = previousAvailableAmount === undefined
      ? 0
      : Math.max(previousAvailableAmount - current.availableAmount, 0);
    return { minutes, amount: fallbackAmount };
  }

  private async sendToAll(payload: NotificationPayload): Promise<NotificationSendSummary> {
    const results = await Promise.all(
      this.database.listDeviceTokens().map((token) => this.apnsClient.send(token, payload))
    );

    return {
      sent: results.filter((result) => result.sent).length,
      skipped: results.filter((result) => !result.sent && result.reason === "APNs is not configured.").length,
      failures: results
        .filter((result) => !result.sent && result.reason !== "APNs is not configured.")
        .map((result) => ({
          token: result.token,
          reason: result.reason,
          status: result.status
        }))
    };
  }
}

export function kstDateKey(date: Date): string {
  const kst = new Date(date.getTime() + 9 * 60 * 60 * 1000);
  const year = kst.getUTCFullYear();
  const month = `${kst.getUTCMonth() + 1}`.padStart(2, "0");
  const day = `${kst.getUTCDate()}`.padStart(2, "0");

  return `${year}-${month}-${day}`;
}

function netSpending(transactions: TransactionRecord[]): number {
  return transactions.reduce((total, transaction) => {
    if (transaction.kind === "expense") {
      return total + transaction.amount;
    }

    return total - transaction.amount;
  }, 0);
}

function todayRangeKst(): { start: Date; end: Date } {
  const now = new Date();
  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const year = kst.getUTCFullYear();
  const month = kst.getUTCMonth();
  const day = kst.getUTCDate();
  const start = new Date(Date.UTC(year, month, day) - 9 * 60 * 60 * 1000);
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000 - 1);

  return { start, end };
}

function won(amount: number): string {
  return `${amount.toLocaleString("ko-KR")}원`;
}
