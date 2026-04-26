# server

Fastify + TypeScript + MongoDB API for ChoresApp. See the repo-root `ARCHITECTURE.md` for the API contract and `BUILD_PLAN.md` for what to build next.

## Setup

```bash
npm install
cp .env.example .env       # fill in Mongo URI + the two secrets
npm run dev
```

`GET http://localhost:8080/health` should return `{"status":"ok",...}`.

## Scripts

| Command | What |
|---|---|
| `npm run dev` | Watches `src/` and restarts |
| `npm run build` | TypeScript → `dist/` |
| `npm start` | Runs the built output |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run lint` | ESLint |
| `npm run format` | Prettier write |
| `npm test` | Vitest, single run |
| `npm run test:watch` | Vitest, watch |

## Layout

```
src/
├── app.ts            buildApp() — used by index.ts and tests
├── index.ts          process entrypoint
├── config/env.ts     Zod-validated env vars (fail-fast at boot)
├── db/mongo.ts       Mongoose connection
├── routes/           one file per resource — register in app.ts
├── services/         crypto (AES-256-GCM), openai facade
├── middleware/       errorHandler (more added in Phase 1)
├── models/           Mongoose schemas (added Phase 1+)
└── utils/errors.ts   AppError + canonical error codes
```

## Conventions

- **No `console.log`.** Use `request.log` / `app.log` (`pino`). The error handler logs unhandled errors centrally.
- **No raw `throw new Error("...")` from route handlers.** Throw `AppError(statusCode, code, message)` so clients get the documented error shape.
- **Validate every request body with Zod** before it reaches business logic.
- **Mongo queries are scoped by `householdId` from middleware**, never from the request body. See the `requireMembership` middleware (Phase 1).
- **Secrets never appear in logs.** The logger redacts `req.headers.authorization`, `req.body.password`, `req.body.key`. If you add a new secret-bearing field, extend the redact paths in `app.ts`.

## Testing

- Vitest. Tests live in `tests/`, named `*.test.ts`.
- Integration tests for routes use `app.inject(...)` (fastify's in-process HTTP) and `mongodb-memory-server` for an isolated database per suite.
- Don't mock at the Mongoose layer — use the in-memory server. Mocking ODM calls hides bugs that real queries surface.
