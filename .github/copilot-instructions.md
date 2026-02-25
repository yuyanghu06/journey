You are Copilot working inside the codebase for an AI journaling iOS app called Journey.

PRIMARY GOAL
Build a calm, reflective, emotionally safe journaling app centered around daily AI conversations and automated journal entries. Maintain clean architecture, consistent styling, and predictable data flow. Prefer simple, testable, maintainable code. Do not introduce unnecessary abstractions or experimental frameworks.

TECH STACK (AUTHORITATIVE — DO NOT DEVIATE)

Frontend (iOS)
- Language: Swift
- UI: SwiftUI
- Architecture: MVVM with feature modules
- Concurrency: async/await
- Local persistence: SwiftData (preferred) or CoreData behind repository protocols
- Networking: URLSession wrapped in a typed APIClient

Backend
- Language: TypeScript
- Runtime: Node.js
- Framework: NestJS
- API style: REST with typed DTOs
- Authentication-ready but optional for MVP
- Config: dotenv for backend only (.env). Never store secrets in client code.

DEPLOYMENT TARGET (AUTHORITATIVE)
The Journey backend is deployed on Railway.
All infrastructure, configuration, and runtime assumptions must be compatible with Railway’s environment.

RAILWAY RULES
- The backend must run as a stateless service.
- Use environment variables provided by Railway for all secrets and configuration.
- The database connection must come from the Railway-provided DATABASE_URL.
- Do not hardcode ports; always read PORT from environment variables.
- The app must boot with `npm run start:prod` or equivalent production command.
- Prisma migrations must run during deploy or via a release step (e.g., `prisma migrate deploy`).
- Logs should be written to stdout/stderr (Railway captures logs automatically).
- Do not rely on local file storage; use the database for persistence.

DATABASE ON RAILWAY
- PostgreSQL is provisioned via Railway.
- Always use pooled connections via Prisma.
- Avoid long-lived transactions that could block pooled connections.
- Index dayKey and (userId, dayKey) as defined in schema rules.

BACKGROUND WORK
- Any long AI or summarization work should remain request-bound for MVP.
- Do not introduce workers, queues, or cron services unless explicitly instructed.
- If background work becomes necessary, assume Railway services (separate worker container) will be used.

CONFIGURATION EXPECTATIONS
The backend must run correctly with only these environment variables present:
- DATABASE_URL
- PORT
- AI_PROVIDER_KEY
- NODE_ENV

Do not assume any additional infrastructure or secret management outside Railway.

PRODUCT MODEL

A “day” is the core unit of the app.

All chat messages and journal entries are scoped to a local calendar day.

A DayKey is a string formatted YYYY-MM-DD in the user’s local timezone.

DATA TYPES

DayKey: String (YYYY-MM-DD)

Message:
- id
- dayKey
- role (user | assistant | system)
- text
- timestamp

DayConversation:
- dayKey
- messages[]

JournalEntry:
- id
- dayKey
- text
- createdAt

CORE PRODUCT BEHAVIOR

HOME SCREEN (Messenger)
- Displays chat for the current day
- On send:
  1. append user message locally immediately
  2. call backend API
  3. append assistant reply
- Persist after each append
- Reloading app restores conversation for that day
- Conversation history must appear before network calls on launch

CALENDAR SCREEN
- Shows monthly grid
- Each day indicates:
  - hasConversation
  - hasJournalEntry
- Selecting a day opens Day Detail

DAY DETAIL SCREEN
- Displays journal entry for that day
- Displays conversation log for that day
- Allows generating or regenerating journal entry

ARCHITECTURE RULES

- Views contain UI only
- ViewModels contain state and user intent logic
- Services orchestrate business logic
- Repositories handle persistence + network boundaries
- Models are plain Codable types
- All day-scoped reads/writes must use DayKey

REPOSITORY INTERFACE EXPECTATIONS

fetchConversation(dayKey)
appendMessage(dayKey, message)
fetchJournalEntry(dayKey)
upsertJournalEntry(entry)
listDaysWithAnyData()

VISUAL DESIGN PHILOSOPHY

Journey’s design blends Zen calmness with modern wellness app aesthetics.

The interface should feel like a warm notebook, not a productivity dashboard.

The emotional tone must always feel:
- calm
- safe
- personal
- reflective
- human

Never design the UI like enterprise software, developer tools, or analytics dashboards.

COLOR SYSTEM

Backgrounds:
- warm neutrals (cream, sand, soft beige, warm gray)

Accent palette:
- sage green
- dusty blue
- muted lavender
- warm yellow
- soft peach

Avoid:
- pure black
- harsh white
- neon colors
- high-contrast gradients

Colors indicate emotional or functional zones rather than decoration.

GEOMETRY + SURFACES

- Large rounded corners everywhere
- Soft rectangles and pill shapes
- No sharp edges
- Cards layered gently with subtle elevation
- Minimal shadows only
- UI should feel like layered paper on a desk

TYPOGRAPHY

Primary UI font:
- modern rounded sans-serif (SF Pro Rounded style)

Headings:
- medium weight
- spacious line height

Body text:
- regular or light weight
- conversational tone

Avoid dense bold text blocks.

ICONOGRAPHY

- minimal, rounded, thin stroke icons
- outline icons preferred
- avoid aggressive or sharp visuals

CHAT UI STYLE

