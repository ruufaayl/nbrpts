# Architecture

```
                                ┌──────────────────────┐
                                │  Anonymous visitor   │
                                └──────────┬───────────┘
                                           │  may visit /, /dev*, /login
                                           ▼
              /            (auth-gated)              /dev, /dev/schema, /dev/triggers
              │           /hospital   (Phase 5)              │
              │           /ai-engine  (Phase 6)              │
              │           /officer    (Phase 7)              │
              ▼                                               ▼
        ┌──────────────────────────────────────────────────────────┐
        │              Next.js 16 (Vercel)                         │
        │  - proxy.ts refreshes Supabase session per request       │
        │  - RSCs use getSupabaseServer() (cookie-aware)           │
        │  - Server Actions wrap every mutation                    │
        │  - Client components use supabaseBrowser (SSR client)    │
        └─────────────────────┬────────────────────────────────────┘
                              │ supabase.rpc() / .from()
                              │ headers carry the auth JWT
                              ▼
        ┌──────────────────────────────────────────────────────────┐
        │              Supabase Postgres                           │
        │                                                          │
        │  • 13 domain tables (3NF) + 12 enums + 2 sequences       │
        │  • app_user links auth.users → role + domain entity      │
        │  • All business logic in Postgres functions              │
        │  • Six trigger functions across four tables              │
        │  • RLS on every table (Phase 4 — see policy matrix)      │
        │  • 4 SECURITY DEFINER helpers used inside RLS:           │
        │      current_app_role, current_hospital_id,              │
        │      current_officer_id, is_admin                        │
        │  • Realtime publication streams query_log → /dev          │
        │  • get_schema, get_pipeline_summary,                     │
        │    get_trigger_lab_data, whoami → JSONB observatory RPCs │
        └──────────────────────────────────────────────────────────┘
```

## Auth flow

```
1. Visitor → /login
2. Submits form  ──► signInAction (Server Action)
                      ├── supabase.auth.signInWithPassword
                      ├── cookies set on Response (sb-* JWT pair)
                      └── redirect → /dev/triggers (or ?next=)
3. Subsequent request
                proxy.ts ──► supabase.auth.getUser
                              ├── reads JWT cookie
                              ├── refreshes if needed
                              └── attaches new tokens to Response
                  Page renders RSC ──► getSupabaseServer()
                              └── all queries carry the JWT
                                    ├── PostgREST validates JWT, sets
                                    │    role = 'authenticated' + auth.uid()
                                    └── RLS policies use auth.uid() to
                                         scope rows via app_user
```

## Why the observatory still works for anon viewers

`/dev`, `/dev/schema`, `/dev/triggers` all render through SECURITY DEFINER RPCs that internally bypass RLS:
- `dev_ping()` — writes to `query_log` (which keeps an anon-permissive SELECT policy)
- `get_schema()` — reads `information_schema` and `pg_class`
- `get_pipeline_summary()` — aggregates over every domain table
- `get_trigger_lab_data()` — returns the lab's lists as one JSONB blob

The trade-off is documented and intentional: the observatory is a teaching tool for the database course; it must work without authentication. The user-facing portals (Phases 5–7) will be auth-gated.

## A single verify_birth_record() in slow motion (unchanged from Phase 3)

```
   client → Supabase → Postgres
     │  rpc('verify_birth_record')
     ▼
   set_config(app.actor_*, app.current_officer_id) — reads from RPC params
   UPDATE birth_record SET status = 'VERIFIED'
     ├── BEFORE: trg_birth_record_state_machine     — validates legal transition
     ├── AFTER:  trg_audit_birth_record             — INSERT into audit_trail
     ├── AFTER:  trg_birth_record_log_status        — INSERT into verification_log (fires its own audit trigger)
     └── AFTER WHEN VERIFIED: trg_birth_record_post_verification
           ├── INSERT child (mints CNIN)            — fires trg_audit_child
           ├── INSERT child_guardian × N            — fires trg_audit_child_guardian
           ├── INSERT bform                         — fires trg_audit_bform
           └── INSERT notifications                 — fires trg_audit_notifications
   INSERT query_log
```

## File map

```
app/
├── (marketing)/        # public landing
│   └── page.tsx
├── login/              # Phase 4
│   ├── page.tsx
│   ├── login-form.tsx
│   └── actions.ts
├── hospital/           # Phase 5 — auth-gated portal
│   ├── layout.tsx                   # role guard + portal nav
│   ├── page.tsx                     # dashboard
│   ├── _components/status-badge.tsx
│   ├── submit/
│   │   ├── page.tsx
│   │   ├── form.tsx                 # 4-step framer-motion form
│   │   └── actions.ts               # submit_birth_record_v2 RPC
│   ├── submissions/page.tsx
│   └── device/
│       ├── page.tsx
│       └── device-simulator.tsx     # IndexedDB queue
├── dev/                # observatory (anon-friendly via RPCs)
│   ├── _components/nav.tsx          # auth-aware nav strip (Phase 4)
│   ├── page.tsx                     # query feed
│   ├── schema/                      # ER diagram
│   └── triggers/                    # interactive lab
└── layout.tsx

lib/
├── supabase/
│   ├── client.ts       # browser, cookie-aware (createBrowserClient)
│   ├── server.ts       # async getSupabaseServer (cookie-aware)
│   ├── admin.ts        # service-role (server-only, optional)
│   └── types.ts
├── schema/  · types.ts, layout.ts (dagre)         — Phase 2
├── domain/  · types.ts                             — Phase 3
└── utils.ts

proxy.ts                 # session refresher (Next 16)

supabase/migrations/
├── 0000_init_query_log.sql                        Phase 1
├── 0001_dev_ping_rpc.sql
├── 0002_enums.sql                                 Phase 2
├── 0003_core_tables.sql
├── 0004_get_schema_rpc.sql
├── 0005_seed.sql
├── 0006_harden_get_schema_row_count.sql
├── 0007_phase3_schema_additions.sql               Phase 3
├── 0008_audit_trigger.sql
├── 0009_state_machine.sql
├── 0010_bform_functions.sql
├── 0011_business_rpcs.sql
├── 0012_harden_function_security.sql
├── 0013_get_trigger_lab_data_rpc.sql
├── 0014_phase4_app_user.sql                       Phase 4
├── 0015_phase4_rls_policies.sql
├── 0016_phase4_seed_demo_users.sql
└── 0017_phase5_hospital_rpcs.sql                  Phase 5
```
