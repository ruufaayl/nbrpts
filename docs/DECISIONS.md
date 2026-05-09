# Architecture Decisions

Decisions locked in during Phase 1. Revisit only when a phase explicitly demands it.

| Decision | Choice | Why |
|---|---|---|
| Framework | Next.js 16 App Router | RSC + Server Actions = clean SQL invocation; free on Vercel |
| Package manager | pnpm 10 | Fast installs, Vercel-native |
| Node | 20 LTS minimum (22 used locally) | Matches Vercel default |
| Styling | Tailwind v4 (PostCSS) + Geist | v4 is config-less; Geist gives instant premium feel |
| DB client | `@supabase/supabase-js` v2 | Auth + Realtime + RPC in one package |
| Migrations | Raw SQL files in `supabase/migrations/` | Pure Postgres = what the course rewards |
| Business logic location | Postgres functions (RPCs), not the JS layer | Triggers + functions = grading goldmine; also makes every action observable in `/dev` |
| Auth | Supabase Auth | Free, RLS-aware (Phase 4) |
| AI | Google Gemini 2.0 Flash (free tier) | Anthropic Claude is paid; Gemini Flash is genuinely free |
| SMS | Mocked into `notifications` table | Twilio is paid |
| State | React Query only when needed | No premature Zustand/Redux |
| Animation | Framer Motion | Industry standard for React |
| Icons | lucide-react | shadcn default |
| Hosting | Vercel hobby + Supabase free | $0 total |
| Region | Supabase `ap-southeast-1` (Singapore) | Closest free region to Pakistan |
| Repo | Public GitHub, `main` branch, PR-based | Free CI minutes; portfolio-friendly |

## Decisions explicitly deferred

- **Monorepo layout** — single Next.js app for now. Promote to `apps/*` only if a second app (docs, device emulator) materializes.
- **Drizzle / Prisma** — not used. Raw SQL beats ORM for a DB course.
- **Postgres.js** — not yet. RPCs cover Phase 1; raw client comes in Phase 8 if needed for the observatory's free-form SQL panel.
