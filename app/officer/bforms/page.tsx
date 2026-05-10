import { getSupabaseServer } from "@/lib/supabase/server";
import type { BformsWorkload } from "@/lib/officer/types";
import { AuthorizeButton, ReissueButton } from "./bform-actions-client";

export const dynamic = "force-dynamic";

async function loadWorkload(): Promise<BformsWorkload | null> {
  const supabase = await getSupabaseServer();
  const { data, error } = await supabase.rpc("get_bforms_workload", { p_limit: 25 });
  if (error) {
    console.error("[officer/bforms]", error.message);
    return null;
  }
  return data as BformsWorkload;
}

export default async function OfficerBformsPage() {
  const data = await loadWorkload();
  if (!data) {
    return (
      <main className="mx-auto max-w-7xl px-6 py-12">
        <p className="text-sm text-[var(--color-fg-muted)]">Could not load B-Forms.</p>
      </main>
    );
  }

  return (
    <main className="mx-auto max-w-7xl px-6 py-10">
      <div>
        <h1 className="text-3xl font-medium tracking-tight md:text-4xl">B-Forms</h1>
        <p className="mt-2 text-sm text-[var(--color-fg-muted)]">
          Authorize newly minted B-Forms for collection. Reissue when parents need a new copy.
        </p>
      </div>

      <section className="mt-10">
        <h2 className="text-sm font-medium uppercase tracking-widest text-[var(--color-fg-muted)]">
          Awaiting authorization ({data.to_authorize.length})
        </h2>
        <div className="mt-3 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
          {data.to_authorize.length === 0 ? (
            <div className="px-6 py-12 text-center text-sm text-[var(--color-fg-muted)]">
              All B-Forms are authorized.
            </div>
          ) : (
            <table className="w-full text-sm">
              <thead className="border-b border-[var(--color-border)] bg-[var(--color-bg-elev)] font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
                <tr>
                  <th className="px-4 py-2.5 text-left">B-Form #</th>
                  <th className="px-4 py-2.5 text-left">Child / CNIN</th>
                  <th className="px-4 py-2.5 text-left">Mother</th>
                  <th className="px-4 py-2.5 text-left">Hospital</th>
                  <th className="px-4 py-2.5 text-left">Created</th>
                  <th className="px-4 py-2.5 text-right">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--color-border)]/60">
                {data.to_authorize.map((bf) => (
                  <tr key={bf.bform_id} className="hover:bg-[var(--color-bg-elev)]">
                    <td className="px-4 py-2.5 font-mono text-xs text-[var(--color-accent)]">
                      {bf.bform_number}
                      {bf.version > 1 ? (
                        <span className="ml-1 rounded bg-[var(--color-fg)]/10 px-1 text-[10px] text-[var(--color-fg-muted)]">
                          v{bf.version}
                        </span>
                      ) : null}
                    </td>
                    <td className="px-4 py-2.5">
                      <div className="text-[var(--color-fg)]">{bf.child_name}</div>
                      <div className="font-mono text-[10px] text-[var(--color-fg-subtle)]">{bf.cnin}</div>
                    </td>
                    <td className="px-4 py-2.5">
                      <div className="text-[var(--color-fg)]">{bf.mother_name}</div>
                      <div className="font-mono text-[10px] text-[var(--color-fg-subtle)]">{bf.mother_contact}</div>
                    </td>
                    <td className="px-4 py-2.5">
                      <div className="text-[var(--color-fg)]">{bf.hospital_name}</div>
                      <div className="text-[10px] text-[var(--color-fg-subtle)]">{bf.district}</div>
                    </td>
                    <td className="px-4 py-2.5 font-mono text-xs text-[var(--color-fg-muted)]">
                      {new Date(bf.created_at).toLocaleDateString()}
                    </td>
                    <td className="px-4 py-2.5 text-right">
                      <AuthorizeButton bformId={bf.bform_id} bformNumber={bf.bform_number} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </section>

      <section className="mt-12">
        <h2 className="text-sm font-medium uppercase tracking-widest text-[var(--color-fg-muted)]">
          Recently authorized
        </h2>
        <div className="mt-3 overflow-hidden rounded-2xl border border-[var(--color-border)] bg-[var(--color-bg-card)]">
          {data.recent_authorized.length === 0 ? (
            <div className="px-6 py-12 text-center text-sm text-[var(--color-fg-muted)]">
              No authorized B-Forms yet.
            </div>
          ) : (
            <table className="w-full text-sm">
              <thead className="border-b border-[var(--color-border)] bg-[var(--color-bg-elev)] font-mono text-[10px] uppercase tracking-widest text-[var(--color-fg-subtle)]">
                <tr>
                  <th className="px-4 py-2.5 text-left">B-Form #</th>
                  <th className="px-4 py-2.5 text-left">Child / CNIN</th>
                  <th className="px-4 py-2.5 text-left">Mother</th>
                  <th className="px-4 py-2.5 text-left">Authorized</th>
                  <th className="px-4 py-2.5 text-right">Reissue</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-[var(--color-border)]/60">
                {data.recent_authorized.map((bf) => (
                  <tr key={bf.bform_id} className="hover:bg-[var(--color-bg-elev)]">
                    <td className="px-4 py-2.5 font-mono text-xs text-[var(--color-accent)]">
                      {bf.bform_number}
                      {bf.version > 1 ? (
                        <span className="ml-1 rounded bg-[var(--color-fg)]/10 px-1 text-[10px] text-[var(--color-fg-muted)]">
                          v{bf.version}
                        </span>
                      ) : null}
                    </td>
                    <td className="px-4 py-2.5">
                      <div className="text-[var(--color-fg)]">{bf.child_name}</div>
                      <div className="font-mono text-[10px] text-[var(--color-fg-subtle)]">{bf.cnin}</div>
                    </td>
                    <td className="px-4 py-2.5 text-[var(--color-fg-muted)]">{bf.mother_name}</td>
                    <td className="px-4 py-2.5 font-mono text-xs text-[var(--color-fg-muted)]">
                      {new Date(bf.authorized_at).toLocaleString()}
                    </td>
                    <td className="px-4 py-2.5 text-right">
                      <ReissueButton childId={bf.child_id} childName={bf.child_name} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </section>
    </main>
  );
}
