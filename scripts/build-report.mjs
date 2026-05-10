// NBRPTS — Academic Project Report builder
// Produces deliverables/NBRPTS_Report.docx (and we convert to PDF separately).
//
// Run: node scripts/build-report.mjs
import {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  AlignmentType, PageOrientation, LevelFormat, ImageRun,
  Header, Footer, HeadingLevel, BorderStyle, WidthType, ShadingType,
  PageNumber, PageBreak, TabStopType, TabStopPosition,
} from "docx";
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { join } from "node:path";

const ROOT = process.cwd();
const SHOTS = join(ROOT, "deliverables", "screenshots");
const OUT  = join(ROOT, "deliverables", "NBRPTS_Report.docx");

// ---- helpers ---------------------------------------------------------------
const ARIAL = "Arial";
const FG    = "111111";
const MUT   = "555555";
const ACC   = "0E8C6E";   // green-ish accent

const p = (text, opts = {}) =>
  new Paragraph({
    spacing: { before: 60, after: 60, line: 300 },
    ...opts,
    children: [new TextRun({ text, font: ARIAL, size: 22, ...opts.run })],
  });

const heading = (text, level) =>
  new Paragraph({
    heading: level === 1 ? HeadingLevel.HEADING_1
            : level === 2 ? HeadingLevel.HEADING_2
            : HeadingLevel.HEADING_3,
    spacing: { before: level === 1 ? 360 : 240, after: 120 },
    pageBreakBefore: level === 1,
    children: [new TextRun({
      text, font: ARIAL, bold: true,
      size: level === 1 ? 36 : level === 2 ? 28 : 24,
      color: level === 1 ? ACC : FG,
    })],
  });

const lead = (text) => new Paragraph({
  spacing: { before: 0, after: 200, line: 320 },
  children: [new TextRun({ text, font: ARIAL, size: 22, color: MUT, italics: true })],
});

const bullet = (text) => new Paragraph({
  numbering: { reference: "bullets", level: 0 },
  spacing: { before: 40, after: 40, line: 280 },
  children: [new TextRun({ text, font: ARIAL, size: 22 })],
});

const numbered = (text) => new Paragraph({
  numbering: { reference: "numbers", level: 0 },
  spacing: { before: 40, after: 40, line: 280 },
  children: [new TextRun({ text, font: ARIAL, size: 22 })],
});

const code = (text) => new Paragraph({
  spacing: { before: 60, after: 60, line: 280 },
  shading: { fill: "F4F5F4", type: ShadingType.CLEAR },
  border: {
    top:    { style: BorderStyle.SINGLE, size: 1, color: "DCE3DC" },
    bottom: { style: BorderStyle.SINGLE, size: 1, color: "DCE3DC" },
    left:   { style: BorderStyle.SINGLE, size: 1, color: "DCE3DC" },
    right:  { style: BorderStyle.SINGLE, size: 1, color: "DCE3DC" },
  },
  indent: { left: 120, right: 120 },
  children: text.split("\n").flatMap((line, i, arr) => {
    const r = [new TextRun({ text: line, font: "Consolas", size: 18, color: FG })];
    if (i < arr.length - 1) r.push(new TextRun({ break: 1 }));
    return r;
  }),
});

const inlineCode = (text) =>
  new TextRun({ text, font: "Consolas", size: 20, color: ACC });

const para = (...runs) => new Paragraph({
  spacing: { before: 60, after: 60, line: 300 },
  children: runs,
});
const t = (text, opts = {}) => new TextRun({ text, font: ARIAL, size: 22, ...opts });

// PNG dims from header
function pngDims(buf) {
  const w = buf.readUInt32BE(16);
  const h = buf.readUInt32BE(20);
  return { w, h };
}

const figure = (relPath, caption) => {
  const file = join(SHOTS, relPath);
  if (!existsSync(file)) {
    console.warn("missing screenshot:", file);
    return p(`[missing screenshot: ${relPath}]`);
  }
  const data = readFileSync(file);
  const { w, h } = pngDims(data);
  const targetW = 600;
  const targetH = Math.round(targetW * h / w);
  return [
    new Paragraph({
      spacing: { before: 200, after: 60 },
      alignment: AlignmentType.CENTER,
      children: [new ImageRun({
        type: "png",
        data,
        transformation: { width: targetW, height: targetH },
        altText: { title: caption, description: caption, name: caption },
      })],
    }),
    new Paragraph({
      spacing: { before: 0, after: 200 },
      alignment: AlignmentType.CENTER,
      children: [new TextRun({
        text: caption, font: ARIAL, size: 18, color: MUT, italics: true,
      })],
    }),
  ];
};

// table builder
const cellBorder = { style: BorderStyle.SINGLE, size: 4, color: "CCCCCC" };
const cellBorders = { top: cellBorder, bottom: cellBorder, left: cellBorder, right: cellBorder };

const tableCell = (text, opts = {}) => new TableCell({
  borders: cellBorders,
  margins: { top: 80, bottom: 80, left: 120, right: 120 },
  shading: opts.header ? { fill: "EEF6F2", type: ShadingType.CLEAR } : undefined,
  width: opts.width,
  children: [new Paragraph({
    children: [new TextRun({
      text, font: ARIAL, size: 20,
      bold: !!opts.header || !!opts.bold,
    })],
  })],
});

