# Architecture

## System overview

```
┌──────────────────┐    HTTPS/JSON     ┌─────────────────────┐    HTTPS    ┌──────────┐
│   iOS app        │ ◄───────────────► │  Fastify backend     │ ◄─────────► │  OpenAI  │
│   (SwiftUI)      │   JWT in header   │  (Node 20 + TS)      │  API key    │   API    │
│                  │                   │                      │  decrypted  │          │
│ Keychain:        │                   │  ┌────────────────┐  │  per req    └──────────┘
│ - access token   │                   │  │  Mongoose ODM  │  │
│ - refresh token  │                   │  └────────┬───────┘  │
└──────────────────┘                   └───────────┼──────────┘
                                                   │
                                            ┌──────▼──────┐
                                            │  MongoDB    │
                                            │  (Atlas)    │
                                            └─────────────┘
```

Critical invariant: **the OpenAI API key only ever exists in three places** — (1) the household admin's memory when they paste it, (2) plaintext in a single backend request handler when proxying to OpenAI, (3) AES-256-GCM ciphertext in the `households` collection. It is never logged, never returned in any API response, never sent to the iOS client.

## Data model (MongoDB)

All collections use `_id: ObjectId`, `createdAt`, `updatedAt` (via Mongoose `timestamps`).

### `users`
| Field | Type | Notes |
|---|---|---|
| `email` | string, unique, lowercased | |
| `passwordHash` | string | Argon2id |
| `displayName` | string | shown in feed/leaderboard |
| `currentHouseholdId` | ObjectId? | last-used household for fast app launch |

### `households`
| Field | Type | Notes |
|---|---|---|
| `name` | string | |
| `inviteCode` | string, unique, 8 chars uppercase alphanum | regenerable by admin |
| `adminUserId` | ObjectId → users | the only one who can rotate the OpenAI key |
| `openAIKey` | `{ ciphertext, iv, tag }` \| null | AES-256-GCM, see `services/crypto.ts` |
| `openAIKeySetAt` | Date \| null | for "key was last set on ..." UI |

### `householdMembers` (join table; users ↔ households is many-to-many)
| Field | Type | Notes |
|---|---|---|
| `householdId` | ObjectId → households, indexed | |
| `userId` | ObjectId → users, indexed | |
| `role` | "admin" \| "member" | |
| `joinedAt` | Date | |
| `currentStreak` | number | days in a row with ≥1 completion |
| `longestStreak` | number | |
| `lastCompletionAt` | Date \| null | drives streak computation |

Compound unique index on `{ householdId, userId }`.

### `rooms`
| Field | Type | Notes |
|---|---|---|
| `householdId` | ObjectId → households, indexed | |
| `name` | string | "Kitchen", "Living Room" |
| `icon` | string \| null | SF Symbol name |
| `archived` | boolean, default false | soft-delete |

### `chores`
| Field | Type | Notes |
|---|---|---|
| `householdId` | ObjectId → households, indexed | |
| `roomId` | ObjectId → rooms, indexed | |
| `title` | string | |
| `description` | string \| null | |
| `recurrence` | `{ kind: "none" \| "daily" \| "weekly" \| "monthly", weekdays?: number[], dayOfMonth?: number }` | |
| `estimatedMinutes` | number \| null | |
| `points` | number, default 1 | toward streaks/leaderboard |
| `createdByUserId` | ObjectId → users | |
| `source` | "manual" \| "ai_text" \| "ai_image" | for analytics |
| `archived` | boolean, default false | |

### `completions`
| Field | Type | Notes |
|---|---|---|
| `choreId` | ObjectId → chores, indexed | |
| `householdId` | ObjectId → households, indexed | denormalized for query speed |
| `completedByUserId` | ObjectId → users, indexed | |
| `completedAt` | Date, indexed (desc) | |
| `notes` | string \| null | |

