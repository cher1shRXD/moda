import { randomUUID } from "node:crypto";
import type { FastifyInstance } from "fastify";
import type { ModaDatabase } from "./database.js";
import {
  asObject,
  assertUuid,
  parseCreateGoal,
  parseCreateTransaction,
  parseInteger,
  parseIsoDate,
  parseOptionalIsoDate,
  parseSignedInteger,
  parseString,
  parseUpdateGoal,
  parseUpdateTransaction
} from "./validation.js";

type RouteDeps = {
  database: ModaDatabase;
};

type IdParams = {
  id: string;
};

export function registerRoutes(app: FastifyInstance, deps: RouteDeps): void {
  const { database } = deps;

  app.get("/health", async () => ({
    ok: true
  }));

  app.get("/snapshot", async (request) => {
    const query = request.query as { from?: string; to?: string };
    database.recalculateDailyBudgetBaseline();

    return {
      balance: database.getBalance(),
      today: database.getDailyBudgetSnapshot(),
      goals: database.listGoals(),
      transactions: database.listTransactions({
        from: query.from ? parseIsoDate(query.from, "from") : undefined,
        to: query.to ? parseIsoDate(query.to, "to") : undefined
      })
    };
  });

  app.get("/balance", async () => database.getBalance());

  app.put("/balance", async (request) => {
    const body = asObject(request.body);
    const balance = database.updateBalance({
      currentBalance: body.currentBalance === undefined
        ? undefined
        : parseInteger(body.currentBalance, "currentBalance"),
      minimumBalance: body.minimumBalance === undefined
        ? undefined
        : parseInteger(body.minimumBalance, "minimumBalance")
    });
    database.recalculateDailyBudgetBaseline();
    return balance;
  });

  app.put("/balance/current", async (request) => {
    const body = asObject(request.body);
    const balance = database.updateBalance({
      currentBalance: parseInteger(body.currentBalance, "currentBalance")
    });
    database.recalculateDailyBudgetBaseline();
    return balance;
  });

  app.put("/balance/minimum", async (request) => {
    const body = asObject(request.body);
    const balance = database.updateBalance({
      minimumBalance: parseInteger(body.minimumBalance, "minimumBalance")
    });
    database.recalculateDailyBudgetBaseline();
    return balance;
  });

  app.get("/today", async () => database.getDailyBudgetSnapshot());

  app.put("/today", async (request) => {
    const body = asObject(request.body);
    database.updateDailyBudget({
      initialAllowance: body.initialAllowance === undefined
        ? undefined
        : parseInteger(body.initialAllowance, "initialAllowance"),
      adjustment: body.adjustment === undefined
        ? undefined
        : parseSignedInteger(body.adjustment, "adjustment")
    });
    return database.getDailyBudgetSnapshot();
  });

  app.get("/goals", async (request) => {
    const query = request.query as { includeArchived?: string };
    return database.listGoals({
      includeArchived: query.includeArchived === "true"
    });
  });

  app.post("/goals", async (request, reply) => {
    const input = parseCreateGoal(request.body);
    const goal = database.createGoal({
      ...input,
      id: randomUUID()
    });
    database.recalculateDailyBudgetBaseline();

    return reply.code(201).send(goal);
  });

  app.get<{ Params: IdParams }>("/goals/:id", async (request, reply) => {
    const id = assertUuid(request.params.id);
    const goal = database.getGoal(id);
    if (!goal) {
      return reply.code(404).send({ error: "Not Found", message: "Goal not found." });
    }

    database.recalculateDailyBudgetBaseline();
    return goal;
  });

  app.patch<{ Params: IdParams }>("/goals/:id", async (request, reply) => {
    const id = assertUuid(request.params.id);
    const goal = database.updateGoal(id, parseUpdateGoal(request.body));
    if (!goal) {
      return reply.code(404).send({ error: "Not Found", message: "Goal not found." });
    }

    database.recalculateDailyBudgetBaseline();
    return goal;
  });

  app.post<{ Params: IdParams }>("/goals/:id/use", async (request, reply) => {
    const id = assertUuid(request.params.id);
    const goal = database.resolveGoal(id, "used");
    if (!goal) {
      return reply.code(404).send({ error: "Not Found", message: "Goal not found." });
    }

    database.recalculateDailyBudgetBaseline();
    return goal;
  });

  app.post<{ Params: IdParams }>("/goals/:id/release", async (request, reply) => {
    const id = assertUuid(request.params.id);
    const goal = database.resolveGoal(id, "released");
    if (!goal) {
      return reply.code(404).send({ error: "Not Found", message: "Goal not found." });
    }

    return goal;
  });

  app.delete<{ Params: IdParams }>("/goals/:id", async (request, reply) => {
    const id = assertUuid(request.params.id);
    const deleted = database.deleteGoal(id);
    if (!deleted) {
      return reply.code(404).send({ error: "Not Found", message: "Goal not found." });
    }

    database.recalculateDailyBudgetBaseline();
    return reply.code(204).send();
  });

  app.get("/transactions", async (request) => {
    const query = request.query as { from?: string; to?: string };
    return database.listTransactions({
      from: parseOptionalIsoDate(query.from, "from"),
      to: parseOptionalIsoDate(query.to, "to")
    });
  });

  app.get("/transactions/day/:date", async (request) => {
    const params = request.params as { date: string };
    const start = parseIsoDate(`${params.date}T00:00:00.000Z`, "date");
    const end = parseIsoDate(`${params.date}T23:59:59.999Z`, "date");
    return database.listTransactions({ from: start, to: end });
  });

  app.post("/transactions", async (request, reply) => {
    const transaction = database.createTransaction(parseCreateTransaction(request.body));
    database.recalculateDailyBudgetBaseline();
    return reply.code(201).send(transaction);
  });

  app.get<{ Params: IdParams }>("/transactions/:id", async (request, reply) => {
    const id = assertUuid(request.params.id);
    const transaction = database.getTransaction(id);
    if (!transaction) {
      return reply.code(404).send({ error: "Not Found", message: "Transaction not found." });
    }

    database.recalculateDailyBudgetBaseline();
    return transaction;
  });

  app.patch<{ Params: IdParams }>("/transactions/:id", async (request, reply) => {
    const id = assertUuid(request.params.id);
    const transaction = database.updateTransaction(id, parseUpdateTransaction(request.body));
    if (!transaction) {
      return reply.code(404).send({ error: "Not Found", message: "Transaction not found." });
    }

    return transaction;
  });

  app.delete<{ Params: IdParams }>("/transactions/:id", async (request, reply) => {
    const id = assertUuid(request.params.id);
    const deleted = database.deleteTransaction(id);
    if (!deleted) {
      return reply.code(404).send({ error: "Not Found", message: "Transaction not found." });
    }

    database.recalculateDailyBudgetBaseline();
    return reply.code(204).send();
  });

  app.post("/apns/device-tokens", async (request, reply) => {
    const body = asObject(request.body);
    const token = parseString(body.token, "token").replace(/\s/g, "");
    const environment = body.environment === "production" ? "production" : "sandbox";

    const record = database.upsertDeviceToken({
      id: randomUUID(),
      token,
      environment
    });

    return reply.code(201).send(record);
  });

  app.get("/apns/device-tokens", async () => database.listDeviceTokens());
}