const buildTable = (rows, columnWidths) => {
  return new Table({
    width: { size: columnWidths.reduce((a, b) => a + b, 0), type: WidthType.DXA },
    columnWidths,
    rows: rows.map((row, i) => new TableRow({
      children: row.map((cell, j) => tableCell(cell, {
        header: i === 0,
        width: { size: columnWidths[j], type: WidthType.DXA },
      })),
    })),
  });
};

// ---- COVER -----------------------------------------------------------------
const cover = [
  new Paragraph({ spacing: { before: 1800, after: 0 }, children: [t("CS2013 — Introduction to Database Systems", { color: MUT, size: 22 })] }),
  new Paragraph({ spacing: { before: 0, after: 0 }, children: [t("Spring 2026 · FAST-NUCES", { color: MUT, size: 22 })] }),
  new Paragraph({ spacing: { before: 480, after: 0 }, children: [t("NBRPTS", { bold: true, size: 84, color: ACC })] }),
  new Paragraph({ spacing: { before: 60, after: 0 }, children: [t("National Birth Registry & Population Tracking System", { bold: true, size: 36 })] }),
  new Paragraph({ spacing: { before: 40, after: 0 }, children: [t("A real-world database design and implementation, end-to-end.", { italics: true, color: MUT, size: 22 })] }),
  new Paragraph({ spacing: { before: 1200, after: 0 }, children: [t("Project Report", { bold: true, size: 28 })] }),
  new Paragraph({ spacing: { before: 60, after: 0 }, children: [t("Submitted to: Ms. Rimsha Riaz · Mr. Adnan Rana", { size: 22 })] }),
  new Paragraph({ spacing: { before: 0, after: 0 }, children: [t("Live deployment: ", { size: 22 }), inlineCode("https://nbrpts.vercel.app")] }),
  new Paragraph({ spacing: { before: 0, after: 0 }, children: [t("Source code: ", { size: 22 }), inlineCode("https://github.com/ruufaayl/nbrpts")] }),
  new Paragraph({ spacing: { before: 1800, after: 0 }, children: [t("─".repeat(40), { color: "CCCCCC", size: 16 })] }),
  new Paragraph({ children: [new PageBreak()] }),
];

// ---- ABSTRACT --------------------------------------------------------------
const abstract = [
  heading("Abstract", 1),
  para(t("NBRPTS is a working implementation of a national-scale birth registry. Hospitals submit a child's birth electronically the moment delivery is complete; an automated verification layer reviews each record; a NADRA officer authorizes the issuance of a B-Form (Pakistan's child identity certificate) — and the parents leave the hospital with their child legally registered in the national population database.")),
  para(t("The system is built on a 13-table relational schema in Third Normal Form, enforced by twenty-four indexes, sixteen CHECK constraints, fifteen foreign-key relationships, twelve PostgreSQL trigger functions, and thirteen tables protected by Row-Level Security. Every meaningful action is recorded in an append-only audit trail; every state transition is governed by an in-database state machine.")),
  para(t("This report documents the system end-to-end: the business rules that motivated each design choice, the entity model that fell out of those rules, the formal normalization process that produced the final schema, the SQL that implements it, and screenshots of the live application demonstrating the design at work.")),
];

// ---- 1. INTRODUCTION -------------------------------------------------------
const introduction = [
  heading("1.  Introduction & Problem Statement", 1),
  heading("1.1  The problem", 2),
  para(t("As of 2024, only 42% of Pakistani children under five hold a birth certificate (UNICEF). The remaining 58% are invisible to the state — they cannot be enrolled in school, cannot access vaccinations, cannot receive welfare benefits, and as adults will struggle to obtain a CNIC, vote, hold a bank account, or travel abroad. The bottleneck is not the law (which has mandated birth registration since 2000) but the workflow: registration happens at a Union Council office, weeks or months after birth, requiring parents to make a separate trip with paper documents.")),
  heading("1.2  The proposed solution", 2),
  para(t("NBRPTS moves the point of registration from the Union Council to the hospital. The moment a child is delivered, the hospital staff captures the birth on a tamper-proof terminal. The record streams to a central PostgreSQL database. An automated verification layer (an LLM-backed scoring engine, with a deterministic rules fallback) reviews the record in real time. If the record is clean it auto-progresses to a NADRA officer for B-Form issuance. If the verification engine has any concern, the record is flagged for human review. The B-Form is ready before the parents are discharged.")),
  heading("1.3  Why this is a database problem", 2),
  para(t("The system is, fundamentally, a relational database problem. The entities are well-defined (hospitals, parents, children, B-Forms, officers), the relationships are clear, the business rules are strict, and the integrity constraints are non-negotiable: a child cannot exist without a verified birth record; a B-Form cannot exist without a child; an officer cannot back-date a verification. Every concept the course covers — entities, attributes, foreign keys, normalization, indexes, transactions, triggers, views, joins, aggregates — has a direct, real-world expression here.")),
];

