# Journey Backend — Railway Deployment Guide

Everything the backend needs is already written in `backend/`. This document tells you exactly what to do in Railway and your DNS provider to make the app fully live.

---

## Prerequisites

Before you start, confirm you have:
- A [Railway](https://railway.app) account
- This repository pushed to GitHub (both `main` and `backend` branches)
- An OpenAI API key (`sk-...`)

---

## Step 1 — Create a New Railway Project

1. Go to [railway.app](https://railway.app) → **New Project**
2. Choose **Deploy from GitHub repo**
3. Select your Journey repository
4. When asked which branch to deploy, choose **`backend`**

Railway will detect Node.js via Nixpacks and start a build automatically. The first build will **fail** — that's expected because the database isn't provisioned yet. Continue to Step 2.

---

## Step 2 — Add a PostgreSQL Database

1. Inside your Railway project, click **+ New** → **Database** → **Add PostgreSQL**
2. Railway will create a Postgres instance and automatically inject `DATABASE_URL` into your service's environment

> You do **not** need to write any SQL manually. Prisma migrations handle all table creation during the deploy step (`npx prisma migrate deploy` runs automatically via `railway.toml`).

---

## Step 3 — Set Environment Variables

In your Railway service, go to **Variables** and add the following:

| Variable | Value |
|---|---|
| `AI_PROVIDER_KEY` | Your OpenAI key: `sk-...` |
| `JWT_ACCESS_SECRET` | Run `openssl rand -hex 32` in your terminal and paste the output |
| `JWT_REFRESH_SECRET` | Run `openssl rand -hex 32` again (use a **different** value) |
| `NODE_ENV` | `production` |

`DATABASE_URL` and `PORT` are injected by Railway automatically — **do not add them manually**.

---

## Step 4 — Trigger a Redeploy

After setting environment variables:

1. Go to your service → **Deployments** tab
2. Click **Deploy** (or push a new commit to the `backend` branch)

Railway will:
1. Run `nest build` → produces `dist/`
2. Run `npx prisma migrate deploy` (release step) → creates all tables in Postgres
3. Start `node dist/main`
4. Health-check `GET /health` — passes when the server responds `{ "status": "ok" }`

**Watch the deploy logs** — you should see:
```
Journey backend listening on port XXXX
```

---

## Step 5 — Set a Custom Domain

The iOS app's `APIClient.swift` is hardcoded to `https://yourjourney.it.com`.

1. In Railway → your service → **Settings** → **Domains**
2. Click **Custom Domain** → enter `yourjourney.it.com`
3. Railway will show you a CNAME record to add, for example:
   ```
   CNAME  yourjourney.it.com  →  <your-service>.up.railway.app
   ```
4. Add this record in your DNS provider (wherever `it.com` is registered — Cloudflare, Namecheap, Route53, etc.)
5. Wait for DNS propagation (usually 5–30 minutes)
6. Railway will auto-provision a TLS certificate via Let's Encrypt

> If you want to test before DNS is ready, temporarily change `baseURL` in `APIClient.swift` to the Railway-provided URL (e.g., `https://journey-backend.up.railway.app`).

---

## Step 6 — Verify the Deployment

Run these smoke tests from your terminal (replace the URL with your domain or Railway URL):

```bash
BASE="https://yourjourney.it.com"

# 1. Health check (no auth required)
curl "$BASE/health"
# Expected: {"status":"ok"}

# 2. Register a new user
curl -s -X POST "$BASE/auth/register" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpass123"}' | jq .
# Expected: { "user": { "id": "...", "email": "..." }, "tokens": { "accessToken": "...", "refreshToken": "..." } }

# 3. Save the access token
TOKEN=$(curl -s -X POST "$BASE/auth/login" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","password":"testpass123"}' | jq -r '.tokens.accessToken')

# 4. Send a chat message
curl -s -X POST "$BASE/chat/sendMessage" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"dayKey":"2026-02-25","userText":"Hello Journey"}' | jq .
# Expected: { "assistantMessage": { "id": "...", "role": "assistant", "text": "..." } }

# 5. Generate a journal entry
curl -s -X POST "$BASE/journal/generate" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"dayKey":"2026-02-25"}' | jq .
# Expected: { "journalEntry": { "id": "...", "text": "...", "dayKey": "2026-02-25" } }

# 6. Calendar summary
curl -s "$BASE/calendar/summary?month=2026-02" \
  -H "Authorization: Bearer $TOKEN" | jq .
# Expected: { "days": [{ "dayKey": "2026-02-25", "hasConversation": true, "hasJournalEntry": true }] }

# 7. Day snapshot
curl -s "$BASE/days/2026-02-25" \
  -H "Authorization: Bearer $TOKEN" | jq .
# Expected: { "conversation": { "messages": [...] }, "journalEntry": { ... } }
```

---

## Step 7 — Wire Up the iOS App

Once the backend is live, uncomment the real API calls in these two files:

### `JourneyApp/Features/Chat/Services/ChatService.swift`

Replace the stub `sendMessage` body:
```swift
func sendMessage(dayKey: DayKey, userText: String, priorMessages: [Message]) async -> String {
    let dto = SendMessageRequest(dayKey: dayKey, text: userText, history: priorMessages)
    let response = try? await apiClient.post("/chat/sendMessage", body: dto, responseType: SendMessageResponse.self)
    return response?.reply ?? "I'm having trouble connecting right now."
}
```

Replace the stub `generateJournalEntry` body:
```swift
func generateJournalEntry(dayKey: DayKey, messages: [Message]) async -> String {
    let dto = GenerateJournalRequest(dayKey: dayKey, messages: messages.filter { $0.role == .user }.map { $0.text })
    let response = try? await apiClient.post("/journal/generate", body: dto, responseType: GenerateJournalResponse.self)
    return response?.entry ?? ""
}
```

### `JourneyApp/Features/Calendar/ViewModels/CalendarViewModel.swift`

Replace the `loadBadgeData()` call with an API fetch:
```swift
private func loadBadgeData() {
    Task {
        let monthStr = // format monthAnchor as "YYYY-MM"
        if let summary = try? await apiClient.get("/calendar/summary?month=\(monthStr)",
                                                   responseType: CalendarSummaryResponse.self) {
            daysWithConversations  = Set(summary.days.filter { $0.hasConversation }.map { $0.dayKey })
            daysWithJournalEntries = Set(summary.days.filter { $0.hasJournalEntry }.map { $0.dayKey })
        }
    }
}
```

---

## Database Schema Reference

For reference, here are the tables Prisma creates. **You never need to run these manually** — `prisma migrate deploy` does it automatically on Railway.

```sql
-- Users table
CREATE TABLE "User" (
    "id"           TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "email"        TEXT UNIQUE NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "createdAt"    TIMESTAMP DEFAULT now()
);

-- Chat messages, scoped by user + day
CREATE TABLE "Message" (
    "id"              TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "userId"          TEXT REFERENCES "User"("id") ON DELETE CASCADE,
    "dayKey"          TEXT NOT NULL,
    "role"            TEXT NOT NULL,  -- 'user' | 'assistant' | 'system'
    "text"            TEXT NOT NULL,
    "timestamp"       TIMESTAMP DEFAULT now(),
    "clientMessageId" TEXT
);
CREATE INDEX ON "Message" ("dayKey");
CREATE INDEX ON "Message" ("userId", "dayKey");
CREATE UNIQUE INDEX ON "Message" ("userId", "clientMessageId");

-- AI-generated journal entries, one per user per day
CREATE TABLE "JournalEntry" (
    "id"        TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "userId"    TEXT REFERENCES "User"("id") ON DELETE CASCADE,
    "dayKey"    TEXT NOT NULL,
    "text"      TEXT NOT NULL,
    "createdAt" TIMESTAMP DEFAULT now(),
    "updatedAt" TIMESTAMP DEFAULT now()
);
CREATE INDEX ON "JournalEntry" ("dayKey");
CREATE INDEX ON "JournalEntry" ("userId", "dayKey");
CREATE UNIQUE INDEX ON "JournalEntry" ("userId", "dayKey");

-- Refresh tokens for JWT rotation
CREATE TABLE "RefreshToken" (
    "id"        TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    "userId"    TEXT NOT NULL REFERENCES "User"("id") ON DELETE CASCADE,
    "token"     TEXT UNIQUE NOT NULL,
    "expiresAt" TIMESTAMP NOT NULL,
    "createdAt" TIMESTAMP DEFAULT now()
);
```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Build fails: `Cannot find module '@prisma/client'` | `prisma generate` didn't run | Add `"postinstall": "prisma generate"` to `package.json` scripts |
| `prisma migrate deploy` fails on release | `DATABASE_URL` not set | Check Railway Variables tab — Postgres plugin must be attached |
| 401 on all requests | JWT secrets not set | Add `JWT_ACCESS_SECRET` and `JWT_REFRESH_SECRET` to Railway Variables |
| AI calls return 503 | `AI_PROVIDER_KEY` missing or invalid | Check your OpenAI key in Railway Variables |
| DNS not resolving | Propagation in progress | Wait up to 30 minutes; use Railway URL directly for now |
| iOS app gets 401 after 15 minutes | Token refresh not wired up | Ensure `AuthService.swift`'s `refreshTokens()` and the 14-minute timer are active |

---

## Ongoing Operations

**View live logs:**  
Railway dashboard → your service → **Logs** tab

**Run a migration after a schema change:**  
```bash
# Locally (generates migration file + applies to dev DB)
cd backend && npx prisma migrate dev --name describe-your-change

# On Railway (applied automatically on next deploy via railway.toml releaseCommand)
git push origin backend
```

**Connect to the production database directly (for debugging):**  
Railway dashboard → PostgreSQL plugin → **Connect** → copy the connection string → use `psql` or any Postgres client.