### `generationJobs` (audit trail)
| Field | Type | Notes |
|---|---|---|
| `householdId` | ObjectId → households, indexed | |
| `requestedByUserId` | ObjectId → users | |
| `inputType` | "text" \| "image" | |
| `inputSummary` | string | first 200 chars of prompt, or "image:<sha256>" |
| `model` | string | e.g. "gpt-4o-2024-08-06" |
| `tokenUsage` | `{ prompt: number, completion: number }` | from OpenAI response |
| `createdChoreIds` | ObjectId[] | |

This collection lets us spot abuse, debug bad generations, and show the user a history.

## API contract (v1)

Base URL: `http://localhost:8080` (dev), `https://choresapp.example.com` (prod).
All non-auth endpoints require `Authorization: Bearer <accessToken>`.
All requests/responses are JSON unless noted.

### Auth

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/auth/signup` | `{ email, password, displayName }` | `{ accessToken, refreshToken, user }` |
| POST | `/auth/login` | `{ email, password }` | `{ accessToken, refreshToken, user }` |
| POST | `/auth/refresh` | `{ refreshToken }` | `{ accessToken, refreshToken }` |
| POST | `/auth/logout` | — | `204` |

Access token TTL: 15 min. Refresh token TTL: 30 days, single-use (rotated on every refresh).

### Households

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/households` | `{ name }` | `{ household, membership }` (caller becomes admin) |
| GET | `/households/me` | — | `Household[]` (all households the caller belongs to) |
| GET | `/households/:id` | — | `{ household, members }` |
| POST | `/households/join` | `{ inviteCode }` | `{ household, membership }` |
| POST | `/households/:id/regenerate-invite` | — (admin only) | `{ inviteCode }` |
| PUT | `/households/:id/openai-key` | `{ key }` (admin only) | `204` (key validated by a $0 test call to OpenAI before persisting) |
| DELETE | `/households/:id/openai-key` | — (admin only) | `204` |
| GET | `/households/:id/openai-key/status` | — | `{ isSet: boolean, setAt: string \| null }` (never returns the key) |

### Rooms

| Method | Path | Body | Returns |
|---|---|---|---|
| GET | `/households/:id/rooms` | — | `Room[]` |
| POST | `/households/:id/rooms` | `{ name, icon? }` | `Room` |
| PUT | `/households/:id/rooms/:roomId` | `{ name?, icon?, archived? }` | `Room` |

### Chores

| Method | Path | Body | Returns |
|---|---|---|---|
| GET | `/households/:id/chores` | query: `?roomId=&includeArchived=` | `Chore[]` |
| POST | `/households/:id/chores` | `{ roomId, title, description?, recurrence, estimatedMinutes?, points? }` | `Chore` |
| PUT | `/households/:id/chores/:choreId` | partial chore | `Chore` |
| DELETE | `/households/:id/chores/:choreId` | — | `204` (soft delete via `archived: true`) |
| POST | `/households/:id/chores/:choreId/complete` | `{ notes? }` | `{ completion, membership }` (returns updated streak) |

### Generation

| Method | Path | Body | Returns |
|---|---|---|---|
| POST | `/households/:id/generate/text` | `{ prompt, roomId? }` | `{ jobId, suggestedChores: ChoreDraft[] }` |
| POST | `/households/:id/generate/image` | `{ imageBase64, mimeType, roomId? }` | `{ jobId, suggestedChores: ChoreDraft[] }` |
| POST | `/households/:id/generate/:jobId/accept` | `{ acceptedIndices: number[] }` | `Chore[]` (the persisted ones) |

`ChoreDraft` is a chore-shaped object with no `_id` — the iOS app shows them in a sheet and the user picks which to keep. Only on accept do they hit the DB.

Rate limit: 30 generation requests per household per hour. Reject with 429.

### Feed & stats

| Method | Path | Returns |
|---|---|---|
| GET | `/households/:id/feed?limit=50` | `Completion[]` (most recent, with chore + user expanded) |
| GET | `/households/:id/leaderboard?period=week` | `{ userId, displayName, points, currentStreak }[]` |

### Errors

All errors return:
```json
{ "error": { "code": "STRING_CODE", "message": "Human readable", "details": {} } }
```

