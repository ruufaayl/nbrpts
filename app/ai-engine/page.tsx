import Link from "next/link";
import { Cpu, AlertTriangle, CheckCircle2, XCircle, Activity, Brain } from "lucide-react";
import { getSupabaseServer } from "@/lib/supabase/server";
import type { AiEngineData } from "@/lib/ai/types";
import { VerdictPill } from "./verdict-pill";
import { EngineControls } from "./engine-controls";

export const dynamic = "force-dynamic";

async function loadData(): Promise<AiEngineData | null> {
  const supabase = await getSupabaseServer();
  const { data, error } = await supabase.rpc("get_ai_engine_data");
  if (error) {
    console.error("[ai-engine]", error.message);
    return null;
  }
  return data as AiEngineData;
}

function formatAge(submittedAt: string): string {
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(submittedAt).getTime()) / 1000));
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
  return `${Math.floor(seconds / 86400)}d`;
}

export default async function AiEnginePage() {
  const data = await loadData();
  if (!data) {
    return (
      <main className="mx-auto max-w-7xl px-6 py-12">
        <p className="text-sm text-[var(--color-fg-muted)]">Could not load AI Engine data.</p>
      </main>
    );
  }

  const c = data.counts;
  const v = data.verdict_breakdown;
  const a = data.avg_confidence;
  const nextBrn = data.next_pending[0]?.brn ?? null;

  return (
    <main className="mx-auto max-w-7xl px-6 py-10">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <div className="flex items-center gap-3">
            <div className="flex size-10 items-center justify-center rounded-xl bg-[var(--color-accent)]/15 text-[var(--color-accent)]">
              <Brain className="size-5" />
            </div>
            <h1 className="text-3xl font-medium tracking-tight md:text-4xl">AI Engine</h1>
          </div>
          <p className="mt-2 max-w-2xl text-sm text-[var(--color-fg-muted)]">
            A deterministic rules engine — eight signals across mother age, birth weight,
            CNIC presence, duplicate detection, and outcome — scores every PENDING record,
            writes to <code className="font-mono">ai_review_log</code>, and transitions
            the state machine. PASS at confidence ≥ 0.85 auto-verifies. FLAG queues for
            human review. REJECT auto-rejects with reasons.
          </p>
        </div>
        <Link
          href="/dev"
          className="text-xs text-[var(--color-fg-muted)] transition hover:text-[var(--color-fg)]"
        >
          ← Database observatory
        </Link>
      </div>

      <div className="mt-8 grid gap-3 md:grid-cols-2 lg:grid-cols-5">
        <Tile icon={<Cpu className="size-4" />}            label="Pending"        value={c.pending_to_process} />
        <Tile icon={<AlertTriangle className="size-4" />} label="Flagged"        value={c.flagged_records}    tone="warn" />
        <Tile icon={<Activity className="size-4" />}      label="Reviews today"  value={c.reviews_today}      tone="accent" />
        <Tile icon={<CheckCircle2 className="size-4" />}  label="Reviews total"  value={c.reviews_total} />
        <Tile icon={<XCircle className="size-4" />}       label="Human overrides" value={c.overrides} />
      </div>

      <div className="mt-6 grid gap-6 lg:grid-cols-3">
        <div className="lg:col-span-1">
          <EngineControls nextBrn={nextBrn} pendingCount={c.pending_to_process} />
        </div>
        <div className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)] p-5 lg:col-span-2">
          <h2 className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
            Verdict breakdown
          </h2>
          <div className="mt-3 grid grid-cols-3 gap-3 text-sm">
            {(["PASS", "FLAG", "REJECT"] as const).map((k) => (
              <div key={k} className="rounded-lg border border-[var(--color-border)]/60 bg-[var(--color-bg)] p-3">
                <div className="flex items-center justify-between">
                  <VerdictPill verdict={k} />
                  <span className="font-mono text-2xl text-[var(--color-fg)]">{v[k] ?? 0}</span>
                </div>
                <div className="mt-2 font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
                  avg confidence
                </div>
                <div className="mt-1 font-mono text-sm text-[var(--color-fg-muted)]">
                  {a[k] ? Number(a[k]).toFixed(3) : "—"}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="mt-12 grid gap-8 lg:grid-cols-2">
        <section>
          <h2 className="text-sm font-medium uppercase tracking-widest text-[var(--color-fg-muted)]">
            Next in queue
          </h2>
          <div className="mt-3 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
            {data.next_pending.length === 0 ? (
              <div className="px-6 py-12 text-center text-sm text-[var(--color-fg-muted)]">
                Queue is empty — nothing to process.
              </div>
            ) : (
              <ul className="divide-y divide-[var(--color-border)]/60">
                {data.next_pending.map((p) => (
                  <li key={p.birth_record_id} className="px-4 py-3">
                    <div className="flex items-center justify-between">
                      <code className="font-mono text-xs text-[var(--color-fg)]">{p.brn}</code>
                      <span className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                        {formatAge(p.submitted_at)} ago
                      </span>
                    </div>
                    <div className="mt-1 flex items-center justify-between text-xs">
                      <span className="text-[var(--color-fg-muted)]">{p.mother_name}</span>
                      <span className="text-[var(--color-fg-subtle)]">
                        {p.hospital_name} · {p.birth_weight_kg}kg · {p.delivery_type}
                      </span>
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </section>

        <section>
          <h2 className="text-sm font-medium uppercase tracking-widest text-[var(--color-fg-muted)]">
            Recent reviews
          </h2>
          <div className="mt-3 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
            {data.recent_reviews.length === 0 ? (
              <div className="px-6 py-12 text-center text-sm text-[var(--color-fg-muted)]">
                No reviews yet. Run the engine to populate this feed.
              </div>
            ) : (
              <ul className="divide-y divide-[var(--color-border)]/60">
                {data.recent_reviews.slice(0, 12).map((r) => {
                  const flagCount = Array.isArray(r.flags_raised) ? r.flags_raised.length : 0;
                  return (
                    <li key={r.review_id} className="px-4 py-3">
                      <div className="flex items-center justify-between gap-2">
                        <div className="flex items-center gap-2">
                          <VerdictPill verdict={r.verdict} />
                          <code className="font-mono text-xs text-[var(--color-fg)]">{r.brn}</code>
                          <span className="font-mono text-[10px] text-[var(--color-fg-muted)]">
                            {r.confidence_score ? Number(r.confidence_score).toFixed(3) : "—"}
                          </span>
                          {r.human_override ? (
                            <span className="rounded bg-[var(--color-fg)]/10 px-1.5 py-0.5 font-mono text-[10px] uppercase text-[var(--color-fg-muted)]">
                              override
                            </span>
                          ) : null}
                        </div>
                        <span className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                          {new Date(r.reviewed_at).toLocaleTimeString()}
                        </span>
                      </div>
                      <div className="mt-1 flex items-center justify-between text-xs">
                        <span className="text-[var(--color-fg-muted)]">
                          {r.mother_name} · {r.hospital_name}
                        </span>
                        {flagCount > 0 ? (
                          <span className="rounded bg-[var(--color-warn)]/10 px-1.5 py-0.5 font-mono text-[10px] uppercase text-[var(--color-warn)]">
                            {flagCount} flag{flagCount === 1 ? "" : "s"}
                          </span>
                        ) : null}
                      </div>
                      {flagCount > 0 && Array.isArray(r.flags_raised) ? (
                        <ul className="mt-1 space-y-0.5 text-[11px] text-[var(--color-fg-muted)]">
                          {r.flags_raised.slice(0, 3).map((f, i) => (
                            <li key={i} className="flex items-center gap-1.5">
                              <span className={
                                "inline-block size-1.5 rounded-full " +
                                (f.severity === "reject"
                                  ? "bg-[var(--color-danger)]"
                                  : "bg-[var(--color-warn)]")
                              } />
                              <code className="font-mono text-[10px] text-[var(--color-fg-subtle)]">{f.code}</code>
                              <span className="truncate">{f.detail}</span>
                            </li>
                          ))}
                          {r.flags_raised.length > 3 ? (
                            <li className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                              + {r.flags_raised.length - 3} more
                            </li>
                          ) : null}
                        </ul>
                      ) : null}
                    </li>
                  );
                })}
              </ul>
            )}
          </div>
        </section>
      </div>
    </main>
  );
}

function Tile({
  icon, label, value, tone,
}: {
  icon: React.ReactNode;
  label: string;
  value: number;
  tone?: "warn" | "accent";
}) {
  const colorClass =
    tone === "accent" ? "text-[var(--color-accent)]"
    : tone === "warn" ? "text-[var(--color-warn)]"
    : "text-[var(--color-fg)]";
  return (
    <div className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)] p-4">
      <div className="flex items-center gap-2 font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
        <span className="text-[var(--color-fg-muted)]">{icon}</span>
        {label}
      </div>
      <div className={"mt-2 font-mono text-3xl " + colorClass}>{value}</div>
    </div>
  );
}
