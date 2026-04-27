# ChoresApp — Project Memory

This file is the entry point for any Claude (or human) working in this repo. **Read this first, then read `BUILD_PLAN.md`.**

## What this is

A two-part product:

1. **iOS app** (SwiftUI, iOS 17+): household members log in, see chores grouped by room, mark them complete, earn streaks, and trigger AI chore generation from a text description or a photo of a room.
2. **Backend API** (Node.js + Fastify + MongoDB): owns auth, households, chores, completions, and proxies all OpenAI calls using a household-level API key.

The user is **Korbin Hillan** (`khillan5223@gmail.com`). Bundle ID prefix `com.korbinhillan`.

## The single most important architectural decision

**OpenAI API keys never live on a phone and never live in source.** One designated household admin sets the family's OpenAI key via the iOS app. The backend encrypts it with AES-256-GCM (key derived from `KEY_ENCRYPTION_SECRET`) and stores it on the `households` document. All generation requests go: **iPhone → our backend → OpenAI**.

This is non-negotiable. Do not add code paths that send the key to the client, log it, or store it unencrypted.

## Repo layout

```
ChoresApp/
├── CLAUDE.md              ← you are here
├── ARCHITECTURE.md        ← system design, data model, API contract
├── MVP_SPEC.md            ← feature list with acceptance criteria
├── BUILD_PLAN.md          ← phased roadmap. Work one phase at a time.
├── README.md              ← quick start for humans
├── ios/                   ← SwiftUI app
│   ├── project.yml          XcodeGen spec (the .xcodeproj is generated, not committed)
│   ├── Sources/ChoresApp/   App code, organized by feature
│   └── Tests/ChoresAppTests/
└── server/                ← Fastify + Mongoose API
    ├── src/
    │   ├── config/          env validation
    │   ├── db/              Mongo connection
    │   ├── routes/          HTTP handlers (one file per resource)
    │   ├── services/        business logic (openai, crypto)
    │   ├── middleware/      auth, error handler
    │   ├── models/          Mongoose schemas
    │   └── utils/
    └── tests/             Vitest
```

## Tech stack & rationale

| Layer | Choice | Why |
|---|---|---|
| iOS UI | SwiftUI | First-class on iOS 17+, less boilerplate than UIKit |
| iOS persistence | SwiftData (local cache) + REST to backend | SwiftData gives offline-friendly cache; backend is source of truth |
| iOS networking | `URLSession` + `async/await` | No third-party HTTP dep needed |
| iOS auth storage | Keychain | Refresh + access tokens only — never API keys |
| Backend runtime | Node.js 20 LTS + TypeScript (strict) | Best OpenAI SDK ergonomics, fast iteration |
| Backend framework | Fastify | Faster than Express, first-class schema validation, plugin model |
| Validation | Zod | Single source of truth for request/response shapes |
| Database | MongoDB (Atlas free tier) | User chose it; document model fits chore/household graphs well |
| ODM | Mongoose | Schema enforcement on a flexible store |
| Auth | `@fastify/jwt` + Argon2id password hash | Argon2id beats bcrypt; JWT keeps backend stateless |
| Secret encryption | Node `crypto` AES-256-GCM | OpenAI keys at rest |
| OpenAI | Official `openai` npm SDK; `gpt-4o-mini` for text, `gpt-4o` for vision | Mini is ~10x cheaper for text-only; vision needs 4o |
| Tests | Vitest (server), XCTest (iOS) | Fast, native to each ecosystem |
| Hosting (planned) | Render or Fly.io free tier + MongoDB Atlas free tier | Zero-cost MVP |

## Hard rules

These are violations, not preferences:

