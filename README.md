# Journey iOS App — Comprehensive Codebase Overview

A reflective, AI-powered journaling companion for iOS built with SwiftUI and SwiftData. This document provides a complete architectural and structural overview.

---

## 1. Project Structure

```
frontend/
├── JourneyApp/                           # Main app source
│   ├── App/                             # App lifecycle & root routing
│   │   ├── Journey_AppApp.swift          # @main entry point, launches background training task
│   │   ├── RootView.swift               # Auth state router (loading → login/main)
│   │   ├── MainTabView.swift            # 4-tab root container (Today, Past Self, Explore, Settings)
│   │   └── AppModelContainer.swift      # Shared SwiftData ModelContainer singleton
│   │
│   ├── Features/                        # Feature modules (MVVM pattern)
│   │   ├── Auth/
│   │   │   ├── Services/
│   │   │   │   ├── AuthService.swift    # Session lifecycle, token refresh, login/register
│   │   │   │   └── Keychain.swift       # Secure token storage wrapper
│   │   │   └── Views/
│   │   │       ├── AuthView.swift       # Login & registration UI
│   │   │       ├── LoginView.swift
│   │   │       └── RegisterView.swift
│   │   │
│   │   ├── Chat/                        # Today's conversation tab
│   │   │   ├── Models/
│   │   │   │   └── Message.swift        # Message, MessageRole, Status enums
│   │   │   ├── Services/
│   │   │   │   └── ChatService.swift    # Talks to /chat/sendMessage & /journal/generate endpoints
│   │   │   ├── ViewModels/
│   │   │   │   └── ChatViewModel.swift  # Today's conversation state, sends & persists messages
│   │   │   └── Views/
│   │   │       ├── ChatView.swift       # Main chat UI with message list, input bar
│   │   │       ├── MessageRow.swift     # Bubble layout for individual messages
│   │   │       ├── TypingIndicator.swift
│   │   │       └── GrowableTextView.swift
│   │   │
│   │   ├── Calendar/                    # Explore tab with month grid
│   │   │   ├── ViewModels/
│   │   │   │   ├── CalendarViewModel.swift  # Month navigation, badge computation
│   │   │   │   └── DayDetailViewModel.swift # Load/display single day's journal & messages
│   │   │   └── Views/
│   │   │       ├── CalendarView.swift       # Month grid with prev/next
│   │   │       ├── DayCell.swift
│   │   │       └── DayDetailView.swift      # Day detail modal with conversation & journal
│   │   │
│   │   ├── Personality/                 # "Past Self" tab (on-device model inference)
│   │   │   ├── Models/
│   │   │   │   ├── PersonalitySession.swift        # In-memory session wrapper
│   │   │   │   ├── PersonalitySessionRecord.swift  # SwiftData persistent record
│   │   │   │   ├── PersonalityMessage.swift        # Single turn in session
│   │   │   │   ├── PersonalityModelVersion.swift   # Trained model metadata
│   │   │   │   ├── PersonalityToken.swift          # Token vocabulary & sampling
│   │   │   │   ├── PersonalityModelConfig.swift    # Model size/architecture config
│   │   │   │   └── ContextDocument.swift           # SwiftData model for memory notes
│   │   │   │
│   │   │   ├── Services/
│   │   │   │   ├── PersonalityModelService.swift   # CoreML inference & training (Actor)
│   │   │   │   ├── MiniLMEmbedder.swift            # Sentence embeddings via all-MiniLM-L6-v2.mlpackage
│   │   │   │   ├── PersonalityTrainingScheduler.swift  # Periodic training, BGProcessingTask
│   │   │   │   └── ContextDocumentService.swift    # Import/save memory documents
│   │   │   │
│   │   │   ├── Repository/
│   │   │   │   └── PersonalityRepository.swift     # SwiftData-backed session/doc storage
│   │   │   │
│   │   │   ├── ViewModels/
│   │   │   │   ├── PersonalityViewModel.swift      # Past Self chat logic, inference, send
│   │   │   │   ├── PersonalityHistoryViewModel.swift
│   │   │   │   └── UploadContextViewModel.swift    # Context document upload state
│   │   │   │
│   │   │   └── Views/
│   │   │       ├── PersonalityTabView.swift        # Main Past Self tab (session switcher)
│   │   │       ├── PersonalitySessionView.swift    # Chat interface with token drawer
│   │   │       ├── PersonalityHistoryView.swift    # List of past simulation sessions
│   │   │       ├── UploadContextView.swift         # File/text import UI
│   │   │       ├── TrainingProgressView.swift      # Shows training status
│   │   │       └── PersonalityVersionRow.swift
│   │   │
│   │   ├── Settings/
│   │   │   └── Views/
│   │   │       └── SettingsView.swift  # Profile, account info, logout
│   │   │
│   │   └── BugReport/
│   │       ├── Services/
│   │       │   └── BugReportService.swift
│   │       └── Views/
│   │           └── BugView.swift
│   │
│   └── Shared/
│       ├── Networking/
│       │   ├── APIClient.swift          # Typed HTTP client with Bearer token auth & 401 retry
│       │   └── BackendDTOs.swift        # Decodable DTOs for backend responses
│       │
│       ├── Persistence/
│       │   ├── ConversationRepository.swift     # Chat message storage (SwiftData + in-memory)
│       │   ├── JournalRepository.swift          # Journal entry storage (in-memory for now)
│       │   └── MessageRecord.swift              # SwiftData model for messages
│       │
│       ├── DesignSystem/
│       │   └── DesignSystem.swift       # Colors, typography, spacing, animations (DS namespace)
│       │
│       ├── Components/
│       │   ├── JourneyAvatar.swift      # Gradient circle with "J" logo
│       │   ├── LoadingView.swift        # Splash screen
│       │   ├── BubbleShape.swift        # Chat bubble tail shape
│       │   └── GrowableTextView.swift   # Auto-expanding text input
│       │
│       └── Utilities/
│           ├── DayKey.swift             # YYYY-MM-DD calendar day identifier
│           └── MessageCompressor.swift  # (Legacy) message compression
│
├── JourneyAppTests/                     # Unit tests (minimal)
│   └── Journey_AppTests.swift
│
├── JourneyAppUITests/                   # UI tests
│   ├── Journey_AppUITests.swift
│   └── Journey_AppUITestsLaunchTests.swift
│
├── Resources/                           # ML models & vocabularies
│   ├── PersonalityModelStock.mlpackage  # Full backbone (384-dim embedding → 325-dim logits)
│   ├── PersonalityHeadUpdatable.mlpackage  # Trainable projection head (512→325)
│   ├── all-MiniLM-L6-v2.mlpackage       # Sentence embedder (to 384 dims)
│   └── all-MiniLM-L6-v2-vocab.txt       # Tokenizer vocab for embedder
│
├── .env                                 # BACKEND_URL=https://journey-production-47d5.up.railway.app/
├── Journey-App-Info.plist              # App info, background task identifier, network config
├── JourneyApp.xcodeproj/               # Xcode project (no SPM/CocoaPods — pure SwiftUI)
└── planning_markdown/                  # Design & architecture docs (not in compiled app)
```

