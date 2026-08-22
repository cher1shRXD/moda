import fs from "node:fs";
import path from "node:path";
import { randomUUID } from "node:crypto";
import { DatabaseSync } from "node:sqlite";
import type {
  BalanceRecord,
  CreateGoalInput,
  CreateTransactionInput,
  DailyBudgetRecord,
  DailyBudgetSnapshot,
  DeviceTokenRecord,
  GoalRecord,
  GoalStatus,
  TransactionRecord,
  UpdateGoalInput,
  UpdateTransactionInput
} from "./types.js";

type GoalRow = {
  id: string;
  title: string;
  target_amount: number;
  due_date: string;
  status: GoalStatus;
  completed_at: string | null;
  created_at: string;
  updated_at: string;
};

type TransactionRow = {
  id: string;
  external_id: string | null;
  date: string;
  title: string;
  amount: number;
  kind: "income" | "expense";
  created_at: string;
  updated_at: string;
};

type BalanceRow = {
  current_balance: number;
  minimum_balance: number;
  updated_at: string;
};

type DeviceTokenRow = {
  id: string;
  token: string;
  environment: "sandbox" | "production";
  created_at: string;
  updated_at: string;
};

type DailyBudgetRow = {
  monthly_allowance: number;
  initial_allowance: number;
  adjustment: number;
  updated_at: string;
};

type NotificationStateRow = {
  key: string;
  value: string | null;
  updated_at: string;
};

export class ModaDatabase {
  private readonly db: DatabaseSync;

  constructor(databasePath: string) {
    fs.mkdirSync(path.dirname(databasePath), { recursive: true });
    this.db = new DatabaseSync(databasePath);
    this.db.exec("PRAGMA foreign_keys = ON;");
    this.db.exec("PRAGMA journal_mode = WAL;");
    this.migrate();
  }

  close(): void {
    this.db.close();
  }

  getBalance(): BalanceRecord {
    const row = this.db
      .prepare("SELECT current_balance, minimum_balance, updated_at FROM account_state WHERE id = 1")
      .get() as BalanceRow | undefined;

    if (!row) {
      const now = new Date().toISOString();
      this.db
        .prepare("INSERT INTO account_state (id, current_balance, minimum_balance, updated_at) VALUES (1, 0, 0, ?)")
        .run(now);
      return { currentBalance: 0, minimumBalance: 0, updatedAt: now };
    }

    return mapBalance(row);
  }

  updateBalance(input: { currentBalance?: number; minimumBalance?: number }): BalanceRecord {
    const current = this.getBalance();
    const next = {
      currentBalance: input.currentBalance ?? current.currentBalance,
      minimumBalance: input.minimumBalance ?? current.minimumBalance,
      updatedAt: new Date().toISOString()
    };

    this.db
      .prepare(
        `UPDATE account_state
         SET current_balance = ?, minimum_balance = ?, updated_at = ?
         WHERE id = 1`
      )
      .run(next.currentBalance, next.minimumBalance, next.updatedAt);

    return next;
  }

  getDailyBudget(): DailyBudgetRecord {
    const row = this.db
      .prepare("SELECT monthly_allowance, initial_allowance, adjustment, updated_at FROM daily_budget_state WHERE id = 1")
      .get() as DailyBudgetRow | undefined;

    if (!row) {
      const now = new Date().toISOString();
      this.db
        .prepare("INSERT INTO daily_budget_state (id, monthly_allowance, initial_allowance, adjustment, updated_at) VALUES (1, 0, 0, 0, ?)")
        .run(now);
      return { monthlyAllowance: 0, initialAllowance: 0, adjustment: 0, updatedAt: now };
    }

    return mapDailyBudget(row);
  }

  updateDailyBudget(input: { monthlyAllowance?: number; initialAllowance?: number; adjustment?: number }): DailyBudgetRecord {
    const current = this.getDailyBudget();
    const next = {
      monthlyAllowance: input.monthlyAllowance ?? current.monthlyAllowance,
      initialAllowance: input.initialAllowance ?? current.initialAllowance,
      adjustment: input.adjustment ?? current.adjustment,
      updatedAt: new Date().toISOString()
    };

    this.db
      .prepare(
        `UPDATE daily_budget_state
         SET monthly_allowance = ?, initial_allowance = ?, adjustment = ?, updated_at = ?
         WHERE id = 1`
      )
      .run(next.monthlyAllowance, next.initialAllowance, next.adjustment, next.updatedAt);

    return next;
  }

