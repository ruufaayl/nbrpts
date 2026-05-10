import { getSupabaseServer } from "@/lib/supabase/server";
import type { PopulationStats } from "@/lib/officer/types";

export const dynamic = "force-dynamic";

async function loadStats(): Promise<PopulationStats | null> {
  const supabase = await getSupabaseServer();
  const { data, error } = await supabase.rpc("get_population_stats");
  if (error) {
    console.error("[officer/stats]", error.message);
    return null;
  }
  return data as PopulationStats;
}

export default async function OfficerStatsPage() {
  const data = await loadStats();
  if (!data) {
    return (
      <main className="mx-auto max-w-7xl px-6 py-12">
        <p className="text-sm text-[var(--color-fg-muted)]">Could not load population stats.</p>
      </main>
    );
  }

  const t = data.totals;

  return (
    <main className="mx-auto max-w-7xl px-6 py-10">
      <div>
        <h1 className="text-3xl font-medium tracking-tight md:text-4xl">Population stats</h1>
        <p className="mt-2 text-sm text-[var(--color-fg-muted)]">
          Aggregate analytics over every record in the system. Generated{" "}
          {new Date(data.generated_at).toLocaleString()}.
        </p>
      </div>

      <div className="mt-8 grid gap-3 md:grid-cols-2 lg:grid-cols-5">
        <Tile label="Total records" value={t.records} />
        <Tile label="Children registered" value={t.children} />
        <Tile label="Hospitals" value={t.hospitals} />
        <Tile label="Parents on file" value={t.parents} />
        <Tile label="B-Forms authorized" value={t.bforms_authorized} accent />
      </div>

      <div className="mt-12 grid gap-8 lg:grid-cols-2">
        <Section title="By province">
          <table className="w-full text-sm">
            <thead className="border-b border-[var(--color-border)] font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
              <tr>
                <th className="px-4 py-2 text-left">Province</th>
                <th className="px-4 py-2 text-right">Total</th>
                <th className="px-4 py-2 text-right">Verified</th>
                <th className="px-4 py-2 text-right">Flagged</th>
                <th className="px-4 py-2 text-right">Pending</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--color-border)]/60">
              {data.by_province.map((r) => (
                <tr key={r.province}>
                  <td className="px-4 py-2 font-medium text-[var(--color-fg)]">{r.province}</td>
                  <td className="px-4 py-2 text-right font-mono text-[var(--color-fg)]">{r.total_births}</td>
                  <td className="px-4 py-2 text-right font-mono text-[var(--color-accent)]">{r.verified}</td>
                  <td className="px-4 py-2 text-right font-mono text-[var(--color-warn)]">{r.flagged}</td>
                  <td className="px-4 py-2 text-right font-mono text-[var(--color-fg-muted)]">{r.pending}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Section>

        <Section title="By district">
          <table className="w-full text-sm">
            <thead className="border-b border-[var(--color-border)] font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
              <tr>
                <th className="px-4 py-2 text-left">District</th>
                <th className="px-4 py-2 text-left">Province</th>
                <th className="px-4 py-2 text-right">Hospitals</th>
                <th className="px-4 py-2 text-right">Births</th>
                <th className="px-4 py-2 text-right">Verified</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-[var(--color-border)]/60">
              {data.by_district.map((r) => (
                <tr key={`${r.province}-${r.district}`}>
                  <td className="px-4 py-2 text-[var(--color-fg)]">{r.district}</td>
                  <td className="px-4 py-2 text-[var(--color-fg-muted)]">{r.province}</td>
                  <td className="px-4 py-2 text-right font-mono text-[var(--color-fg-muted)]">{r.hospitals}</td>
                  <td className="px-4 py-2 text-right font-mono text-[var(--color-fg)]">{r.total_births}</td>
                  <td className="px-4 py-2 text-right font-mono text-[var(--color-accent)]">{r.verified}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </Section>

        <Section title="By gender">
          <ul className="px-4 py-2">
            {Object.entries(data.by_gender).map(([k, v]) => (
              <li key={k} className="flex items-center justify-between border-b border-[var(--color-border)]/40 py-2 last:border-0">
                <span className="text-[var(--color-fg)]">{k}</span>
                <span className="font-mono text-[var(--color-fg-muted)]">{v}</span>
              </li>
            ))}
          </ul>
        </Section>

        <Section title="By delivery type">
          <ul className="px-4 py-2">
            {Object.entries(data.by_delivery_type).map(([k, v]) => (
              <li key={k} className="flex items-center justify-between border-b border-[var(--color-border)]/40 py-2 last:border-0">
                <span className="text-[var(--color-fg)]">{k}</span>
                <span className="font-mono text-[var(--color-fg-muted)]">{v}</span>
              </li>
            ))}
          </ul>
        </Section>
      </div>

      <Section title="Top hospitals by submissions" className="mt-12">
        <table className="w-full text-sm">
          <thead className="border-b border-[var(--color-border)] font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
            <tr>
              <th className="px-4 py-2 text-left">Hospital</th>
              <th className="px-4 py-2 text-left">District</th>
              <th className="px-4 py-2 text-left">Province</th>
              <th className="px-4 py-2 text-right">Births</th>
              <th className="px-4 py-2 text-right">Verified %</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-[var(--color-border)]/60">
            {data.top_hospitals.map((h) => (
              <tr key={`${h.hospital_name}-${h.district}`}>
                <td className="px-4 py-2 text-[var(--color-fg)]">{h.hospital_name}</td>
                <td className="px-4 py-2 text-[var(--color-fg-muted)]">{h.district}</td>
                <td className="px-4 py-2 text-[var(--color-fg-muted)]">{h.province}</td>
                <td className="px-4 py-2 text-right font-mono text-[var(--color-fg)]">{h.total_births}</td>
                <td className="px-4 py-2 text-right font-mono text-[var(--color-accent)]">{Number(h.verified_pct ?? 0).toFixed(1)}%</td>
              </tr>
            ))}
          </tbody>
        </table>
      </Section>
    </main>
  );
}

function Tile({ label, value, accent }: { label: string; value: number; accent?: boolean }) {
  return (
    <div className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)] p-4">
      <div className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
        {label}
      </div>
      <div className={"mt-2 font-mono text-3xl " + (accent ? "text-[var(--color-accent)]" : "text-[var(--color-fg)]")}>
        {value}
      </div>
    </div>
  );
}

function Section({
  title, children, className = "",
}: {
  title: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section className={className}>
      <h2 className="text-sm font-medium uppercase tracking-widest text-[var(--color-fg-muted)]">
        {title}
      </h2>
      <div className="mt-3 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
        {children}
      </div>
    </section>
  );
}
