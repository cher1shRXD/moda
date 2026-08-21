import { loadConfig } from "./config.js";
import { ModaDatabase } from "./database.js";
import { buildApp } from "./app.js";
import { BankApiSyncService } from "./bankApiSync.js";
import { ApnsClient } from "./apns.js";
import { BudgetNotificationService } from "./budgetNotification.js";
import { DailyBudgetScheduler } from "./dailyBudgetScheduler.js";

const config = loadConfig();
const database = new ModaDatabase(config.databasePath);
const apnsClient = new ApnsClient(config.apns);
const budgetNotification = new BudgetNotificationService(database, apnsClient);
const dailyBudgetScheduler = new DailyBudgetScheduler(budgetNotification);
const bankApiSync = new BankApiSyncService(config.bankApi, database, async () => {
  await budgetNotification.checkAndNotify();
});
const app = buildApp({ config, database });

app.post("/sync/bankapi", async () => bankApiSync.pullOnce());
app.post("/notifications/budget/check", async () => budgetNotification.checkAndNotify());
app.post("/notifications/budget/daily", async () => budgetNotification.sendDailySummary());

bankApiSync.start();
dailyBudgetScheduler.start();

const shutdown = async () => {
  bankApiSync.stop();
  dailyBudgetScheduler.stop();
  await app.close();
  database.close();
};

process.on("SIGINT", () => {
  void shutdown().then(() => process.exit(0));
});

process.on("SIGTERM", () => {
  void shutdown().then(() => process.exit(0));
});

await app.listen({
  host: config.host,
  port: config.port
});