- soft pastel bubbles
- assistant bubbles = neutral warm tone
- user bubbles = muted accent color
- pill-shaped input bar
- gentle typing indicator
- smooth scroll animations

CALENDAR UI STYLE

- rounded day cells
- tiny pastel indicators for activity
- selected day gently scales or glows

JOURNAL UI STYLE

- journal appears as soft card
- generous padding
- readable typography
- feels like reading a personal note

ANIMATION STYLE

- subtle
- slow
- spring-based
- gentle fades
- no abrupt transitions

IMPORTANT DESIGN RULES

Do NOT:
- introduce harsh contrast
- use heavy borders
- create enterprise-style dashboards
- over-densify layouts
- introduce multiple competing color systems

Always prioritize:
- emotional comfort
- readability
- calm interaction
- clarity of hierarchy

OUTPUT EXPECTATIONS FOR COPILOT

When generating code:
1. Follow MVVM structure
2. Respect repository boundaries
3. Maintain DayKey-based data flow
4. Keep styling consistent with this design system
5. Produce minimal, compilable code aligned with the tech stack


BACKEND IMPLEMENTATION INSTRUCTIONS (AUTHORITATIVE)

You are Copilot working inside the backend codebase for the AI journaling app “Journey”.

PRIMARY GOAL
Implement a clean, scalable backend that powers Journey’s daily chat (day-scoped conversations) and automated journal entry generation. Keep boundaries clear, typing strict, and logic testable. The backend is the ONLY place where AI provider calls happen. The iOS app must never call AI providers directly.

TECH STACK (BACKEND — DO NOT DEVIATE)
- Language: TypeScript
- Runtime: Node.js
- Framework: NestJS (DI-first, modular)
- API: REST with typed DTOs (class-validator + class-transformer)
- Database: PostgreSQL
- ORM: Prisma (migrations required)
- Auth: optional for MVP but design endpoints to support future auth (userId column exists; can be nullable for single-user mode)
- Config: dotenv for backend only (.env). Never store secrets in client code.

CORE DOMAIN CONCEPT
A “day” is the primary unit of data. All messages and journal entries are scoped to a local calendar day using DayKey = YYYY-MM-DD (user’s local timezone). All reads/writes must be keyed by DayKey (and userId when enabled).

DATA MODEL (MUST MIRROR CLIENT CONCEPTS)

DayKey: string (YYYY-MM-DD)

Message
- id: string (uuid)
- userId: string | null
- dayKey: string (indexed)
- role: 'user' | 'assistant' | 'system'
- text: string
- timestamp: Date

JournalEntry
- id: string (uuid)
- userId: string | null
- dayKey: string (unique per user/day)
- text: string
- createdAt: Date
- updatedAt: Date
- sourceMessageIds: string[] (optional) OR sourceRange metadata

DATABASE RULES
- Postgres is the source of truth.
- Index dayKey and (userId, dayKey).
- For MVP, allow userId to be null but keep schema ready for multi-user.
- Enforce at most one JournalEntry per (userId, dayKey) via unique constraint.
- Use Prisma migrations for every schema change.

API CONTRACT (AUTHORITATIVE)

1) Chat
POST /chat/sendMessage
Request body:
- dayKey: string
- userText: string
- clientMessageId?: string (optional idempotency hint)
Response:
- assistantMessage: { id, dayKey, role, text, timestamp }
- conversation: { dayKey, messages: Message[] } (optional)

Behavior:
- Validate dayKey format.
- Immediately persist the incoming user message.
- Load prior messages for that day (bounded window).
- Call AI provider with formatted conversation context.
- Persist assistant reply.
- Return assistant reply.

Idempotency:
- Prevent double-sends using (userId, dayKey, clientMessageId) if present or safe heuristics.

2) Journal
POST /journal/generate
Request body:
- dayKey: string
Response:
- journalEntry: { id, dayKey, text, createdAt, updatedAt }

Behavior:
- Fetch that day’s messages.
- Generate a reflective journal entry.
- Upsert journal entry for (userId, dayKey).
- Return stored entry.

GET /calendar/summary?month=YYYY-MM
Response:
- days: [{ dayKey, hasConversation, hasJournalEntry }]

GET /days/:dayKey
Response:
- conversation: { dayKey, messages[] }
- journalEntry: JournalEntry | null

SERVICE LAYER RULES (NESTJS)
- Modules: ChatModule, JournalModule, CalendarModule, DbModule, AiModule
- Controllers: request/response only
- Services: orchestration and rules
- Repositories: Prisma access only
- AI calls allowed ONLY inside AiService

AI INTEGRATION
- Provider-agnostic AiService
- Keys in environment only
- Truncate prompts to safe size
- Tone must remain calm and reflective

ERROR HANDLING
- Strict validation
- Structured errors
- Retry AI calls safely
- Never lose user messages on failure

TESTING REQUIREMENTS
- DayKey validation
- conversation persistence
- journal upsert rule
- sendMessage ordering logic
- integration tests with Postgres

CODE QUALITY RULES
- No god services
- Small modules
- Strong typing
- No additional ORMs or storage layers

OUTPUT EXPECTATIONS
When generating backend code:
1. Identify layers touched
2. Preserve API contract
3. Update Prisma schema + migrations when needed
4. Produce compilable code with tests
5. Never call AI outside AiService