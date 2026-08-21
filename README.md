# Moda

Moda is a local-first iOS personal finance app built with SwiftUI.

The product centers on one recurring question:

> 오늘 얼마까지 써도 괜찮은가?

## Current Scope

- SwiftUI iOS app
- Local JSON persistence in Application Support
- TypeScript server for atomic financial data storage
- Savings goal setup
- Today's available spending amount
- Usage rate and remaining/over-spent state
- Borrow/defer spending controls
- Monthly spending calendar
- Monthly spending graph and previous-month comparison
- APNs registration flow on the client

## Notes

APNs is wired on the app side through notification permission requests, remote notification registration, and device token capture. Sending push notifications still requires an Apple Developer account, valid provisioning, and a server or provider that sends notifications to APNs.

The backend intentionally stores only atomic data:

- current account balance
- minimum balance to keep unallocated
- savings goals, including archived status (`used` or `released`)
- income and expense transactions
- APNs device tokens
- daily budget baseline used by the app (`initialAllowance`, `adjustment`)

The backend does not persist derived budget calculations, goal progress, monthly summaries, or spending advice. The only exception is a server-side transient calculation after bank polling so it can decide whether to send a push notification.

## Server

```bash
cd server
npm install
cp .env.example .env
npm run dev
```

Set `MODA_API_KEY` in `.env`, then call protected endpoints with:

```bash
X-MODA-API-KEY: your-key
```

The iOS app reads backend settings from build settings expanded into `Info.plist`, or from `UserDefaults` overrides:

- `MODAServerBaseURL` comes from `MODA_SERVER_BASE_URL`.
- `MODAServerAPIKey` comes from `MODA_SERVER_API_KEY`.

App secrets live in `ios/Config/ModaSecrets.xcconfig`, which is ignored by git. For local testing, set `MODA_API_KEY` there to the same value as `server/.env`'s `MODA_API_KEY`. On a real device, use your Mac's LAN address instead of `127.0.0.1`.

Core endpoints:

- `GET /health`
- `GET /snapshot?from=2026-08-01T00:00:00.000Z&to=2026-08-31T23:59:59.999Z`
- `GET /balance`
- `PUT /balance`
- `PUT /balance/current`
- `PUT /balance/minimum`
- `GET /today`
- `PUT /today`
- `GET /goals`
- `GET /goals?includeArchived=true`
- `POST /goals`
- `PATCH /goals/:id`
- `POST /goals/:id/use`
- `POST /goals/:id/release`
- `DELETE /goals/:id`
- `GET /transactions?from=...&to=...`
- `GET /transactions/day/:yyyy-mm-dd`
- `POST /transactions`
- `PATCH /transactions/:id`
- `DELETE /transactions/:id`
- `POST /apns/device-tokens`
- `POST /sync/bankapi`
- `POST /notifications/budget/check`
- `POST /notifications/budget/daily`

Bank API polling is disabled by default. To enable the server-side 5-minute polling loop, fill in the `MODA_BANKAPI_*` values and set `MODA_BANKAPI_SYNC_ENABLED=true`.

The Bank API adapter matches `bankapi.co.kr` transaction lookup:

- `POST https://api.bankapi.co.kr/v1/transactions`
- `Authorization: Bearer {apiKey}:{secretKey}`
- `bankCode=KB` by default
- request dates use `YYYYMMDD`
- `deposit` becomes `income`, `withdrawal` becomes `expense`
- `accountInfo.balance` updates `currentBalance`

Account number, account password, and resident number are read from environment variables only and are not written to SQLite.

After each Bank API polling run, the server compares the newly calculated available amount with the previous polling result. If it changed, APNs sends:

- today's available amount
- percentage used against today's budget

The notification calculation uses only stored atomic data:

- `daily_budget_state.initialAllowance + adjustment`
- today's net spending from transactions (`expense - income`)
- previous available amount from `notification_state`

Separately, the server sends a daily budget summary every day at 07:30 KST. The daily summary includes today's available amount and the percentage used against today's budget. It stores only the sent date in `notification_state` to prevent duplicate sends for the same day.

## Build

Open `ios/Moda.xcodeproj` in Xcode, select the `Moda` scheme, and run on an iOS simulator or device.

For command-line simulator builds:

```bash
xcodebuild -project ios/Moda.xcodeproj -scheme Moda -destination 'platform=iOS Simulator,name=iPhone 17' CODE_SIGNING_ALLOWED=NO build
```
