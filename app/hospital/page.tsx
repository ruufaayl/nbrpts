import Link from "next/link";
import { ArrowRight, Baby, FileCheck2, Clock, AlertTriangle, CheckCircle2 } from "lucide-react";
import { getSupabaseServer } from "@/lib/supabase/server";
import type { HospitalDashboard } from "@/lib/hospital/types";
import { StatusBadge } from "./_components/status-badge";

export const dynamic = "force-dynamic";

async function loadDashboard(): Promise<HospitalDashboard | null> {
  const supabase = await getSupabaseServer();
  const { data, error } = await supabase.rpc("get_hospital_dashboard_data");
  if (error) {
    console.error("[hospital] dashboard:", error.message);
    return null;
  }
  return data as HospitalDashboard;
}

export default async function HospitalDashboardPage() {
  const data = await loadDashboard();
  if (!data || data.error) {
    return (
      <main className="mx-auto max-w-7xl px-6 py-12">
        <p className="text-sm text-[var(--color-fg-muted)]">
          {data?.error ?? "Could not load dashboard."}
        </p>
      </main>
    );
  }

  const counts = data.records_by_status;
  const total =
    (counts.PENDING ?? 0) +
    (counts.FLAGGED ?? 0) +
    (counts.VERIFIED ?? 0) +
    (counts.REJECTED ?? 0) +
    (counts.AMENDED ?? 0);

  return (
    <main className="mx-auto max-w-7xl px-6 py-10">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-3xl font-medium tracking-tight md:text-4xl">
            {data.hospital.hospital_name}
          </h1>
          <p className="mt-2 text-sm text-[var(--color-fg-muted)]">
            <code className="font-mono">{data.hospital.hrn}</code> ·{" "}
            {data.hospital.district}, {data.hospital.province} ·{" "}
            <span className="text-[var(--color-fg-subtle)]">
              {total} record{total === 1 ? "" : "s"} on file
            </span>
          </p>
        </div>
        <Link
          href="/hospital/submit"
          className="group inline-flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-5 py-2.5 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90"
        >
          Submit a new birth record
          <ArrowRight className="size-4 transition group-hover:translate-x-0.5" />
        </Link>
      </div>

      <div className="mt-8 grid gap-3 md:grid-cols-2 lg:grid-cols-5">
        <StatTile
          icon={<Clock className="size-4" />}
          label="Pending"
          value={counts.PENDING ?? 0}
          tone="default"
        />
        <StatTile
          icon={<AlertTriangle className="size-4" />}
          label="Flagged"
          value={counts.FLAGGED ?? 0}
          tone="warn"
        />
        <StatTile
          icon={<CheckCircle2 className="size-4" />}
          label="Verified"
          value={counts.VERIFIED ?? 0}
          tone="accent"
        />
        <StatTile
          icon={<Baby className="size-4" />}
          label="Children registered"
          value={data.children_registered}
          tone="default"
        />
        <StatTile
          icon={<FileCheck2 className="size-4" />}
          label="B-Forms ready"
          value={data.bforms_ready}
          tone="default"
        />
      </div>

      <div className="mt-12">
        <div className="flex items-center justify-between">
          <h2 className="text-sm font-medium uppercase tracking-widest text-[var(--color-fg-muted)]">
            Recent submissions
          </h2>
          <Link
            href="/hospital/submissions"
            className="text-xs text-[var(--color-fg-muted)] transition hover:text-[var(--color-fg)]"
          >
            View all →
          </Link>
        </div>

        <div className="mt-4 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
          {data.recent_submissions.length === 0 ? (
            <div className="px-6 py-12 text-center text-sm text-[var(--color-fg-muted)]">
              No submissions yet — start with the form above.
            </div>
          ) : (
            <table className="w-full text-sm">
              <thead className="border-b border-[var(--color-border)] bg-[var(--color-bg-elev)] font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
                <tr>
                  <th className="px-4 py-2.5 text-left">BRN</th>
                  <th className="px-4 py-2.5 text-left">Mother</th>
                  <th className="px-4 py-2.5 text-left">Child</th>
                  <th className="px-4 py-2.5 text-left">Status</th>
                  <th className="px-4 py-2.5 text-left">Submitted</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--color-border)]/60">
                {data.recent_submissions.map((s) => (
                  <tr key={s.birth_record_id} className="hover:bg-[var(--color-bg-elev)]">
                    <td className="px-4 py-2.5 font-mono text-xs text-[var(--color-fg)]">
                      {s.brn}
                    </td>
                    <td className="px-4 py-2.5 text-[var(--color-fg)]">{s.mother_name}</td>
                    <td className="px-4 py-2.5 text-[var(--color-fg-muted)]">
                      {s.child_name ?? "—"}
                    </td>
                    <td className="px-4 py-2.5">
                      <StatusBadge status={s.status} />
                    </td>
                    <td className="px-4 py-2.5 font-mono text-xs text-[var(--color-fg-subtle)]">
                      {new Date(s.submitted_at).toLocaleString()}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </div>
    </main>
  );
}

function StatTile({
  icon,
  label,
  value,
  tone,
}: {
  icon: React.ReactNode;
  label: string;
  value: number;
  tone: "default" | "warn" | "accent";
}) {
  const colorClass =
    tone === "accent"
      ? "text-[var(--color-accent)]"
      : tone === "warn"
        ? "text-[var(--color-warn)]"
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