---

## 2. App Architecture (MVVM)

The app follows **Model-View-ViewModel (MVVM)** with protocol-based abstraction for testability:

```
┌─────────────────────────────────────────────────────────────┐
│  View Layer (SwiftUI)                                       │
│  ├── ChatView, CalendarView, PersonalitySessionView, etc   │
│  └── Observes @Published properties on ViewModels          │
└──────────────┬──────────────────────────────────────────────┘
               │ (reads/writes via)
               ↓
┌─────────────────────────────────────────────────────────────┐
│  ViewModel Layer (@MainActor, ObservableObject)             │
│  ├── ChatViewModel — manages messages, typing, delivery     │
│  ├── DayDetailViewModel — loads journal & conversation      │
│  ├── PersonalityViewModel — inference, training, sessions   │
│  ├── CalendarViewModel — grid layout, badge data            │
│  └── PersonalityTrainingScheduler — auto-training          │
└──────────────┬──────────────────────────────────────────────┘
               │ (uses)
               ↓
┌─────────────────────────────────────────────────────────────┐
│  Service & Repository Layer                                 │
│  ├── ChatService — POST /chat/sendMessage, /journal/generate│
│  ├── AuthService — login, register, token refresh           │
│  ├── PersonalityModelService — inference, training (Actor)  │
│  ├── MiniLMEmbedder — on-device sentence embedding          │
│  ├── ConversationRepository — message persistence (SwiftData)
│  ├── JournalRepository — journal storage (in-memory)        │
│  ├── PersonalityRepository — session storage (SwiftData)    │
│  └── ContextDocumentService — file import & parsing         │
└──────────────┬──────────────────────────────────────────────┘
               │ (calls)
               ↓
┌─────────────────────────────────────────────────────────────┐
│  API & Persistence Layer                                    │
│  ├── APIClient — typed HTTP requests with Bearer auth       │
│  ├── Keychain — secure token storage                        │
│  ├── SwiftData ModelContext — chat messages, sessions       │
│  ├── CoreML — on-device personality model inference         │
│  └── FileManager — model files, context docs                │
└─────────────────────────────────────────────────────────────┘
```

**Key design principles:**
- All services/repos are **protocol-backed** for easy mocking in tests
- **@MainActor** ensures UI updates are thread-safe
- **Actor-based PersonalityModelService** isolates concurrent model operations
- Async/await throughout; no callback hell
- **Dependency injection** via initializer parameters with sensible defaults

---

## 3. All Swift Source Files (56 total)

### App Lifecycle (3)
1. **Journey_AppApp.swift** — @main entry, registers background training task
2. **RootView.swift** — Route: loading → auth check → MainTabView or AuthLandingView
3. **MainTabView.swift** — 4-tab container: Today | Past Self | Explore | Settings

### Auth (3)
4. **AuthService.swift** — Login, register, token refresh, logout. Main app service.
5. **Keychain.swift** — Minimal wrapper around Security.framework for token storage
6. **AuthView.swift** — Login form, register link, error display