// ---- 2. BUSINESS RULES -----------------------------------------------------
const businessRules = [
  heading("2.  Business Rules", 1),
  lead("These are the rules the database must enforce. Each rule is realized later as a CHECK constraint, foreign key, trigger, or RLS policy."),
  heading("2.1  Hospitals & registration", 2),
  numbered("Every hospital must hold a unique Hospital Registration Number in the format HRN-YYYY-NNNN."),
  numbered("Only registered, active hospitals may submit birth records."),
  numbered("A hospital is associated with exactly one province and one district."),
  heading("2.2  Parents & guardians", 2),
  numbered("Every adult is identified by a CNIC in the format 12345-1234567-1, OR by a temporary registration ID in the format TMP-XXXXXXXX if their CNIC is unavailable."),
  numbered("A single person can play multiple roles (mother of one child, guardian of another) — they are stored exactly once and referenced from each role."),
  numbered("The mother and the father on a birth record must be different people."),
  numbered("Every parent record requires either a CNIC or a temporary registration ID; both being NULL is forbidden."),
  heading("2.3  Births", 2),
  numbered("Every birth is identified by a globally unique Birth Record Number in the format BRN-YYYY-NNNNNNNN, generated by a sequence on submission."),
  numbered("Birth weight must be between 0.30 kg and 7.00 kg; values outside this range indicate either data entry errors or genuine medical anomalies that require manual entry."),
  numbered("The birth datetime must not be more than one day in the future (a small future grace allows for clock drift and pre-submitted records on the day of delivery)."),
  numbered("The attending doctor's PMDC license must match the format PMDC-NNNNNN."),
  heading("2.4  Verification state machine", 2),
  numbered("A new birth record begins in PENDING state."),
  numbered("Allowed transitions are: PENDING → VERIFIED, PENDING → FLAGGED, PENDING → REJECTED, FLAGGED → VERIFIED, FLAGGED → REJECTED, REJECTED → PENDING (resubmission), VERIFIED → AMENDED, AMENDED → AMENDED."),
  numbered("All other transitions raise an exception. A trigger enforces this — the application code cannot bypass it."),
  heading("2.5  Children & CNINs", 2),
  numbered("A child entity is created automatically the first time the parent birth record reaches VERIFIED state — never manually."),
  numbered("Every child receives a unique 14-character CNIN in the format CNIN-NNNNNNNNNN, drawn from a sequence."),
  numbered("There is exactly one child per verified birth record (the schema enforces 1:1)."),
  heading("2.6  B-Forms", 2),
  numbered("A B-Form is issued by exactly one NADRA officer."),
  numbered("B-Forms are versioned. Originals are never deleted; instead the previous version's is_current flag is cleared and a new version is inserted."),
  numbered("Exactly one B-Form per child may have is_current = true at any moment (enforced by a partial unique index)."),
  heading("2.7  Auditing & immutability", 2),
  numbered("Every meaningful database action is recorded in audit_trail (system-wide append-only log)."),
  numbered("Every state transition on a birth record is recorded in verification_log with the officer's identity and a timestamp."),
  numbered("Audit-trail rows are write-only — no UPDATE or DELETE policy permits modification."),
  heading("2.8  Access control", 2),
  numbered("A hospital staff user may only see birth records, parents, children, B-Forms, and notifications belonging to their own hospital."),
  numbered("A NADRA officer may see all hospitals' records but only their own user account."),
  numbered("An admin role may see and modify everything."),
  numbered("These rules are enforced inside the database (Row-Level Security), not just at the application layer — direct REST queries cannot circumvent them."),
];

// ---- 3. ENTITIES -----------------------------------------------------------
const entityTable = buildTable([
  ["#", "Entity",            "Cardinality", "Purpose"],
  ["1", "hospital",          "≈ 4 K", "Every authorized facility"],
  ["2", "nadra_office",      "~ 30",  "Regional NADRA offices"],
  ["3", "nadra_officer",     "~ 800", "Officers who verify and issue B-Forms"],
  ["4", "parent_guardian",   "millions", "Mothers, fathers, legal guardians"],
  ["5", "birth_record",      "millions", "One row per birth (transactional core)"],
  ["6", "child",             "≈ births × 0.95", "Created on verification; assigned a CNIN"],
  ["7", "child_guardian",    "≥ children", "M:N junction (handles adoption, joint custody)"],
  ["8", "bform",             "≥ children", "Versioned B-Form documents"],
  ["9", "verification_log",  "≥ records × 1.5", "Every state transition"],
  ["10", "ai_review_log",    "≥ records",       "Every AI verdict"],
  ["11", "audit_trail",      "≥ all writes",    "System-wide audit"],
  ["12", "offline_queue",    "device-local",    "Records buffered offline"],
  ["13", "notifications",    "outbound",        "SMS / email / in-app"],
], [600, 2200, 1900, 4660]);

const entities = [
  heading("3.  Entities & Attributes", 1),
  para(t("Thirteen entities, distilled from the business rules. Cardinality estimates are based on Pakistan's annual ~6 million births.")),
  entityTable,
  heading("3.1  Identifying attributes", 2),
  bullet("All primary keys are surrogate UUIDs (gen_random_uuid()) — they are stable, opaque, and never reused."),
  bullet("Domain identifiers (HRN, BRN, CNIN, B-Form number) are separate UNIQUE-constrained text columns with format-validating regex CHECK constraints."),
  bullet("This separation lets us refactor display formats without breaking foreign-key relationships."),
];

