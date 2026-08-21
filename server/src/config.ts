import path from "node:path";

export type ServerConfig = {
  host: string;
  port: number;
  apiKey: string;
  databasePath: string;
  bankApi: {
    syncEnabled: boolean;
    syncIntervalMs: number;
    baseUrl: string;
    apiKey?: string;
    secretKey?: string;
    bankCode: string;
    accountNumber?: string;
    accountPassword?: string;
    residentNumber?: string;
    lookbackDays: number;
  };
  apns: {
    teamId?: string;
    keyId?: string;
    bundleId: string;
    privateKeyPath?: string;
  };
};

function optionalEnv(name: string): string | undefined {
  const value = process.env[name]?.trim();
  return value && value.length > 0 ? value : undefined;
}

function numberEnv(name: string, fallback: number): number {
  const value = optionalEnv(name);
  if (!value) {
    return fallback;
  }

  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function booleanEnv(name: string, fallback: boolean): boolean {
  const value = optionalEnv(name);
  if (!value) {
    return fallback;
  }

  return ["1", "true", "yes", "on"].includes(value.toLowerCase());
}

export function loadConfig(): ServerConfig {
  const databasePath = optionalEnv("MODA_DATABASE_PATH") ?? "./data/moda.sqlite";

  return {
    host: optionalEnv("MODA_HOST") ?? "127.0.0.1",
    port: numberEnv("MODA_PORT", 8080),
    apiKey: optionalEnv("MODA_API_KEY") ?? "dev-moda-api-key",
    databasePath: path.resolve(process.cwd(), databasePath),
    bankApi: {
      syncEnabled: booleanEnv("MODA_BANKAPI_SYNC_ENABLED", false),
      syncIntervalMs: numberEnv("MODA_BANKAPI_SYNC_INTERVAL_MS", 300_000),
      baseUrl: optionalEnv("MODA_BANKAPI_BASE_URL") ?? "https://api.bankapi.co.kr",
      apiKey: optionalEnv("MODA_BANKAPI_KEY"),
      secretKey: optionalEnv("MODA_BANKAPI_SECRET_KEY"),
      bankCode: optionalEnv("MODA_BANKAPI_BANK_CODE") ?? "KB",
      accountNumber: optionalEnv("MODA_BANKAPI_ACCOUNT_NUMBER"),
      accountPassword: optionalEnv("MODA_BANKAPI_ACCOUNT_PASSWORD"),
      residentNumber: optionalEnv("MODA_BANKAPI_RESIDENT_NUMBER"),
      lookbackDays: numberEnv("MODA_BANKAPI_LOOKBACK_DAYS", 7)
    },
    apns: {
      teamId: optionalEnv("MODA_APNS_TEAM_ID"),
      keyId: optionalEnv("MODA_APNS_KEY_ID"),
      bundleId: optionalEnv("MODA_APNS_BUNDLE_ID") ?? "me.cher1shrxd.moda",
      privateKeyPath: optionalEnv("MODA_APNS_PRIVATE_KEY_PATH")
    }
  };
}
