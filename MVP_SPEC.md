# MVP Spec

The MVP is the smallest version of ChoresApp that delivers the full experience: a household signs up, sets an OpenAI key, generates chores, and tracks them collaboratively.

## In scope (v1)

### 1. Account & household onboarding

**As a new user, I can:**
- Sign up with email + password + display name.
- Log in.
- Create a new household (I become its admin) — and get an 8-character invite code.
- Or join an existing household using an invite code from another member.
- Switch between households I belong to.

**Acceptance:**
- Passwords < 8 chars are rejected client-side and server-side.
- Invite codes are case-insensitive, alphanumeric, exclude ambiguous chars (no `0/O/I/1`).
- A user not in any household lands on a "Create or join" screen after first login.

### 2. Family OpenAI key (admin only)

**As the admin, I can:**
- Open Household Settings → Family AI Key.
- Paste an OpenAI key. The app sends it to the backend, which validates it against OpenAI (a $0 models.list call) and only persists if valid.
- See "Key set on April 10, 2026" — never the key itself.
- Remove the key.

**As a non-admin, I can:**
- See whether a key is set, but not view it or change it.

**Acceptance:**
- Trying to generate chores with no key set shows a clear empty state with a "Ask your admin to set the family AI key" message (with the admin's name).

### 3. Rooms

**As a member, I can:**
- See a list of rooms in my household.
- Add a new room with a name and an optional SF Symbol icon.
- Edit a room's name and icon.
- **Delete a room.** Deletion is permanent and cascades: every chore in that room and every completion record for those chores is removed. The UI confirms with a destructive dialog naming the room before deleting.

### 4. Chores — manual

**As a member, I can:**
- View chores grouped by room.
- Create a chore in a room with: title, optional description, recurrence (none / daily / weekly on selected weekdays / monthly on day N), optional estimated minutes, optional points (default 1).
- Edit a chore.
- **Delete a chore.** Deletion is permanent and removes the chore plus every completion record for it. There is no archive/restore in v1.

**Acceptance:**
- Recurring chores show their next due date in the list.
- The DELETE action requires a destructive confirmation dialog naming the chore.
- Streak history and the global feed are not affected by deleting a chore the user did not complete; they only lose the rows tied to the deleted chore itself.

### 5. Chores — AI generation from text

**As a member with a household key set, I can:**
- Tap "Generate" → "From description".
- Type something like *"3 bedroom 2 bathroom apartment with a dog and two kids under 5"*.
- See a sheet of suggested chores (each with title, room, recurrence, estimated minutes).
- Toggle which ones I want, then Save → they get added to the household.

**Acceptance:**
- Suggestions never auto-save. The user always confirms.
- If the model proposes a room that doesn't exist yet, the suggestion shows "+ New room: {name}" and creates the room on accept.
- Generation failures (network, OpenAI error, rate limit) surface a non-blocking banner with a retry button.

### 6. Chores — AI generation from a photo

**As a member with a household key set, I can:**
- Tap "Generate" → "From a photo".
- Take a photo OR pick one from my library.
- See suggested chores tailored to what's visible (e.g. "Wipe stovetop", "Empty crumb tray on toaster").
- Same accept/reject flow as text.

**Acceptance:**
- Camera and photo library prompts use the strings in `Info.plist` (NSCameraUsageDescription / NSPhotoLibraryUsageDescription).
- The image is sent once to the backend, used for one OpenAI call, and discarded. Not stored anywhere.
- Images larger than 4 MB are downscaled client-side before upload.

### 7. Completing chores

**As a member, I can:**
- Tap a chore → mark complete (optional notes).
- See a household feed: "Sarah completed Vacuum living room — 5 min ago".
- See my current streak and longest streak on my profile tab.

**Acceptance:**
- Completing the same recurring chore twice in the same recurrence window is allowed (we don't block; some households want it).
- Streak only increments once per calendar day per user (using their device timezone).

### 8. Reminders (local notifications)

**As a member, I can:**
- Grant notification permission.
- Get a local reminder for chores assigned to my household that are due "today" (recurrence-based), at a configurable daily reminder time (default 9 AM local).

**Acceptance:**
- Notifications are scheduled locally on iOS — no server push in v1.
- Notification only fires if the chore hasn't already been completed today.
- Disabling notifications in iOS Settings is respected; we don't nag.

### 9. Leaderboard

**As a member, I can:**
- See a weekly leaderboard for my household: total points completed, current streak, member.
- Default sort is points-this-week descending.

### 10. Multi-household switching

**As a member of more than one household, I can:**
- Open Profile → "Switch household" and pick which household the rest of the app shows.
- The selected household persists in Keychain so the app reopens to it.

**Acceptance:**
- Members with exactly one household never see the picker UI.
- Switching is instant — every tab re-runs its `.task(id: householdId)` against the new household.

### 11. Biometric session lock (Face ID / Touch ID)

**As any member, I can:**
- Open Profile → Security and toggle "Require Face ID" (or Touch ID / Optic ID, depending on the device).
- Once enabled, returning to the app from a fresh launch shows an unlock screen that requires biometrics before chores are visible. The current network session (access + refresh tokens) stays in Keychain throughout — biometrics gate the *UI*, not the API.

**Acceptance:**
- The toggle is hidden on devices that don't support biometrics (`LAContext.canEvaluatePolicy` is false).
- Cancelling the biometric prompt leaves the user on the unlock screen with a "Sign out" escape hatch, never silently signs them out.
- The setting is per-device (stored in `UserDefaults`), not synced.

## Explicitly out of scope for v1

- Push notifications (APNs)
- Real-time updates between devices (we poll on app foreground + offer pull-to-refresh)
- Photo evidence on completion
- Chore assignment to specific users (anyone can complete any chore)
- Recurring chore auto-rotation between members
- Reward redemption / allowance integration
- Calendar export
- Apple Watch app
- iPad-optimized layout (it'll work in compatibility mode)
- Sign in with Apple (deferred to v1.1)
- Internationalization beyond English
- Web or Android client
- Soft delete / archive UI for chores and rooms (the `archived` field exists on the schema for a future "pause" feature, but DELETE is the only destructive user action in v1)

## Screens (high level)

| Screen | Purpose | Notes |
|---|---|---|
| Welcome | Logo + Sign up / Log in buttons | First launch only |
| Sign up / Log in | Standard forms | |
| Onboarding: Create or Join | Two big buttons | After login if user has no households |
| Household Picker | If user has 2+ households, sheet to switch | Accessible from Settings |
| Home (Chores tab) | Sectioned list by room, with a big "Generate" button | Default tab |
| Generate — Choose source | Text vs Photo | Modal sheet |
| Generate — Text input | TextField + "Generate" CTA | |
| Generate — Photo input | Camera / library picker | |
| Generate — Review suggestions | Toggleable list, Save | |
| Chore detail | Title, description, recurrence, complete button, completion history | Push from list |
| Feed tab | Recent completions, household-wide | |
| Leaderboard tab | This week | |
| Profile tab | Display name, biometric toggle, household switcher entry, household settings entry, sign out | |
| Household picker | Sheet listing every household the user belongs to; tap to switch | Hidden if user only belongs to one household |
| Notification settings | Daily reminder toggle + time picker; permission prompt | Push from Profile |
| Household settings | Household name, members + streaks, invite code (reveal-on-tap), AI key entry | Push from Profile |
| Family AI key | Status, Set / Replace / Remove (admin only) | Push from Household settings |
| Session unlock | Face ID / Touch ID prompt with sign-out fallback | Shown on cold launch when biometric lock is on |

## Definition of MVP done

- A new user can install the app, sign up, create a household, set the AI key, generate 5 chores from a photo of their kitchen, complete one, and see the streak go to 1 — without crashes, without seeing any error UI.
- Backend is deployed to a staging environment with a real Mongo Atlas DB.
- All hard rules in `CLAUDE.md` pass a manual audit.
