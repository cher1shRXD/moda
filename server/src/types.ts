export type TransactionKind = "income" | "expense";
export type GoalStatus = "active" | "used" | "released";

export type BalanceRecord = {
  currentBalance: number;
  minimumBalance: number;
  updatedAt: string;
};

export type GoalRecord = {
  id: string;
  title: string;
  targetAmount: number;
  dueDate: string;
  status: GoalStatus;
  completedAt: string | null;
  createdAt: string;
  updatedAt: string;
};

export type TransactionRecord = {
  id: string;
  externalId: string | null;
  date: string;
  title: string;
  amount: number;
  kind: TransactionKind;
  createdAt: string;
  updatedAt: string;
};

export type DeviceTokenRecord = {
  id: string;
  token: string;
  environment: "sandbox" | "production";
  createdAt: string;
  updatedAt: string;
};

export type DailyBudgetRecord = {
  initialAllowance: number;
  adjustment: number;
  updatedAt: string;
};

export type NotificationStateRecord = {
  key: string;
  value: string | null;
  updatedAt: string;
};

export type AtomicSnapshot = {
  balance: BalanceRecord;
  today: DailyBudgetRecord;
  goals: GoalRecord[];
  transactions: TransactionRecord[];
};

export type CreateGoalInput = {
  title: string;
  targetAmount: number;
  dueDate: string;
};

export type UpdateGoalInput = Partial<CreateGoalInput>;

export type CreateTransactionInput = {
  id?: string;
  externalId?: string | null;
  date: string;
  title: string;
  amount: number;
  kind: TransactionKind;
};

export type UpdateTransactionInput = Partial<CreateTransactionInput>;
