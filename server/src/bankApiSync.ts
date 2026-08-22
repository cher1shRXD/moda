import type { ServerConfig } from "./config.js";
import type { ModaDatabase } from "./database.js";
import type { CreateTransactionInput, TransactionKind } from "./types.js";

type BankApiSyncResult = {
  enabled: boolean;
  importedTransactions: number;
  balanceUpdated: boolean;
  from?: string;
  to?: string;
};

type RawBankTransaction = {
  date?: unknown;
  time?: unknown;
  title?: unknown;
  description?: unknown;
  displayName?: unknown;
  counterparty?: unknown;
  branch?: unknown;
  memo?: unknown;
  amount?: unknown;
  balance?: unknown;
  kind?: unknown;
  type?: unknown;
};

type RawBankResponse = {
  success?: unknown;
  transactions?: RawBankTransaction[];
  accountInfo?: {
    balance?: unknown;
  };
};

export class BankApiSyncService {
  private timer: NodeJS.Timeout | undefined;

  constructor(
    private readonly config: ServerConfig["bankApi"],
    private readonly database: ModaDatabase,
    private readonly onPulled?: () => Promise<void>
  ) {}

  start(): void {
    if (!this.config.syncEnabled) {
      return;
    }

    void this.pullOnce().catch((error: unknown) => {
      console.error(error);
    });
    this.timer = setInterval(() => {
      void this.pullOnce().catch((error: unknown) => {
        console.error(error);
      });
    }, this.config.syncIntervalMs);
  }

  stop(): void {
    if (this.timer) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
  }

  async pullOnce(): Promise<BankApiSyncResult> {
    if (
      !this.config.syncEnabled ||
      !this.config.apiKey ||
      !this.config.secretKey ||
      !this.config.accountNumber ||
      !this.config.accountPassword ||
      !this.config.residentNumber
    ) {
      return {
        enabled: false,
        importedTransactions: 0,
        balanceUpdated: false
      };
    }

    const { startDate, endDate } = this.dateRange();
    const url = new URL("/v1/transactions", this.config.baseUrl);

    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${this.config.apiKey}:${this.config.secretKey}`,
        "Content-Type": "application/json",
        Accept: "application/json"
      },
      body: JSON.stringify({
        bankCode: this.config.bankCode,
        accountNumber: this.config.accountNumber,
        accountPassword: this.config.accountPassword,
        residentNumber: this.config.residentNumber,
        startDate,
        endDate
      })
    });

    const payload = await response.json() as RawBankResponse & { error?: unknown; message?: unknown };
    if (!response.ok) {
      const error = stringValue(payload.error) ?? `HTTP ${response.status}`;
      const message = stringValue(payload.message);
      throw new Error(`bankapi sync failed: ${error}${message ? ` - ${message}` : ""}`);
    }

    const transactions = normalizeTransactions(payload.transactions ?? []);

    for (const transaction of transactions) {
      this.database.createTransaction(transaction);
    }

    const balance = normalizeBalance(payload.accountInfo?.balance);
    if (balance !== undefined) {
      this.database.updateBalance({ currentBalance: balance });
    }
    this.database.recalculateDailyBudgetBaseline();

    this.database.setSyncCursor("bankapi:last_success", new Date().toISOString());
    await this.onPulled?.();

    return {
      enabled: true,
      importedTransactions: transactions.length,
      balanceUpdated: balance !== undefined,
      from: startDate,
      to: endDate
    };
  }

  private dateRange(): { startDate: string; endDate: string } {
    const end = new Date();
    const start = new Date(end);
    start.setDate(start.getDate() - this.config.lookbackDays);

    return {
      startDate: formatBankApiDate(start),
      endDate: formatBankApiDate(end)
    };
  }
}

function normalizeTransactions(rawTransactions: RawBankTransaction[]): CreateTransactionInput[] {
  return rawTransactions.flatMap((raw) => {
    const date = dateValue(raw.date, raw.time);
    const title = stringValue(raw.displayName) ??
      stringValue(raw.counterparty) ??
      stringValue(raw.description) ??
      stringValue(raw.title) ??
      "거래";
    const amount = integerValue(raw.amount);
    const kind = kindValue(raw.kind ?? raw.type);

    if (!date || amount === undefined || !kind) {
      return [];
    }

    return [{
      externalId: stableExternalId(raw, date, title, amount, kind),
      date,
      title,
      amount,
      kind
    }];
  });
}

function stringValue(value: unknown): string | undefined {
  if (typeof value !== "string") {
    return undefined;
  }

  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : undefined;
}

function dateValue(date: unknown, time: unknown): string | undefined {
  const rawDate = stringValue(date)?.replaceAll("/", "-");
  if (!rawDate) {
    return undefined;
  }

  const rawTime = stringValue(time) ?? "00:00:00";
  const text = `${rawDate}T${rawTime}+09:00`;
  if (!text) {
    return undefined;
  }

  const timestamp = Date.parse(text);
  return Number.isFinite(timestamp) ? new Date(timestamp).toISOString() : undefined;
}

function integerValue(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    return undefined;
  }

  return Math.abs(Math.trunc(value));
}

function kindValue(value: unknown): TransactionKind | undefined {
  const text = stringValue(value)?.toLowerCase();
  if (text === "income" || text === "deposit" || text === "in") {
    return "income";
  }

  if (text === "expense" || text === "withdrawal" || text === "out") {
    return "expense";
  }

  return undefined;
}

function stableExternalId(raw: RawBankTransaction, date: string, title: string, amount: number, kind: TransactionKind): string {
  return [
    "bankapi",
    date,
    kind,
    amount,
    title,
    stringValue(raw.description) ?? "",
    stringValue(raw.counterparty) ?? "",
    stringValue(raw.branch) ?? "",
    integerValue(raw.balance) ?? ""
  ].join(":");
}

function normalizeBalance(value: unknown): number | undefined {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0) {
    return undefined;
  }

  return Math.trunc(value);
}

function formatBankApiDate(date: Date): string {
  const year = date.getFullYear();
  const month = `${date.getMonth() + 1}`.padStart(2, "0");
  const day = `${date.getDate()}`.padStart(2, "0");
  return `${year}${month}${day}`;
}