### Chat (6)
7. **Message.swift** — Value type: id, dayKey, role (user|assistant), text, timestamp, status
8. **ChatService.swift** — Calls /chat/sendMessage and /journal/generate endpoints
9. **ChatViewModel.swift** — Today's conversation state, send logic, journal generation
10. **ChatView.swift** — Main chat UI: header, scrolling message list, input bar
11. **MessageRow.swift** — Individual message bubble with alignment, status, avatar
12. **TypingIndicator.swift** — Animated dots while assistant responds

### Calendar (5)
13. **CalendarViewModel.swift** — Month grid computation, badge data (conversations/journals)
14. **DayDetailViewModel.swift** — Load day's journal + messages from backend/local
15. **CalendarView.swift** — Month grid with prev/next navigation
16. **DayCell.swift** — Single day cell (shows date, badges for data)
17. **DayDetailView.swift** — Modal showing selected day's full conversation & journal

### Personality (13)
**Models (7):**
18. **PersonalitySession.swift** — In-memory session wrapper (id, modelVersion, messages, createdAt)
19. **PersonalitySessionRecord.swift** — SwiftData model, persists sessions to disk
20. **PersonalityMessage.swift** — Single turn (role: user|pastSelf, text, activeTokens)
21. **PersonalityModelVersion.swift** — Metadata for trained model (period, size, fileName)
22. **PersonalityToken.swift** — Vocabulary loader, random sampling, seeded RNG
23. **PersonalityModelConfig.swift** — Model architecture config (target param count, topK, etc)
24. **ContextDocument.swift** — SwiftData model for memory notes

**Services (4):**
25. **PersonalityModelService.swift** — Core inference & training (Actor). Two-model architecture:
    - PersonalityModelStock (frozen backbone from bundle)
    - PersonalityHeadUpdatable (trainable projection head)
26. **MiniLMEmbedder.swift** — On-device sentence embedding (384-dim vectors from all-MiniLM-L6-v2)
27. **PersonalityTrainingScheduler.swift** — Periodic 14-day training, BGProcessingTask handling
28. **ContextDocumentService.swift** — Import PDFs/text, parse, save to repo

**ViewModels (3):**
29. **PersonalityViewModel.swift** — Past Self chat logic: token inference, send, message persistence
30. **PersonalityHistoryViewModel.swift** — (minimal) List past sessions
31. **UploadContextViewModel.swift** — Drive context import UI

**Views (5):**
32. **PersonalityTabView.swift** — Tab root: session list or new session
33. **PersonalitySessionView.swift** — Active conversation with token drawer
34. **PersonalityHistoryView.swift** — List of past simulation sessions
35. **UploadContextView.swift** — File picker + text input for memory documents
36. **TrainingProgressView.swift** — Show training status (progress bar, status text)

### Settings (1)
37. **SettingsView.swift** — Profile (edit name), account info (email, user ID), logout

### Bug Report (2)
38. **BugReportService.swift** — (Stub) Bug reporting service
39. **BugView.swift** — Bug report UI

### Shared: Networking (2)
40. **APIClient.swift** — Typed HTTP client: GET/POST with Bearer token, 401 retry, logging
41. **BackendDTOs.swift** — Decodable response structures (DayDataResponse, PersonalityDTOs, etc)

### Shared: Persistence (3)
42. **ConversationRepository.swift** — Protocol + 2 implementations:
    - InMemoryConversationRepository (ephemeral)
    - SwiftDataConversationRepository (persistent, shared default)
43. **JournalRepository.swift** — Protocol + InMemoryJournalRepository
44. **MessageRecord.swift** — SwiftData @Model for persisting messages

### Shared: DesignSystem (1)
45. **DesignSystem.swift** — DS namespace: colors, spacing, radius, animations, typography

### Shared: Components (4)
46. **JourneyAvatar.swift** — Gradient circle with "J"
47. **LoadingView.swift** — Splash screen
48. **BubbleShape.swift** — Chat bubble geometry with tail
49. **GrowableTextView.swift** — UIViewRepresentable auto-expanding TextInput (for chat)

### Shared: Utilities (2)
50. **DayKey.swift** — Calendar day identifier (YYYY-MM-DD) with Comparable, Codable
51. **MessageCompressor.swift** — (Legacy) message compression/decompression

### Shared: App Config (1)
52. **AppModelContainer.swift** — Singleton SwiftData ModelContainer setup

### Tests (4)
53. **Journey_AppTests.swift** — Unit test template (minimal content)
54. **Journey_AppUITests.swift** — UI test template
55. **Journey_AppUITestsLaunchTests.swift** — Launch performance test

### Personality Repository (1)
56. **PersonalityRepository.swift** — Protocol + 2 implementations:
    - InMemoryPersonalityRepository (for testing)
    - SwiftDataPersonalityRepository (persistent, shared default)

---

## 4. Data Models & Structures

### Core Chat Models
- **Message**
  - `id: UUID`
  - `dayKey: DayKey` (which day this message belongs to)
  - `role: MessageRole` (.user | .assistant | .system)
  - `text: String`
  - `timestamp: Date`
  - `status: Status` (.sending | .sent | .delivered | .read)
  - Methods: `isFromCurrentUser` (convenience)

