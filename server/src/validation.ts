import { randomUUID } from "node:crypto";
import type {
  CreateGoalInput,
  CreateTransactionInput,
  TransactionKind,
  UpdateGoalInput,
  UpdateTransactionInput
} from "./types.js";

type JsonObject = Record<string, unknown>;

export function asObject(value: unknown): JsonObject {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("Body must be a JSON object.");
  }

  return value as JsonObject;
}

export function assertUuid(value: string): string {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new Error("Invalid UUID.");
  }

  return value;
}

export function parseOptionalInteger(value: unknown, field: string): number | undefined {
  if (value === undefined) {
    return undefined;
  }

  return parseInteger(value, field);
}

export function parseInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0) {
    throw new Error(`${field} must be a non-negative integer.`);
  }

  return value;
}

export function parseSignedInteger(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    throw new Error(`${field} must be an integer.`);
  }

  return value;
}

export function parseString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new Error(`${field} must be a non-empty string.`);
  }

  return value.trim();
}

export function parseOptionalString(value: unknown, field: string): string | undefined {
  if (value === undefined || value === null) {
    return undefined;
  }

  return parseString(value, field);
}

export function parseIsoDate(value: unknown, field: string): string {
  const text = parseString(value, field);
  const timestamp = Date.parse(text);
  if (!Number.isFinite(timestamp)) {
    throw new Error(`${field} must be an ISO-8601 date string.`);
  }

  return new Date(timestamp).toISOString();
}

export function parseOptionalIsoDate(value: unknown, field: string): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  return parseIsoDate(value, field);
}

export function parseTransactionKind(value: unknown): TransactionKind {
  if (value === "income" || value === "expense") {
    return value;
  }

  throw new Error("kind must be income or expense.");
}

export function parseCreateGoal(value: unknown): CreateGoalInput {
  const body = asObject(value);
  return {
    title: parseString(body.title, "title"),
    targetAmount: parseInteger(body.targetAmount, "targetAmount"),
    dueDate: parseIsoDate(body.dueDate, "dueDate")
  };
}

export function parseUpdateGoal(value: unknown): UpdateGoalInput {
  const body = asObject(value);
  return {
    title: parseOptionalString(body.title, "title"),
    targetAmount: parseOptionalInteger(body.targetAmount, "targetAmount"),
    dueDate: parseOptionalIsoDate(body.dueDate, "dueDate")
  };
}

export function parseCreateTransaction(value: unknown): CreateTransactionInput {
  const body = asObject(value);
  const id = body.id === undefined ? randomUUID() : assertUuid(parseString(body.id, "id"));
  const externalId = body.externalId === undefined || body.externalId === null
    ? null
    : parseString(body.externalId, "externalId");

  return {
    id,
    externalId,
    date: parseIsoDate(body.date, "date"),
    title: parseString(body.title, "title"),
    amount: parseInteger(body.amount, "amount"),
    kind: parseTransactionKind(body.kind)
  };
}

export function parseUpdateTransaction(value: unknown): UpdateTransactionInput {
  const body = asObject(value);

  return {
    externalId: body.externalId === undefined || body.externalId === null
      ? undefined
      : parseString(body.externalId, "externalId"),
    date: parseOptionalIsoDate(body.date, "date"),
    title: parseOptionalString(body.title, "title"),
    amount: parseOptionalInteger(body.amount, "amount"),
    kind: body.kind === undefined ? undefined : parseTransactionKind(body.kind)
  };
}