// ---- 4. RELATIONSHIPS ------------------------------------------------------
const relationships = [
  heading("4.  Relationships", 1),
  para(t("Fifteen foreign-key relationships connect the thirteen entities. Most are 1:N. Two are 1:1. One is M:N (resolved with a junction table).")),
  heading("4.1  One-to-many (1:N)", 2),
  bullet("hospital → birth_record  (a hospital files many birth records)"),
  bullet("parent_guardian (mother) → birth_record  (a mother may have many children)"),
  bullet("parent_guardian (father, optional) → birth_record"),
  bullet("birth_record → verification_log  (every record has many state-change events)"),
  bullet("birth_record → ai_review_log     (every record has many review attempts)"),
  bullet("nadra_office → nadra_officer"),
  bullet("nadra_officer → verification_log"),
  bullet("nadra_officer → bform"),
  bullet("hospital → offline_queue"),
  heading("4.2  One-to-one (1:1)", 2),
  bullet("birth_record → child  (a verified birth produces exactly one child; UNIQUE FK)"),
  bullet("auth.users → app_user (the auth.users.id appears at most once in app_user)"),
  heading("4.3  Many-to-many (M:N)", 2),
  para(t("The relationship between a child and their guardians is genuinely many-to-many. A child can have multiple legal guardians; a single guardian can be linked to multiple children. This is resolved through the "), inlineCode("child_guardian"), t(" junction table:")),
  code(`child   ── 1 ── child_guardian ── N ──   parent_guardian
                       │
                       ├── relationship_type   (MOTHER, FATHER, GUARDIAN, ADOPTIVE_PARENT, ...)
                       ├── is_primary          (one primary guardian per child)
                       └── linked_at`),
  para(t("This shape lets us model adoption (an adoptive parent links to a child without affecting the original birth_record), joint custody, and step-parent arrangements without compromising the immutability of the birth record itself.")),
];

// ---- 5. ERD ----------------------------------------------------------------
const erd = [
  heading("5.  Entity-Relationship Diagram", 1),
  para(t("The ER diagram below is generated live by the application — at runtime, the page reads "), inlineCode("information_schema.tables"), t(" and "), inlineCode("information_schema.table_constraints"), t(" through a SECURITY DEFINER RPC and renders the result as a draggable, zoomable graph. The fact that the database itself can describe its own structure is part of what makes this project a teaching tool.")),
  ...figure("03_dev_er_diagram.png", "Figure 5.1 — Live ER diagram, rendered at /dev/schema from information_schema."),
  heading("5.1  Reading the diagram", 2),
  bullet("Filled green dots mark primary keys."),
  bullet("Open green circles mark foreign keys."),
  bullet("Grey dots mark unique-constrained columns."),
  bullet("Edges indicate FK relationships, drawn with arrows from child to parent."),
];

