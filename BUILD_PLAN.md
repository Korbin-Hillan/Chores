# Build Plan

This is the phased roadmap. **Pick exactly one phase. Finish it. Move on.** Each phase ends with a "Done when" checklist that must be 100% green before opening the PR.

The intent is that another Claude (Sonnet) can pick up any phase below, read the referenced sections of `ARCHITECTURE.md` and `MVP_SPEC.md`, and ship it.

---

## Phase 0 — Skeleton (this commit)

**Goal:** the repo builds and boots end-to-end with placeholder screens and a `/health` endpoint.

**Deliverables:**
- Monorepo layout (`ios/`, `server/`)
- Planning docs: `CLAUDE.md`, `ARCHITECTURE.md`, `MVP_SPEC.md`, `BUILD_PLAN.md`, `README.md`
- Backend: Fastify boot, env validation, Mongo connection, `/health` route, Vitest set up, ESLint/Prettier
- iOS: XcodeGen `project.yml`, SwiftUI app target with a "Skeleton ready" placeholder view, XCTest target

**Done when:**
- [ ] `cd server && npm install && npm run dev` starts on port 8080 and `/health` returns `{"status":"ok"}`.
- [ ] `cd server && npm test` runs and passes (even if only a smoke test).
- [ ] `cd ios && xcodegen generate && xcodebuild -scheme ChoresApp -destination 'generic/platform=iOS Simulator' build` succeeds.
- [ ] Repo has the planning docs at the root.

---

## Phase 1 — Auth & households

**Goal:** users can sign up, log in, create a household, get an invite code, and join one.

**Backend tasks:**
1. Add Mongoose models: `User`, `Household`, `HouseholdMember` (see `ARCHITECTURE.md` → Data model).
2. Add `services/passwords.ts` (Argon2id hash + verify).
3. Add `services/tokens.ts` (issue + verify access/refresh JWTs; refresh tokens stored hashed in `refreshTokens` collection with single-use rotation).
4. Add `middleware/requireAuth.ts` and `middleware/requireMembership.ts` (the latter loads `HouseholdMember` and 403s if not a member; attaches `request.membership` for handlers).
5. Implement routes:
   - `POST /auth/signup`, `POST /auth/login`, `POST /auth/refresh`, `POST /auth/logout`
   - `POST /households`, `GET /households/me`, `GET /households/:id`, `POST /households/join`, `POST /households/:id/regenerate-invite`
6. Generate invite codes from a 32-char alphabet excluding `0/O/I/1`.
7. Vitest integration tests for each route, using `mongodb-memory-server`.

**iOS tasks:**
1. Add `Networking/APIClient.swift` (single `actor`, generic `request<Req, Res>` method, attaches Bearer token from `AuthStore`).
2. Add `Persistence/KeychainStore.swift` (read/write/delete for access + refresh tokens).
3. Add `Networking/AuthStore.swift` (`@Observable`; loads tokens on launch, exposes `isLoggedIn`, handles sign-up/login/logout/refresh).
4. Add `Features/Auth/`: `WelcomeView`, `SignUpView`, `LoginView`.
5. Add `Features/Households/`: `HouseholdOnboardingView` (Create or Join), `CreateHouseholdView`, `JoinHouseholdView`.
6. Wire `RootView` to switch between Auth / Onboarding / Main based on `AuthStore.state`.
7. Add an `APIError` enum and a reusable `ErrorBanner` view modifier.

**Done when:**
- [ ] All backend tests for auth + households pass.
- [ ] In the simulator: sign up → land on Create/Join → create household → see the invite code on screen.
- [ ] Quitting and relaunching the app keeps me logged in (tokens survive in Keychain).
- [ ] A second simulator device can join with the invite code.

---

## Phase 2 — Rooms & chores (manual)

**Goal:** household members can manage rooms and chores, and mark them complete.

