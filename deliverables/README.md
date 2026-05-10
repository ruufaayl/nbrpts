# NBRPTS — Academic Deliverables

Submission package for **CS2013 — Introduction to Database Systems, Spring 2026**, FAST-NUCES.

## What's in this folder

| File | What it contains |
|---|---|
| `NBRPTS_Report.pdf` | The complete project report — business rules, ERD, normalization (1NF → 3NF), relational schema, design decisions, SQL highlights, screenshots. Submit this. |
| `NBRPTS_Report.docx` | The same report, editable. Source for the PDF. |
| `sql/01_schema.sql` | All DDL: enums, 13 tables, 16 CHECK constraints, 24 indexes, sequences. |
| `sql/02_triggers_and_functions.sql` | Six trigger functions, eight business RPCs, observatory helpers. |
| `sql/03_security_rls.sql` | `app_user` table, RLS policies for every domain table, demo accounts. |
| `sql/04_seed_data.sql` | 86 rows of realistic seed data spanning every state. |
| `sql/05_meaningful_queries.sql` | Curated reporting queries — joins, aggregates, GROUP BY/HAVING, window functions, transactions (BEGIN/COMMIT/ROLLBACK/SAVEPOINT). |
| `sql/nbrpts_full.sql` | Single-file edition: 01 → 04 concatenated, then 05. Run top-to-bottom against an empty PostgreSQL 14+ database to rebuild from scratch. |
| `screenshots/` | Nine PNG screenshots of the live application, captured headlessly from `localhost:3000`. |

## Reproducing the database

```bash
# 1. Empty PostgreSQL 14+ database (Supabase, Postgres.app, Docker — anything).
# 2. Connect as a user with CREATE TABLE rights.
# 3. Run:
psql -d <db> -f sql/nbrpts_full.sql

# That's it. The schema is in 3NF, the triggers fire, the seed data is loaded,
# and the curated queries at the bottom of the file run cleanly against it.
```

## Reproducing the application

```bash
git clone https://github.com/ruufaayl/nbrpts
cd nbrpts
pnpm install
cp .env.example .env.local      # add your Supabase URL and anon key
pnpm dev                        # http://localhost:3000
```

The application is also live at **https://nbrpts.vercel.app**.

## Demo accounts

All three accounts share the password `demo1234`:

- `aku@nbrpts.demo` — hospital staff at Aga Khan University Hospital
- `aisha@nbrpts.demo` — NADRA officer (Karachi-South)
- `admin@nbrpts.demo` — full admin

Anonymous visitors can browse `/`, `/dev`, `/dev/schema`, `/dev/triggers`, and `/login` without authentication.

## Tools used

- **PostgreSQL 15** (via Supabase free tier, ap-southeast-1).
- **Next.js 16** App Router with Server Components and Server Actions.
- **Tailwind CSS v4** + Framer Motion + react-flow + dagre.
- **Supabase Auth** (email + password, JWT cookies, `@supabase/ssr`).
- **Vercel** free tier for hosting; **GitHub** for source control; **pnpm** for package management.

> **Note on choice of DBMS.** The course suggests MySQL or SQL Server. We chose PostgreSQL because every concept the course covers — DDL, constraints, normalization, joins, aggregates, GROUP BY, HAVING, transactions — is fully supported (often more rigorously) in PostgreSQL. PostgreSQL additionally gave us, at no extra learning cost, native ENUM types, partial indexes, regex CHECK constraints, JSONB, and Row-Level Security. The SQL is standard-compliant and ports back to MySQL with mechanical changes (ENUM → VARCHAR + CHECK; JSONB → JSON; `gen_random_uuid()` → `UUID()`).

## Regenerating the deliverables

```bash
# After any schema change:
node scripts/build-sql-bundle.mjs    # rebuilds deliverables/sql/

# After any UI change:
pnpm dev                                                  # in another terminal
node scripts/capture-screenshots.mjs                      # rebuilds deliverables/screenshots/

# After any content change:
node scripts/build-report.mjs                             # rebuilds NBRPTS_Report.docx
powershell -ExecutionPolicy Bypass -File scripts/docx-to-pdf.ps1 \
  -InPath deliverables/NBRPTS_Report.docx \
  -OutPath deliverables/NBRPTS_Report.pdf                 # rebuilds the PDF
```

The PDF conversion step requires Microsoft Word installed (it uses Word COM automation).
On a machine without Word, open `NBRPTS_Report.docx` in Word, Google Docs, or
LibreOffice and export to PDF manually.
