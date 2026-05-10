import Link from "next/link";
import { ArrowRight, Clock, AlertTriangle, CheckCircle2, FileCheck2, Activity } from "lucide-react";
import { getSupabaseServer } from "@/lib/supabase/server";
import type { OfficerDashboard } from "@/lib/officer/types";
import { StatusBadge } from "./_components/status-badge";

export const dynamic = "force-dynamic";

async function loadDashboard(): Promise<OfficerDashboard | null> {
  const supabase = await getSupabaseServer();
  const { data, error } = await supabase.rpc("get_officer_dashboard_data");
  if (error) {
    console.error("[officer] dashboard:", error.message);
    return null;
  }
  return data as OfficerDashboard;
}

function formatAge(seconds: number) {
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
  return `${Math.floor(seconds / 86400)}d`;
}

export default async function OfficerDashboardPage() {
  const data = await loadDashboard();
  if (!data) {
    return (
      <main className="mx-auto max-w-7xl px-6 py-12">
        <p className="text-sm text-[var(--color-fg-muted)]">Could not load dashboard.</p>
      </main>
    );
  }

  const c = data.counts;

  return (
    <main className="mx-auto max-w-7xl px-6 py-10">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-3xl font-medium tracking-tight md:text-4xl">
            Welcome, {data.officer.full_name.split(" ")[0]}
          </h1>
          <p className="mt-2 text-sm text-[var(--color-fg-muted)]">
            <code className="font-mono">{data.officer.employee_no}</code> ·{" "}
            {data.officer.designation} · {data.officer.office_name}, {data.officer.city}
          </p>
        </div>
        <Link
          href="/officer/queue"
          className="group inline-flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-5 py-2.5 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90"
        >
          Open queue
          <ArrowRight className="size-4 transition group-hover:translate-x-0.5" />
        </Link>
      </div>

      <div className="mt-8 grid gap-3 md:grid-cols-2 lg:grid-cols-5">
        <StatTile icon={<Clock className="size-4" />}         label="Pending"          value={c.pending}             tone="default" />
        <StatTile icon={<AlertTriangle className="size-4" />} label="Flagged"          value={c.flagged}             tone="warn" />
        <StatTile icon={<CheckCircle2 className="size-4" />}  label="My actions today" value={c.my_actions_today}    tone="accent" />
        <StatTile icon={<FileCheck2 className="size-4" />}    label="B-Forms to auth"  value={c.bforms_to_authorize} tone="default" />
        <StatTile icon={<Activity className="size-4" />}      label="Children total"   value={c.children_total}      tone="default" />
      </div>

      <div className="mt-12 grid gap-8 lg:grid-cols-2">
        <section>
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-medium uppercase tracking-widest text-[var(--color-fg-muted)]">
              Oldest pending / flagged
            </h2>
            <Link
              href="/officer/queue"
              className="text-xs text-[var(--color-fg-muted)] transition hover:text-[var(--color-fg)]"
            >
              View all →
            </Link>
          </div>
          <div className="mt-4 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
            {data.oldest_pending.length === 0 ? (
              <div className="px-6 py-12 text-center text-sm text-[var(--color-fg-muted)]">
                Inbox zero. Nothing waiting.
              </div>
            ) : (
              <ul className="divide-y divide-[var(--color-border)]/60">
                {data.oldest_pending.map((row) => (
                  <li key={row.birth_record_id}>
                    <Link
                      href={`/officer/record/${encodeURIComponent(row.brn)}`}
                      className="flex items-center justify-between gap-4 px-4 py-3 transition hover:bg-[var(--color-bg-elev)]"
                    >
                      <div className="min-w-0">
                        <div className="flex items-center gap-2">
                          <code className="font-mono text-xs text-[var(--color-fg)]">{row.brn}</code>
                          <StatusBadge status={row.status} />
                        </div>
                        <div className="mt-0.5 truncate text-xs text-[var(--color-fg-muted)]">
                          {row.mother_name} · {row.hospital_name}, {row.district}
                        </div>
                      </div>
                      <span className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                        {formatAge(row.age_seconds)} ago
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </section>

        <section>
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-medium uppercase tracking-widest text-[var(--color-fg-muted)]">
              My recent actions
            </h2>
          </div>
          <div className="mt-4 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
            {data.recent_actions.length === 0 ? (
              <div className="px-6 py-12 text-center text-sm text-[var(--color-fg-muted)]">
                No actions yet today.
              </div>
            ) : (
              <ul className="divide-y divide-[var(--color-border)]/60">
                {data.recent_actions.map((a) => (
                  <li key={a.log_id} className="px-4 py-3">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <span className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
                          {a.action}
                        </span>
                        <StatusBadge status={a.previous_status} />
                        <span className="font-mono text-[10px] text-[var(--color-fg-subtle)]">→</span>
                        <StatusBadge status={a.new_status} />
                      </div>
                      <span className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                        {new Date(a.action_datetime).toLocaleTimeString()}
                      </span>
                    </div>
                    <Link
                      href={`/officer/record/${encodeURIComponent(a.brn)}`}
                      className="mt-1 block truncate text-xs text-[var(--color-fg-muted)] transition hover:text-[var(--color-fg)]"
                    >
                      <code className="font-mono text-[var(--color-fg)]">{a.brn}</code>
                      <span className="ml-2">{a.hospital_name}</span>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </section>
      </div>
    </main>
  );
}

function StatTile({
  icon, label, value, tone,
}: {
  icon: React.ReactNode;
  label: string;
  value: number;
  tone: "default" | "warn" | "accent";
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
