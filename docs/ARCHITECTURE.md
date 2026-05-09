# Architecture

```
                                ┌──────────────────────┐
                                │  Anonymous visitor   │
                                └──────────┬───────────┘
                                           │
              /            (auth-gated)    ▼            /dev
              │           /hospital                     │
              │           /ai-engine                    │
              │           /officer                      │
              ▼                                          ▼
        ┌──────────────────────────────────────────────────────────┐
        │                  Next.js 16 (Vercel)                     │
        │  - RSC pages render through `lib/supabase/server`        │
        │  - Client components subscribe via `lib/supabase/client` │
        │  - Privileged ops use `lib/supabase/admin` (server-only) │
        └─────────────────────┬────────────────────────────────────┘
                              │ supabase.rpc() / .from()
                              ▼
        ┌──────────────────────────────────────────────────────────┐
        │                  Supabase Postgres                       │
        │                                                          │
        │  • All schema in supabase/migrations/*.sql               │
        │  • All business logic in Postgres functions              │
        │  • Audit + verification triggers (Phase 3)               │
        │  • Row-Level Security on every table (Phase 4)           │
        │  • Realtime publication streams query_log → /dev          │
        └──────────────────────────────────────────────────────────┘
```

## The query_log convention

Every RPC the app calls writes a row to `public.query_log` recording:

- `caller` — name of the RPC or component
- `sql_text` — the SQL the function ran
- `params` — bound parameters as JSONB
- `duration_ms` — wall-clock duration captured with `clock_timestamp()`
- `rows_returned` — affected rows
- `plan` — `EXPLAIN (FORMAT JSON)` output as JSONB

The `/dev` observatory subscribes to this table via Supabase Realtime. New rows animate in within ~100 ms of being written.

This convention scales: every function added in later phases (`submit_birth_record`, `verify_record`, `issue_bform`, …) writes its own `query_log` entry, so the observatory automatically tracks everything without app-level instrumentation.

## File map

```
app/
├── (marketing)/        # public landing — Phase 1
│   └── page.tsx
├── (portals)/          # auth-gated — Phases 5–7
│   ├── hospital/
│   ├── ai-engine/
│   └── officer/
├── dev/                # database observatory — Phase 1 (skeleton), Phase 8 (full)
│   ├── page.tsx
│   ├── query-feed.tsx
│   └── ping-button.tsx
└── layout.tsx

lib/
├── supabase/
│   ├── client.ts       # browser, anon
│   ├── server.ts       # server, anon
│   ├── admin.ts        # server-only, service role
│   └── types.ts
└── utils.ts

supabase/
└── migrations/
    ├── 0000_init_query_log.sql
    └── 0001_dev_ping_rpc.sql
```