  recalculateDailyBudgetBaseline(): DailyBudgetRecord {
    const budget = this.getDailyBudget();
    const spentBeforeToday = Math.max(netSpending(this.listTransactions(monthBeforeTodayRangeKst())), 0);
    const remainingMonthlyAllowance = Math.max(budget.monthlyAllowance - spentBeforeToday, 0);
    const dailyAllowance = Math.floor(remainingMonthlyAllowance / remainingDaysInKstMonth());

    return this.updateDailyBudget({
      initialAllowance: dailyAllowance
    });
  }

  getDailyBudgetSnapshot(): DailyBudgetSnapshot {
    const budget = this.getDailyBudget();
    const spentAmount = netSpending(this.listTransactions(todayRangeKst()));
    const normalizedSpentAmount = Math.max(spentAmount, 0);
    const currentAllowance = Math.max(budget.initialAllowance + budget.adjustment, 0);
    const availableAmount = Math.max(currentAllowance - normalizedSpentAmount, 0);
    const usagePercent = currentAllowance > 0
      ? Math.min(100, Math.max(0, Math.round((normalizedSpentAmount / currentAllowance) * 100)))
      : 100;

    return {
      ...budget,
      currentAllowance,
      spentAmount: normalizedSpentAmount,
      availableAmount,
      overspentAmount: Math.max(normalizedSpentAmount - currentAllowance, 0),
      usagePercent
    };
  }

  listGoals(options: { includeArchived?: boolean } = {}): GoalRecord[] {
    const where = options.includeArchived ? "" : "WHERE status = 'active'";
    const rows = this.db
      .prepare(`SELECT * FROM goals ${where} ORDER BY due_date ASC, created_at ASC`)
      .all() as GoalRow[];
    return rows.map(mapGoal);
  }

  createGoal(input: CreateGoalInput & { id: string }): GoalRecord {
    const now = new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO goals (id, title, target_amount, due_date, status, completed_at, created_at, updated_at)
         VALUES (?, ?, ?, ?, 'active', NULL, ?, ?)`
      )
      .run(input.id, input.title, input.targetAmount, input.dueDate, now, now);

    return this.getGoal(input.id)!;
  }

  getGoal(id: string): GoalRecord | undefined {
    const row = this.db.prepare("SELECT * FROM goals WHERE id = ?").get(id) as GoalRow | undefined;
    return row ? mapGoal(row) : undefined;
  }

  updateGoal(id: string, input: UpdateGoalInput): GoalRecord | undefined {
    const current = this.getGoal(id);
    if (!current) {
      return undefined;
    }

    const next = {
      title: input.title ?? current.title,
      targetAmount: input.targetAmount ?? current.targetAmount,
      dueDate: input.dueDate ?? current.dueDate,
      updatedAt: new Date().toISOString()
    };

    this.db
      .prepare(
        `UPDATE goals
         SET title = ?, target_amount = ?, due_date = ?, updated_at = ?
         WHERE id = ?`
      )
      .run(next.title, next.targetAmount, next.dueDate, next.updatedAt, id);

    return this.getGoal(id);
  }

  resolveGoal(id: string, status: Exclude<GoalStatus, "active">): GoalRecord | undefined {
    const current = this.getGoal(id);
    if (!current) {
      return undefined;
    }

    const now = new Date().toISOString();
    this.db
      .prepare("UPDATE goals SET status = ?, completed_at = ?, updated_at = ? WHERE id = ?")
      .run(status, now, now, id);

    return this.getGoal(id);
  }

  deleteGoal(id: string): boolean {
    const now = new Date().toISOString();
    const result = this.db
      .prepare("UPDATE goals SET status = 'released', completed_at = ?, updated_at = ? WHERE id = ? AND status = 'active'")
      .run(now, now, id);
    return result.changes > 0;
  }

  listTransactions(filters: { from?: string; to?: string }): TransactionRecord[] {
    const conditions: string[] = [];
    const values: string[] = [];

    if (filters.from) {
      conditions.push("date >= ?");
      values.push(filters.from);
    }

    if (filters.to) {
      conditions.push("date <= ?");
      values.push(filters.to);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(" AND ")}` : "";
    const rows = this.db
      .prepare(`SELECT * FROM transactions ${where} ORDER BY date DESC, created_at DESC`)
      .all(...values) as TransactionRow[];

    return rows.map(mapTransaction);
  }

