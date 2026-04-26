# ChoresApp

iOS app + Node backend for AI-generated household chores.

> **Start here:** read [`CLAUDE.md`](./CLAUDE.md), then [`BUILD_PLAN.md`](./BUILD_PLAN.md). Architectural details and the API contract live in [`ARCHITECTURE.md`](./ARCHITECTURE.md). User-visible behavior is defined in [`MVP_SPEC.md`](./MVP_SPEC.md).

## Quick start

### Backend (Node 20+ + MongoDB)

```bash
cd server
npm install
cp .env.example .env       # then fill in MONGO_URI and the two secrets
npm run dev
```

`GET http://localhost:8080/health` should return `{"status":"ok",...}`.

For local Mongo: `brew install mongodb-community && brew services start mongodb-community`.

### iOS (Xcode 15+, iOS 17+)

The Xcode project is generated from [`ios/project.yml`](./ios/project.yml) by [XcodeGen](https://github.com/yonaskolb/XcodeGen) so it can live in git without merge-conflict hell.

```bash
brew install xcodegen      # one-time
cd ios
xcodegen generate          # produces ChoresApp.xcodeproj (gitignored)
open ChoresApp.xcodeproj
```

Then ⌘R in Xcode. The simulator hits `http://localhost:8080` by default.

## Free backend deploy

The easiest free option for this repo is a Render web service plus MongoDB Atlas.

1. Push this repo to GitHub.
2. Create a free MongoDB Atlas cluster if you don't already have one.
3. In Render, create a new Blueprint and point it at this repo. The repo now includes [`render.yaml`](./render.yaml), which tells Render to deploy the `server/` app as a free Node web service with `/health` as the health check.
4. In Render, set `MONGO_URI` to your Atlas connection string. `JWT_SECRET` and `KEY_ENCRYPTION_SECRET` can be auto-generated from the Blueprint.
5. In MongoDB Atlas, allow the Render service to connect. The simplest setup is adding `0.0.0.0/0` to the Atlas IP access list, but only do that with strong database credentials.
6. After deploy, copy your Render URL, such as `https://choresapp-api.onrender.com`.

To point the iPhone app at the hosted API instead of your Mac:

1. Edit [`ios/project.yml`](./ios/project.yml).
2. Change the `Debug` `API_BASE_URL` from `http://localhost:8080` to your Render URL.
3. Regenerate the Xcode project:

```bash
cd ios
xcodegen generate
open ChoresApp.xcodeproj
```

Render's free web services spin down after 15 minutes of inactivity, so the first request after idle can take about a minute to wake up.

## Repo layout

```
ChoresApp/
├── CLAUDE.md, ARCHITECTURE.md, MVP_SPEC.md, BUILD_PLAN.md   ← read these
├── ios/                 SwiftUI app
└── server/              Fastify + Mongoose API
```