**Backend tasks:**
1. Add models: `Room`, `Chore`, `Completion`.
2. Implement routes for rooms and chores per `ARCHITECTURE.md`.
3. Implement `POST /households/:id/chores/:choreId/complete` with streak update logic (see `ARCHITECTURE.md` → Streak computation). Accepts `?tz=America/Los_Angeles` query.
4. Implement `GET /households/:id/feed` (recent completions with `chore` and `user` populated).
5. Tests for each.

**iOS tasks:**
1. Add `Models/APIModels.swift` with `Codable` mirrors of API types (Room, Chore, Completion, Recurrence).
2. Add `Features/Chores/ChoreListView.swift` — sectioned by room.
3. Add `Features/Chores/ChoreDetailView.swift`.
4. Add `Features/Chores/ChoreEditorView.swift` (create + edit).
5. Add `Features/Chores/RoomEditorView.swift`.
6. Add `Features/Chores/ChoresViewModel.swift` (`@Observable`, owns the chore list, refresh, complete actions).
7. Add a Feed tab using `Features/Feed/FeedView.swift`.
8. Add SwiftData models that mirror the server types and act as an offline cache (load from cache on launch, then refresh from server).

**Done when:**
- [ ] I can add a room, add a chore in it, mark it complete, and see the entry in the Feed tab.
- [ ] My streak goes from 0 → 1 after the first completion of the day, and doesn't increase on a second completion the same day.
- [ ] Closing the app and reopening it offline still shows my chores (from SwiftData cache).

---

## Phase 3 — OpenAI key management & text generation

**Goal:** admin sets a family OpenAI key; any member can generate chores from a description.

**Backend tasks:**
1. Implement `services/crypto.ts` (already scaffolded — round-trip test).
2. Implement `services/openai.ts`:
   - `validateKey(key): Promise<boolean>` — calls `models.list()`.
   - `generateChoresFromText(key, prompt, existingRoomNames): Promise<ChoreDraft[]>` — uses `gpt-4o-mini` with `response_format: json_schema`. Schema documented in this file below.
3. Implement routes:
   - `PUT /households/:id/openai-key` (admin-only; validates before persisting; never returns the key)
   - `DELETE /households/:id/openai-key` (admin-only)
   - `GET /households/:id/openai-key/status` (any member)
   - `POST /households/:id/generate/text`
   - `POST /households/:id/generate/:jobId/accept`
4. Add `@fastify/rate-limit` plugin scoped to generation routes (30/hr/household).
5. Persist `generationJobs` rows.
6. Tests with the OpenAI client mocked.

**iOS tasks:**
1. Add `Features/Households/FamilyKeyView.swift` (admin-only UI to paste/replace/remove the key; shows status for non-admins).
2. Add `Features/Generation/GenerateSheet.swift` (entry point: pick text vs photo).
3. Add `Features/Generation/GenerateFromTextView.swift`.
4. Add `Features/Generation/SuggestedChoresView.swift` (toggleable list, "Save selected" CTA).
5. Wire the Chores tab "Generate" button to present `GenerateSheet`.
6. Show a friendly empty state when no key is set, with the admin's name from the household members list.

**Done when:**
- [ ] As admin, I can paste a real OpenAI key and see "Key set on {date}". Backend logs do not contain the key.
- [ ] As a member, I can describe my home in 1–2 sentences, see a list of suggested chores, toggle them, and save 5 to the household. They appear in the chore list with `source: "ai_text"` (visible in DB).
- [ ] Hitting the endpoint 31 times in an hour returns 429.

**JSON schema for text generation response (use as `response_format`):**

```json
{
  "name": "chore_suggestions",
  "schema": {
    "type": "object",
    "properties": {
      "chores": {
        "type": "array",
        "items": {
          "type": "object",
          "properties": {
            "title": { "type": "string", "maxLength": 80 },
            "description": { "type": "string", "maxLength": 300 },
            "suggestedRoomName": { "type": "string", "maxLength": 40 },
            "recurrence": {
              "type": "object",
              "properties": {
                "kind": { "type": "string", "enum": ["none", "daily", "weekly", "monthly"] },
                "weekdays": { "type": "array", "items": { "type": "integer", "minimum": 0, "maximum": 6 } },
                "dayOfMonth": { "type": "integer", "minimum": 1, "maximum": 31 }
              },
              "required": ["kind"],
              "additionalProperties": false
            },
            "estimatedMinutes": { "type": "integer", "minimum": 1, "maximum": 240 }
          },
          "required": ["title", "suggestedRoomName", "recurrence"],
          "additionalProperties": false
        }
      }
    },
    "required": ["chores"],
    "additionalProperties": false
  },
  "strict": true
}
```