  createTransaction(input: CreateTransactionInput): TransactionRecord {
    const now = new Date().toISOString();
    const id = input.id ?? randomUUID();
    this.db
      .prepare(
        `INSERT INTO transactions (id, external_id, date, title, amount, kind, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(external_id) DO UPDATE SET
           date = excluded.date,
           title = excluded.title,
           amount = excluded.amount,
           kind = excluded.kind,
           updated_at = excluded.updated_at`
      )
      .run(id, input.externalId ?? null, input.date, input.title, input.amount, input.kind, now, now);

    const key = input.externalId
      ? this.db.prepare("SELECT id FROM transactions WHERE external_id = ?").get(input.externalId) as { id: string }
      : { id };

    return this.getTransaction(key.id)!;
  }

  getTransaction(id: string): TransactionRecord | undefined {
    const row = this.db.prepare("SELECT * FROM transactions WHERE id = ?").get(id) as TransactionRow | undefined;
    return row ? mapTransaction(row) : undefined;
  }

  updateTransaction(id: string, input: UpdateTransactionInput): TransactionRecord | undefined {
    const current = this.getTransaction(id);
    if (!current) {
      return undefined;
    }

    const next = {
      externalId: input.externalId ?? current.externalId,
      date: input.date ?? current.date,
      title: input.title ?? current.title,
      amount: input.amount ?? current.amount,
      kind: input.kind ?? current.kind,
      updatedAt: new Date().toISOString()
    };

    this.db
      .prepare(
        `UPDATE transactions
         SET external_id = ?, date = ?, title = ?, amount = ?, kind = ?, updated_at = ?
         WHERE id = ?`
      )
      .run(next.externalId, next.date, next.title, next.amount, next.kind, next.updatedAt, id);

    return this.getTransaction(id);
  }

  deleteTransaction(id: string): boolean {
    const result = this.db.prepare("DELETE FROM transactions WHERE id = ?").run(id);
    return result.changes > 0;
  }

  upsertDeviceToken(input: { id: string; token: string; environment: "sandbox" | "production" }): DeviceTokenRecord {
    const now = new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO apns_device_tokens (id, token, environment, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(token, environment) DO UPDATE SET updated_at = excluded.updated_at`
      )
      .run(input.id, input.token, input.environment, now, now);

    const row = this.db
      .prepare("SELECT * FROM apns_device_tokens WHERE token = ? AND environment = ?")
      .get(input.token, input.environment) as DeviceTokenRow;

    return mapDeviceToken(row);
  }

  listDeviceTokens(): DeviceTokenRecord[] {
    const rows = this.db
      .prepare("SELECT * FROM apns_device_tokens ORDER BY updated_at DESC")
      .all() as DeviceTokenRow[];
    return rows.map(mapDeviceToken);
  }

  getNotificationState(key: string): string | undefined {
    const row = this.db
      .prepare("SELECT key, value, updated_at FROM notification_state WHERE key = ?")
      .get(key) as NotificationStateRow | undefined;

    return row?.value ?? undefined;
  }

  setNotificationState(key: string, value: string): void {
    const now = new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO notification_state (key, value, updated_at)
         VALUES (?, ?, ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value, updated_at = excluded.updated_at`
      )
      .run(key, value, now);
  }

  getSyncCursor(source: string): string | undefined {
    const row = this.db
      .prepare("SELECT cursor FROM sync_cursors WHERE source = ?")
      .get(source) as { cursor: string | null } | undefined;
    return row?.cursor ?? undefined;
  }

  setSyncCursor(source: string, cursor: string): void {
    const now = new Date().toISOString();
    this.db
      .prepare(
        `INSERT INTO sync_cursors (source, cursor, updated_at)
         VALUES (?, ?, ?)
         ON CONFLICT(source) DO UPDATE SET cursor = excluded.cursor, updated_at = excluded.updated_at`
      )
      .run(source, cursor, now);
  }

