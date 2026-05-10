import Link from "next/link";
import { ArrowRight } from "lucide-react";
import { getSupabaseServer } from "@/lib/supabase/server";
import type { HospitalSubmission } from "@/lib/hospital/types";
import { StatusBadge } from "../_components/status-badge";

export const dynamic = "force-dynamic";

async function loadSubmissions(): Promise<HospitalSubmission[]> {
  const supabase = await getSupabaseServer();
  const { data, error } = await supabase.rpc("get_hospital_submissions", {
    p_limit: 200,
  });
  if (error) {
    console.error("[hospital/submissions]", error.message);
    return [];
  }
  return (data ?? []) as HospitalSubmission[];
}

export default async function SubmissionsPage() {
  const rows = await loadSubmissions();

  return (
    <main className="mx-auto max-w-7xl px-6 py-10">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-3xl font-medium tracking-tight md:text-4xl">
            Submissions
          </h1>
          <p className="mt-2 text-sm text-[var(--color-fg-muted)]">
            Every birth record this hospital has filed. Row-Level Security
            scopes you to your own facility automatically.
          </p>
        </div>
        <Link
          href="/hospital/submit"
          className="group inline-flex items-center gap-2 rounded-full bg-[var(--color-accent)] px-5 py-2.5 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90"
        >
          New record
          <ArrowRight className="size-4 transition group-hover:translate-x-0.5" />
        </Link>
      </div>

      <div className="mt-8 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
        {rows.length === 0 ? (
          <div className="px-6 py-16 text-center text-sm text-[var(--color-fg-muted)]">
            No submissions yet. <Link href="/hospital/submit" className="text-[var(--color-accent)]">File the first one.</Link>
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="border-b border-[var(--color-border)] bg-[var(--color-bg-elev)] font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
              <tr>
                <th className="px-4 py-2.5 text-left">BRN</th>
                <th className="px-4 py-2.5 text-left">Status</th>
                <th className="px-4 py-2.5 text-left">Mother</th>
                <th className="px-4 py-2.5 text-left">Child</th>
                <th className="px-4 py-2.5 text-left">CNIN</th>
                <th className="px-4 py-2.5 text-left">Born</th>
                <th className="px-4 py-2.5 text-left">Submitted</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--color-border)]/60">
              {rows.map((r) => (
                <tr key={r.birth_record_id} className="hover:bg-[var(--color-bg-elev)]">
                  <td className="px-4 py-2.5 font-mono text-xs text-[var(--color-fg)]">
                    {r.brn}
                  </td>
                  <td className="px-4 py-2.5">
                    <StatusBadge status={r.status} />
                  </td>
                  <td className="px-4 py-2.5">
                    <div className="text-[var(--color-fg)]">{r.mother_name}</div>
                    <div className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                      {r.mother_cnic}
                    </div>
                  </td>
                  <td className="px-4 py-2.5 text-[var(--color-fg-muted)]">
                    {r.child_full_name ?? "(unnamed)"}{" "}
                    <span className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                      {r.child_gender} · {r.birth_weight_kg} kg
                    </span>
                  </td>
                  <td className="px-4 py-2.5 font-mono text-[10px] text-[var(--color-accent)]">
                    {r.cnin ?? "—"}
                  </td>
                  <td className="px-4 py-2.5 font-mono text-xs text-[var(--color-fg-muted)]">
                    {new Date(r.birth_datetime).toLocaleString()}
                  </td>
                  <td className="px-4 py-2.5 font-mono text-xs text-[var(--color-fg-subtle)]">
                    {new Date(r.submitted_at).toLocaleString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </main>
  );
}
