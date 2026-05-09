# NBRPTS — Phase Roadmap

Eight phases plus a polish phase. Each phase ends with a deployable, demo-able artifact.

| # | Phase | Status | Deliverable |
|---|---|---|---|
| 1 | Foundations | 🟢 done | Repo, Vercel deploy, Supabase project, Next.js + Tailwind scaffold, CI, `/dev` observatory with `dev_ping()` streaming via Realtime |
| 2 | **Schema & migrations** | 🟢 done | All 13 tables (`hospital`, `nadra_office`, `nadra_officer`, `parent_guardian`, `birth_record`, `child`, `child_guardian`, `bform`, `verification_log`, `ai_review_log`, `audit_trail`, `offline_queue`, `notifications`) as raw `.sql` migrations; 12 enums; realistic seed data; `get_schema()` RPC; live ER diagram on `/dev/schema` via react-flow + dagre |
| 3 | Triggers & functions | ⚪ pending | `audit_trail` trigger on every relevant table, `verification_log` trigger on status change, B-Form generation function, CNIN assignment, reissuance versioning, state-machine validator |
| 4 | RLS & auth | ⚪ pending | Hospital-staff / officer / admin roles, RLS policies on every table, login UI, signed-in `/dev` features |
| 5 | Hospital portal | ⚪ pending | Multi-step birth form, IndexedDB offline queue, submissions table, device-simulator page |
| 6 | AI engine | ⚪ pending | Gemini Flash integration + rules fallback, `ai_review_log` writes, live processing feed |
| 7 | Officer portal | ⚪ pending | Flagged queue, B-Form authorization, reissuance, search, population stats |
| 8 | Dev observatory full build-out | ⚪ pending | Full query log filters, `pg_stat_statements` panel, RLS policy inspector, free-form SQL panel, EXPLAIN flame graph, state-machine visualizer |
| 9 | Polish | ⚪ pending | Landing animation pass, demo video, viva prep |

## Phase 1 — Done ✅

- Supabase project (`ap-southeast-1`, free tier)
- `query_log` table + `dev_ping` RPC
- Next.js 16 + Tailwind v4 + Geist scaffold
- Three-tier Supabase clients
- `/dev` observatory streams query log via Realtime
- Marketing landing
- GitHub repo + Vercel auto-deploy + CI
- Phase 1 docs

## Phase 2 — Done ✅

### Schema
- **13 tables** in 3NF with PKs, FKs, CHECK constraints, partial indexes, and table comments
- **12 enums** for type-safe state machines (`record_status_t`, `gender_t`, `delivery_type_t`, `birth_outcome_t`, `ai_verdict_t`, `relationship_type_t`, `notification_channel_t`, `notification_status_t`, `recipient_type_t`, `queue_status_t`, `actor_type_t`, `hospital_type_t`, `province_t`)
- **RLS enabled** on every table (policies arrive in Phase 4 — current state denies all anon access, which is the secure default)
- **24 indexes** including partial indexes (`bform_one_current_per_child`, `birth_record_father_idx`, `offline_queue_pending_idx`)
- Format CHECKs on identifiers: CNIC `XXXXX-XXXXXXX-X`, BRN `BRN-YYYY-XXXXXXXX`, CNIN `CNIN-XXXXXXXXXX`, B-Form `BF-YYYY-XXXXXXXX`, PMDC license `PMDC-NNNNNN`, etc.

### Seed data (deterministic, idempotent)
- 5 hospitals across SINDH / PUNJAB / KPK
- 4 NADRA offices
- 6 officers
- 12 parent_guardian rows (5 mothers + 5 fathers + 1 temp-ID-only mother + 1 grandmother as secondary guardian)
- 8 birth_records spanning every state in the verification state machine: 4 VERIFIED, 1 FLAGGED, 1 PENDING, 1 REJECTED, 1 AMENDED
- 4 children with CNINs assigned and dual-parent linkage
- 3 issued B-Forms (4th awaits officer authorization)
- 7 ai_review_log entries (5 PASS + 2 FLAG with realistic flag payloads)
- 7 verification_log entries
- 4 notifications (3 SENT + 1 QUEUED)
- 4 audit_trail entries
- 2 offline_queue rows (1 SYNCED + 1 PENDING)

### Observatory
- `public.get_schema()` SECURITY DEFINER RPC introspects `information_schema` and returns `{tables[], foreign_keys[], generated_at}` as JSONB
- `/dev/schema` server-renders the ER diagram from that RPC; client uses **react-flow** with **dagre** auto-layout (rankdir LR)
- Custom `TableNode` shows: PK/FK/UQ icons, NOT NULL marker, RLS badge, row-count estimate, type abbreviations
- Animated FK edges with column-name labels
- Stat strip: 14 tables · 15 FKs · ~70 seed rows
- Shared `DevNav` connects `/dev` (query feed) and `/dev/schema`

### Advisor verdict
- 13× INFO `rls_enabled_no_policy` — **expected**, Phase 4 will add policies
- 2× WARN `anon_security_definer_function_executable` on `dev_ping` and `get_schema` — **intentional**, both are explicitly public observatory RPCs
- Zero ERROR-level findings