// ---- 6. NORMALIZATION ------------------------------------------------------
const norm = [
  heading("6.  Normalization (1NF → 3NF)", 1),
  para(t("The schema is in Third Normal Form. This section walks the journey of a single concept — a birth record and its parents — through the three normal forms to demonstrate the process.")),
  heading("6.1  Pre-1NF (the naive design)", 2),
  para(t("If we tried to capture every birth in a single flat table, we would write something like:")),
  code(`birth_records (
  brn,
  hospital_name, hospital_district, hospital_province, hospital_contact,
  mother_name, mother_cnic, mother_dob, mother_address,
  mother_blood_group,
  father_name, father_cnic, father_dob, father_address,
  guardian_names_csv,                           -- "Aunt Fatima, Uncle Asif"
  attending_doctor, doctor_license,
  birth_datetime, delivery_type, birth_weight,
  child_name, child_gender, child_cnin,
  bform_number, bform_issue_date, bform_officer
)`),
  para(t("This violates almost every normal form simultaneously.")),
  heading("6.2  1NF — atomic, single-valued attributes", 2),
  para(t("First normal form requires every column to hold a single, atomic value, and forbids repeating groups. The "), inlineCode("guardian_names_csv"), t(" column is an obvious 1NF violation: a comma-separated list is a repeating group hidden inside a string.")),
  para(t("To reach 1NF we extract guardians into their own row-per-guardian table:")),
  code(`birth_records         (..., as before, minus guardian_names_csv)
guardians_of_record   (brn, guardian_name, relationship_type)`),
  para(t("Every column now holds exactly one value of its declared type.")),
  heading("6.3  2NF — no partial dependencies on a composite key", 2),
  para(t("Second normal form applies when a table has a composite primary key. The "), inlineCode("guardians_of_record"), t(" table from 1NF has the composite key (brn, guardian_name). If we ever add an attribute that depends on only part of the key — say, "), inlineCode("guardian_cnic"), t(" — we have a 2NF violation: the CNIC depends on the guardian, not on the (record, guardian) pair.")),
  para(t("The fix is to split the guardian into its own entity:")),
  code(`parent_guardian   (guardian_id PK, full_name, cnic, dob, address, ...)
child_guardian    (cg_id PK, child_id FK, guardian_id FK, relationship_type)`),
  para(t("Every non-key attribute now depends on the whole key.")),
  heading("6.4  3NF — no transitive dependencies", 2),
  para(t("Third normal form forbids transitive dependencies — non-key attributes depending on other non-key attributes. The naive design has many of these:")),
  bullet("hospital_district and hospital_province depend on hospital_name, not on brn."),
  bullet("mother_blood_group depends on mother_cnic, not on brn."),
  bullet("bform_officer depends on bform_number, not on brn."),
  para(t("Each transitive dependency is resolved by extracting a new entity:")),
  code(`hospital          (hospital_id PK, hrn UQ, name, district, province, ...)
parent_guardian   (guardian_id PK, cnic UQ, name, dob, blood_group, ...)
nadra_officer     (officer_id PK, employee_no UQ, full_name, ...)
bform             (bform_id PK, bform_number UQ, child_id FK, issued_by FK, ...)
birth_record      (birth_record_id PK, brn UQ, hospital_id FK,
                   mother_id FK, father_id FK,
                   attending_doctor, birth_datetime, delivery_type, ...)
child             (child_id PK, cnin UQ, birth_record_id FK UQ, full_name, ...)`),
  heading("6.5  Verification table", 2),
  para(t("To prove the result is in 3NF we apply the textbook test: for every non-trivial functional dependency X → A, either X is a superkey, or A belongs to a candidate key.")),
  buildTable([
    ["Functional dependency", "Holds in schema?", "Reason it satisfies 3NF"],
    ["hospital_id → hrn, name, district",  "Yes", "hospital_id is the PK of hospital"],
    ["hrn → hospital_id, name, district",  "Yes", "hrn is UNIQUE — also a candidate key"],
    ["mother_id → cnic, name, dob",        "Yes", "mother_id is the PK of parent_guardian"],
    ["birth_record_id → brn, mother_id, hospital_id, status", "Yes", "birth_record_id is the PK"],
    ["child_id → cnin, full_name, birth_record_id", "Yes", "child_id is the PK"],
    ["bform_number → child_id, issued_by, version",  "Yes", "bform_number is UNIQUE"],
  ], [3600, 1500, 4260]),
  para(t("No non-key attribute determines another non-key attribute, in any table. The schema is in 3NF.")),
  heading("6.6  Why we did not push to BCNF / 4NF", 2),
  para(t("Boyce-Codd Normal Form requires that every determinant be a superkey. Our schema satisfies this trivially — no compound determinants exist. Fourth Normal Form requires the elimination of multi-valued dependencies; we have none, because the M:N relationship between child and guardian was already broken into a junction table at 2NF. Pushing further (5NF, DKNF) would not change a single column.")),
];

// ---- 7. SCHEMA -------------------------------------------------------------
const schemaIntro = [
  heading("7.  Relational Schema", 1),
  para(t("The thirteen tables, with primary keys, foreign keys, and the most important constraints. The full DDL is reproduced verbatim in "), inlineCode("deliverables/sql/01_schema.sql"), t(".")),
];

// table summary rows
const schemaSummary = buildTable([
  ["Table", "PK", "Notable columns", "FKs out"],
  ["hospital", "hospital_id", "hrn UQ regex, hospital_type enum, province enum", "—"],
  ["nadra_office", "office_id", "jurisdiction_districts text[]", "—"],
  ["nadra_officer", "officer_id", "employee_no UQ regex, email UQ regex", "office_id"],
  ["parent_guardian", "guardian_id", "cnic UQ regex, gender enum, blood_group", "—"],
  ["birth_record", "birth_record_id", "brn UQ, status enum, ai_review_result jsonb", "hospital_id, mother_id, father_id?"],
  ["child", "child_id", "cnin UQ regex (mothered by trigger)", "birth_record_id (UQ → 1:1)"],
  ["child_guardian", "cg_id", "relationship_type enum, is_primary", "child_id, guardian_id"],
  ["bform", "bform_id", "bform_number UQ, version, is_current", "child_id, issued_by"],
  ["verification_log", "log_id", "previous_status, new_status enums", "birth_record_id, officer_id"],
  ["ai_review_log", "review_id", "verdict enum, confidence_score 0..1, raw_response jsonb", "birth_record_id, override_officer_id?"],
  ["audit_trail", "audit_id", "actor_type enum, action_type, ip_address inet", "—"],
  ["offline_queue", "queue_id", "payload jsonb, status enum", "hospital_id, birth_record_id?"],
  ["notifications", "notification_id", "channel enum, status enum, recipient_contact", "—"],
  ["app_user", "user_id (auth.users)", "role enum (hospital_staff, nadra_officer, admin)", "hospital_id?, officer_id?"],
], [1900, 1500, 4060, 1900]);