  private migrate(): void {
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS account_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        current_balance INTEGER NOT NULL DEFAULT 0 CHECK (current_balance >= 0),
        minimum_balance INTEGER NOT NULL DEFAULT 0 CHECK (minimum_balance >= 0),
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS daily_budget_state (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        monthly_allowance INTEGER NOT NULL DEFAULT 0 CHECK (monthly_allowance >= 0),
        initial_allowance INTEGER NOT NULL DEFAULT 0 CHECK (initial_allowance >= 0),
        adjustment INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS goals (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        target_amount INTEGER NOT NULL CHECK (target_amount >= 0),
        due_date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'used', 'released')),
        completed_at TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS transactions (
        id TEXT PRIMARY KEY,
        external_id TEXT UNIQUE,
        date TEXT NOT NULL,
        title TEXT NOT NULL,
        amount INTEGER NOT NULL CHECK (amount >= 0),
        kind TEXT NOT NULL CHECK (kind IN ('income', 'expense')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );

      CREATE INDEX IF NOT EXISTS idx_transactions_date ON transactions(date);

      CREATE TABLE IF NOT EXISTS apns_device_tokens (
        id TEXT PRIMARY KEY,
        token TEXT NOT NULL,
        environment TEXT NOT NULL CHECK (environment IN ('sandbox', 'production')),
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        UNIQUE(token, environment)
      );

      CREATE TABLE IF NOT EXISTS sync_cursors (
        source TEXT PRIMARY KEY,
        cursor TEXT,
        updated_at TEXT NOT NULL
      );

      CREATE TABLE IF NOT EXISTS notification_state (
        key TEXT PRIMARY KEY,
        value TEXT,
        updated_at TEXT NOT NULL
      );
    `);

    this.addColumnIfMissing("goals", "status", "TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'used', 'released'))");
    this.addColumnIfMissing("goals", "completed_at", "TEXT");
    this.addColumnIfMissing("daily_budget_state", "monthly_allowance", "INTEGER NOT NULL DEFAULT 0 CHECK (monthly_allowance >= 0)");
  }

  private addColumnIfMissing(table: string, column: string, definition: string): void {
    const rows = this.db.prepare(`PRAGMA table_info(${table})`).all() as { name: string }[];
    if (!rows.some((row) => row.name === column)) {
      this.db.exec(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition};`);
    }
  }
}

function mapBalance(row: BalanceRow): BalanceRecord {
  return {
    currentBalance: row.current_balance,
    minimumBalance: row.minimum_balance,
    updatedAt: row.updated_at
  };
}

function mapDailyBudget(row: DailyBudgetRow): DailyBudgetRecord {
  return {
    monthlyAllowance: row.monthly_allowance,
    initialAllowance: row.initial_allowance,
    adjustment: row.adjustment,
    updatedAt: row.updated_at
  };
}

function mapGoal(row: GoalRow): GoalRecord {
  return {
    id: row.id,
    title: row.title,
    targetAmount: row.target_amount,
    dueDate: row.due_date,
    status: row.status,
    completedAt: row.completed_at,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function mapTransaction(row: TransactionRow): TransactionRecord {
  return {
    id: row.id,
    externalId: row.external_id,
    date: row.date,
    title: row.title,
    amount: row.amount,
    kind: row.kind,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}

function netSpending(transactions: TransactionRecord[]): number {
  return transactions.reduce((total, transaction) => {
    if (transaction.kind === "expense") {
      return total + transaction.amount;
    }

    return total - transaction.amount;
  }, 0);
}

function todayRangeKst(): { from: string; to: string } {
  const now = new Date();
  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const year = kst.getUTCFullYear();
  const month = kst.getUTCMonth();
  const day = kst.getUTCDate();
  const start = new Date(Date.UTC(year, month, day) - 9 * 60 * 60 * 1000);
  const end = new Date(Date.UTC(year, month, day + 1) - 9 * 60 * 60 * 1000 - 1);

  return {
    from: start.toISOString(),
    to: end.toISOString()
  };
}

function monthBeforeTodayRangeKst(): { from: string; to: string } {
  const now = new Date();
  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const year = kst.getUTCFullYear();
  const month = kst.getUTCMonth();
  const day = kst.getUTCDate();
  const start = new Date(Date.UTC(year, month, 1) - 9 * 60 * 60 * 1000);
  const end = new Date(Date.UTC(year, month, day) - 9 * 60 * 60 * 1000 - 1);

  return {
    from: start.toISOString(),
    to: end.toISOString()
  };
}

function remainingDaysInKstMonth(): number {
  const now = new Date();
  const kst = new Date(now.getTime() + 9 * 60 * 60 * 1000);
  const year = kst.getUTCFullYear();
  const month = kst.getUTCMonth();
  const day = kst.getUTCDate();
  const lastDay = new Date(Date.UTC(year, month + 1, 0)).getUTCDate();

  return Math.max(lastDay - day + 1, 1);
}

function mapDeviceToken(row: DeviceTokenRow): DeviceTokenRecord {
  return {
    id: row.id,
    token: row.token,
    environment: row.environment,
    createdAt: row.created_at,
    updatedAt: row.updated_at
  };
}
