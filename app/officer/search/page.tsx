import Link from "next/link";
import { Search } from "lucide-react";
import { getSupabaseServer } from "@/lib/supabase/server";
import type { SearchResult } from "@/lib/officer/types";
import { StatusBadge } from "../_components/status-badge";

export const dynamic = "force-dynamic";

async function runSearch(q: string): Promise<SearchResult | null> {
  if (q.length < 2) return null;
  const supabase = await getSupabaseServer();
  const { data, error } = await supabase.rpc("search_records", { p_query: q, p_limit: 50 });
  if (error) {
    console.error("[officer/search]", error.message);
    return null;
  }
  return data as SearchResult;
}

export default async function OfficerSearchPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const sp = await searchParams;
  const q = (sp.q ?? "").trim();
  const result = q ? await runSearch(q) : null;

  return (
    <main className="mx-auto max-w-5xl px-6 py-10">
      <div>
        <h1 className="text-3xl font-medium tracking-tight md:text-4xl">Search</h1>
        <p className="mt-2 text-sm text-[var(--color-fg-muted)]">
          Find a record by CNIN, BRN, mother CNIC, mother name, or child name.
        </p>
      </div>

      <form action="/officer/search" method="get" className="mt-6 flex items-center gap-2">
        <div className="relative flex-1">
          <Search className="pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-[var(--color-fg-muted)]" />
          <input
            name="q"
            defaultValue={q}
            placeholder="e.g. CNIN-0000000003 or 42101-1234567-8 or Ayesha"
            className="w-full rounded-full border border-[var(--color-border)] bg-[var(--color-bg-card)] py-2.5 pl-10 pr-4 text-sm focus:border-[var(--color-accent)] focus:outline-none"
            autoFocus
          />
        </div>
        <button
          type="submit"
          className="rounded-full bg-[var(--color-accent)] px-5 py-2.5 text-sm font-medium text-[var(--color-accent-fg)] transition hover:opacity-90"
        >
          Search
        </button>
      </form>

      {!q ? (
        <p className="mt-12 text-center text-sm text-[var(--color-fg-subtle)]">
          Type a query above to begin.
        </p>
      ) : !result ? (
        <p className="mt-12 text-center text-sm text-[var(--color-fg-muted)]">
          Search failed. Try a longer query.
        </p>
      ) : result.rows.length === 0 ? (
        <p className="mt-12 text-center text-sm text-[var(--color-fg-muted)]">
          No matches for <code className="font-mono">{result.query}</code>.
        </p>
      ) : (
        <div className="mt-8 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
          <table className="w-full text-sm">
            <thead className="border-b border-[var(--color-border)] bg-[var(--color-bg-elev)] font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
              <tr>
                <th className="px-4 py-2.5 text-left">Match</th>
                <th className="px-4 py-2.5 text-left">BRN / CNIN</th>
                <th className="px-4 py-2.5 text-left">Mother</th>
                <th className="px-4 py-2.5 text-left">Child</th>
                <th className="px-4 py-2.5 text-left">Hospital</th>
                <th className="px-4 py-2.5 text-left">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--color-border)]/60">
              {result.rows.map((r) => (
                <tr key={r.birth_record_id} className="hover:bg-[var(--color-bg-elev)]">
                  <td className="px-4 py-2.5">
                    <span className="rounded bg-[var(--color-accent)]/10 px-1.5 py-0.5 font-mono text-[10px] uppercase text-[var(--color-accent)]">
                      {r.match_field}
                    </span>
                  </td>
                  <td className="px-4 py-2.5 font-mono text-xs">
                    <Link
                      href={`/officer/record/${encodeURIComponent(r.brn)}`}
                      className="text-[var(--color-fg)] transition hover:text-[var(--color-accent)]"
                    >
                      {r.brn}
                    </Link>
                    {r.cnin ? (
                      <div className="text-[10px] text-[var(--color-accent)]">{r.cnin}</div>
                    ) : null}
                  </td>
                  <td className="px-4 py-2.5">
                    <div className="text-[var(--color-fg)]">{r.mother_name}</div>
                    <div className="font-mono text-[10px] text-[var(--color-fg-subtle)]">{r.mother_cnic ?? "—"}</div>
                  </td>
                  <td className="px-4 py-2.5 text-[var(--color-fg-muted)]">
                    {r.child_full_name ?? "—"}{" "}
                    <span className="text-[10px] text-[var(--color-fg-subtle)]">{r.child_gender}</span>
                  </td>
                  <td className="px-4 py-2.5">
                    <div className="text-[var(--color-fg-muted)]">{r.hospital_name}</div>
                    <div className="text-[10px] text-[var(--color-fg-subtle)]">{r.district}</div>
                  </td>
                  <td className="px-4 py-2.5"><StatusBadge status={r.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </main>
  );
}
