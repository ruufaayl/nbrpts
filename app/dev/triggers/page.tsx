import { getSupabaseServer } from "@/lib/supabase/server";
import type {
  AuditEntry,
  CurrentBformOption,
  PendingBformOption,
  PendingBirthOption,
  PipelineSummary,
} from "@/lib/domain/types";
import { DevNav } from "../_components/nav";
import { TriggerLab } from "./trigger-lab";

export const dynamic = "force-dynamic";

type LabData = {
  pending_records: PendingBirthOption[];
  pending_bforms: PendingBformOption[];
  current_bforms: CurrentBformOption[];
  recent_audit: AuditEntry[];
  officers: { officer_id: string; full_name: string; employee_no: string }[];
  generated_at: string;
};

async function loadAll() {
  const supabase = await getSupabaseServer();
  const [summaryRes, labRes] = await Promise.all([
    supabase.rpc("get_pipeline_summary"),
    supabase.rpc("get_trigger_lab_data"),
  ]);

  const summary = (summaryRes.data ?? null) as PipelineSummary | null;
  const lab = (labRes.data ?? null) as LabData | null;

  return {
    summary,
    pending: lab?.pending_records ?? [],
    pendingBforms: lab?.pending_bforms ?? [],
    currentBforms: lab?.current_bforms ?? [],
    audit: lab?.recent_audit ?? [],
    officers: lab?.officers ?? [],
  };
}

export default async function TriggersLabPage() {
  const data = await loadAll();

  return (
    <main className="min-h-screen">
      <DevNav active="/dev/triggers" />
      <div className="mx-auto max-w-6xl px-6 py-12">
        <div className="max-w-2xl">
          <h1 className="text-3xl font-medium tracking-tight md:text-4xl">
            Trigger lab
          </h1>
          <p className="mt-2 text-sm leading-relaxed text-[var(--color-fg-muted)]">
            Every action below is a single{" "}
            <code className="font-mono text-[var(--color-fg)]">supabase.rpc()</code>{" "}
            call. Watch the pipeline summary update and the audit trail grow as
            the Postgres state-machine validator, audit trigger, status logger,
            and post-verification cascade all fire from one UPDATE.
          </p>
        </div>

        <PipelineSummaryStrip summary={data.summary} />
        <TriggerLab data={data} />
        <RecentActivity entries={data.audit} />
      </div>
    </main>
  );
}

function PipelineSummaryStrip({ summary }: { summary: PipelineSummary | null }) {
  if (!summary) {
    return (
      <div className="mt-8 rounded-xl border border-[var(--color-danger)]/40 bg-[var(--color-danger)]/10 p-4 text-sm">
        Could not load pipeline summary. Check that{" "}
        <code className="font-mono">get_pipeline_summary()</code> is granted to{" "}
        <code className="font-mono">anon</code>.
      </div>
    );
  }

  const stats: { label: string; value: number | string; tone?: "accent" | "warn" }[] =
    [
      { label: "PENDING",   value: summary.records_by_status.PENDING ?? 0 },
      { label: "FLAGGED",   value: summary.records_by_status.FLAGGED ?? 0, tone: "warn" },
      { label: "VERIFIED",  value: summary.records_by_status.VERIFIED ?? 0, tone: "accent" },
      { label: "Children",  value: summary.children },
      { label: "B-Forms",   value: `${summary.bforms_authorized}/${summary.bforms_total}` },
      { label: "SMS queued",value: summary.notifications_queued, tone: "warn" },
      { label: "SMS sent",  value: summary.notifications_sent },
      { label: "Audit rows",value: summary.audit_entries },
    ];

  return (
    <div className="mt-8 grid grid-cols-2 gap-px overflow-hidden rounded-xl border border-[var(--color-border)] bg-[var(--color-border)] sm:grid-cols-4 lg:grid-cols-8">
      {stats.map((s) => (
        <div key={s.label} className="bg-[var(--color-bg-card)] px-4 py-3">
          <div className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
            {s.label}
          </div>
          <div
            className={
              "mt-1 font-mono text-2xl " +
              (s.tone === "accent"
                ? "text-[var(--color-accent)]"
                : s.tone === "warn"
                  ? "text-[var(--color-warn)]"
                  : "text-[var(--color-fg)]")
            }
          >
            {s.value}
          </div>
        </div>
      ))}
    </div>
  );
}

function RecentActivity({ entries }: { entries: AuditEntry[] }) {
  return (
    <div className="mt-12">
      <h2 className="text-sm font-medium uppercase tracking-widest text-[var(--color-fg-muted)]">
        Recent audit trail
      </h2>
      <p className="mt-1 text-xs text-[var(--color-fg-subtle)]">
        Every row is written by{" "}
        <code className="font-mono">fn_audit_trail()</code>, fired as an{" "}
        <code className="font-mono">AFTER INSERT/UPDATE/DELETE</code> trigger on
        12 tables. The actor is read from session-local config that the RPCs set.
      </p>
      <div className="mt-4 overflow-hidden rounded-xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
        <table className="w-full font-mono text-xs">
          <thead className="border-b border-[var(--color-border)] bg-[var(--color-bg-elev)] text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
            <tr>
              <th className="px-3 py-2 text-left">when</th>
              <th className="px-3 py-2 text-left">actor</th>
              <th className="px-3 py-2 text-left">op</th>
              <th className="px-3 py-2 text-left">table</th>
              <th className="px-3 py-2 text-left">description</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--color-border)]/60">
            {entries.length === 0 && (
              <tr>
                <td colSpan={5} className="px-3 py-6 text-center text-[var(--color-fg-muted)]">
                  No audit rows yet.
                </td>
              </tr>
            )}
            {entries.map((e) => (
              <tr key={e.audit_id} className="hover:bg-[var(--color-bg-elev)]">
                <td className="whitespace-nowrap px-3 py-1.5 text-[var(--color-fg-muted)]">
                  {new Date(e.action_datetime).toLocaleTimeString()}
                </td>
                <td className="px-3 py-1.5 text-[var(--color-accent)]">
                  {e.actor_type}
                </td>
                <td className="px-3 py-1.5 text-[var(--color-fg)]">
                  {e.action_type}
                </td>
                <td className="px-3 py-1.5 text-[var(--color-fg)]">
                  {e.table_affected}
                </td>
                <td className="px-3 py-1.5 text-[var(--color-fg-muted)]">
                  {e.description ?? "—"}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
