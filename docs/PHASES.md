# NBRPTS — Phase Roadmap

Eight phases plus a polish phase. Each phase ends with a deployable, demo-able artifact.

| # | Phase | Status | Deliverable |
|---|---|---|---|
| 1 | **Foundations** | 🟢 in progress | Repo, Vercel deploy, Supabase project, Next.js + Tailwind scaffold, CI, `/dev` observatory with `dev_ping()` streaming via Realtime |
| 2 | Schema & migrations | ⚪ pending | All 12 tables (`HOSPITAL`, `PARENT_GUARDIAN`, `BIRTH_RECORD`, `CHILD`, `CHILD_GUARDIAN`, `NADRA_OFFICE`, `NADRA_OFFICER`, `VERIFICATION_LOG`, `BFORM`, `AI_REVIEW_LOG`, `AUDIT_TRAIL`, `OFFLINE_QUEUE`, `NOTIFICATIONS`) as raw `.sql` migrations + seed data + ER diagram |
| 3 | Triggers & functions | ⚪ pending | `audit_trail` trigger, `verification_log` trigger, B-Form generation function, CNIN assignment, reissuance versioning |
| 4 | RLS & auth | ⚪ pending | Hospital-staff / officer / admin roles, RLS policies on every table, login UI |
| 5 | Hospital portal | ⚪ pending | Multi-step birth form, IndexedDB offline queue, submissions table, device-simulator page |
| 6 | AI engine | ⚪ pending | Gemini Flash integration + rules fallback, `AI_REVIEW_LOG` writes, live processing feed |
| 7 | Officer portal | ⚪ pending | Flagged queue, B-Form authorization, reissuance, search, population stats |
| 8 | Dev observatory full build-out | ⚪ pending | Full query log, ER diagram, state machine viz, EXPLAIN plan flame graph, `pg_stat_statements` panel, RLS policy inspector |
| 9 | Polish | ⚪ pending | Landing animation pass, demo video, viva prep |

## Phase 1 — Definition of Done

- [x] Supabase project created (region `ap-southeast-1`, free tier)
- [x] First migrations applied (`query_log` table + `dev_ping` RPC)
- [x] Next.js 16 + TypeScript + Tailwind v4 scaffold
- [x] Geist font, dark theme, accent palette
- [x] Supabase clients (`browser`, `server`, `admin`) wired
- [x] `/dev` observatory page streams live `query_log` rows via Realtime
- [x] Marketing landing placeholder
- [ ] Pushed to GitHub (`ruufaayl/nbrpts`)
- [ ] Deployed to Vercel with env vars
- [ ] CI workflow green on `main`
- [ ] `pnpm build` passes with zero TS errors
- [ ] Public Vercel URL loads `/dev` in <2s
