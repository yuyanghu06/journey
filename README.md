# Journey Backend

The server-side API for **Journey** — a calm, AI-powered journaling iOS app. This backend powers daily AI conversations, reflective journal entry generation, and a calendar view of past activity.

Built with **NestJS**, **PostgreSQL** (via Prisma), and **OpenAI (GPT-4o mini)**. Deployed on **Railway** via Docker.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Getting Started (Local Development)](#getting-started-local-development)
- [Environment Variables](#environment-variables)
- [API Reference](#api-reference)
  - [Authentication](#authentication)
  - [Chat](#chat)
  - [Journal](#journal)
  - [Calendar](#calendar)
  - [Days](#days)
  - [Memories](#memories)
  - [Personality](#personality)
  - [Health Check](#health-check)
- [Database Schema](#database-schema)
- [AI Integration](#ai-integration)
- [Deploying on Railway](#deploying-on-railway)
- [Running Tests](#running-tests)
- [Project Structure](#project-structure)

---

## Architecture Overview

```
iOS App ──► REST API (NestJS)
                │
                ├── Auth (JWT, bcrypt)
                ├── Chat (day-scoped messages + OpenAI)
                ├── Journal (AI-generated entries)
                ├── Calendar (monthly activity summary)
                ├── Days (snapshot of one day)
                ├── Memories (user context notes)
                └── Personality (stateless impersonation chat)
                │
                └── PostgreSQL (Prisma ORM)
```

All AI calls are strictly confined to `AiService`. The iOS app never calls OpenAI directly.

Every piece of data is scoped to a **DayKey** — a string in `YYYY-MM-DD` format representing a calendar day in the user's local timezone.

---

## Getting Started (Local Development)

### Prerequisites

- Node.js 20+
- PostgreSQL (local or remote)
- An OpenAI API key

### Setup

```bash
# 1. Install dependencies (also generates Prisma client via postinstall)
npm install

# 2. Create .env from the template below and fill in values
cp .env.example .env   # or create .env manually

# 3. Apply database migrations
npm run migrate:dev

# 4. Start the development server (with hot reload)
npm run start:dev
```

The API will be available at `http://localhost:8080`.

### Available Scripts

| Script | Description |
|--------|-------------|
| `npm run build` | Compile TypeScript → `dist/` |
| `npm run start` | Start (NestJS runner) |
| `npm run start:dev` | Start with hot reload |
| `npm run start:debug` | Start with debugger + hot reload |
| `npm run start:prod` | Run compiled JS (`node dist/main`) |
| `npm run migrate:dev` | Create and apply a new Prisma migration |
| `npm run db:generate` | Regenerate Prisma client |
| `npm run db:studio` | Open Prisma Studio UI |
| `npm run test` | Run unit tests |
| `npm run test:watch` | Run tests in watch mode |
| `npm run test:cov` | Run tests with coverage report |

---

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `DATABASE_URL` | ✅ | PostgreSQL connection string (e.g. `postgresql://user:pass@host:5432/dbname`) |
| `AI_PROVIDER_KEY` | ✅ | OpenAI API key (`sk-proj-...`) |
| `JWT_ACCESS_SECRET` | ✅ | Secret for signing access tokens (recommend 64+ char hex string) |
| `JWT_REFRESH_SECRET` | ✅ | Secret for signing refresh tokens (recommend 64+ char hex string) |
| `PORT` | No | HTTP port (defaults to `8080`) |
| `NODE_ENV` | No | `development` or `production` |

> ⚠️ If `JWT_ACCESS_SECRET` or `JWT_REFRESH_SECRET` are missing in production, the server will fall back to insecure dev defaults and log a warning. Always set these in production.

---

## API Reference

All protected endpoints require a JWT access token in the `Authorization` header:

```
Authorization: Bearer <accessToken>
```

Validation errors return HTTP `400` with a JSON body:
```json
{
  "statusCode": 400,
  "message": ["dayKey must match YYYY-MM-DD"],
  "error": "Bad Request"
}
```

---

### Authentication

#### `POST /auth/register`

Create a new user account.

**Request body:**
```json
{
  "email": "user@example.com",
  "password": "securepassword"
}
```
- `password` must be at least 8 characters.

**Response `200`:**
```json
{
  "user": { "id": "uuid", "email": "user@example.com" },
  "tokens": {
    "accessToken": "eyJ...",
    "refreshToken": "eyJ..."
  }
}
```

**Errors:**
- `409 Conflict` — Email already registered.

---

#### `POST /auth/login`

Authenticate an existing user.

**Request body:**
```json
{
  "email": "user@example.com",
  "password": "securepassword"
}
```

**Response `200`:**
```json
{
  "user": { "id": "uuid", "email": "user@example.com" },
  "tokens": {
    "accessToken": "eyJ...",
    "refreshToken": "eyJ..."
  }
}
```

**Errors:**
- `401 Unauthorized` — Invalid credentials.

---

#### `POST /auth/refresh`

Exchange a refresh token for new tokens.

**Request body:**
```json
{
  "refreshToken": "eyJ..."
}
```

**Response `200`:**
```json
{
  "tokens": {
    "accessToken": "eyJ...",
    "refreshToken": "eyJ..."
  }
}
```

**Errors:**
- `401 Unauthorized` — Token expired or invalid.

---

#### `POST /auth/logout`

Invalidate a refresh token.

**Request body:**
```json
{
  "refreshToken": "eyJ..."
}
```

**Response `200`:** `{}`

---

### Chat

#### `POST /chat/sendMessage` 🔒

Send a user message and receive an AI reply. The user message is persisted immediately before calling the AI, so it is never lost even if the AI call fails.

**Request body:**
```json
{
  "dayKey": "2026-03-07",
  "userText": "I had a really rough day today.",
  "clientMessageId": "optional-uuid-for-idempotency"
}
```

- `dayKey` must match `YYYY-MM-DD`.
- `clientMessageId` is optional. If provided and already seen for this user/day, the previous response is returned (idempotency).

**Response `201`:**
```json
{
  "assistantMessage": {
    "id": "uuid",
    "dayKey": "2026-03-07",
    "role": "assistant",
    "text": "That sounds really hard. What was the hardest part?",
    "timestamp": "2026-03-07T18:30:00.000Z"
  }
}
```

**Errors:**
- `400` — Invalid `dayKey` format.
- `503` — AI provider unavailable after retries.

---

#### `POST /chat/personality` 🔒

Send a message using a personality-token-aware AI. Requires personality tokens.

**Request body:**
```json
{
  "dayKey": "2026-03-07",
  "userText": "What do I usually do when I feel overwhelmed?",
  "personalityTokens": ["empathetic", "overthinks", "creative problem-solver"],
  "clientMessageId": "optional-uuid"
}
```

**Response `201`:** Same shape as `/chat/sendMessage`.

---

### Journal

#### `POST /journal/generate` 🔒

Generate (or regenerate) a reflective journal entry for a given day from that day's conversation. Upserts — calling it again replaces the existing entry.

**Request body:**
```json
{
  "dayKey": "2026-03-07"
}
```

**Response `201`:**
```json
{
  "journalEntry": {
    "id": "uuid",
    "dayKey": "2026-03-07",
    "text": "Today I found myself wrestling with a feeling of overwhelm...",
    "createdAt": "2026-03-07T19:00:00.000Z",
    "updatedAt": "2026-03-07T19:00:00.000Z"
  }
}
```

**Errors:**
- `400` — No conversation found for this day.
- `503` — AI provider unavailable.

---

### Calendar

#### `GET /calendar/summary?month=YYYY-MM` 🔒

Returns activity indicators for every day in the given month.

**Query parameters:**

| Param | Required | Description |
|-------|----------|-------------|
| `month` | ✅ | Month to summarize in `YYYY-MM` format |

**Response `200`:**
```json
{
  "days": [
    { "dayKey": "2026-03-01", "hasConversation": true, "hasJournalEntry": true },
    { "dayKey": "2026-03-02", "hasConversation": false, "hasJournalEntry": false },
    { "dayKey": "2026-03-07", "hasConversation": true, "hasJournalEntry": false }
  ]
}
```

Only days with at least one message or a journal entry are included.

**Errors:**
- `400` — `month` does not match `YYYY-MM`.

---

### Days

#### `GET /days/:dayKey` 🔒

Fetch the full snapshot for a single day — conversation history and journal entry.

**Path parameter:** `:dayKey` — must match `YYYY-MM-DD` (validated by `DayKeyPipe`).

**Response `200`:**
```json
{
  "conversation": {
    "dayKey": "2026-03-07",
    "messages": [
      {
        "id": "uuid",
        "dayKey": "2026-03-07",
        "role": "user",
        "text": "I had a really rough day today.",
        "timestamp": "2026-03-07T18:30:00.000Z"
      },
      {
        "id": "uuid",
        "dayKey": "2026-03-07",
        "role": "assistant",
        "text": "That sounds really hard. What was the hardest part?",
        "timestamp": "2026-03-07T18:30:01.000Z"
      }
    ]
  },
  "journalEntry": {
    "id": "uuid",
    "dayKey": "2026-03-07",
    "text": "Today I found myself wrestling with a feeling of overwhelm...",
    "createdAt": "2026-03-07T19:00:00.000Z",
    "updatedAt": "2026-03-07T19:00:00.000Z"
  }
}
```

`journalEntry` is `null` if no entry has been generated for the day.

**Errors:**
- `400` — Invalid `dayKey` format.

---

### Memories

Memories are short context notes about the user (personality traits, life events, preferences) that are injected into the Personality API to improve impersonation quality.

#### `POST /memories` 🔒

Create a new memory.

**Request body:**
```json
{
  "title": "Conflict avoidance",
  "text": "I tend to avoid confrontation even when I know I should speak up. This often leaves me feeling resentful."
}
```

- `title`: max 200 characters.
- `text`: max 50,000 characters.

**Response `201`:**
```json
{
  "id": "uuid",
  "userId": "uuid",
  "title": "Conflict avoidance",
  "text": "I tend to avoid confrontation...",
  "createdAt": "2026-03-07T18:00:00.000Z",
  "updatedAt": "2026-03-07T18:00:00.000Z"
}
```

---

#### `GET /memories` 🔒

Retrieve all memories for the authenticated user.

**Response `200`:**
```json
[
  {
    "id": "uuid",
    "userId": "uuid",
    "title": "Conflict avoidance",
    "text": "I tend to avoid confrontation...",
    "createdAt": "2026-03-07T18:00:00.000Z",
    "updatedAt": "2026-03-07T18:00:00.000Z"
  }
]
```

---

#### `DELETE /memories/:id` 🔒

Delete a memory by ID.

**Response `200`:** The deleted memory object.

**Errors:**
- `404 Not Found` — Memory with the given ID does not exist (or belongs to another user).

---

### Personality

#### `POST /personality/sendMessage` 🔒

Stateless personality-aware chat. The AI impersonates the user's reflective inner voice using personality tokens, memories, and an optional conversation history. **Nothing is persisted** — the client is responsible for storing messages.

**Request body:**
```json
{
  "dayKey": "2026-03-07",
  "userText": "Why do I always procrastinate on things that matter to me?",
  "personalityTokens": ["perfectionist", "fear of failure", "introspective"],
  "conversationHistory": [
    { "dayKey": "2026-03-06", "role": "user", "text": "I keep putting off my creative work." },
    { "dayKey": "2026-03-06", "role": "assistant", "text": "Maybe the stakes feel too high when it really matters." }
  ],
  "memories": [
    "I often abandon projects when I feel they're not going perfectly.",
    "I value creative expression but rarely give myself permission to be imperfect."
  ],
  "userName": "Alex",
  "clientMessageId": "optional-uuid"
}
```

- `personalityTokens`: required, non-empty array of trait strings.
- `conversationHistory`, `memories`, `userName`, `clientMessageId`: all optional.

**Response `201`:**
```json
{
  "assistantMessage": {
    "id": "uuid",
    "dayKey": "2026-03-07",
    "role": "assistant",
    "text": "Because when something really matters to me, the fear of doing it wrong feels bigger than the desire to do it at all.",
    "timestamp": "2026-03-07T18:30:00.000Z"
  }
}
```

---

### Health Check

#### `GET /health`

No authentication required. Used by Railway for container health checks.

**Response `200`:**
```json
{
  "status": "ok",
  "timestamp": "2026-03-07T18:30:00.000Z"
}
```

---

## Database Schema

The schema lives in `prisma/schema.prisma`. Run `npm run migrate:dev` after any changes.

### User

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | Primary key |
| `email` | String | Unique |
| `passwordHash` | String | bcrypt hash |
| `createdAt` | DateTime | Auto-set |

### Message

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | Primary key |
| `userId` | UUID? | FK → User (cascade delete), nullable for single-user mode |
| `dayKey` | String | `YYYY-MM-DD`, indexed |
| `role` | String | `user` \| `assistant` \| `system` |
| `text` | String | |
| `timestamp` | DateTime | Auto-set |
| `clientMessageId` | String? | Idempotency key |

**Indexes:** `(dayKey)`, `(userId, dayKey)`
**Unique:** `(userId, clientMessageId)`

### JournalEntry

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | Primary key |
| `userId` | UUID? | FK → User (cascade delete), nullable |
| `dayKey` | String | `YYYY-MM-DD`, indexed |
| `text` | String | AI-generated journal text |
| `createdAt` | DateTime | Auto-set |
| `updatedAt` | DateTime | Auto-updated |

**Indexes:** `(dayKey)`, `(userId, dayKey)`
**Unique:** `(userId, dayKey)` — enforces one journal entry per user per day

### RefreshToken

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | Primary key |
| `userId` | UUID | FK → User (cascade delete) |
| `token` | String | Unique |
| `expiresAt` | DateTime | 30-day TTL |
| `createdAt` | DateTime | Auto-set |

### Memory

| Column | Type | Notes |
|--------|------|-------|
| `id` | UUID | Primary key |
| `userId` | UUID? | FK → User (cascade delete), nullable |
| `title` | String | Short label |
| `text` | String | Full memory content |
| `createdAt` | DateTime | Auto-set |
| `updatedAt` | DateTime | Auto-updated |

**Index:** `(userId)`

---

## AI Integration

All AI calls happen exclusively inside `AiService` (`src/ai/ai.service.ts`). No other part of the codebase calls OpenAI.

### Configuration

| Setting | Value |
|---------|-------|
| Provider | OpenAI |
| Model | `gpt-4o-mini` |
| Max tokens | 512 per response |
| Temperature | 0.7 |
| Max context | 24,000 characters (oldest messages dropped first) |
| Retry on 429 | Yes — 1 retry after 2s delay |
| Retry on 5xx | Yes — 1 retry after 1s delay |

### Prompts

Prompt templates live in `prompts/` and are bundled into the Docker image at build time.

| File | Used by | Purpose |
|------|---------|---------|
| `prompts/chat.txt` | `ChatService` | System prompt for daily reflective conversation |
| `prompts/journal.txt` | `JournalService` | System prompt for journal entry summarization |
| `prompts/personality.txt` | `PersonalityService` | System prompt template for user impersonation |

`prompts/personality.txt` contains `{PERSONALITY_TOKENS}`, `{MEMORIES_SECTION}`, and `{USER_NAME}` placeholders that are substituted at runtime.

### Failure Behavior

- User messages are persisted **before** any AI call — they are never lost if the AI fails.
- After 2 failed attempts, `AiService` throws a `503 Service Unavailable`.

---

## Deploying on Railway

### First Deploy

1. **Create a Railway project** and connect this repository.

2. **Add a PostgreSQL database** in your Railway project (via the Railway dashboard → Add Plugin → PostgreSQL). Railway will automatically set `DATABASE_URL` in your service's environment.

3. **Set the required environment variables** in Railway (Settings → Variables):

   | Variable | Value |
   |----------|-------|
   | `AI_PROVIDER_KEY` | Your OpenAI API key |
   | `JWT_ACCESS_SECRET` | A random 64+ character string |
   | `JWT_REFRESH_SECRET` | A different random 64+ character string |

   `DATABASE_URL` and `PORT` are set automatically by Railway.

4. **Deploy.** Railway builds the Docker image and runs `sh start.sh`, which:
   - Validates `DATABASE_URL` is present
   - Runs `prisma migrate deploy` (applies all pending migrations)
   - Starts the Node server

### How It Works

```
railway.toml
  └── builder: DOCKERFILE
  └── startCommand: sh start.sh
  └── healthcheckPath: /health
  └── restartPolicy: ON_FAILURE (max 3 retries)

Dockerfile (multi-stage)
  Stage 1 (builder): npm ci → nest build → dist/
  Stage 2 (runner):  npm ci (prod deps) → prisma generate → copy dist/ + prompts/

start.sh
  1. Assert DATABASE_URL is set
  2. prisma migrate deploy
  3. node dist/main
```

### Subsequent Deploys

Push to your connected branch. Railway rebuilds the image and re-runs `start.sh`, which applies any new migrations automatically.

### Generating JWT Secrets

```bash
# macOS / Linux
openssl rand -hex 32   # run twice — once for access, once for refresh
```

### Health Check

Railway uses `GET /health` to verify the container is healthy before routing traffic. The endpoint returns `{ "status": "ok" }` and requires no authentication.

---

## Running Tests

```bash
# Run all unit tests
npm test

# Watch mode
npm run test:watch

# Generate coverage report
npm run test:cov
```

Tests live alongside source files as `*.spec.ts`. The test suite covers:

- DayKey validation
- Conversation persistence
- Journal upsert behavior (one entry per user per day)
- `sendMessage` ordering and idempotency logic
- AI failure resilience (user message saved even when AI throws)

---

## Project Structure

```
src/
├── main.ts                     # Bootstrap (CORS, global ValidationPipe)
├── app.module.ts               # Root module
│
├── auth/                       # JWT authentication
│   ├── auth.controller.ts
│   ├── auth.service.ts
│   ├── jwt.strategy.ts
│   ├── auth.module.ts
│   └── dto/                    # RegisterDto, LoginDto, RefreshDto, LogoutDto
│
├── chat/                       # Day-scoped AI conversation
│   ├── chat.controller.ts
│   ├── chat.service.ts
│   ├── chat.repository.ts      # Prisma access for Message model
│   ├── chat.module.ts
│   └── dto/                    # SendMessageDto, PersonalitySendMessageDto
│
├── journal/                    # AI journal entry generation
│   ├── journal.controller.ts
│   ├── journal.service.ts
│   ├── journal.repository.ts   # Prisma access for JournalEntry model
│   ├── journal.module.ts
│   ├── journal.service.spec.ts
│   └── dto/                    # GenerateJournalDto
│
├── calendar/                   # Monthly activity summary
│   ├── calendar.controller.ts
│   ├── calendar.service.ts
│   └── calendar.module.ts
│
├── days/                       # Single-day snapshot (conversation + journal)
│   ├── days.controller.ts
│   ├── days.service.ts
│   └── days.module.ts
│
├── personality/                # Stateless personality-aware chat
│   ├── personality.controller.ts
│   ├── personality.service.ts
│   ├── personality.module.ts
│   └── dto/                    # PersonalitySendMessageDto
│
├── memories/                   # User context notes
│   ├── memories.controller.ts
│   ├── memories.service.ts
│   ├── memories.repository.ts
│   ├── memories.module.ts
│   └── dto/                    # CreateMemoryDto
│
├── health/                     # Health check endpoint
│   ├── health.controller.ts
│   └── health.module.ts
│
├── legacy/                     # Stub endpoints for legacy iOS client
│   ├── legacy.controller.ts
│   └── legacy.module.ts
│
├── ai/                         # OpenAI integration (all AI calls live here)
│   ├── ai.service.ts
│   └── ai.module.ts
│
├── db/                         # Prisma client wrapper
│   ├── prisma.service.ts
│   └── db.module.ts
│
└── common/                     # Shared utilities
    ├── guards/
    │   └── jwt-auth.guard.ts   # JwtAuthGuard (extends AuthGuard('jwt'))
    └── pipes/
        └── daykey.pipe.ts      # Validates YYYY-MM-DD format

prisma/
├── schema.prisma               # Database schema
└── migrations/                 # Migration history

prompts/
├── chat.txt                    # System prompt for daily chat
├── journal.txt                 # System prompt for journal generation
└── personality.txt             # System prompt template for personality chat
```