1. **No secrets in source or in client code.** OpenAI keys, JWT secrets, Mongo URIs all come from env vars on the server. The iOS app never sees an OpenAI key.
2. **No raw passwords stored or logged anywhere.** Argon2id hash only. Never log a request body that could contain a password.
3. **All inbound request bodies validated with Zod** before they touch business logic. Reject with 400 on parse failure.
4. **Auth required on every endpoint except `/health`, `/auth/signup`, `/auth/login`.** The `requireAuth` middleware must be applied — no implicit "public" routes.
5. **Multi-tenant isolation**: every chore/room/completion query MUST filter by `householdId` taken from the authenticated user's membership, not from the request body. Never trust client-supplied `householdId` without verifying membership.
6. **No `any` in TypeScript.** If you need an escape hatch, use `unknown` and narrow.
7. **No force-unwraps in Swift** (`!`) outside of test code and `#Preview`. Use `guard let` / `if let` / `try?`.
8. **No `print` in shipped Swift code** and no `console.log` on the server. Use the structured logger (`pino` on server, `os_log` / `Logger` on iOS).
9. **Rate-limit the OpenAI endpoints** (`/households/:id/generate/*`) — they cost money and could be abused.

## Coding conventions

### TypeScript (server)

- ES modules (`"type": "module"`). Import paths end in `.js` even when sources are `.ts` (Node ESM requirement).
- One resource per route file. Routes register with Fastify under their plugin scope (e.g. `app.register(choresRoutes, { prefix: "/households/:householdId/chores" })`).
- Mongoose models in `src/models/`. Schemas use `timestamps: true` and `versionKey: false`.
- Errors: throw a typed `AppError(statusCode, code, message)` from `utils/errors.ts`. The error handler middleware turns it into a JSON response. Never let raw Mongoose / OpenAI errors leak to clients.
- Tests live in `server/tests/`, mirror `src/` structure, named `*.test.ts`.

### Swift (iOS)

- SwiftUI views are small (under ~80 lines). Extract subviews liberally.
- State: `@Observable` view models for screens with logic; `@State` for purely local UI state. Don't reach for Combine unless we hit a real need.
- Networking goes through one `APIClient` actor. View models call the client; views never call the client directly.
- Errors surface to the UI as a typed `enum APIError` rendered by a shared `ErrorBanner`. Don't swallow errors.
- Group code by **feature** (`Features/Chores/...`), not by type (`Models/`, `Views/`, `ViewModels/`). Cross-feature primitives live in `DesignSystem/`, `Networking/`, `Persistence/`.

## Running locally

### Backend

```bash
cd server
npm install
cp .env.example .env   # fill in MONGO_URI, JWT_SECRET, KEY_ENCRYPTION_SECRET
npm run dev            # http://localhost:8080/health should return {status:"ok"}
```

A local Mongo via `brew install mongodb-community && brew services start mongodb-community` works for dev. Production uses Atlas.

### iOS

```bash
brew install xcodegen        # one-time
cd ios
xcodegen generate            # produces ChoresApp.xcodeproj (gitignored)
open ChoresApp.xcodeproj
```

Then ⌘R. The simulator hits `http://localhost:8080` by default (configured via `ApiBaseURL` in the generated Info.plist — see `ios/project.yml`).

## How to work in this repo

- **Always read `BUILD_PLAN.md` and pick exactly one phase.** Don't half-finish two phases. Each phase has a "Done when" checklist — meet all of it before moving on.
- **Reference `ARCHITECTURE.md` for the data model and API contract** before adding a new endpoint or schema. If you need to deviate, update that doc *in the same change*.
- **Update `MVP_SPEC.md` if you change user-visible behavior.** The spec is the source of truth for what the app does.
- For any new dependency, justify it in the PR description and add it to the table above if it's load-bearing.

## What this app is *not* (anti-scope for v1)

To prevent bloat, the following are explicitly out of v1:
- Push notifications (APNs) — local notifications only
- Real-time sync (websockets/SSE) — polling on app foreground + pull-to-refresh
- Photo evidence on completion
- Chore assignment to specific users / auto-rotation between members
- Reward redemption / allowance integration
- Soft delete / restore for chores and rooms (the user-facing destructive action is hard `DELETE` with a confirmation dialog)
- Calendar integration
- Web client
- Android
- Gamification beyond per-user streak counts and the weekly leaderboard

These are tracked for v2 in `BUILD_PLAN.md` but should not creep into v1 PRs.

**Already shipped beyond the original v1 scope** (don't re-add these as new work):
- Multi-household switching via Profile → Switch household
- Biometric session lock (Face ID / Touch ID / Optic ID), opt-in per device, gates the UI not the API session
- Per-household rate limit on `/generate/*` (30 req/hr/household, in addition to the global per-IP limit)
