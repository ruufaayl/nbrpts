# NBRPTS — Phase Roadmap

| # | Phase | Status | Deliverable |
|---|---|---|---|
| 1 | Foundations | 🟢 done | Repo, Vercel deploy, Supabase project, Next.js + Tailwind scaffold, CI, `/dev` observatory streaming `query_log` via Realtime |
| 2 | Schema & migrations | 🟢 done | 13 tables + 12 enums + 24 indexes + 86 seed rows + `get_schema()` RPC + live ER diagram on `/dev/schema` |
| 3 | Triggers & functions | 🟢 done | 12 audit triggers + state-machine validator + verification log + post-verification cascade + 8 business RPCs + interactive `/dev/triggers` lab |
| 4 | **RLS & auth** | 🟢 done | `app_user` role table, four helper functions, RLS policies on every domain table, three demo accounts, `/login` page, cookie-aware SSR clients, role-aware DevNav |
| 5 | Hospital portal | ⚪ pending | Multi-step birth form, IndexedDB offline queue, submissions table, device-simulator page |
| 6 | AI engine | ⚪ pending | Gemini Flash integration + rules fallback, `ai_review_log` writes, live processing feed |
| 7 | Officer portal | ⚪ pending | Flagged queue, B-Form authorization, reissuance, search, population stats |
| 8 | Dev observatory full build-out | ⚪ pending | Full query log filters, `pg_stat_statements` panel, RLS policy inspector, free-form SQL panel, EXPLAIN flame graph |
| 9 | Polish | ⚪ pending | Landing animation pass, demo video, viva prep |

## Phase 4 — Done ✅

### Auth schema
- **`app_user`** bridges `auth.users` to NBRPTS domain entities. CHECK constraint enforces exactly one of `(hospital_id, officer_id, neither)` based on role.
- Three roles via the `role` column: `hospital_staff`, `nadra_officer`, `admin`.
- Helper functions (all SECURITY DEFINER, search_path pinned):
  - `current_app_role()` — returns the caller's role or NULL.
  - `current_hospital_id()` — for hospital_staff users.
  - `current_officer_id()` — for nadra_officer users.
  - `is_admin()` — true iff role is admin.
  - `whoami()` — full profile JSONB used by the nav widget.

### RLS policies
SELECT policies on all 13 domain tables, plus admin ALL policies:

| Table | hospital_staff | nadra_officer | admin | anon |
|---|---|---|---|---|
| hospital | own row | all | ALL | ✗ |
| nadra_office | ✗ | all | ALL | ✗ |
| nadra_officer | ✗ | self + same office | ALL | ✗ |
| parent_guardian | parents linked to own hospital | all | ALL | ✗ |
| birth_record | own hospital | all | ALL | ✗ |
| child | own hospital's children | all | ALL | ✗ |
| child_guardian | own hospital's links | all | ALL | ✗ |
| bform | own hospital's B-Forms | all | ALL | ✗ |
| verification_log | own hospital's events | all | ALL | ✗ |
| ai_review_log | ✗ | all | ALL | ✗ |
| audit_trail | ✗ | all | ALL | ✗ |
| offline_queue | own hospital | all | ALL | ✗ |
| notifications | ✗ | all | ALL | ✗ |
| query_log | (public — observatory) | (public) | (public) | ✓ SELECT |

The 13× INFO `rls_enabled_no_policy` advisor warnings from Phase 2 are now **all cleared**.

### Demo accounts
| Email | Role | Domain link |
|---|---|---|
| `admin@nbrpts.demo` | `admin` | — |
| `aisha@nbrpts.demo` | `nadra_officer` | EMP-100201 (Aisha Khan, Karachi-South) |
| `aku@nbrpts.demo` | `hospital_staff` | Aga Khan University Hospital |

Password for all three: `demo1234`. Seeded directly into `auth.users` + `auth.identities` via `extensions.crypt(..., gen_salt('bf'))` (Supabase docs explicitly support this).

### Frontend
- `@supabase/ssr` cookie-aware clients (`lib/supabase/server.ts` exports `getSupabaseServer()`, `lib/supabase/client.ts` exports `supabaseBrowser`).
- `proxy.ts` (Next 16's renamed middleware) refreshes the session on every request.
- `/login` — premium two-column page with demo creds revealed on the left, sign-in form on the right. Form uses a Server Action that calls `signInWithPassword` and redirects.
- `DevNav` is now an async server component that calls `whoami()` and shows an "Acting as …" strip plus sign-in / sign-out controls.
- `signOutAction` server action ends the session and revalidates the layout.

### Observability
The observatory pages (`/dev`, `/dev/schema`, `/dev/triggers`) continue to work for anonymous viewers because they read through SECURITY DEFINER RPCs (`get_schema`, `get_pipeline_summary`, `get_trigger_lab_data`, `dev_ping`) that bypass the new RLS. Authenticated users see the same UI plus their identity in the nav strip.

### Advisor verdict
- 0 `rls_enabled_no_policy` (was 13)
- WARN `*_security_definer_function_executable` only on functions intentionally exposed (8 business RPCs + 4 helpers + 4 observatory RPCs)
- WARN `auth_leaked_password_protection` — paid-tier feature, unavailable on free
- 0 ERROR-level findings

## Earlier phases (collapsed)

### Phase 1 — Done ✅
Foundations: Supabase project, scaffold, query-log table + `dev_ping()` RPC, `/dev` realtime feed, GitHub + Vercel auto-deploy, CI.

### Phase 2 — Done ✅
13 tables in 3NF, 12 enums, 15 FKs, 24 indexes, format-validating CHECKs, `get_schema()` RPC, react-flow ER diagram on `/dev/schema`, 86 rows of realistic seed data spanning every state in the verification state machine.

### Phase 3 — Done ✅
Six trigger functions across four tables (12 audit triggers, state-machine validator, status logger, post-verification cascade), eight business RPCs, sequences for CNIN + B-Form numbering, AI Engine system officer (EMP-999999), interactive `/dev/triggers` lab.
