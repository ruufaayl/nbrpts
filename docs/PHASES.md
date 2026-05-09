# NBRPTS — Phase Roadmap

Eight phases plus a polish phase. Each phase ends with a deployable, demo-able artifact.

| # | Phase | Status | Deliverable |
|---|---|---|---|
| 1 | Foundations | 🟢 done | Repo, Vercel deploy, Supabase project, Next.js + Tailwind scaffold, CI, `/dev` observatory with `dev_ping()` streaming via Realtime |
| 2 | Schema & migrations | 🟢 done | All 13 tables as raw `.sql` migrations; 12 enums; 24 indexes; realistic seed data; `get_schema()` RPC; live ER diagram on `/dev/schema` via react-flow + dagre |
| 3 | **Triggers & functions** | 🟢 done | Generic audit trigger on 12 tables, birth-record state machine validator, status-change logger, post-verification cascade (auto-creates child + B-Form + SMS), B-Form authorization & versioned reissuance, six business RPCs, interactive `/dev/triggers` lab |
| 4 | RLS & auth | ⚪ pending | Hospital-staff / officer / admin roles, RLS policies on every table, login UI, signed-in `/dev` features |
| 5 | Hospital portal | ⚪ pending | Multi-step birth form, IndexedDB offline queue, submissions table, device-simulator page |
| 6 | AI engine | ⚪ pending | Gemini Flash integration + rules fallback, `ai_review_log` writes, live processing feed |
| 7 | Officer portal | ⚪ pending | Flagged queue, B-Form authorization, reissuance, search, population stats |
| 8 | Dev observatory full build-out | ⚪ pending | Full query log filters, `pg_stat_statements` panel, RLS policy inspector, free-form SQL panel, EXPLAIN flame graph, state-machine visualizer |
| 9 | Polish | ⚪ pending | Landing animation pass, demo video, viva prep |

## Phase 1 — Done ✅

Foundations: Supabase project, scaffold, query-log table + `dev_ping()` RPC, `/dev` realtime feed, GitHub + Vercel auto-deploy, CI.

## Phase 2 — Done ✅

13 tables in 3NF, 12 enums, 15 FKs, 24 indexes, format-validating CHECKs, `get_schema()` RPC, react-flow ER diagram on `/dev/schema`, 86 rows of realistic seed data spanning every state in the verification state machine.

## Phase 3 — Done ✅

### Schema additions
- `birth_record.child_full_name` (nullable) and `child_gender` (NOT NULL) — captured at submission, copied into `child` on verification
- `bform.authorized_at` — timestamp the officer flips after review; until set, the SMS is held in `notifications` with status `QUEUED`
- Two sequences (`cnin_seq` starts at 1000000005, `bform_seq` starts at 10010004) for deterministic identifier minting
- `EMP-999999` AI Engine system officer so trigger-driven status changes have a non-null `officer_id`

### Triggers (six total across four tables)
| Trigger | Table | Timing | Purpose |
|---|---|---|---|
| `trg_audit_<table>` × 12 | every domain table | AFTER INSERT/UPDATE/DELETE | writes one row to `audit_trail` per mutation; actor pulled from `app.actor_type` / `app.actor_id` session vars |
| `trg_birth_record_state_machine` | birth_record | BEFORE UPDATE OF status | rejects illegal transitions per the proposal's state machine |
| `trg_birth_record_log_status` | birth_record | AFTER UPDATE OF status | inserts a `verification_log` row for every status change |
| `trg_birth_record_post_verification` | birth_record | AFTER UPDATE OF status WHEN VERIFIED | creates `child` (with new CNIN), links `child_guardian` for mother + father, generates `bform` (unauthorized), queues SMS |

A single `verify_birth_record(...)` call therefore fires **6 triggers** (state machine, audit, status logger, cascade, plus 4 audit triggers on each cascaded INSERT) and produces **5 new rows** across 5 tables, all in one transaction.

### State machine (enforced by trigger)
```
PENDING ──► VERIFIED        (AI auto-approve or officer)
PENDING ──► FLAGGED         (AI flag → human review)
PENDING ──► REJECTED        (officer rejects)
FLAGGED ──► VERIFIED        (officer approves)
FLAGGED ──► REJECTED        (officer rejects)
REJECTED ──► PENDING        (hospital resubmits)
VERIFIED ──► AMENDED        (officer edits)
AMENDED  ──► AMENDED        (subsequent edits)
```
Anything else raises `errcode = check_violation`.

### Business RPCs (six)
- `submit_birth_record(...)` — hospital portal entry point
- `verify_birth_record(birth_record_id, officer_id, remarks)` — officer or AI auto-approve
- `flag_birth_record(...)` — AI engine flags for human review
- `reject_birth_record(...)` — officer rejects (reason required)
- `resubmit_birth_record(...)` — hospital pushes a REJECTED record back to PENDING
- `authorize_bform(bform_id, officer_id)` — officer flips `authorized_at`; SMS promoted from QUEUED to SENT
- `reissue_bform(child_id, officer_id, reason)` — versioned reissuance; prior version retained, marked `is_current = false`
- `get_pipeline_summary()` — JSONB roll-up used by `/dev/triggers`

All RPCs are SECURITY DEFINER, instrument themselves into `query_log`, and set the audit-actor session vars before the UPDATE.

### Interactive demo
`/dev/triggers` — four action cards (submit / verify / authorize / reissue), live pipeline-summary stat strip, and the latest 20 `audit_trail` entries. Every click is a single `supabase.rpc()` call; the page revalidates and the new state appears.

### Hardening (migration 0012)
- Trigger-only functions (`fn_audit_trail`, `fn_log_status_change`, `fn_post_verification_cascade`) had EXECUTE revoked from `anon`, `authenticated`, and `public` so they can no longer be called via `/rest/v1/rpc/*`. They still fire as triggers because Postgres invokes trigger functions internally regardless of grants.
- `fn_validate_birth_record_status` had its search_path pinned to `public`.

### Advisor verdict
- 13× INFO `rls_enabled_no_policy` — expected; Phase 4 fixes
- WARN advisors only on functions intentionally exposed (the 7 business RPCs + 3 observatory RPCs)
- Trigger-only function warnings cleared by 0012
- Zero ERROR-level findings