const schema = [
  ...schemaIntro,
  schemaSummary,
  heading("7.1  Constraint summary", 2),
  bullet("15 foreign keys with explicit ON DELETE behavior (RESTRICT for primary lineage, CASCADE for owned data, SET NULL for optional links)."),
  bullet("16 CHECK constraints enforcing business rules (CNIC, BRN, CNIN, PMDC, HRN, B-Form-number formats; weight 0.30–7.00 kg; future-dated birth grace; date-of-birth not in future; one-of-many parent identifier)."),
  bullet("24 indexes — every foreign key column, every status column, every date column used in WHERE/ORDER BY."),
  bullet("4 UNIQUE constraints (HRN, BRN, CNIC, employee_no) and 1 partial unique index (one current B-Form per child)."),
];

// ---- 8. DESIGN DECISIONS ---------------------------------------------------
const decisions = [
  heading("8.  Design Decisions & Assumptions", 1),
  heading("8.1  PostgreSQL instead of MySQL", 2),
  para(t("The course suggests MySQL or SQL Server. We chose PostgreSQL because every concept the course covers — DDL, constraints, normal forms, joins, aggregates, GROUP BY, HAVING, transactions — is fully supported (and in many cases more rigorously enforced) in PostgreSQL. PostgreSQL additionally gave us, at no extra learning cost: enumerated types instead of magic strings; partial indexes for efficient queries on subsets; CHECK constraints with regex; JSONB for the AI verdict payload; and Row-Level Security for the access-control rules in §2.8. The SQL is standard-compliant and ports back to MySQL with mechanical changes (replace ENUM types with VARCHAR + CHECK, replace JSONB with JSON, replace gen_random_uuid() with UUID()).")),
  heading("8.2  Surrogate UUID keys", 2),
  para(t("Every primary key is a UUID rather than an integer. A national database is concurrent, distributed, and likely sharded; integer sequences create a single point of contention and reveal record counts to anyone who can guess. UUIDs are independent, opaque, stable, and globally unique. Domain identifiers (HRN, BRN, CNIN, B-Form number) live in separate UNIQUE columns so their format can evolve independently of the foreign-key graph.")),
  heading("8.3  Single parent_guardian table for mothers, fathers, and guardians", 2),
  para(t("A naive design would model mother, father, and guardian as three separate tables. This is wrong: the same person frequently appears in multiple roles (a woman is the mother of one child and the legal guardian of her sister's child). Storing her three times invites contradiction the moment any of the duplicates is updated. Instead, we have one parent_guardian row per person, referenced from birth_record (mother_id, father_id) and from child_guardian (any number of guardians). This is identical to how a library models a person who is both an author and a borrower.")),
  heading("8.4  Children created only by trigger, never by application code", 2),
  para(t("The application code never inserts directly into "), inlineCode("child"), t(". A trigger on "), inlineCode("birth_record"), t(" fires when (and only when) the record reaches VERIFIED state for the first time, and creates the child + guardian links + B-Form + notification rows in a single atomic transaction. This is what guarantees the business rule “a child entity exists ⇔ a birth record is verified.” No application bug can violate it.")),
  heading("8.5  Versioned B-Forms, never deleted", 2),
  para(t("When parents need a duplicate B-Form (the original is lost, damaged, or has a name correction), we never UPDATE the existing row. We INSERT a new B-Form with version = previous + 1, and SET is_current = false on the old row. A partial unique index ("), inlineCode("ON bform(child_id) WHERE is_current"), t(") makes it physically impossible for two B-Forms to be “current” for the same child. The audit trail of every reissue is preserved forever, which matters for legal disputes.")),
  heading("8.6  Append-only audit_trail and verification_log", 2),
  para(t("Both tables have RLS policies that permit INSERT but never UPDATE or DELETE for any role. The PostgreSQL roles that the application uses do not have UPDATE or DELETE privileges on these tables either. Combined, this gives a regulator-grade audit log: even an admin cannot rewrite history without a database-level privilege escalation.")),
  heading("8.7  Row-Level Security for tenant isolation", 2),
  para(t("Hospitals must not see each other's records. We enforce this in the database, not in the application. Every domain table has RLS enabled with policies that read auth.uid() (the JWT subject) and look up the user's hospital_id in app_user. Even if the application code has a bug that issues a SELECT without a WHERE clause, the database returns only the rows the user is allowed to see.")),
  heading("8.8  Assumptions", 2),
  bullet("CNIC numbers are unique nationally and never re-issued. (True per NADRA documentation.)"),
  bullet("A single PMDC license belongs to a single doctor at a time. (True per the Pakistan Medical & Dental Council registry.)"),
  bullet("Hospital staff users are pre-provisioned by the hospital's IT department; the system does not handle staff onboarding."),
  bullet("Network connectivity at the hospital is intermittent but not absent; a record may be queued for up to 72 hours offline."),
  bullet("AI verification is best-effort, not authoritative — every verdict can be overridden by a NADRA officer, and every override is recorded."),
];