- **MessageRole** (enum: user, assistant, system)
- **Message.Status** (enum: sending, sent, delivered, read)
- **DayConversation** (wrapper: dayKey + [Message])

### Personality Models
- **PersonalitySession**
  - `id: UUID`
  - `modelVersion: PersonalityModelVersion?`
  - `messages: [PersonalityMessage]`
  - `createdAt: Date`

- **PersonalityMessage**
  - `id: UUID`
  - `role: PersonalityRole` (.user | .pastSelf)
  - `text: String`
  - `timestamp: Date`
  - `activeTokens: [String]` (personality tokens active at time of send)
  - Property: `isFromCurrentUser`

- **PersonalityModelVersion**
  - `id: UUID`
  - `periodStart: Date`, `periodEnd: Date`
  - `createdAt: Date`
  - `fileSizeBytes: Int64`
  - `parameterCount: Int`
  - Computed: `fileName` (YYYY-MM-DD_YYYY-MM-DD.mlpackage), `displayRange`, `formattedSize`

- **ContextDocument** (SwiftData @Model)
  - `id: UUID`
  - `title: String`
  - `rawText: String`
  - `createdAt: Date`
  - Computed: `characterCount`, `preview` (first 100 chars)

### Journal & Calendar
- **JournalEntry**
  - `id: UUID`
  - `dayKey: DayKey`
  - `text: String`
  - `createdAt: Date`

### Utility Types
- **DayKey** (RawRepresentable, Comparable, Codable, Hashable)
  - Format: "YYYY-MM-DD" (local timezone)
  - Statics: `.today`, `.from(Date)`
  - Instance: `.date` (parses back to midnight Date), `.displayString` ("Monday, March 3")

- **PersonalityVocabulary** (enum)
  - Loads personality tokens from `personality-tokens.json` bundle file
  - Fallback: 24 hardcoded personality trait tokens
  - Method: `randomSample(k: Int, seed: UInt64?)` for bootstrap sampling

- **PersonalityModelConfig**
  - `targetParameterCount` (default: 20M)
  - `topK: Int` (8)
  - `temperature: Float` (1.0)
  - `inputDim: Int` (384 from MiniLM)
  - Computed: `hiddenDim` (solves quadratic to hit parameter target)
  - Presets: `.small`, `.medium`, `.large`

---

## 5. ViewModels & State Management

### ChatViewModel (@MainActor, ObservableObject)
**Published State:**
- `messages: [Message]` — today's conversation
- `draft: String` — text input buffer
- `isPeerTyping: Bool` — assistant is responding
- `isLoadingHistory: Bool` — fetching today's messages on load
- `errorMessage: String?`

**Responsibilities:**
- Load today's conversation from backend (fallback to local SwiftData)
- Append user messages immediately (optimistic UI)
- Fetch assistant replies via ChatService
- Persist every message to ConversationRepository
- Generate journal entry when app backgrounds

**Key Methods:**
- `loadTodayConversation()` — init, fetches from /days/today
- `send()` — user sends message, fetches AI reply
- `saveConversationAndGenerateJournal()` — triggered on app background

### DayDetailViewModel (@MainActor, ObservableObject)
**Published State:**
- `journalEntry: JournalEntry?`
- `conversation: DayConversation?`
- `isLoadingJournal`, `isLoadingConversation`, `isGeneratingJournal`
- `errorMessage: String?`

**Responsibilities:**
- Load a specific day's data from /days/:dayKey endpoint
- Auto-generate journal if messages exist but no entry yet
- Display full conversation history + journal on calendar detail screen

### PersonalityViewModel (@MainActor, ObservableObject)
**Published State:**
- `messages: [PersonalityMessage]` — current simulation session
- `draft: String`
- `activeTokens: [String]` — personality tokens active now
- `isPeerTyping`, `isLoadingTokens`, `isAutoTraining`
- `isTokenDrawerExpanded`
- `errorMessage: String?`

**Responsibilities:**
- On load: infer personality tokens from today's conversation
- Auto-train first model if none exists
- Gather inference messages (today first, then last 14 days from backend)
- Re-infer tokens before each send (to reflect latest conversation state)
- Call /personality/sendMessage with tokens + conversation history
- Persist session messages to PersonalityRepository

**Key Methods:**
- `loadTokensForToday()` — init load, ensureModelLoaded, infer tokens, restore session
- `send()` — user message → re-infer tokens → backend call → persist
- `gatherInferenceMessages()`, `gatherHistoryForBackend()` — fetch messages for inference
- `hydratePastDaysFromBackend()` — fetch last 14 days once per session

### CalendarViewModel (@MainActor, ObservableObject)
**Published State:**
- `monthAnchor: Date` — currently displayed month
- `monthTitle: String`, `weekdaySymbols: [String]`, `gridDates: [Date]`
- `daysWithConversations: Set<String>` — badge data
- `daysWithJournalEntries: Set<String>`

**Responsibilities:**
- Compute month grid (padding from prev/next months)
- Navigate months (prev/next buttons)
- Load badge data from both repositories
- Query: `isCurrentMonth()`, `isToday()`, `hasConversation()`, `hasJournalEntry()`