System prompt sketch:
> You are a helpful assistant that generates realistic, specific household chores for a family. Given a description of a home, return 5–12 chores. Prefer concrete, actionable titles ("Wipe down stovetop") over vague ones ("Clean kitchen"). Suggest a room name; pick from this list of existing rooms when reasonable: {roomNames}. Otherwise propose a new short room name. Choose recurrence based on the chore's nature.

---

## Phase 4 — Image generation

**Goal:** members can take a photo of a room and get tailored chores.

**Backend tasks:**
1. Add `generateChoresFromImage(key, imageBase64, mimeType, existingRoomNames)` to `services/openai.ts`. Use `gpt-4o` with `image_url: data:<mime>;base64,...` content.
2. Add `POST /households/:id/generate/image`. Validate `imageBase64.length < 4 * 1024 * 1024 * (4/3)` (base64 expansion).
3. Hash image (SHA-256) for the audit trail; never persist the image bytes.
4. Tests with mocked OpenAI.

**iOS tasks:**
1. Add `Features/Generation/GenerateFromImageView.swift` with a `PhotosPicker` and `UIImagePickerController` (camera) wrapper.
2. Downscale the image to max 1280 px on the long edge before base64 encoding.
3. Show a thumbnail of the chosen photo while waiting on the response.
4. Reuse `SuggestedChoresView` for the accept flow.

**Done when:**
- [ ] I can point my phone at my kitchen, generate, and see kitchen-specific chores.
- [ ] Backend logs do not include any base64 payloads.

---

## Phase 5 — Local notifications & polish

**Goal:** members get a daily reminder of due chores. App feels finished.

**iOS tasks:**
1. Request notification permission on first visit to the Profile tab.
2. Schedule a daily local notification at the user's chosen time (default 9 AM) listing today's due chores.
3. Recompute the schedule when chores or recurrence change.
4. Empty states for: no households, no rooms, no chores in a room, no key set.
5. Loading skeletons (or `ProgressView`) for all network-driven screens.
6. Pull-to-refresh on Chores and Feed tabs.
7. Accessibility: every tappable element has a label; Dynamic Type works up to XXL.
8. Light/dark mode visual pass.

**Done when:**
- [ ] At the configured time, I get a notification listing my due chores.
- [ ] No screen has placeholder text like "TODO" or unstyled controls.
- [ ] VoiceOver can complete the create-chore flow.

---

## Phase 6 — Deploy

**Goal:** backend running in staging on a real domain; iOS build on TestFlight.

**Tasks:**
1. Provision MongoDB Atlas free cluster.
2. Deploy backend to Render (Dockerfile or native Node service). Set env vars from `.env.example`.
3. Configure ATS exception only if necessary; prefer a real HTTPS domain.
4. Update `ApiBaseURL` build setting in `ios/project.yml` for the Release config to point at staging.
5. Apple Developer account: app ID, provisioning, TestFlight build.
6. Smoke test: full MVP flow end-to-end against staging from a TestFlight build on a real device.

**Done when:**
- [ ] Definition of MVP done from `MVP_SPEC.md` is satisfied against the deployed backend.

---

## v2 backlog (do not start during v1)

- APNs push notifications (server-side, including Live Activities for active chore generation)
- Sign in with Apple
- Realtime sync via SSE (`GET /households/:id/stream`)
- Photo evidence on completion (with R2/S3 storage)
- Per-member assignment + auto-rotation
- iPad-optimized split view
- Apple Watch complication for streak
- Localization (start with es-MX)
