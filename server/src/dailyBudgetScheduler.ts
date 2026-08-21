import type { BudgetNotificationService } from "./budgetNotification.js";

const KST_OFFSET_MS = 9 * 60 * 60 * 1000;

export class DailyBudgetScheduler {
  private timer: NodeJS.Timeout | undefined;

  constructor(
    private readonly budgetNotification: BudgetNotificationService,
    private readonly hour = 7,
    private readonly minute = 30
  ) {}

  start(): void {
    this.scheduleNext();
  }

  stop(): void {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
  }

  private scheduleNext(): void {
    const delay = this.nextDelayMs(new Date());
    this.timer = setTimeout(() => {
      void this.budgetNotification
        .sendDailySummary()
        .catch((error: unknown) => {
          console.error(error);
        })
        .finally(() => {
          this.scheduleNext();
        });
    }, delay);
  }

  private nextDelayMs(now: Date): number {
    const next = nextKstTime(now, this.hour, this.minute);
    return Math.max(next.getTime() - now.getTime(), 1_000);
  }
}

function nextKstTime(now: Date, hour: number, minute: number): Date {
  const kst = new Date(now.getTime() + KST_OFFSET_MS);
  let year = kst.getUTCFullYear();
  let month = kst.getUTCMonth();
  let day = kst.getUTCDate();

  let next = new Date(Date.UTC(year, month, day, hour, minute) - KST_OFFSET_MS);
  if (next <= now) {
    const tomorrow = new Date(Date.UTC(year, month, day + 1, hour, minute) - KST_OFFSET_MS);
    year = tomorrow.getUTCFullYear();
    month = tomorrow.getUTCMonth();
    day = tomorrow.getUTCDate();
    next = new Date(Date.UTC(year, month, day, hour, minute) - KST_OFFSET_MS);
  }

  return next;
}