### PersonalityTrainingScheduler (@MainActor, ObservableObject)
**Published State:**
- `isTraining: Bool`
- `trainingProgress: Double` (0.0 → 1.0)
- `trainingStatusText: String`
- `lastError: String?`

**UserDefaults-backed:**
- `autoTrainEnabled` (default: true)
- `lastTrainingDate: Date?`
- `daysSinceLastTraining: Int?`
- `shouldTrain: Bool` (returns true if 14+ days since last training and autoTrainEnabled)

**Responsibilities:**
- Called every foreground (via lifecycle hook)
- Initiate training if `shouldTrain` is true
- Register & handle BGProcessingTask (`com.journey.personality.train`)
- Display training progress in UI

---

## 6. Views & Screens (User-Facing)

### Authentication Flow
- **AuthLandingView** → splash with hero, LoginView, register link
- **LoginView** → email + password form, calls AuthService.login()
- **RegisterView** → email + password + optional name, calls AuthService.register()
- Errors displayed inline (e.g., "Sign in failed (401)")

### Main Tab Navigation (4 tabs)
1. **Today Tab**
   - **ChatView** — today's conversation, message list with auto-scroll, input bar
   - Header: "Journey" avatar + buttons (bug report, logout)
   - Messages: bubbles with sender distinction, delivery ticks, typing indicator
   - Input: growable text field + send button (appears when text present)

2. **Past Self Tab**
   - **PersonalityTabView** — switcher between new session or restore existing
   - **PersonalitySessionView** — active Past Self conversation
     - Shows personality tokens in drawer (expandable)
     - Message history with role distinction
     - Input bar (same UX as Chat)
   - **PersonalityHistoryView** — list of past simulation sessions
   - **UploadContextView** — import text/PDF files for training context
   - **TrainingProgressView** — shows when model training is in progress

3. **Explore Tab**
   - **CalendarView** — month grid with prev/next navigation
   - **DayCell** — each day shows badges (dots) for conversations & journal entries
   - **DayDetailView** (modal) — clicking a day shows full conversation + journal text
     - Can regenerate journal entry via "Generate" button
     - Shows loading states and errors

4. **Settings Tab**
   - **SettingsView** — profile (edit display name), account (email, user ID), logout button

### Shared Components
- **JourneyAvatar** — gradient circle with "J" (28px to 84px sizes)
- **MessageRow** — chat bubble with role-based alignment, avatar (assistant only), status label
- **BubbleShape** — chat bubble geometry with corner radius and tail
- **GrowableTextView** — UIViewRepresentable TextInput that expands with content
- **LoadingView** — simple splash screen (appears during auth check)
- **DesignSystem** — all colors, spacing, typography accessed via `DS` namespace

---

## 7. Services & Repositories

### Services (Stateless, Protocol-Backed)

**AuthService** (@MainActor, ObservableObject)
- Published: `isAuthenticated`, `email`, `userId`, `userName`
- Methods:
  - `register(email, password, userName)` → POST /auth/register
  - `login(email, password)` → POST /auth/login
  - `logout()` → POST /auth/logout (best-effort)
  - `refreshTokens()` → POST /auth/refresh (one-shot)
  - `startTokenRefresher()` → auto-refresh every 14 minutes
  - `getCompressedHistory(date)` → GET /history/:date
  - `getSummaries(date)` → GET /summaries/:date
  - `postCompressedHistory(date, compressedHistory, summary)` → POST /history
- Stores tokens in Keychain; restores session on init

**ChatService** (ChatServiceProtocol)
- Methods:
  - `sendMessage(dayKey, userText, priorMessages)` → POST /chat/sendMessage
  - `generateJournalEntry(dayKey, messages)` → POST /journal/generate
- Returns fallback strings ("I'm here. Tell me more.", "") on network error
- Uses APIClient for typed requests

**PersonalityModelService** (Actor)
- Methods:
  - `ensureModelLoaded()` — loads CoreML backbone + embedder
  - `infer(currentDayMessages)` → top-k personality tokens (with fallback tiers)
  - `trainNewVersion(conversations, memories)` → MLUpdateTask training, persists to disk
  - `listVersions()` → all trained model versions
- Two-model architecture:
  - **PersonalityModelStock** (frozen, from bundle) — backbone (384-dim → 512-dim latent + 325-dim logits)
  - **PersonalityHeadUpdatable** (from trained versions or bundle) — projection head only (512 → 325)
- Inference tier fallback: CoreML (best) → RandomWeightEngine (bootstrap) → random tokens
- Model files stored in Application Support/PersonalityModels/

**MiniLMEmbedder**
- Loads all-MiniLM-L6-v2.mlpackage from bundle or cache
- Embeds user text to 384-dim vectors for inference input
- Falls back to NLEmbedding (if CoreML unavailable)

**ContextDocumentService**
- Methods:
  - `importFile(from: URL)` → parse PDF/text, create ContextDocument
  - `deleteDocument(id)` → remove from repository
- Supports PDF (text extraction) and plaintext files

