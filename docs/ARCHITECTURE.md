# Architecture

```
                                ┌──────────────────────┐
                                │  Anonymous visitor   │
                                └──────────┬───────────┘
                                           │
              /            (auth-gated)    ▼            /dev, /dev/schema
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
        │  • 13 tables (3NF) + 12 enums in supabase/migrations/    │
        │  • All business logic lives in Postgres functions        │
        │  • Audit + verification triggers (Phase 3)               │
        │  • Row-Level Security on every table (Phase 4)           │
        │  • Realtime publication streams query_log → /dev          │
        │  • get_schema() RPC drives /dev/schema observatory       │
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

The `/dev` observatory subscribes to this table via Supabase Realtime. New rows animate in within ~100 ms.

## The 13 entities (Phase 2)

```
hospital ──┬─── birth_record ──┬─── child ──── child_guardian ──── parent_guardian
           │       │            │      │
           │       │            │      └─── bform ──── nadra_officer ── nadra_office
           │       │            │
           │       ├── verification_log ── nadra_officer
           │       │
           │       └── ai_review_log ── nadra_officer (override)
           │
           ├── offline_queue
           │
           └── audit_trail (free-form, references any table)

           notifications  (free-form, references any table)
```

Visit [`/dev/schema`](/dev/schema) for the live, draggable rendering.

## File map

```
app/
├── (marketing)/        # public landing
│   └── page.tsx
├── (portals)/          # auth-gated — Phases 5–7
│   ├── hospital/
│   ├── ai-engine/
│   └── officer/
├── dev/                # database observatory
│   ├── _components/
│   │   └── nav.tsx     # shared nav strip
│   ├── page.tsx        # query feed (Phase 1)
│   ├── query-feed.tsx
│   ├── ping-button.tsx
│   └── schema/         # Phase 2
│       ├── page.tsx
│       ├── schema-diagram.tsx
│       └── table-node.tsx
└── layout.tsx

lib/
├── supabase/
│   ├── client.ts       # browser, anon
│   ├── server.ts       # server, anon
│   ├── admin.ts        # server-only, service role
│   └── types.ts
├── schema/             # Phase 2
│   ├── types.ts
│   └── layout.ts       # dagre wrapper
└── utils.ts

supabase/
└── migrations/
    ├── 0000_init_query_log.sql
    ├── 0001_dev_ping_rpc.sql
    ├── 0002_enums.sql
    ├── 0003_core_tables.sql
    ├── 0004_get_schema_rpc.sql
    └── 0005_seed.sql
```
