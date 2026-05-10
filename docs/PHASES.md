# NBRPTS — Phase Roadmap

| # | Phase | Status | Deliverable |
|---|---|---|---|
| 1 | Foundations | 🟢 done | Repo, Vercel deploy, Supabase project, Next.js + Tailwind scaffold, CI, `/dev` observatory streaming `query_log` via Realtime |
| 2 | Schema & migrations | 🟢 done | 13 tables + 12 enums + 24 indexes + 86 seed rows + `get_schema()` RPC + live ER diagram on `/dev/schema` |
| 3 | Triggers & functions | 🟢 done | 12 audit triggers + state-machine validator + verification log + post-verification cascade + 8 business RPCs + interactive `/dev/triggers` lab |
| 4 | **RLS & auth** | 🟢 done | `app_user` role table, four helper functions, RLS policies on every domain table, three demo accounts, `/login` page, cookie-aware SSR clients, role-aware DevNav |
| 5 | **Hospital portal** | 🟢 done | Auth-guarded `/hospital`, dashboard, 4-step submit form, submissions table, IndexedDB-backed device simulator |
| 6 | **AI engine** | 🟢 done | Deterministic rules engine (8 signals) — score, log, transition state machine; `/ai-engine` page with controls + live verdict feed |
| 7 | **Officer portal** | 🟢 done | Auth-guarded `/officer`, dashboard, queue (pending+flagged), record detail with verify/reject/flag, B-Form authorization+reissuance, search, population stats |
| 8 | Dev observatory full build-out | ⚪ pending | Full query log filters, `pg_stat_statements` panel, RLS policy inspector, free-form SQL panel, EXPLAIN flame graph |
| 9 | Polish | ⚪ pending | Landing animation pass, demo video, viva prep |
| 10 | **Academic deliverables** | 🟢 done | Project report PDF (business rules, ERD, schema, 3NF, design decisions), consolidated SQL script bundle, screenshots package — see [`/deliverables`](../deliverables/README.md) |

## Phase 10 — Done ✅

The CS2013 academic submission package, generated from the live codebase. Everything in `deliverables/` is reproducible from `scripts/`.

### Outputs
- `deliverables/NBRPTS_Report.pdf` (885 kB) — 12-section project report with cover, abstract, business rules, entities, relationships, ERD figure, 1NF→3NF walkthrough with verification table, schema, design decisions, SQL highlights, triggers + transactions, nine inline screenshots, conclusion.
- `deliverables/NBRPTS_Report.docx` (690 kB) — editable source.
- `deliverables/sql/{01..05}.sql` + `nbrpts_full.sql` — sectioned SQL script bundle.
- `deliverables/screenshots/*.png` — nine 1440×900 captures of the live app (landing, dev observatory triplet, login, hospital portal quartet).
- `deliverables/README.md` — submission guide.

### Generators (under `scripts/`)
- `build-sql-bundle.mjs` — concatenates migrations into the four section SQL files plus the mega-bundle.
- `capture-screenshots.mjs` — drives headless Edge via CDP (no Playwright needed), authenticates as `aku@nbrpts.demo`, walks every public + hospital page.
- `build-report.mjs` — generates the .docx with `docx` (npm), embedding the screenshots at runtime.
- `docx-to-pdf.ps1` — Word COM automation to export the .docx as PDF.

## Phase 6 — Done ✅

### Migration `0019_phase6_ai_engine.sql`
A pure-SQL deterministic rules engine — no external API key required. Three RPCs:

| RPC | Purpose |
|---|---|
| `ai_score_record(brn)` | Pure scoring, no side effects. Returns `{verdict, confidence_score, flags_raised, reasons}`. Eight signals: implausible weight, future birth date, mother age, weight band, missing CNIC, no father, non-live outcome, duplicate detection (mother + DOB within 12h). |
| `ai_process_record(brn)` | Score → INSERT `ai_review_log` → UPDATE `birth_record.status`. The state-machine + post-verification cascade triggers fire automatically. PASS at confidence ≥ 0.85 auto-verifies. FLAG queues for human review. REJECT auto-rejects with reasons. |
| `ai_process_all_pending(limit)` | Batch processor. Per-record `BEGIN/EXCEPTION/END` so one failure doesn't poison the batch. Returns processed/passed/flagged/rejected/error counts. |
| `get_ai_engine_data()` | Dashboard data: counts, verdict_breakdown, avg_confidence per verdict, recent_reviews (25), next_pending (10). |

The engine acts as the AI system officer (`EMP-999999`) so verification_log + audit_trail entries are correctly attributed.