// ---- 9. SQL HIGHLIGHTS -----------------------------------------------------
const sqlHighlights = [
  heading("9.  SQL Implementation Highlights", 1),
  para(t("Every SQL artefact below is reproduced verbatim in "), inlineCode("deliverables/sql/"), t(". Excerpts are shown here for illustration.")),
  heading("9.1  Table creation with constraints (excerpt)", 2),
  code(`create table public.birth_record (
  birth_record_id    uuid primary key default gen_random_uuid(),
  brn                text not null unique
                       check (brn ~ '^BRN-[0-9]{4}-[0-9]{8}$'),
  hospital_id        uuid not null
                       references public.hospital(hospital_id) on delete restrict,
  mother_id          uuid not null
                       references public.parent_guardian(guardian_id) on delete restrict,
  father_id          uuid
                       references public.parent_guardian(guardian_id) on delete restrict,
  attending_doctor   text not null,
  doctor_license_no  text not null
                       check (doctor_license_no ~ '^PMDC-[0-9]{6}$'),
  birth_datetime     timestamptz not null
                       check (birth_datetime <= now() + interval '1 day'),
  birth_weight_kg    numeric(4, 2) not null
                       check (birth_weight_kg between 0.30 and 7.00),
  status             record_status_t not null default 'PENDING',
  submitted_at       timestamptz not null default now(),
  ai_review_result   jsonb,
  constraint different_parents
    check (father_id is null or mother_id <> father_id)
);`),
  para(t("Every business rule from §2 has its echo here: format regex, range CHECK, foreign-key integrity, and a custom CHECK that the mother and father are different people.")),
  heading("9.2  Joins, aggregates, GROUP BY, HAVING", 2),
  para(t("From the curated query catalogue (Q2 — “hospitals with > 5 flagged records this year”):")),
  code(`select
  h.hospital_name,
  count(*) as flagged_this_year
from   public.hospital      h
join   public.birth_record  b on b.hospital_id = h.hospital_id
where  b.status = 'FLAGGED'
  and  b.submitted_at >= date_trunc('year', current_date)
group  by h.hospital_id, h.hospital_name
having count(*) > 5
order  by flagged_this_year desc;`),
  para(t("And Q3 — a four-way INNER JOIN producing the verified-births report (child × birth × mother × hospital):")),
  code(`select c.cnin, c.full_name, c.date_of_birth,
       m.full_name as mother_name, m.cnic as mother_cnic,
       h.hospital_name, h.district
from   public.child           c
join   public.birth_record    b on b.birth_record_id = c.birth_record_id
join   public.parent_guardian m on m.guardian_id     = b.mother_id
join   public.hospital        h on h.hospital_id     = b.hospital_id
where  b.status = 'VERIFIED'
order  by c.created_at desc
limit  50;`),
  para(t("The full nine-query catalogue is in "), inlineCode("deliverables/sql/05_meaningful_queries.sql"), t(" and includes ROLLUP, window functions (RANK), filtered aggregates, date-arithmetic CASE buckets, and string aggregation.")),
];

// ---- 10. TRIGGERS & TRANSACTIONS ------------------------------------------
const triggersTx = [
  heading("10.  Triggers & Transaction Management", 1),
  heading("10.1  Triggers (active business logic)", 2),
  para(t("Six trigger functions live in the database. Together they fire across twelve different triggers spanning four tables.")),
  buildTable([
    ["Trigger function", "Fires on", "Purpose"],
    ["fn_audit_trail",                  "INSERT/UPDATE/DELETE on 12 tables", "Inserts an audit_trail row capturing who/what/when"],
    ["fn_birth_record_state_machine",   "BEFORE UPDATE on birth_record",     "Validates the status transition is legal; raises if not"],
    ["fn_birth_record_log_status",      "AFTER UPDATE on birth_record",      "Inserts a verification_log row whenever status changed"],
    ["fn_birth_record_post_verification", "AFTER UPDATE on birth_record (WHEN status -> VERIFIED)", "Mints child + child_guardian + B-Form + notifications"],
    ["fn_bform_supersede",              "BEFORE INSERT on bform",            "Sets the previous current B-Form to is_current = false"],
    ["fn_set_updated_at",               "BEFORE UPDATE on every table that has updated_at", "Maintains updated_at for free"],
  ], [3000, 2400, 4260]),
  heading("10.2  Transaction management", 2),
  para(t("Three worked examples are shipped in "), inlineCode("deliverables/sql/05_meaningful_queries.sql"), t(":")),
  numbered("TX1 — successful officer verification: a single BEGIN/COMMIT containing the status update (which fires four post-verification triggers) plus a verification-log insert. If any trigger raises, the entire transaction rolls back."),
  numbered("TX2 — savepoint + rollback to savepoint: stages a provisional flag, attempts an illegal transition, catches the exception, rolls back only that statement, and continues with a legal alternative — all inside one outer transaction."),
  numbered("TX3 — full rollback: an INSERT followed by ROLLBACK; the row never reaches the database."),
  para(t("Together these three examples cover BEGIN, COMMIT, ROLLBACK, SAVEPOINT, and ROLLBACK TO SAVEPOINT — every transaction-management primitive the rubric calls for.")),
];

