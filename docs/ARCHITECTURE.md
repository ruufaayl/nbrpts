# Architecture

```
                                ┌──────────────────────┐
                                │  Anonymous visitor   │
                                └──────────┬───────────┘
                                           │
              /            (auth-gated)    ▼            /dev, /dev/schema, /dev/triggers
              │           /hospital                     │
              │           /ai-engine                    │
              │           /officer                      │
              ▼                                          ▼
        ┌──────────────────────────────────────────────────────────┐
        │                  Next.js 16 (Vercel)                     │
        │  - RSC pages render through `lib/supabase/server`        │
        │  - Server Actions call SECURITY DEFINER RPCs             │
        │  - Client components subscribe via `lib/supabase/client` │
        │  - Privileged ops use `lib/supabase/admin` (server-only) │
        └─────────────────────┬────────────────────────────────────┘
                              │ supabase.rpc() / .from()
                              ▼
        ┌──────────────────────────────────────────────────────────┐
        │                  Supabase Postgres                       │
        │                                                          │
        │  • 13 tables (3NF) + 12 enums + 2 sequences              │
        │  • All business logic in Postgres functions:             │
        │      - submit/verify/flag/reject/resubmit_birth_record   │
        │      - authorize_bform, reissue_bform                    │
        │      - get_pipeline_summary, get_schema, dev_ping        │
        │  • Six trigger functions across four tables:             │
        │      - generic audit (12 tables)                         │
        │      - state-machine validator                           │
        │      - status-change logger (verification_log)           │
        │      - post-verification cascade                         │
        │  • Row-Level Security on every table (Phase 4)           │
        │  • Realtime publication streams query_log → /dev          │
        └──────────────────────────────────────────────────────────┘
```

## A single verify_birth_record() in slow motion

```
   client                        Supabase                            Postgres
     │                              │                                    │
     │  rpc('verify_birth_record')  │                                    │
     ├─────────────────────────────►│                                    │
     │                              │  call verify_birth_record(...)     │
     │                              ├───────────────────────────────────►│
     │                              │                                    │
     │                              │  set_config('app.current_officer') │
     │                              │  set_config('app.actor_*')         │
     │                              │  UPDATE birth_record SET status…   │
     │                              │     ▼                              │
     │                              │   trg_birth_record_state_machine   │  BEFORE — validates legal transition
     │                              │     ▼                              │
     │                              │   trg_audit_birth_record           │  AFTER — INSERT into audit_trail (1 row)
     │                              │     ▼                              │
     │                              │   trg_birth_record_log_status      │  AFTER — INSERT into verification_log (1 row)
     │                              │     │                              │      │
     │                              │     │     trg_audit_verification_log     │  AFTER — INSERT audit (1 row)
     │                              │     ▼                              │
     │                              │   trg_birth_record_post_verification     │  AFTER WHEN VERIFIED:
     │                              │     ├── INSERT child (new CNIN)    │      → trg_audit_child           (1 row)
     │                              │     ├── INSERT child_guardian × N  │      → trg_audit_child_guardian  (N rows)
     │                              │     ├── INSERT bform               │      → trg_audit_bform           (1 row)
     │                              │     └── INSERT notifications       │      → trg_audit_notifications   (1 row)
     │                              │                                    │
     │                              │  INSERT query_log                  │
     │  birth_record row            │                                    │
     │◄─────────────────────────────┤                                    │
```

One round-trip. ≈10 rows written. Every step observable in `/dev`, `/dev/triggers`, and the `audit_trail` table.

## The query_log convention

Every business RPC writes a row to `public.query_log` recording `caller`, `sql_text`, `params` (JSONB), `duration_ms`, `rows_returned`. The `/dev` observatory subscribes to this table via Supabase Realtime; new rows animate in within ~100ms.

## File map

```
app/
├── (marketing)/        # public landing
│   └── page.tsx
├── (portals)/          # auth-gated — Phases 5–7
├── dev/                # database observatory
│   ├── _components/
│   │   └── nav.tsx     # shared nav strip
│   ├── page.tsx        # query feed (Phase 1)
│   ├── query-feed.tsx
│   ├── ping-button.tsx
│   ├── schema/         # Phase 2
│   │   ├── page.tsx
│   │   ├── schema-diagram.tsx
│   │   └── table-node.tsx
│   └── triggers/       # Phase 3
│       ├── page.tsx
│       ├── trigger-lab.tsx
│       └── actions.ts  # 'use server' actions
└── layout.tsx

lib/
├── supabase/  · client.ts, server.ts, admin.ts, types.ts
├── schema/    · types.ts, layout.ts (dagre)   — Phase 2
├── domain/    · types.ts                       — Phase 3
└── utils.ts

supabase/
└── migrations/
    ├── 0000_init_query_log.sql
    ├── 0001_dev_ping_rpc.sql
    ├── 0002_enums.sql                       (Phase 2)
    ├── 0003_core_tables.sql
    ├── 0004_get_schema_rpc.sql
    ├── 0005_seed.sql
    ├── 0006_harden_get_schema_row_count.sql
    ├── 0007_phase3_schema_additions.sql      (Phase 3)
    ├── 0008_audit_trigger.sql
    ├── 0009_state_machine.sql
    ├── 0010_bform_functions.sql
    ├── 0011_business_rpcs.sql
    └── 0012_harden_function_security.sql
```
