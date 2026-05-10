import Link from "next/link";
import { ArrowRight, Clock, AlertTriangle } from "lucide-react";
import { getSupabaseServer } from "@/lib/supabase/server";
import type { OfficerQueue } from "@/lib/officer/types";
import { StatusBadge } from "../_components/status-badge";

export const dynamic = "force-dynamic";

async function loadQueue(status: "all" | "pending" | "flagged"): Promise<OfficerQueue | null> {
  const supabase = await getSupabaseServer();
  const { data, error } = await supabase.rpc("get_officer_queue", {
    p_status: status, p_limit: 100, p_offset: 0,
  });
  if (error) {
    console.error("[officer] queue:", error.message);
    return null;
  }
  return data as OfficerQueue;
}

function formatAge(seconds: number) {
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
  return `${Math.floor(seconds / 86400)}d`;
}

export default async function OfficerQueuePage({
  searchParams,
}: {
  searchParams: Promise<{ status?: string }>;
}) {
  const sp = await searchParams;
  const filter: "all" | "pending" | "flagged" =
    sp.status === "pending" ? "pending"
    : sp.status === "flagged" ? "flagged"
    : "all";

  const data = await loadQueue(filter);

  return (
    <main className="mx-auto max-w-7xl px-6 py-10">
      <div className="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 className="text-3xl font-medium tracking-tight md:text-4xl">Review queue</h1>
          <p className="mt-2 text-sm text-[var(--color-fg-muted)]">
            Records awaiting officer action. Flagged records are surfaced first.
          </p>
        </div>
        <div className="flex items-center gap-1 rounded-full border border-[var(--color-border)] bg-[var(--color-bg-elev)] p-1 font-mono text-xs">
          {(["all", "pending", "flagged"] as const).map((s) => {
            const active = s === filter;
            return (
              <Link
                key={s}
                href={s === "all" ? "/officer/queue" : `/officer/queue?status=${s}`}
                className={
                  "inline-flex items-center gap-1 rounded-full px-3 py-1.5 transition " +
                  (active
                    ? "bg-[var(--color-bg)] text-[var(--color-fg)]"
                    : "text-[var(--color-fg-muted)] hover:text-[var(--color-fg)]")
                }
              >
                {s === "pending" && <Clock className="size-3.5" />}
                {s === "flagged" && <AlertTriangle className="size-3.5" />}
                {s.toUpperCase()}
              </Link>
            );
          })}
        </div>
      </div>

      <div className="mt-8 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
        {!data || data.rows.length === 0 ? (
          <div className="px-6 py-16 text-center text-sm text-[var(--color-fg-muted)]">
            Queue is empty for filter <code className="font-mono">{filter}</code>.
          </div>
        ) : (
          <table className="w-full text-sm">
            <thead className="border-b border-[var(--color-border)] bg-[var(--color-bg-elev)] font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
              <tr>
                <th className="px-4 py-2.5 text-left">BRN</th>
                <th className="px-4 py-2.5 text-left">Status</th>
                <th className="px-4 py-2.5 text-left">Mother</th>
                <th className="px-4 py-2.5 text-left">Hospital</th>
                <th className="px-4 py-2.5 text-left">AI</th>
                <th className="px-4 py-2.5 text-left">Age</th>
                <th className="px-4 py-2.5 text-right">Action</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--color-border)]/60">
              {data.rows.map((r) => (
                <tr key={r.birth_record_id} className="hover:bg-[var(--color-bg-elev)]">
                  <td className="px-4 py-2.5 font-mono text-xs text-[var(--color-fg)]">{r.brn}</td>
                  <td className="px-4 py-2.5"><StatusBadge status={r.status} /></td>
                  <td className="px-4 py-2.5">
                    <div className="text-[var(--color-fg)]">{r.mother_name}</div>
                    <div className="font-mono text-[10px] text-[var(--color-fg-subtle)]">{r.mother_cnic ?? "—"}</div>
                  </td>
                  <td className="px-4 py-2.5">
                    <div className="text-[var(--color-fg)]">{r.hospital_name}</div>
                    <div className="text-[10px] text-[var(--color-fg-subtle)]">{r.district}, {r.province}</div>
                  </td>
                  <td className="px-4 py-2.5">
                    {r.latest_ai_review ? (
                      <div className="flex items-center gap-2">
                        <span
                          className={
                            "rounded px-1.5 py-0.5 font-mono text-[10px] uppercase " +
                            (r.latest_ai_review.verdict === "PASS"
                              ? "bg-[var(--color-accent)]/15 text-[var(--color-accent)]"
                              : r.latest_ai_review.verdict === "FLAG"
                                ? "bg-[var(--color-warn)]/15 text-[var(--color-warn)]"
                                : "bg-[var(--color-danger)]/15 text-[var(--color-danger)]")
                          }
                        >
                          {r.latest_ai_review.verdict}
                        </span>
                        <span className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                          {r.latest_ai_review.confidence_score
                            ? Number(r.latest_ai_review.confidence_score).toFixed(2)
                            : "—"}
                        </span>
                      </div>
                    ) : (
                      <span className="text-[10px] text-[var(--color-fg-subtle)]">—</span>
                    )}
                  </td>
                  <td className="px-4 py-2.5 font-mono text-xs text-[var(--color-fg-muted)]">
                    {formatAge(r.age_seconds)}
                  </td>
                  <td className="px-4 py-2.5 text-right">
                    <Link
                      href={`/officer/record/${encodeURIComponent(r.brn)}`}
                      className="inline-flex items-center gap-1 rounded-full border border-[var(--color-border)] px-3 py-1 text-xs text-[var(--color-fg-muted)] transition hover:border-[var(--color-border-strong)] hover:text-[var(--color-fg)]"
                    >
                      Review
                      <ArrowRight className="size-3" />
                    </Link>
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