// ---- 11. SCREENSHOTS -------------------------------------------------------
const screenshots = [
  heading("11.  Screenshots", 1),
  para(t("The screenshots below are captured directly from the running application. The data shown is real seed data; the URLs are live.")),
  ...figure("01_landing.png", "Figure 11.1 — Landing page (anonymous visitor)."),
  ...figure("02_dev_query_feed.png", "Figure 11.2 — /dev — live PostgreSQL query feed via Supabase Realtime."),
  ...figure("03_dev_er_diagram.png", "Figure 11.3 — /dev/schema — live ER diagram from information_schema."),
  ...figure("04_dev_trigger_lab.png", "Figure 11.4 — /dev/triggers — interactive trigger lab. Buttons fire the eight business RPCs and the resulting trigger fan-out is visible in the audit_trail panel."),
  ...figure("05_login_page.png", "Figure 11.5 — Authentication page with role-aware demo accounts."),
  ...figure("06_hospital_dashboard.png", "Figure 11.6 — Hospital dashboard, RLS-scoped to Aga Khan University Hospital — only their records are visible."),
  ...figure("07_hospital_submissions.png", "Figure 11.7 — Hospital submissions list with status badges and pagination."),
  ...figure("08_hospital_submit_step1.png", "Figure 11.8 — Multi-step birth-record submission form."),
  ...figure("09_hospital_device_simulator.png", "Figure 11.9 — Device simulator — IndexedDB-backed offline queue with manual online/offline toggle."),
];

// ---- 12. CONCLUSION --------------------------------------------------------
const conclusion = [
  heading("12.  Conclusion", 1),
  para(t("NBRPTS demonstrates that every concept in CS2013 — entities, relationships, normalization, constraints, joins, aggregates, GROUP BY, HAVING, triggers, transactions — has a direct, working expression when applied to a real problem. The system is deployed live, the schema is in 3NF, and every query in the rubric runs against real data.")),
  para(t("The codebase is open and reproducible: clone the repository, run "), inlineCode("supabase db push"), t(", run "), inlineCode("pnpm dev"), t(", and the same screens shown in §11 will load in your browser, backed by your own copy of the database. Every line of SQL — every CREATE TABLE, every CHECK, every trigger — is exactly as it is documented in this report.")),
  heading("Live URLs", 2),
  bullet("Application:  https://nbrpts.vercel.app"),
  bullet("Source:       https://github.com/ruufaayl/nbrpts"),
  bullet("Demo accounts (password demo1234): aku@nbrpts.demo (hospital_staff), aisha@nbrpts.demo (nadra_officer), admin@nbrpts.demo (admin)."),
  heading("Tools used", 2),
  bullet("PostgreSQL 15 (via Supabase free tier, ap-southeast-1)."),
  bullet("Next.js 16 + React 19 (App Router, Server Components, Server Actions)."),
  bullet("Tailwind CSS v4, Framer Motion, react-flow + dagre."),
  bullet("Supabase Auth (email + password, JWT cookies, @supabase/ssr)."),
  bullet("Vercel free tier for hosting; GitHub for source control; pnpm for package management."),
];

// ---- DOCUMENT --------------------------------------------------------------
const doc = new Document({
  creator: "NBRPTS",
  title: "NBRPTS — Project Report",
  description: "CS2013 Spring 2026 — National Birth Registry & Population Tracking System",
  styles: {
    default: { document: { run: { font: ARIAL, size: 22 } } },
    paragraphStyles: [
      { id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: ARIAL, size: 36, bold: true, color: ACC },
        paragraph: { spacing: { before: 360, after: 120 }, outlineLevel: 0 } },
      { id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: ARIAL, size: 28, bold: true, color: FG },
        paragraph: { spacing: { before: 240, after: 120 }, outlineLevel: 1 } },
      { id: "Heading3", name: "Heading 3", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { font: ARIAL, size: 24, bold: true, color: FG },
        paragraph: { spacing: { before: 180, after: 80 }, outlineLevel: 2 } },
    ],
  },
  numbering: {
    config: [
      { reference: "bullets",
        levels: [{ level: 0, format: LevelFormat.BULLET, text: "•", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
      { reference: "numbers",
        levels: [{ level: 0, format: LevelFormat.DECIMAL, text: "%1.", alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 720, hanging: 360 } } } }] },
    ],
  },
  sections: [{
    properties: {
      page: {
        size: { width: 12240, height: 15840 },
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 },
      },
    },
    headers: {
      default: new Header({ children: [new Paragraph({
        alignment: AlignmentType.RIGHT,
        children: [new TextRun({ text: "NBRPTS · CS2013 · Spring 2026", font: ARIAL, size: 18, color: MUT })],
      })] }),
    },
    footers: {
      default: new Footer({ children: [new Paragraph({
        alignment: AlignmentType.CENTER,
        children: [
          new TextRun({ text: "Page ", font: ARIAL, size: 18, color: MUT }),
          new TextRun({ children: [PageNumber.CURRENT], font: ARIAL, size: 18, color: MUT }),
        ],
      })] }),
    },
    children: [
      ...cover,
      ...abstract,
      ...introduction,
      ...businessRules,
      ...entities,
      ...relationships,
      ...erd,
      ...norm,
      ...schema,
      ...decisions,
      ...sqlHighlights,
      ...triggersTx,
      ...screenshots,
      ...conclusion,
    ],
  }],
});

const buf = await Packer.toBuffer(doc);
writeFileSync(OUT, buf);
console.log(`wrote ${OUT}  (${(buf.length / 1024).toFixed(1)} kB)`);