Standard codes: `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `VALIDATION_FAILED`, `RATE_LIMITED`, `OPENAI_KEY_MISSING`, `OPENAI_FAILED`, `INTERNAL`.

## Auth & authorization flow

1. Sign up / log in returns `{accessToken, refreshToken}`. iOS stores both in **Keychain** (not UserDefaults).
2. Every authenticated request: `Authorization: Bearer <accessToken>`.
3. On 401, iOS attempts a refresh once. If refresh also fails, log the user out.
4. **Authorization for household-scoped routes**: `requireMembership` middleware loads `householdMembers` for `(authedUserId, params.householdId)`. If no row exists, return 403. The middleware attaches `request.membership` (`role`, etc.) for downstream handlers.
5. **Admin-only routes** (`PUT /households/:id/openai-key`, etc.) additionally check `request.membership.role === "admin"`.

## OpenAI proxy: how generation actually works

### Text path (`POST /households/:id/generate/text`)

1. Validate body with Zod.
2. Verify caller is a member of the household (middleware).
3. Load household. If `openAIKey == null`, return 400 `OPENAI_KEY_MISSING`.
4. Decrypt the key in-memory (never logged).
5. Build an OpenAI client, call `chat.completions.create` with `model: "gpt-4o-mini"` and **structured outputs** (`response_format: { type: "json_schema", schema: ChoreListSchema }`). System prompt instructs the model to return an array of chore drafts shaped like `{ title, description, suggestedRoomName, recurrence, estimatedMinutes }`.
6. Map response → `ChoreDraft[]`. If `roomId` was provided, lock all drafts to that room. Otherwise, fuzzy-match `suggestedRoomName` against existing rooms (or mark as "new room needed").
7. Persist a `generationJob` row with token usage; return `{ jobId, suggestedChores }`.

### Image path (`POST /households/:id/generate/image`)

Same flow, but:
- Body is `{ imageBase64, mimeType: "image/jpeg" | "image/png", roomId? }`. Validate `imageBase64` size (reject > 4 MB before decoding).
- Send to OpenAI as `gpt-4o` with the image in the user message content (`{type:"image_url", image_url:{url:"data:<mime>;base64,..."}}`).
- We do **not** persist the image. Hash it (SHA-256) for the audit trail and discard.

### Accept path

The user picks which suggested chores to keep, the app POSTs `{ acceptedIndices }`, the backend writes them to `chores` with `source: "ai_text" | "ai_image"`. This split lets us avoid creating clutter in the DB from rejected suggestions.

## Streak computation

When a completion is recorded:
1. Load the caller's `householdMembers` row.
2. Let `last = membership.lastCompletionAt` (date in user's local TZ, sent as `?tz=` query). If `last` is yesterday → `currentStreak += 1`. If `last` is today → no change. If older than yesterday → `currentStreak = 1`.
3. `longestStreak = max(longestStreak, currentStreak)`.
4. `lastCompletionAt = now`.
5. Save and return.

Edge case: timezone. Until v2, the iOS app sends its IANA TZ on each completion request. The server uses it to compute "yesterday" boundaries. Document this in code comments.

## Security model summary

| Threat | Mitigation |
|---|---|
| API key extraction from binary | Key never on device |
| Key dump from DB breach | AES-256-GCM with separate `KEY_ENCRYPTION_SECRET` env var (key encryption key not in DB) |
| Cross-household data leak | All queries filter by `householdId` from middleware, not request body |
| Brute-force login | Rate limit `/auth/login` to 10/min/IP; Argon2id password hashing |
| Stolen access token | Short TTL (15 min); refresh tokens rotate single-use |
| Generation abuse (cost) | 30 req/hr/household rate limit; image size cap; audit log |
| MITM | HTTPS only in prod; ATS enforced on iOS |

## Future architecture notes (v2+)

- **Push notifications**: introduce APNs. Backend stores device tokens per user, sends a push when a completion is recorded for a chore the user is "watching".
- **Realtime**: SSE (`/households/:id/stream`) is simpler than websockets for one-way server→client updates.
- **Image storage**: if we ever want to keep the image, it goes to S3/R2 with signed URLs, never base64 in Mongo.
