import { supabaseServer } from "@/lib/supabase/server";
import type { SchemaPayload } from "@/lib/schema/types";
import { DevNav } from "../_components/nav";
import { SchemaDiagram } from "./schema-diagram";

export const dynamic = "force-dynamic";

async function loadSchema(): Promise<SchemaPayload | null> {
  const { data, error } = await supabaseServer.rpc("get_schema");
  if (error) {
    console.error("[dev/schema] get_schema failed:", error.message);
    return null;
  }
  return data as SchemaPayload;
}

export default async function SchemaObservatoryPage() {
  const payload = await loadSchema();

  if (!payload) {
    return (
      <main className="min-h-screen">
        <DevNav active="/dev/schema" />
        <div className="mx-auto max-w-6xl px-6 py-12">
          <div className="rounded-xl border border-[var(--color-danger)]/40 bg-[var(--color-danger)]/10 p-6 text-sm text-[var(--color-fg)]">
            Schema metadata is unavailable. Check that{" "}
            <code className="font-mono">public.get_schema()</code> is granted to{" "}
            <code className="font-mono">anon</code>.
          </div>
        </div>
      </main>
    );
  }

  const totalRows = payload.tables.reduce(
    (sum, t) => sum + Number(t.row_count || 0),
    0
  );
  const tablesWithRls = payload.tables.filter((t) => t.rls_enabled).length;

  return (
    <main className="min-h-screen">
      <DevNav active="/dev/schema" />

      <div className="mx-auto max-w-6xl px-6 py-12">
        <div className="flex flex-wrap items-end justify-between gap-6">
          <div>
            <h1 className="text-3xl font-medium tracking-tight md:text-4xl">
              Live schema
            </h1>
            <p className="mt-2 max-w-xl text-sm leading-relaxed text-[var(--color-fg-muted)]">
              Generated in real time from{" "}
              <code className="font-mono text-[var(--color-fg)]">
                information_schema
              </code>{" "}
              by the{" "}
              <code className="font-mono text-[var(--color-fg)]">
                public.get_schema()
              </code>{" "}
              RPC. Drag any table, zoom with the wheel, follow the FK arrows.
            </p>
          </div>

          <div className="grid grid-cols-3 gap-px overflow-hidden rounded-xl border border-[var(--color-border)] bg-[var(--color-border)]">
            <Stat label="Tables" value={payload.tables.length} />
            <Stat label="Foreign keys" value={payload.foreign_keys.length} />
            <Stat label="Seed rows" value={totalRows} />
          </div>
        </div>

        <div className="mt-8 flex items-center gap-3 text-xs text-[var(--color-fg-subtle)]">
          <Legend
            color="var(--color-accent)"
            label="primary key"
          />
          <Legend
            color="var(--color-fg-muted)"
            label="foreign key"
          />
          <Legend
            color="var(--color-fg-subtle)"
            label="unique"
          />
          <span className="ml-auto font-mono">
            RLS enabled on {tablesWithRls} / {payload.tables.length}
          </span>
        </div>

        <div className="mt-4">
          <SchemaDiagram payload={payload} />
        </div>

        <div className="mt-12">
          <h2 className="text-sm font-medium uppercase tracking-widest text-[var(--color-fg-muted)]">
            Tables
          </h2>
          <div className="mt-4 grid gap-3 md:grid-cols-2 lg:grid-cols-3">
            {payload.tables.map((t) => (
              <div
                key={t.name}
                className="rounded-xl border border-[var(--color-border)] bg-[var(--color-bg-card)] p-4"
              >
                <div className="flex items-center justify-between">
                  <div className="font-mono text-sm text-[var(--color-fg)]">
                    {t.name}
                  </div>
                  <div className="font-mono text-[10px] text-[var(--color-fg-subtle)]">
                    {t.columns.length} cols · {t.row_count} rows
                  </div>
                </div>
                {t.comment && (
                  <p className="mt-2 text-xs leading-relaxed text-[var(--color-fg-muted)]">
                    {t.comment}
                  </p>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>
    </main>
  );
}

function Stat({ label, value }: { label: string; value: number }) {
  return (
    <div className="bg-[var(--color-bg-card)] px-5 py-3">
      <div className="font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
        {label}
      </div>
      <div className="mt-1 font-mono text-2xl text-[var(--color-fg)]">
        {value}
      </div>
    </div>
  );
}

function Legend({ color, label }: { color: string; label: string }) {
  return (
    <span className="inline-flex items-center gap-1.5 font-mono">
      <span
        className="size-1.5 rounded-full"
        style={{ background: color }}
      />
      {label}
    </span>
  );
}
