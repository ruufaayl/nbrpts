# NBRPTS — National Birth Registry & Population Tracking System

A real-time alternative to the decennial census of Pakistan.

> Semester project for **CS2013 — Introduction to Database Systems** at FAST-NUCES, Spring 2026.

## What this is

Three real portals (hospital data entry, AI verification monitor, NADRA officer dashboard) plus a **live database observatory** at `/dev` that streams every tracked SQL call to the page in real time — including duration and the `EXPLAIN (FORMAT JSON)` plan.

## Stack

| Layer | Tech |
|---|---|
| Framework | Next.js 16 (App Router) + TypeScript |
| Styling | Tailwind v4 + Geist font |
| Animation | Framer Motion |
| Database | Supabase Postgres (free tier) |
| Auth | Supabase Auth (Phase 4) |
| Realtime | Supabase Realtime |
| Hosting | Vercel (free hobby tier) |
| AI | Google Gemini Flash (free tier) — Phase 6 |

All schema lives in [`supabase/migrations/`](./supabase/migrations) as raw SQL. All business logic lives in Postgres functions. The frontend calls `supabase.rpc(...)` so every action maps to a single visible SQL call.

## Run locally

```bash
pnpm install
cp .env.example .env.local   # fill in Supabase URL + publishable key
pnpm dev
```

Open <http://localhost:3000>. The `/dev` route fires `dev_ping()` on every load and shows the live feed.

## Phase status

See [`docs/PHASES.md`](./docs/PHASES.md). Currently on **Phase 1 — Foundations**.