### Frontend
| Route | What it does |
|---|---|
| `/ai-engine` | Anonymous-accessible. 5 stat tiles (pending, flagged, reviews today, reviews total, human overrides). Engine controls panel: "Process next" + "Process all (N)". Verdict breakdown card with avg confidence per verdict. Next-in-queue list. Recent reviews feed with verdict pill, confidence, flag codes inline. |

Landing page pillars now link to `/hospital`, `/ai-engine`, `/officer`. The AI engine RPCs are granted to `anon` so the demo runs without a sign-in.

## Phase 7 — Done ✅

### Migration `0018_phase7_officer_rpcs.sql`
12 SECURITY DEFINER RPCs for the NADRA officer console:

| RPC | Purpose |
|---|---|
| `assert_officer()` | Helper — raises 42501 if caller is not nadra_officer or admin |
| `get_officer_dashboard_data()` | 8 stat-tile counts + recent actions (last 10) + oldest pending (8) |
| `get_officer_queue(status, limit, offset)` | Paged queue with mother/hospital/father data + latest AI review per record |
| `get_officer_record_detail(brn)` | Full single-record view: birth, hospital, parents, child, B-Form, AI history, verification log |
| `search_records(query, limit)` | ILIKE search across BRN/CNIN/CNIC/mother name/child name with match_field annotation |
| `get_population_stats()` | by_province + by_district + by_gender + by_delivery_type + top_hospitals |
| `get_bforms_workload(limit)` | to_authorize + recent_authorized lists |
| `verify_birth_record_v2(brn, remarks)` | Auth-aware (reads `current_officer_id()`, no parameter) |
| `reject_birth_record_v2(brn, remarks)` | Auth-aware, requires reason |
| `flag_birth_record_v2(brn, remarks)` | Auth-aware |
| `authorize_bform_v2(bform_id)` | Auth-aware, promotes queued SMS to SENT |
| `reissue_bform_v2(child_id, reason)` | Auth-aware, supersedes via partial unique index, queues new SMS |

### Frontend
| Route | What it does |
|---|---|
| `/officer` | Dashboard: 5 stat tiles (pending, flagged, my actions today, B-Forms to auth, children total), oldest pending list, recent actions feed |
| `/officer/queue` | Filterable queue (all / pending / flagged); shows AI verdict + confidence per row |
| `/officer/record/[brn]` | Full record view with 6 cards (birth, hospital, mother, father, child, B-Form), AI history, verification log; verify/reject/flag buttons (state-aware enable/disable) |
| `/officer/bforms` | Awaiting authorization (one-click authorize) + recently authorized (with reissue button) |
| `/officer/search` | Free-text search across CNIN, BRN, CNIC, mother name, child name |
| `/officer/stats` | Population analytics: by province, district, gender, delivery type, top hospitals |

Server actions in `app/officer/actions.ts` wrap the v2 RPCs with `revalidatePath`. Sonner toasts surface success/error. Layout enforces `nadra_officer` or `admin` role; other roles get a friendly access-denied screen.

## Phase 5 — Done ✅

### Migration `0017_phase5_hospital_rpcs.sql`
Three SECURITY DEFINER RPCs that let `hospital_staff` clients bypass RLS for legitimate writes/reads scoped to their own hospital:
- **`submit_birth_record_v2(p_payload jsonb)`** — upserts mother+father by CNIC (re-uses existing `parent_guardian` rows if found), inserts `birth_record` + `birth_record_parent` links, returns `{ brn, status, parent_ids }`. Validates `current_hospital_id()` matches, otherwise raises `insufficient_privilege`.
- **`get_hospital_dashboard_data()`** — single round-trip JSONB blob with stat tiles (pending/verified/flagged counts, today's submissions, average AI score) plus the latest 10 submissions.
- **`get_hospital_submissions(p_limit int)`** — paged list of every birth record this hospital has ever filed.

### Frontend
| Route | What it does |
|---|---|
| `/hospital` | Dashboard: 5 stat tiles, recent submissions table, status badges |
| `/hospital/submit` | 4-step form (Mother → Father → Birth → Review) with Framer Motion `AnimatePresence` page transitions, per-step validation including CNIC `^[0-9]{5}-[0-9]{7}-[0-9]$` and PMDC `^PMDC-[0-9]{6}$` regex, sonner success toast |
| `/hospital/submissions` | Full submissions table with BRN, status, mother+CNIC, child, CNIN, born/submitted timestamps |
| `/hospital/device` | IndexedDB-backed device simulator: online/offline toggle, queue records while offline, auto-sync on going back online, status PENDING → SYNCING → SYNCED/FAILED |

Layout enforces auth + role: anonymous → `/login?next=/hospital`; non-hospital roles → friendly access-denied screen with a sign-out button.

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