**BugReportService**
- (Stub) Placeholder for bug reporting

### Repositories (Protocol-Backed, Persistent)

**ConversationRepository** (protocol)
- Methods:
  - `fetchConversation(dayKey)` → DayConversation
  - `appendMessage(message, dayKey)` → add single message
  - `setMessages(messages, dayKey)` → replace all messages for day
  - `listDaysWithConversations()` → all DayKeys with data

**Implementations:**
- **InMemoryConversationRepository** — ephemeral (tests/previews)
- **SwiftDataConversationRepository** (shared singleton) — persists MessageRecord models

**JournalRepository** (protocol)
- Methods:
  - `fetchJournalEntry(dayKey)` → JournalEntry?
  - `upsertJournalEntry(entry)` → create/replace
  - `deleteJournalEntry(dayKey)`
  - `listDaysWithJournalEntries()` → all DayKeys with entries

**Implementations:**
- **InMemoryJournalRepository** — ephemeral (in-memory dict)
- (SwiftData version planned but not yet implemented)

**PersonalityRepository** (protocol)
- Methods:
  - `saveSession(session)`, `fetchSessions()`, `deleteSession(id)`
  - `saveContextDocument(doc)`, `fetchContextDocuments()`, `deleteContextDocument(id)`

**Implementations:**
- **InMemoryPersonalityRepository** (actor-isolated for thread safety)
- **SwiftDataPersonalityRepository** (shared singleton) — persists PersonalitySessionRecord & ContextDocument

---

## 8. API Client & Networking

### APIClient (APIClientProtocol)
**Configuration:**
- Base URL: `https://journey-production-47d5.up.railway.app/`
- Singleton: `APIClient.shared`
- Injected tokenProvider: KeychainTokenProvider (defaults to reading from Keychain)

**Methods:**
- `get<Response: Decodable>(_ path, responseType)` → authenticated GET, auto-retries on 401
- `post<Body: Encodable, Response: Decodable>(_ path, body, responseType)` → authenticated POST
- `postRaw<Response: Decodable>(_ path, body: [String: Any], responseType)` → raw dict POST
- `postPublic<Body: Encodable, Response: Decodable>(_ path, body, responseType)` → unauthenticated POST

**Bearer Token Handling:**
- Automatically injects `Authorization: Bearer <accessToken>` on authenticated requests
- On 401 response: calls `tokenProvider.refreshTokens()` once, then retries original request
- Token comes from Keychain (AuthKeys.access)

**Logging:**
- Prints [APIClient] request/response summary to console (method, path, status, error body on failure)

**Error Handling:**
- Throws `HTTPError(status, data)` on non-2xx responses
- Throws `URLError` on network or parsing failures

### Endpoints Called

**Auth (unauthenticated):**
- POST /auth/register → {email, password, userName?} → {user, tokens}
- POST /auth/login → {email, password} → {user, tokens}
- POST /auth/logout → {refreshToken}
- POST /auth/refresh → {userId, refreshToken} → {tokens}

**Chat (authenticated):**
- GET /days/:dayKey → DayDataResponse {conversation, journalEntry?}
- POST /chat/sendMessage → {dayKey, userText} → {assistantMessage}
- POST /journal/generate → {dayKey, messages} → {journalEntry}

**Personality (authenticated):**
- POST /personality/sendMessage → {dayKey, userText, personalityTokens, clientMessageId, conversationHistory, memories, userName} → {assistantMessage}

**History (AuthService, authenticated):**
- GET /history/:date → {compressed_history}
- GET /summaries/:date → {summaries: [String]}
- POST /history → {date, compressedHistory, summary}

### Data Transfer Objects (DTOs)

**Backend→App (Decodable):**
- `BackendMessageDTO` → Message
- `BackendConversationDTO` → [Message]
- `BackendJournalEntryDTO` → JournalEntry
- `DayDataResponse` — root response for GET /days/:dayKey
- `PersonalityMessageResponse` — single message in personality response
- `PersonalitySendMessageResponse` — root response for POST /personality/sendMessage

**App→Backend (Encodable):**
- `SendMessageRequest` {dayKey, userText}
- `GenerateJournalRequest` {dayKey, messages: [MessageDTO]}
- `PersonalitySendMessageRequest` {dayKey, userText, personalityTokens, clientMessageId, conversationHistory, memories, userName}
- `PersonalityHistoryMessageDTO` {dayKey, role, text}

---

## 9. Local Persistence (SwiftData)

### SwiftData Models (@Model)

**MessageRecord**
- `id: UUID` (unique)
- `dayKey: String` — which day
- `role: String` — "user" or "assistant"
- `text: String`
- `timestamp: Date`
- `status: String` — "sending", "sent", "delivered", "read"
- Conversions: from/to Message struct

**PersonalitySessionRecord**
- `id: UUID`
- `modelVersionId: UUID?` — which model version generated this session
- `createdAt: Date`
- `@Relationship(deleteRule: .cascade) messages: [PersonalityMessageRecord]` — cascade delete

**PersonalityMessageRecord**
- `id: UUID`
- `role: String` — "user" or "past_self"
- `text: String`
- `timestamp: Date`
- `activeTokens: [String]` — tokens active at time of send

