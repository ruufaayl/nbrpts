// Concatenates all Supabase migrations into the deliverable SQL files
// expected by the CS2013 rubric. Run with `node scripts/build-sql-bundle.mjs`.
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { join, basename } from "node:path";

const ROOT = process.cwd();
const MIG_DIR = join(ROOT, "supabase", "migrations");
const OUT_DIR = join(ROOT, "deliverables", "sql");

const files = readdirSync(MIG_DIR).filter((f) => f.endsWith(".sql")).sort();
const read = (f) => readFileSync(join(MIG_DIR, f), "utf8").trimEnd();

const sections = {
  "01_schema.sql": {
    title: "Schema (enums, tables, constraints, indexes, sequences)",
    files: ["0002_enums.sql", "0003_core_tables.sql", "0007_phase3_schema_additions.sql"],
  },
  "02_triggers_and_functions.sql": {
    title: "Triggers, business RPCs, and observatory helpers",
    files: [
      "0001_dev_ping_rpc.sql",
      "0004_get_schema_rpc.sql",
      "0006_harden_get_schema_row_count.sql",
      "0008_audit_trigger.sql",
      "0009_state_machine.sql",
      "0010_bform_functions.sql",
      "0011_business_rpcs.sql",
      "0012_harden_function_security.sql",
      "0013_get_trigger_lab_data_rpc.sql",
      "0017_phase5_hospital_rpcs.sql",
    ],
  },
  "03_security_rls.sql": {
    title: "Row-Level Security, app_user, and demo accounts",
    files: ["0014_phase4_app_user.sql", "0015_phase4_rls_policies.sql", "0016_phase4_seed_demo_users.sql"],
  },
  "04_seed_data.sql": {
    title: "Seed data — 86 rows spanning every state",
    files: ["0000_init_query_log.sql", "0005_seed.sql"],
  },
};

const banner = (title) =>
  `-- =============================================================================\n-- ${title}\n-- =============================================================================\n`;

let allParts = [];

for (const [outName, def] of Object.entries(sections)) {
  let body = banner(`NBRPTS — ${def.title}`) + "\n";
  for (const f of def.files) {
    if (!files.includes(f)) {
      console.warn(`!! migration ${f} not found, skipping`);
      continue;
    }
    body += `\n-- ----- ${f} ${"-".repeat(70 - f.length)}\n\n`;
    body += read(f) + "\n";
  }
  writeFileSync(join(OUT_DIR, outName), body);
  console.log(`wrote deliverables/sql/${outName}  (${(body.length / 1024).toFixed(1)} kB)`);
  allParts.push({ name: outName, body });
}

// Mega-bundle
let mega = banner("NBRPTS — Complete Database Build (single-file edition)") + "\n";
mega += "-- This is the full data layer. To build a fresh database run this script\n";
mega += "-- top-to-bottom, then load deliverables/sql/05_meaningful_queries.sql for\n";
mega += "-- the rubric-required reporting queries.\n\n";
for (const p of allParts) mega += "\n" + p.body + "\n";
mega += "\n" + banner("Curated reporting queries (joins, aggregates, transactions)");
mega += readFileSync(join(OUT_DIR, "05_meaningful_queries.sql"), "utf8");
writeFileSync(join(OUT_DIR, "nbrpts_full.sql"), mega);
console.log(`wrote deliverables/sql/nbrpts_full.sql  (${(mega.length / 1024).toFixed(1)} kB)`);