**ContextDocument**
- `id: UUID`
- `title: String` — document title
- `rawText: String` — full text content
- `createdAt: Date`

### ModelContainer Setup

**AppModelContainer** (singleton enum)
- Shared `ModelContainer` for all models: MessageRecord, ContextDocument, PersonalitySessionRecord, PersonalityMessageRecord
- Fallback to in-memory storage if creation fails
- All repositories init their ModelContext from `AppModelContainer.shared`

### Query Examples (SwiftData)

```swift
// Fetch all messages for a day
let descriptor = FetchDescriptor<MessageRecord>(
    predicate: #Predicate { $0.dayKey == "2025-01-15" },
    sortBy: [SortDescriptor(\.timestamp)]
)
let records = try context.fetch(descriptor)

// Fetch all sessions (reverse chronological)
let descriptor = FetchDescriptor<PersonalitySessionRecord>(
    sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
)
let sessions = try context.fetch(descriptor)
```

---

## 10. Configuration & Build Settings

### Info Plist (Journey-App-Info.plist)
- `NSAppTransportSecurity` → `NSAllowsArbitraryLoads: true` (allows HTTP for dev)
- `BGTaskSchedulerPermittedIdentifiers` → ["com.journey.personality.train"]
- Minimal content — most settings in Xcode project

### Environment Variables (.env)
- `BACKEND_URL=https://journey-production-47d5.up.railway.app/`
- (Loaded at build time or runtime depending on setup)

### Xcode Project (JourneyApp.xcodeproj)

**ML Models (bundled resources):**
- PersonalityModelStock.mlpackage — frozen backbone CoreML model
- PersonalityHeadUpdatable.mlpackage — trainable head CoreML model
- all-MiniLM-L6-v2.mlpackage — sentence embedder model

**Target Build Settings:**
- iOS 15.0+ (or later)
- SwiftUI framework
- SwiftData framework
- CoreML framework
- Security framework

---

## 11. Dependencies

### Swift Frameworks (Built-in)
- **SwiftUI** — UI framework
- **SwiftData** — persistence (MessageRecord, ContextDocument, PersonalitySessionRecord)
- **CoreML** — on-device ML inference & training (PersonalityModelService)
- **Foundation** — basic types, URLSession, JSON coding
- **Combine** — ObservableObject, @Published
- **Accelerate** — vector math in model service
- **Security** — Keychain access (AuthService)
- **NaturalLanguage** — fallback embedding (if MiniLM unavailable)
- **BackgroundTasks** — BGProcessingTask for personality training
- **PDFKit** — PDF text extraction (ContextDocumentService)
- **UniformTypeIdentifiers** — file type filtering

### No External Dependencies
- **NO CocoaPods**
- **NO Swift Package Manager**
- All third-party functionality implemented natively or via bundled ML models

---

## 12. Tests

### Unit Tests (JourneyAppTests)
- **Journey_AppTests.swift** — template with single example test (minimal content)
- Uses Swift's native `Testing` framework (not XCTest)

### UI Tests (JourneyAppUITests)
- **Journey_AppUITests.swift** — template for UI automation tests
- **Journey_AppUITestsLaunchTests.swift** — launch performance baseline

### Current Test Coverage
- Minimal — mostly test infrastructure setup
- Future: Add tests for:
  - ChatViewModel message sending
  - PersonalityViewModel token inference
  - Repository SwiftData queries
  - APIClient request building & 401 retry
  - AuthService token refresh

---

## 13. App Entry Point & Boot Sequence

### Launch Flow

```
1. @main Journey_AppApp.swift
   ↓
2. app initializes: PersonalityTrainingScheduler.registerBackgroundTask()
   ↓
3. WindowGroup wraps RootView() with AppModelContainer.shared
   ↓
4. RootView initializes AuthService (checks Keychain for tokens)
   ↓
5. if isRefreshing: show LoadingView
     ├─ Task: await auth.refreshTokens() (attempt silent login)
     └─ Result: set isRefreshing = false
   ↓
6. Route based on isAuthenticated:
   ├─ true → MainTabView (4-tab container)
   ├─ false → AuthLandingView (login form)
   ↓
7. MainTabView initializes TabView with:
   ├─ ChatView (today's conversation)
   ├─ PersonalityTabView (past self simulation)
   ├─ CalendarView (explore past days)
   └─ SettingsView (profile & logout)
```

### Foreground/Background Handling

**On App Foreground:**
- PersonalityTrainingScheduler.checkAndTrainIfNeeded() — evaluate 14-day training condition
- AuthService.startTokenRefresher() — auto-refresh tokens every 14 minutes

**On App Background:**
- ChatView listens to `scenePhase` — on .background, calls `ChatViewModel.saveConversationAndGenerateJournal()`
- PersonalityTrainingScheduler — submits BGProcessingTask if `shouldTrain` is true

**On App Terminate:**
- SwiftData auto-saves pending changes
- Keychain persists tokens (survives app deletion)

---

## 14. Design System (DS Namespace)

All styling is centralized in `DesignSystem.swift`:

### Colors
- **Backgrounds:** background, backgroundAlt, surface, surfaceElevated (warm neutrals)
- **Accents:** sage (muted green), dustyBlue, warmYellow, softLavender, blush (pastels)
- **Text:** primary (dark brown), secondary (medium brown), tertiary (light brown), onAccent (white)
- **Semantic:** error (coral), success (sage)
- **Chat:** userBubble (dustyBlue), assistantBubble (backgroundAlt)

### Spacing
- xxs (2px), xs (4px), sm (8px), md (16px), lg (24px), xl (32px), xxl (48px)

### Radius
- xs (6px), sm (10px), md (16px), lg (22px), xl (30px), pill (9999px)

### Typography
- Font: SF Pro Rounded (via `design: .rounded`)
- Function: `DS.font(.subheadline, weight: .semibold)` or `DS.fontSize(16, weight: .medium)`

### Animations
- gentle (spring, 0.45s response, 0.80 damping)
- subtle (easeInOut, 0.28s)
- fade (easeInOut, 0.22s)

### Modifiers
- `.journeyCard()` — elevated surface with rounded corners + shadow

---

## 15. Key Architectural Decisions

1. **MVVM with Protocol Abstraction**
   - Every service/repo is protocol-backed for testability
   - ViewModels are @MainActor ObservableObjects for thread safety
   - Models are value types (structs) or SwiftData @Models

2. **No Backend Model Sync Yet**
   - Chat messages sync to SwiftData (ConversationRepository)
   - Journal entries are in-memory only (InMemoryJournalRepository)
   - Future: Replace with persistent SwiftData backend

3. **On-Device Personality Model**
   - Two-model architecture: frozen backbone + trainable head
   - Inference: embedding → latent (backbone) → logits (head) → top-k tokens
   - Training: MLUpdateTask updates only head weights (no backprop through backbone)
   - All weights stay on-device; tokens only sent to backend for context

4. **Token-Based Personality**
   - Each inference produces top-8 personality tokens (e.g., "reflective", "curious")
   - Tokens are injected into personality prompt sent to backend
   - Vocabulary: 325 tokens loaded from `personality-tokens.json`

5. **14-Day Training Cycle**
   - Personality model auto-trains when 14+ days pass since last training
   - Can trigger manually or in background (BGProcessingTask)
   - Training uses last 14 days of conversation + memory documents

6. **Lightweight Token Storage**
   - AuthService stores access/refresh tokens in Keychain (never in UserDefaults)
   - Each token is Data, converted to/from UTF-8 on access
   - Session restored on app launch from Keychain

7. **Async/Await Throughout**
   - No callbacks or RxSwift — pure async/await
   - ViewModels dispatch Tasks for background work
   - Repositories (ConversationRepository, PersonalityRepository) are async-aware

8. **Deferred Backend Integration**
   - JournalRepository currently in-memory (InMemoryJournalRepository)
   - Can swap to SwiftData-backed version when backend is ready
   - Protocol design allows transparent migration

---

## 16. Future Roadmap

### Short-term
- Implement SwiftDataJournalRepository (currently in-memory)
- Add unit tests for ViewModels & services
- Implement BugReportService (currently a stub)
- Polish UI animations & transitions

### Medium-term
- Offline-first sync strategy for chat messages
- Multi-model personality support (fine-tuned variants)
- Conversation search / filtering
- Export conversation / journal as PDF

### Long-term
- Push notifications for model training completion
- Sync to iCloud / multi-device support
- Rich media support (photos, voice notes)
- Integration with Apple Health / Mindfulness

---

## 17. Build & Run Instructions

### Requirements
- Xcode 15.0+
- iOS 15.0+ target
- M1/M2 Mac (or Intel with Rosetta) for Xcode
- Internet connection (for backend API)

### Build
```bash
cd /Users/yuyang/Documents/Journey/frontend
open JourneyApp.xcodeproj
# In Xcode: Product → Build (⌘B)
```

### Run
```bash
# In Xcode: Product → Run (⌘R) on simulator or device
```

### Debug
- Set breakpoints in Xcode editor
- View [APIClient] logs in console (network requests/responses)
- Set LLDB breakpoints in SwiftUI previews

### Clean
```bash
# In Xcode: Product → Clean Build Folder (⇧⌘K)
rm -rf ~/Library/Developer/Xcode/DerivedData/Journey*
```

---

## Summary

**Journey** is a fully-featured iOS journaling app with:
- ✅ Chat-based interface for daily reflection
- ✅ AI-powered journal generation
- ✅ On-device personality model (inference & training)
- ✅ Persistent local storage (SwiftData)
- ✅ Secure authentication (Keychain tokens, refresh cycle)
- ✅ Calendar grid with data visualization
- ✅ Memory/context document import
- ✅ Background task scheduling
- ✅ Calm, reflective design system
- ✅ Protocol-based architecture for testability

Built with **SwiftUI**, **SwiftData**, **CoreML**, and **Async/Await** — no external dependencies.

---

**Last Updated:** March 7, 2026
**Codebase Stats:** 56 Swift files, ~12K lines of Swift code, 4 ML models bundled
